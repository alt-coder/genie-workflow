#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# hermes-spawn.sh v2 — Interactive spawn (manager-orchestrator)
# ============================================================
# Changes from v1:
#   - Removed: --bare --print --effort --append-system-prompt --permission-mode
#   - Added:   --brief (SendUserMessage), --agents (subagents), --model (when needed)
#   - Uses:    _enrichment.sh for dynamic prompt building
#   - Uses:    _sessions.sh for tmux session interaction
#   - Flow:    enrich → budget gate → worktree → spawn tmux → wait ready →
#              send enriched prompt via paste-buffer → pipe-pane logging
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh"
source "${HOME}/.hermes/scripts/lib/_roles.sh"
source "${HOME}/.hermes/scripts/lib/_models.sh"
source "${HOME}/.hermes/scripts/lib/_sessions.sh"
source "${HOME}/.hermes/scripts/lib/_enrichment.sh"

genie_spawn() {
    local role="$1"
    local goal_id="$2"
    local goal_dir="$3"
    local goal_desc="$4"
    local idx="${5:-}"
    local user_message="${6:-}"      # optional: original user message (enriched)
    local has_image="${7:-false}"    # optional: does user message include image?
    local image_path="${8:-}"        # optional: path to saved image

    local suffix="${idx:+-${idx}}"

    # ─── 1. Enrich prompt (model decision tree, image, clarification, skills) ───
    log_info "Enriching prompt for ${role}..."

    local prompt_file
    prompt_file=$(genie_enrich_prompt \
        "$role" "$goal_desc" "$goal_dir" \
        "$user_message" "$has_image" "$image_path" "$idx")

    # Read model and agents from enrichment output files
    local model_file="${goal_dir}/.model-${role}${suffix}.txt"
    local agents_file="${goal_dir}/.agents-${role}${suffix}.json"
    local main_model=""
    local agents_json="{}"

    if [[ -f "$model_file" ]]; then
        main_model=$(cat "$model_file")
    fi
    if [[ -f "$agents_file" ]]; then
        agents_json=$(cat "$agents_file")
    fi

    # ─── 2. Budget gate ───
    local est_cost
    est_cost=$(genie_estimate_cost "$role" 8000 "$goal_dir")
    log_info "Budget check: ${role} estimated \$${est_cost}"
    if ! python3 "${GENIE_DIR}/budget_tracker.py" check "$goal_id" --estimate "$est_cost"; then
        log_error "Budget gate blocked spawn of ${role}"
        return 1
    fi

    # ─── 3. Generate session name + paths ───
    local session_name="${goal_id}-${role}${suffix}"
    local agent_file="${goal_dir}/agent-${role}${suffix}.md"
    local session_log="${VAULT_DIR}/11-sessions/${session_name}.md"

    # ─── 4. Worktree setup ───
    local worktree_path=""
    local project_dir="."
    local goal_context="${goal_dir}/goal-context.json"
    if [[ -f "$goal_context" ]]; then
        project_dir=$(python3 -c "import json; print(json.load(open('$goal_context')).get('project_dir','.'))" 2>/dev/null || echo ".")
    fi
    if git -C "$project_dir" rev-parse --git-dir &>/dev/null 2>&1; then
        local worktree_base="${HOME}/.hermes/worktrees/${goal_id}"
        worktree_path="${worktree_base}/${role}${suffix}"
        safe_mkdir "$worktree_path" 2>/dev/null || true
        local branch_name="${goal_id}-${role}${suffix}"
        if ! git -C "$project_dir" worktree list | grep -q "$worktree_path"; then
            git -C "$project_dir" worktree add -b "$branch_name" "$worktree_path" 2>/dev/null || true
        fi
    fi

    # ─── 5. Build claude launch command ───
    # Simple: cd project && claude --dangerously-skip-permissions --brief --name SESSION
    # Optional: --model MODEL, --agents JSON
    local claude_cmd="cd '${project_dir}' && claude --dangerously-skip-permissions --brief --name '${session_name}'"
    if [[ -n "$main_model" ]] && [[ "$main_model" != "default" ]]; then
        claude_cmd+=" --model '${main_model}'"
    fi
    if [[ -n "$agents_json" ]] && [[ "$agents_json" != "{}" ]]; then
        claude_cmd+=" --agents '${agents_json}'"
    fi

    log_info "Spawning ${role} (model: ${main_model:-default}) -> ${session_name}"

    # ─── 6. Spawn tmux session ───
    tmux new-session -d -s "$session_name" -x 140 -y 40 2>/dev/null || {
        log_error "Failed to create tmux session: $session_name"
        return 1
    }

    # Export TERM=dumb to suppress tcsetattr warnings
    tmux send-keys -t "$session_name" "export TERM=dumb" Enter

    # Launch claude
    tmux send-keys -t "$session_name" "$claude_cmd" Enter

    # ─── 7. Wait for claude to be ready ───
    session_wait_ready "$session_name" 30

    # ─── 8. Send enriched prompt via paste-buffer (handles multi-line) ───
    # CAUTION: rendering the ❯ prompt ≠ stdin is being drained. Claude Code
    # paints the welcome screen, THEN enters its input select-loop. Pasting
    # in that gap gets swallowed by the startup flush → the agent idles at
    # the welcome screen forever (root-caused 2026-06-28). So: settle, paste,
    # VERIFY the agent actually started, and retry the paste if it didn't
    # land. Verification is what makes retry safe (no double-paste).
    sleep 3  # let the TUI enter its input-reading loop (measured ~8s readiness)
    local _paste_attempts=0
    while (( _paste_attempts < 8 )); do
      tmux send-keys -t "$session_name" C-u 2>/dev/null
      if tmux load-buffer "$prompt_file" 2>/dev/null; then
        tmux paste-buffer -t "$session_name" -d 2>/dev/null
        sleep 2.5  # let the full multi-line paste settle into the input box
        tmux send-keys -t "$session_name" Enter
      else
        log_warn "load-buffer failed, using send-keys fallback"
        tmux send-keys -t "$session_name" -l "$(cat "$prompt_file")"
        tmux send-keys -t "$session_name" Enter
      fi
      sleep 3
      local _pane; _pane=$(tmux capture-pane -p -t "$session_name" -S -40 2>/dev/null || echo "")
      # Success = the agent is ACTUALLY working (spinner/thinking/tool-use).
      # Do NOT match pasted prompt text ("You are the …") or the ● / /effort
      # input-activity indicator — those appear when a paste merely lands in
      # the input unsubmitted, which gives a false positive and breaks the
      # retry loop before Enter has submitted a large multi-line prompt
      # (root-caused 2026-06-28: BSA sat idle, no spec written, timed out).
      if echo "$_pane" | grep -qiE 'thinking for|reading [0-9]+ files?|↓ [0-9]+ tokens|wibbling|crunched|shenanigan|fiddle|baked|✻ [a-z]'; then
        log_ok "Prompt pasted + agent working in '$session_name' (attempt $((_paste_attempts+1)))"
        break
      fi
      _paste_attempts=$((_paste_attempts+1))
      log_warn "paste not landed in '$session_name' (attempt ${_paste_attempts}); retrying"
      sleep 1
    done

    # ─── 9. Pipe-pane logging ───
    local raw_log="${goal_dir}/raw-logs/${session_name}.raw"
    safe_mkdir "$(dirname "$raw_log")" 2>/dev/null || mkdir -p "$(dirname "$raw_log")" 2>/dev/null || true
    tmux pipe-pane -t "$session_name" -O "bash ${GENIE_DIR}/filter.sh >> '${session_log}' 2>> '${raw_log}'" 2>/dev/null || true

    # ─── 10. Get PID + write session metadata ───
    local pid
    pid=$(tmux list-panes -t "$session_name" -F '#{pane_pid}' 2>/dev/null | head -1 || echo "")

    local session_meta="${VAULT_DIR}/11-sessions/${session_name}.meta.json"
    cat > "$session_meta" <<EOF
{
  "session_name": "${session_name}",
  "role": "${role}",
  "goal_id": "${goal_id}",
  "model": "${main_model:-default}",
  "agents": "${agents_json}",
  "pid": "${pid}",
  "started": "$(date -Iseconds)",
  "agent_file": "${agent_file}",
  "session_log": "${session_log}",
  "worktree": "${worktree_path}",
  "prompt_file": "${prompt_file}",
  "status": "active"
}
EOF

    # ─── 11. Record cost ───
    python3 "${GENIE_DIR}/budget_tracker.py" record "$goal_id" --cost "$est_cost" --phase "${role}${suffix}" 2>/dev/null || true

    log_ok "Spawned ${role} -> ${session_name} (PID: ${pid:-unknown})"
    echo "$session_name"
}

# Main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 4 ]]; then
        log_error "Usage: $0 <role> <goal_id> <goal_dir> <goal_desc> [idx] [user_message] [has_image] [image_path]"
        exit 1
    fi
    genie_spawn "$@"
fi
