#!/usr/bin/env bash
set -euo pipefail
source "${HOME}/.hermes/scripts/lib/_common.sh"
source "${HOME}/.hermes/scripts/lib/_roles.sh"

genie_spawn() {
    local role="$1"
    local goal_id="$2"
    local goal_dir="$3"
    local goal_desc="$4"
    local idx="${5:-}"

    # Model selection with fallback (from _roles.sh via _models.sh)
    local model effort tools permission
    model=$(genie_select_model "$role")
    effort=$(genie_get_effort "$role")
    tools=$(genie_get_tools "$role")
    permission=$(genie_get_permission "$role")

    # Budget gate
    local est_cost
    est_cost=$(genie_estimate_cost "$role" 8000)
    log_info "Budget check: ${role} estimated \$${est_cost}"
    if ! python3 "${GENIE_DIR}/budget_tracker.py" check "$goal_id" --estimate "$est_cost"; then
        log_error "Budget gate blocked spawn of ${role}"
        return 1
    fi

    # Generate session name
    local session_name="${goal_id}-${role}${idx:+-${idx}}"
    local agent_file="${goal_dir}/agent-${role}${idx}.md"
    local session_log="${VAULT_DIR}/11-sessions/${session_name}.md"

    # Load role prompt (if exists)
    local role_prompt_file="${GENIE_LIB}/roles/${ROLE_PROMPTS[$role]:-}"
    local role_prompt=""
    if [[ -n "$role_prompt_file" && -f "$role_prompt_file" ]]; then
        role_prompt=$(cat "$role_prompt_file")
    fi

    # Build system prompt
    local sys_prompt="You are the ${role} for goal: ${goal_desc}.

Write all output to your designated file: ${agent_file}
Read the shared goal context at: ${goal_dir}/goal-context.json
Read the spec at: ${goal_dir}/spec.md
Read the plan at: ${goal_dir}/plan.md
Read pattern discovery at: ${goal_dir}/context/pattern-discovery.md
Use wikilinks [[${goal_id}]] to reference related work.

When done, write a JSON completion marker to: ${goal_dir}/completion-markers/${role}${idx:+-${idx}}.done.json
Marker format: {\"status\":\"done\",\"exit_code\":0,\"role\":\"${role}\"}

${role_prompt}"

    # Skill injection (summaries only)
    local skill_dir="${goal_dir}/skill-summaries"
    if [[ -d "$skill_dir" ]]; then
        sys_prompt="${sys_prompt}

Relevant skills:"
        for skill_file in "$skill_dir"/*.md; do
            [[ -f "$skill_file" ]] || continue
            local skill_name
            skill_name=$(basename "$skill_file" .md)
            sys_prompt="${sys_prompt}
- ${skill_name}"
        done
    fi

    # Worktree setup (if in a git repo)
    local worktree_path=""
    local goal_context="${goal_dir}/goal-context.json"
    local project_dir="."
    if [[ -f "$goal_context" ]]; then
        project_dir=$(python3 -c "import json; print(json.load(open('$goal_context')).get('project_dir','.'))" 2>/dev/null || echo ".")
    fi
    if git -C "$project_dir" rev-parse --git-dir &>/dev/null 2>&1; then
        local worktree_base="${HOME}/.hermes/worktrees/${goal_id}"
        worktree_path="${worktree_base}/${role}${idx:+-${idx}}"
        safe_mkdir "$worktree_path" 2>/dev/null || true
        # Create worktree on a new branch
        local branch_name="${goal_id}-${role}${idx:+-${idx}}"
        if ! git -C "$project_dir" worktree list | grep -q "$worktree_path"; then
            git -C "$project_dir" worktree add -b "$branch_name" "$worktree_path" 2>/dev/null || true
        fi
        sys_prompt="${sys_prompt}

Your working directory (git worktree): ${worktree_path}
Branch: ${branch_name}
Commit your work as you go. Use conventional commit format."
    fi

    # Spawn tmux session
    log_info "Spawning ${role} (model: ${model}, effort: ${effort}) -> ${session_name}"

    tmux new-session -d -s "$session_name" \
        "claude --name '${session_name}' \
        --model '${model}' \
        --effort '${effort}' \
        --append-system-prompt '${sys_prompt}' \
        --permission-mode '${permission}' \
        2>&1 | tee '${agent_file}'"

    # Get PID
    local pid
    pid=$(tmux list-panes -t "$session_name" -F '#{pane_pid}' | head -1)

    # Attach pipe-pane with filter
    local raw_log="${goal_dir}/raw-logs/${session_name}.raw"
    safe_mkdir "$(dirname "$raw_log")"
    tmux pipe-pane -t "$session_name" -O "bash ${GENIE_DIR}/filter.sh >> '${session_log}' 2>> '${raw_log}'"

    # Write session metadata
    local session_meta="${VAULT_DIR}/11-sessions/${session_name}.meta.json"
    cat > "$session_meta" <<EOF
{
  "session_name": "${session_name}",
  "role": "${role}",
  "goal_id": "${goal_id}",
  "model": "${model}",
  "effort": "${effort}",
  "tools": "${tools}",
  "permission": "${permission}",
  "pid": "${pid}",
  "started": "$(date -Iseconds)",
  "agent_file": "${agent_file}",
  "session_log": "${session_log}",
  "worktree": "${worktree_path}",
  "status": "active"
}
EOF

    # Record estimated cost
    python3 "${GENIE_DIR}/budget_tracker.py" record "$goal_id" --cost "$est_cost" --phase "${role}${idx:+-$idx}"

    log_ok "Spawned ${role} -> ${session_name} (PID: ${pid})"
    echo "${session_name}"
}

# Main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 4 ]]; then
        log_error "Usage: $0 <role> <goal_id> <goal_dir> <goal_desc> [idx]"
        exit 1
    fi
    genie_spawn "$@"
fi
