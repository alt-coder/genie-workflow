#!/usr/bin/env bash
# ============================================================
# _bridge.sh — Human-agent bridge decision tree
# ============================================================
# When an agent asks a question, classify it:
#   trivial  → Hermes answers from context files
#   critical → Forward to user (write pending question, signal)
#   expert   → Spawn expert session, relay answer back
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh" 2>/dev/null || true
source "${HOME}/.hermes/scripts/lib/_sessions.sh" 2>/dev/null || true

# ─── Question classification ─────────────────────────────────
# Returns: trivial | critical | expert
classify_question() {
  local question="$1"
  local question_lower; question_lower=$(echo "$question" | tr '[:upper:]' '[:lower:]')

  # Trivial: questions about project structure, conventions, file locations
  local trivial_patterns='which file|what format|where (do|to|should)|what.*name|which directory|what.*path|file (name|path|location)'
  if echo "$question_lower" | grep -qE "$trivial_patterns"; then
    echo "trivial"
    return
  fi

  # Expert: domain-specific knowledge (check FIRST — more specific)
  local expert_patterns='which .*(library|package|framework)|how to handle|best practice|security implication|crypto|encryption|gdpr|compliance|performance (optim|tuning)|scale (to|up)|concurrency'
  if echo "$question_lower" | grep -qE "$expert_patterns"; then
    echo "expert"
    return
  fi

  # Critical: architecture/product decisions needing user input
  local critical_patterns='should (we|i) use|do you want|which approach|would you (like|prefer)|shall (we|i)|confirm|approve|what should|do you prefer|rest vs|graphql|sql vs|nosql|monorepo|microservice|break (it|this) (down|up)'
  if echo "$question_lower" | grep -qE "$critical_patterns"; then
    echo "critical"
    return
  fi

  # Default: treat as critical (better to ask user than guess wrong)
  echo "critical"
}

# ─── Derive answer from context (trivial questions) ──────────
# Looks up answer from goal context, spec, plan files.
# Returns: answer string (may be empty if not found).
derive_answer_from_context() {
  local question="$1"
  local goal_dir="$2"
  local answers=""

  # Check goal-context.json
  if [[ -f "${goal_dir}/goal-context.json" ]]; then
    local desc
    desc=$(python3 -c "import json; print(json.load(open('${goal_dir}/goal-context.json')).get('description',''))" 2>/dev/null)
    if [[ -n "$desc" ]]; then
      answers+="Goal: ${desc}. "
    fi
  fi

  # Check spec.md
  if [[ -f "${goal_dir}/spec.md" ]]; then
    local spec; spec=$(cat "${goal_dir}/spec.md")
    # Look for relevant sections based on question keywords
    if echo "$question" | grep -qi 'format'; then
      local format_section
      format_section=$(echo "$spec" | grep -A5 -i 'format\|structure\|schema' | head -10)
      [[ -n "$format_section" ]] && answers+="Spec says: ${format_section}. "
    fi
    if echo "$question" | grep -qi 'file\|path\|directory'; then
      local file_section
      file_section=$(echo "$spec" | grep -A5 -i 'file\|path\|directory\|location\|structure' | head -10)
      [[ -n "$file_section" ]] && answers+="Spec mentions: ${file_section}. "
    fi
  fi

  # Check plan.md
  if [[ -f "${goal_dir}/plan.md" ]]; then
    local plan; plan=$(cat "${goal_dir}/plan.md")
    if echo "$question" | grep -qi 'step\|phase\|order\|sequence'; then
      local plan_steps
      plan_steps=$(echo "$plan" | grep -E '^\s*(Step|Phase|##|[0-9]\.)' | head -15)
      [[ -n "$plan_steps" ]] && answers+="Plan steps: ${plan_steps}. "
    fi
  fi

  # Check clarification answers
  if [[ -f "${goal_dir}/context/clarification.md" ]]; then
    local clar; clar=$(cat "${goal_dir}/context/clarification.md")
    answers+="Clarifications: ${clar}. "
  fi

  echo "$answers"
}

# ─── Write pending question (for user) ───────────────────────
write_pending_question() {
  local goal_dir="$1"
  local role="$2"
  local question="$3"

  local q_dir="${goal_dir}/pending-questions"
  safe_mkdir "$q_dir" 2>/dev/null || mkdir -p "$q_dir" 2>/dev/null || true

  local q_file="${q_dir}/${role}.question"
  cat > "$q_file" <<EOF
{
  "role": "${role}",
  "question": $(printf '%s' "$question" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"${question}\""),
  "timestamp": "$(date -Iseconds)",
  "status": "pending"
}
EOF
  echo "$q_file"
}

# ─── Read pending answer (from user) ─────────────────────────
read_pending_answer() {
  local goal_dir="$1"
  local role="$2"

  local a_file="${goal_dir}/pending-answers/${role}.answer"
  if [[ -f "$a_file" ]]; then
    cat "$a_file"
    return 0
  fi
  return 1
}

# ─── Write pending answer ────────────────────────────────────
write_pending_answer() {
  local goal_dir="$1"
  local role="$2"
  local answer="$3"

  local a_dir="${goal_dir}/pending-answers"
  safe_mkdir "$a_dir" 2>/dev/null || mkdir -p "$a_dir" 2>/dev/null || true

  local a_file="${a_dir}/${role}.answer"
  cat > "$a_file" <<EOF
{
  "role": "${role}",
  "answer": $(printf '%s' "$answer" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"${answer}\""),
  "timestamp": "$(date -Iseconds)"
}
EOF
  echo "$a_file"
}

# ─── Spawn expert session ────────────────────────────────────
# Spawns a claude session with an expert model to answer a question.
# Expert writes answer to {goal_dir}/expert-answers/{role}.answer
spawn_expert() {
  local question="$1"
  local goal_dir="$2"
  local goal_id="${3:-}"
  local role="${4:-architect}"
  local expert_model="${5:-sonnet}"

  local expert_sess="${goal_id}-expert-${role}"
  local expert_dir="${goal_dir}/expert-answers"
  safe_mkdir "$expert_dir" 2>/dev/null || mkdir -p "$expert_dir" 2>/dev/null || true
  local answer_file="${expert_dir}/${role}.answer"

  local project_dir="."
  if [[ -f "${goal_dir}/goal-context.json" ]]; then
    project_dir=$(python3 -c "import json; print(json.load(open('${goal_dir}/goal-context.json')).get('project_dir','.'))" 2>/dev/null || echo ".")
  fi

  local expert_prompt="You are a domain expert answering a question for goal ${goal_id}.

Question from ${role}: ${question}

Provide a clear, specific recommendation with reasoning.
Keep it concise — focus on the decision and why.

Write your answer to: ${answer_file}"

  local prompt_file="${goal_dir}/.expert-prompt-${role}.md"
  printf '%s' "$expert_prompt" > "$prompt_file"

  # Spawn expert in tmux
  tmux new-session -d -s "$expert_sess" -x 140 -y 40 2>/dev/null || true
  tmux send-keys -t "$expert_sess" "cd '${project_dir}' && claude --dangerously-skip-permissions --model '${expert_model}'" Enter

  session_wait_ready "$expert_sess" 20 2>/dev/null || true

  # Send the question
  tmux send-keys -t "$expert_sess" "$(cat '$prompt_file')" Enter

  log_info "Expert spawned: $expert_sess (model: $expert_model) for question from $role"

  # Monitor expert until done (simplified — just wait for answer file)
  local expert_start; expert_start=$(date +%s)
  local expert_ttl=120  # 2 minutes for expert
  while true; do
    if [[ -f "$answer_file" ]] && [[ -s "$answer_file" ]]; then
      log_ok "Expert answered: $answer_file"
      session_kill "$expert_sess"
      echo "$answer_file"
      return 0
    fi
    local now; now=$(date +%s)
    if (( now - expert_start >= expert_ttl )); then
      log_warn "Expert timeout — killing session"
      session_kill "$expert_sess"
      return 1
    fi
    sleep 5
  done
}

# ─── Main bridge function ────────────────────────────────────
# Called when session_detect_question fires.
# Decides: answer trivial, forward critical, or spawn expert.
#
# Returns (echoed): answered | needs_user_input | expert_spawned | no_action
genie_bridge() {
  local sess="$1"
  local question="$2"
  local role="$3"
  local goal_dir="$4"
  local goal_id="${5:-}"

  log_info "Bridge: question from ${role}: ${question:0:100}..."

  # Classify the question
  local classification
  classification=$(classify_question "$question")

  case "$classification" in
    trivial)
      # Try to answer from context
      local answer
      answer=$(derive_answer_from_context "$question" "$goal_dir")
      if [[ -n "$answer" ]] && [[ "$answer" != *"Goal:"* ]] || echo "$answer" | grep -qE 'Spec says|Plan steps|Clarifications'; then
        # We found relevant context
        local full_answer="Based on project context: ${answer}"
        session_send "$sess" "$full_answer"
        echo "answered"
      else
        # Couldn't find answer in context — escalate to user
        write_pending_question "$goal_dir" "$role" "$question"
        echo "NEEDS_USER_INPUT:${role}:${question}"
        echo "needs_user_input"
      fi
      ;;

    critical)
      # Forward to user — write pending question
      write_pending_question "$goal_dir" "$role" "$question"
      echo "NEEDS_USER_INPUT:${role}:${question}"
      echo "needs_user_input"
      ;;

    expert)
      # Spawn expert session
      local expert_answer
      expert_answer=$(spawn_expert "$question" "$goal_dir" "$goal_id" "$role" "sonnet" 2>/dev/null || echo "")
      if [[ -n "$expert_answer" ]] && [[ -f "$expert_answer" ]]; then
        local answer_content; answer_content=$(cat "$expert_answer")
        session_send "$sess" "Expert recommendation: ${answer_content}"
        echo "expert_spawned"
      else
        # Expert failed — escalate to user
        write_pending_question "$goal_dir" "$role" "$question"
        echo "needs_user_input"
      fi
      ;;

    *)
      # Unknown classification — treat as critical
      write_pending_question "$goal_dir" "$role" "$question"
      echo "needs_user_input"
      ;;
  esac
}

# Export
export -f classify_question derive_answer_from_context
export -f write_pending_question read_pending_answer write_pending_answer
export -f spawn_expert genie_bridge
