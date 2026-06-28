#!/usr/bin/env bash
# ============================================================
# _sessions.sh — Tmux session interaction helpers
# ============================================================
# Provides: send, read, detect (question/idle/done/error),
#           wait_ready, kill, and single-pass monitor.
# Used by genie.sh manager loop to actively manage claude sessions.
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh" 2>/dev/null || true

# ─── Send text to a tmux session ────────────────────────────
session_send() {
  local sess="$1"; local text="$2"
  if ! tmux has-session -t "$sess" 2>/dev/null; then
    log_warn "session_send: session '$sess' not found"
    return 1
  fi
  # Use literal Enter key (send-keys handles special key names)
  tmux send-keys -t "$sess" -l "$text"
  tmux send-keys -t "$sess" Enter
}

# ─── Read last N lines from session ──────────────────────────
session_read() {
  local sess="$1"; local lines="${2:-30}"
  tmux capture-pane -t "$sess" -p -S -"$lines" 2>/dev/null || echo ""
}

# ─── Wait for claude to be ready ─────────────────────────────
# Polls session output for ready indicators, up to timeout.
session_wait_ready() {
  local sess="$1"; local timeout="${2:-30}"
  local start; start=$(date +%s)
  log_info "Waiting for claude ready in '$sess' (timeout ${timeout}s)"

  while true; do
    local out; out=$(session_read "$sess" 15)

    # Ready indicator: the `❯` input prompt (or bottom status "for agents")
    # appears ONLY when Claude Code's TUI input loop is running and ready to
    # accept a paste. Matching the early "Claude Code" banner is a bug — it
    # fires during boot, before stdin is being read, so the pasted prompt is
    # swallowed by claude's startup stdin flush → agent sits idle forever.
    # Keep the boot-guard below; on timeout we still assume ready (best-effort).
    if echo "$out" | grep -qE '❯|for agents|/help|/exit'; then
      if ! echo "$out" | grep -qiE 'starting|loading|initializing'; then
        log_ok "Claude ready in '$sess' (❯ prompt detected)"
        return 0
      fi
    fi

    local now; now=$(date +%s)
    if (( now - start >= timeout )); then
      log_warn "session_wait_ready: timeout (${timeout}s) — assuming ready"
      return 0  # best-effort: assume ready rather than block forever
    fi
    sleep 2
  done
}

# ─── Detect if agent is asking a question ───────────────────
# Returns 0 if question detected, 1 otherwise.
# Echoes the question text (last meaningful line ending with ?).
session_detect_question() {
  local sess="$1"
  local out; out=$(session_read "$sess" 20)

  # Pattern 1: SendUserMessage (structured, from --brief)
  if echo "$out" | grep -qiE 'SendUserMessage|send_user_message'; then
    echo "$out" | grep -iE 'SendUserMessage' | tail -1
    return 0
  fi

  # Pattern 2: question phrases
  local q_patterns='should I|do you want|which .+ |would you like|confirm|approve|clarify|waiting for|can you|shall I|do you prefer|which approach|what should|where should|how should'
  local q_line
  q_line=$(echo "$out" | grep -iE "$q_patterns" | tail -1)
  if [[ -n "$q_line" ]]; then
    echo "$q_line"
    return 0
  fi

  # Pattern 3: line ending with ? (but not inside code)
  q_line=$(echo "$out" | grep -vE '^\s*#|^\s*//|\bconsole\.log|\bprint\(' | grep -E '\?\s*$' | tail -1)
  if [[ -n "$q_line" ]]; then
    echo "$q_line"
    return 0
  fi

  return 1
}

# ─── Detect if agent is idle (no output for N seconds) ──────
# Compares pipe-pane log mtime to current time.
session_is_idle() {
  local sess="$1"; local idle_secs="${2:-60}"
  local log_file="${2:-}"

  # Try to find the pipe-pane log for this session
  # The log path is stored in session metadata, but we can also
  # check if the pane's output hasn't changed.
  local pane_hash
  pane_hash=$(tmux display-message -p -t "$sess" '#{pane_id}' 2>/dev/null)
  if [[ -z "$pane_hash" ]]; then
    return 1
  fi

  # Check if session's pane is at a prompt (idle = waiting for input)
  local out; out=$(session_read "$sess" 5)

  # If last non-empty line is just a prompt indicator → idle
  local last_line
  last_line=$(echo "$out" | grep -vE '^\s*$' | tail -1)
  if echo "$last_line" | grep -qE '^\s*>\s*$|^╭─|^│\s*$'; then
    return 0
  fi

  # Fallback: check if pane current command is just bash (claude exited)
  local pane_cmd
  pane_cmd=$(tmux display-message -p -t "$sess" '#{pane_current_command}' 2>/dev/null)
  if [[ "$pane_cmd" == "bash" || "$pane_cmd" == "sh" ]]; then
    return 0  # claude has exited, session is idle
  fi

  return 1
}

# ─── Detect if agent completed its task ──────────────────────
# Checks: completion marker file exists AND output file non-empty.
session_detect_done() {
  local goal_dir="$1"; local role="$2"; local idx="${3:-}"
  local marker="${goal_dir}/completion-markers/${role}${idx:+-${idx}}.done.json"

  if [[ -f "$marker" ]]; then
    local status
    status=$(python3 -c "import json; print(json.load(open('$marker')).get('status',''))" 2>/dev/null)
    if [[ "$status" == "done" ]]; then
      return 0
    fi
  fi

  # Also check agent output file exists and non-empty
  local agent_file="${goal_dir}/agent-${role}${idx:+-${idx}}.md"
  if [[ -f "$agent_file" ]] && [[ -s "$agent_file" ]]; then
    # Output file exists and non-empty — likely done even without marker
    return 0
  fi

  return 1
}

# ─── Detect errors in session output ─────────────────────────
session_detect_error() {
  local sess="$1"
  local out; out=$(session_read "$sess" 20)

  local err_patterns='Traceback|Exception|Error:|FAILED|fatal:|panic:|undefined reference|command not found|permission denied|FATAL'
  local err_line
  err_line=$(echo "$out" | grep -iE "$err_patterns" | tail -1)

  if [[ -n "$err_line" ]]; then
    echo "$err_line"
    return 0
  fi
  return 1
}

# ─── Kill a session cleanly ──────────────────────────────────
session_kill() {
  local sess="$1"
  if tmux has-session -t "$sess" 2>/dev/null; then
    tmux kill-session -t "$sess" 2>/dev/null || true
    log_warn "Killed session: $sess"
  fi
}

# ─── Nudge an idle session ───────────────────────────────────
session_nudge() {
  local sess="$1"; local role="$2"
  session_send "$sess" "Status? Any blockers? If done, write your output file and the completion marker."
  log_info "Nudged idle session: $sess ($role)"
}

# ─── Single-pass monitor ─────────────────────────────────────
# Returns status string: working|question|error|done|idle
# Echoes relevant info (question text, error line) if applicable.
# Does NOT handle the situation — just reports. Caller decides.
session_monitor() {
  local sess="$1"; local goal_dir="$2"; local role="$3"; local idx="${4:-}"

  # 1. Check for errors first (highest priority)
  local err; err=$(session_detect_error "$sess")
  if [[ -n "$err" ]]; then
    echo "error:${err}"
    return 0
  fi

  # 2. Check for questions
  local q; q=$(session_detect_question "$sess")
  if [[ -n "$q" ]]; then
    echo "question:${q}"
    return 0
  fi

  # 3. Check for completion
  if session_detect_done "$goal_dir" "$role" "$idx"; then
    echo "done"
    return 0
  fi

  # 4. Check for idle
  if session_is_idle "$sess"; then
    echo "idle"
    return 0
  fi

  # 5. Default: working
  echo "working"
  return 0
}

# ─── Full monitor loop (blocking, with TTL) ──────────────────
# Monitors a single session until done or timeout.
# Handles trivial questions and idle nudges inline.
# For critical/expert questions: writes pending question, returns 2.
# For errors: returns 3.
# For done: returns 0.
# For timeout: returns 1.
session_monitor_loop() {
  local sess="$1"; local goal_dir="$2"; local role="$3"
  local goal_id="$4"; local idx="${5:-}"; local ttl="${6:-$WAITFOR_TTL}"
  local start; start=$(date +%s)
  local last_nudge=0
  local poll_interval=10

  log_info "Monitor loop started for '$sess' (TTL: ${ttl}s)"

  while true; do
    local status; status=$(session_monitor "$sess" "$goal_dir" "$role" "$idx")
    local kind="${status%%:*}"
    local detail="${status#*:}"

    case "$kind" in
      working)
        # Agent is actively working — just wait
        ;;
      question)
        # Source the bridge library
        source "${GENIE_LIB}/_bridge.sh" 2>/dev/null || true
        local action
        action=$(genie_bridge "$sess" "$detail" "$role" "$goal_dir" "$goal_id")
        case "$action" in
          answered)
            log_ok "Bridge: answered trivial question for $role"
            ;;
          needs_user_input)
            echo "NEEDS_USER_INPUT:${role}:${detail}"
            # Wait for answer file to appear
            local answer_dir="${goal_dir}/pending-answers"
            local answer_file="${answer_dir}/${role}.answer"
            while [[ ! -f "$answer_file" ]]; do
              local now; now=$(date +%s)
              if (( now - start >= ttl )); then
                log_warn "Monitor loop: timeout waiting for user answer"
                return 1
              fi
              sleep 2
            done
            # Answer file exists — send it to session
            local answer; answer=$(cat "$answer_file")
            session_send "$sess" "$answer"
            log_ok "Bridge: relayed user answer to $role"
            ;;
          expert_spawned)
            log_ok "Bridge: spawned expert for $role"
            ;;
          *)
            log_warn "Bridge: unknown action '$action' for $role"
            ;;
        esac
        ;;
      error)
        log_error "Monitor: error detected in $sess: $detail"
        return 3
        ;;
      done)
        log_ok "Monitor: $role completed"
        return 0
        ;;
      idle)
        local now; now=$(date +%s)
        if (( now - last_nudge >= 60 )); then
          session_nudge "$sess" "$role"
          last_nudge=$now
        fi
        ;;
    esac

    # Timeout check
    local now; now=$(date +%s)
    if (( now - start >= ttl )); then
      log_warn "Monitor loop: timeout (${ttl}s) for $sess"
      return 1
    fi

    sleep "$poll_interval"
  done
}

# ─── Verify output quality (enhanced gating) ────────────────
# Returns 0 if quality sufficient, 1 if insufficient.
# Echoes specific issues found (if any).
session_verify_output() {
  local goal_dir="$1"; local role="$2"; local idx="${3:-}"
  # BSA's deliverable is spec.md (not agent-bsa.md) — verify the right file.
  # NOTE: this function MUST return 0. Callers check the echoed $issues
  # string, not the return code — and a non-zero return here trips `set -e`
  # in spawn_and_monitor (`issues=$(session_verify_output ...)`) and
  # silently kills the whole pipeline right after BSA, before Phase 1b
  # (root-caused 2026-06-28). Echo issues; never fail.
  local agent_file
  case "$role" in
    bsa) agent_file="${goal_dir}/spec.md" ;;
    *)   agent_file="${goal_dir}/agent-${role}${idx:+-${idx}}.md" ;;
  esac

  if [[ ! -f "$agent_file" ]] || [[ ! -s "$agent_file" ]]; then
    echo "Output file missing or empty (${agent_file})"
    return 0
  fi

  local content; content=$(cat "$agent_file")
  local issues=""

  case "$role" in
    bsa)
      # Spec should have: requirements, acceptance criteria
      if ! echo "$content" | grep -qi 'acceptance criteria\|AC[0-9]\|AC:|AC -'; then
        issues+="No acceptance criteria found. "
      fi
      if ! echo "$content" | grep -qiE 'requirement|user story|feature'; then
        issues+="No requirements/user story found. "
      fi
      ;;
    architect)
      # Plan should have: steps, file structure, tech approach
      if ! echo "$content" | grep -qiE 'step|phase|stage|implement'; then
        issues+="No implementation steps found. "
      fi
      ;;
    critic)
      # Critique should have: specific findings, not just generic
      local word_count; word_count=$(echo "$content" | wc -w)
      if (( word_count < 50 )); then
        issues+="Critique too short (${word_count} words). "
      fi
      ;;
    implementor)
      # Code should have: actual implementation, not just stubs
      if echo "$content" | grep -qiE 'TODO|FIXME|stub|not implemented|placeholder'; then
        issues+="Contains TODO/stub/placeholder. "
      fi
      ;;
    qas)
      # QAS should have: verdict (approved/changes needed)
      if ! echo "$content" | grep -qiE 'APPROVED|CHANGES_NEEDED|PASS|FAIL'; then
        issues+="No clear verdict (APPROVED/CHANGES_NEEDED). "
      fi
      ;;
    security-engineer)
      if ! echo "$content" | grep -qiE 'SECURITY_BLOCKED|SECURITY_PASSED|no.*security.*issue|secure'; then
        issues+="No security verdict. "
      fi
      ;;
    *)
      # Generic: just check non-empty and reasonable length
      local word_count; word_count=$(echo "$content" | wc -w)
      if (( word_count < 20 )); then
        issues+="Output too short (${word_count} words). "
      fi
      ;;
  esac

  if [[ -n "$issues" ]]; then
    echo "$issues"
  fi
  return 0
}

# Export all functions
export -f session_send session_read session_wait_ready
export -f session_detect_question session_is_idle session_detect_done
export -f session_detect_error session_kill session_nudge
export -f session_monitor session_monitor_loop session_verify_output
