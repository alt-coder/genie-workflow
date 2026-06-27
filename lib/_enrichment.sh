#!/usr/bin/env bash
# ============================================================
# _enrichment.sh — Prompt enrichment + model decision tree
# ============================================================
# Called before every spawn. Builds a dynamic, context-aware
# prompt that includes: role template, goal context, clarification
# answers, skills, patterns, image handling, vision delegation,
# and subagent instructions.
#
# Model decision tree produces dual output:
#   - Main model  → --model flag (command level)
#   - Subtask models → prompt text (instructions for agent)
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh" 2>/dev/null || true
source "${HOME}/.hermes/scripts/lib/_models.sh" 2>/dev/null || true

# ─── Find a vision-capable model ─────────────────────────────
# Scans model-capabilities.json for a model with has_vision=true.
# Prefers sonnet tier (good vision + reasonable cost).
# Falls back to any vision-capable model.
# Returns: model name string.
find_vision_model() {
  local cache="${HOME}/.hermes/model-capabilities.json"

  if [[ ! -f "$cache" ]]; then
    echo "sonnet"
    return
  fi

  local model
  model=$(python3 -c "
import json
with open('$cache') as f:
    db = json.load(f)
# Prefer sonnet-tier models first, then any with vision
vision_models = []
for m, caps in db.items():
    if caps.get('has_vision', False) and caps.get('available', True):
        vision_models.append(m)
if vision_models:
    # Prefer models with 'sonnet' in the name
    for m in vision_models:
        if 'sonnet' in m.lower():
            print(m)
            exit()
    # Otherwise return first vision model
    print(vision_models[0])
else:
    print('sonnet')  # fallback
" 2>/dev/null)

  echo "${model:-sonnet}"
}

# ─── Model decision tree (dual output) ───────────────────────
# Inputs: role, goal_desc, has_image, goal_dir
# Outputs (pipe-delimited on stdout):
#   main_model|subtask_instructions|agents_json
#
# main_model         → for --model flag (may be empty for default)
# subtask_instructions → embedded in prompt text
# agents_json        → for --agents flag (may be empty)
genie_model_decision_tree() {
  local role="$1"
  local goal_desc="${2:-}"
  local has_image="${3:-false}"
  local goal_dir="${4:-}"

  # 1. Main model selection (existing logic)
  local main_model
  main_model=$(genie_select_model "$role" "$goal_desc" "$goal_dir")

  # 2. Subtask model instructions
  local subtask_instructions=""
  local agents_json="{}"

  # Check main model vision capability
  local caps
  caps=$(get_model_capabilities "$main_model" 2>/dev/null || echo '{}')
  local has_vision
  has_vision=$(echo "$caps" | python3 -c "import sys,json; print(json.load(sys.stdin).get('has_vision',False))" 2>/dev/null || echo "False")

  # Vision subtask: if image present and main model lacks vision
  if [[ "$has_image" == "true" ]] && [[ "$has_vision" != "True" ]]; then
    local vision_model
    vision_model=$(find_vision_model)

    subtask_instructions+="For image/screenshot/diagram analysis: You lack vision capability. "
    subtask_instructions+="Use @vision-analyst subagent (model: ${vision_model}) to analyze images. "
    subtask_instructions+="Pass the image file path to the subagent. Wait for text description, then proceed with that description. "

    # Build agents JSON for --agents flag
    agents_json=$(python3 -c "
import json
agents = {
    'vision-analyst': {
        'description': 'Analyzes images, screenshots, diagrams. Use when you need visual analysis.',
        'prompt': 'You are a vision analyst. Analyze the provided image. Return a detailed text description of what you see, including any text, diagrams, UI elements, or code visible in the image.'
    }
}
print(json.dumps(agents))
" 2>/dev/null)

  elif [[ "$has_image" == "true" ]] && [[ "$has_vision" == "True" ]]; then
    # Main model has vision — just pass the image path
    subtask_instructions+="You have vision capability. Analyze images directly by reading the file at the given path. "
  fi

  # Code review subtask: critics should use a strong model
  if [[ "$role" == "critic" || "$role" == "reviewer" ]]; then
    subtask_instructions+="For deep code review, you may use @domain-expert subagent for specialized analysis. "
  fi

  # Security subtask
  if echo "$goal_desc" | grep -qiE 'security|auth|crypto|encrypt|token|password|vulnerability'; then
    if [[ "$role" == "security-engineer" || "$role" == "architect" ]]; then
      subtask_instructions+="For security-specific decisions, use @security-advisor subagent. "
    fi
  fi

  # Output: pipe-delimited
  echo "${main_model}|${subtask_instructions}|${agents_json}"
}

# ─── Main enrichment function ───────────────────────────────
# Builds the full enriched prompt for a role.
#
# Inputs: role, goal_desc, goal_dir, [user_message], [has_image], [image_path]
# Outputs:
#   - Writes enriched prompt to {goal_dir}/.prompt-{role}{idx}.md
#   - Writes main model to {goal_dir}/.model-{role}{idx}.txt
#   - Writes agents JSON to {goal_dir}/.agents-{role}{idx}.json
#   - Echoes the prompt file path
genie_enrich_prompt() {
  local role="$1"
  local goal_desc="$2"
  local goal_dir="$3"
  local user_message="${4:-}"
  local has_image="${5:-false}"
  local image_path="${6:-}"
  local idx="${7:-}"

  local suffix="${idx:+-${idx}}"
  local prompt_file="${goal_dir}/.prompt-${role}${suffix}.md"
  local model_file="${goal_dir}/.model-${role}${suffix}.txt"
  local agents_file="${goal_dir}/.agents-${role}${suffix}.json"

  # 1. Run model decision tree
  local decision
  decision=$(genie_model_decision_tree "$role" "$goal_desc" "$has_image" "$goal_dir")
  local main_model; main_model=$(echo "$decision" | cut -d'|' -f1)
  local subtask_instructions; subtask_instructions=$(echo "$decision" | cut -d'|' -f2)
  local agents_json; agents_json=$(echo "$decision" | cut -d'|' -f3)

  # Save model and agents for spawn script
  printf '%s' "$main_model" > "$model_file"
  printf '%s' "$agents_json" > "$agents_file"

  # 2. Load role prompt
  local role_prompt=""
  local role_prompt_key="${ROLE_PROMPTS[$role]:-}"
  if [[ -n "$role_prompt_key" ]]; then
    local role_prompt_file="${GENIE_LIB}/roles/${role_prompt_key}"
    if [[ -f "$role_prompt_file" ]]; then
      role_prompt=$(cat "$role_prompt_file")
    fi
  fi

  # 3. Build base prompt
  local agent_file="${goal_dir}/agent-${role}${suffix}.md"
  local prompt="You are the ${role} for goal: ${goal_desc}.

## Output
Write all output to your designated file: ${agent_file}

## Context Files
Read the shared goal context at: ${goal_dir}/goal-context.json
Read the spec at: ${goal_dir}/spec.md (if exists)
Read the plan at: ${goal_dir}/plan.md (if exists)
Read pattern discovery at: ${goal_dir}/context/pattern-discovery.md (if exists)
Use wikilinks [[${goal_id:-}]] to reference related work.
"

  # 4. Add clarification answers (if Phase 0.5 ran)
  local clarification_file="${goal_dir}/context/clarification.md"
  if [[ -f "$clarification_file" ]] && [[ -s "$clarification_file" ]]; then
    prompt+="
## Clarification Answers
The following clarifications were provided before work began:
$(cat "$clarification_file")
"
  fi

  # 5. Add model capability + subtask instructions
  if [[ -n "$subtask_instructions" ]]; then
    prompt+="
## Model Capability Notes
${subtask_instructions}
"
  fi

  # 6. Add image handling
  if [[ "$has_image" == "true" ]] && [[ -n "$image_path" ]]; then
    prompt+="
## Image Resource
Image file available at: ${image_path}
"
    # Already handled by subtask_instructions for vision delegation
    # But if main model has vision, add direct instruction
    if echo "$subtask_instructions" | grep -q "You have vision capability"; then
      prompt+="Analyze the image directly by reading the file at the above path. Use the Read tool to load the image.\n"
    fi
  fi

  # 7. Add user message enrichment (if provided and different from goal_desc)
  if [[ -n "$user_message" ]] && [[ "$user_message" != "$goal_desc" ]]; then
    prompt+="
## Additional User Context
Original user message: ${user_message}
"
  fi

  # 8. Add skill summaries
  local skill_dir="${goal_dir}/skill-summaries"
  if [[ -d "$skill_dir" ]]; then
    local skill_list=""
    for skill_file in "$skill_dir"/*.md; do
      [[ -f "$skill_file" ]] || continue
      local skill_name; skill_name=$(basename "$skill_file" .md)
      skill_list+="- ${skill_name}"$'\n'
    done
    if [[ -n "$skill_list" ]]; then
      prompt+="
## Relevant Skills
${skill_list}
"
    fi
  fi

  # 9. Add role-specific prompt
  if [[ -n "$role_prompt" ]]; then
    prompt+="
## Role Instructions
${role_prompt}
"
  fi

  # 10. Add worktree info
  local goal_context="${goal_dir}/goal-context.json"
  local project_dir="."
  if [[ -f "$goal_context" ]]; then
    project_dir=$(python3 -c "import json; print(json.load(open('$goal_context')).get('project_dir','.'))" 2>/dev/null || echo ".")
  fi
  if git -C "$project_dir" rev-parse --git-dir &>/dev/null 2>&1; then
    local worktree_path="${HOME}/.hermes/worktrees/${goal_id:-unknown}/${role}${suffix}"
    local branch_name="${goal_id:-unknown}-${role}${suffix}"
    prompt+="
## Working Directory
Your working directory (git worktree): ${worktree_path}
Branch: ${branch_name}
Commit your work as you go. Use conventional commit format.
"
  fi

  # 11. Add completion instructions
  local marker_file="${goal_dir}/completion-markers/${role}${suffix}.done.json"
  prompt+="
## Completion
When done, write a JSON completion marker to: ${marker_file}
Marker format: {\"status\":\"done\",\"exit_code\":0,\"role\":\"${role}\"}
"

  # Write enriched prompt
  printf '%s' "$prompt" > "$prompt_file"
  echo "$prompt_file"
}

# Export
export -f find_vision_model genie_model_decision_tree genie_enrich_prompt
