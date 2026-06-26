#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# factory-start.sh — Launch persistent Dark Factory tmux session
# Creates team layout (story/feature/epic), worktrees, starts agents.
# Usage: genie factory start <story|feature|epic> [ticket-id] [--project-dir=.] [--attach]
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh"
source "${HOME}/.hermes/scripts/lib/_roles.sh"

CONFIG_DIR="${HOME}/.hermes/factory"

die() { log_error "$*"; exit 1; }

# ── Parse args ──
team_size=""
ticket_id=""
project_dir="."
auto_attach=false

for arg in "$@"; do
    case "$arg" in
        --project-dir=*) project_dir="${arg#*=}" ;;
        --attach) auto_attach=true ;;
        story|feature|epic) team_size="$arg" ;;
        *) [[ -z "$ticket_id" ]] && ticket_id="$arg" ;;
    esac
done

[[ -z "$team_size" ]] && die "Usage: genie factory start <story|feature|epic> [ticket-id] [--project-dir=.] [--attach]"

# ── Source config ──
if [[ -f "${CONFIG_DIR}/env" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_DIR}/env"
fi

FACTORY_LOG_DIR="${FACTORY_LOG_DIR:-${CONFIG_DIR}/logs}"
FACTORY_USE_WORKTREES="${FACTORY_USE_WORKTREES:-true}"
FACTORY_WORKTREE_DIR="${FACTORY_WORKTREE_DIR:-${CONFIG_DIR}/worktrees}"
FACTORY_AUTO_PERMISSIONS="${FACTORY_AUTO_PERMISSIONS:-false}"
FACTORY_PROJECT_DIR="${FACTORY_PROJECT_DIR:-$project_dir}"

# ── Validate layout ──
layout_file="${GENIE_LIB}/team-layouts/${team_size}-team.sh"
[[ ! -f "$layout_file" ]] && die "Team layout not found: $layout_file"

# ── Session name ──
if [[ -n "$ticket_id" ]]; then
    SESSION_NAME="factory-${ticket_id}"
else
    SESSION_NAME="factory-$(date +%Y%m%d-%H%M%S)"
fi

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    die "Session '${SESSION_NAME}' already exists. Stop first: genie factory stop ${SESSION_NAME}"
fi

# ── Pane count per team size ──
case "$team_size" in
    story)   pane_count=3 ;;
    feature) pane_count=5 ;;
    epic)    pane_count=9 ;;
esac

# ── Create worktrees ──
declare -A FACTORY_PANE_WORKDIRS
export FACTORY_PANE_WORKDIRS

if [[ "$FACTORY_USE_WORKTREES" == "true" ]]; then
    if ! git -C "$FACTORY_PROJECT_DIR" rev-parse --git-dir &>/dev/null 2>&1; then
        log_warn "Not a git repo — worktrees disabled, all agents share project dir."
        FACTORY_USE_WORKTREES=false
    else
        log_v "Creating git worktrees..."
        repo_root="$(git -C "$FACTORY_PROJECT_DIR" rev-parse --show-toplevel)"
        current_branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD)"

        for i in $(seq 1 "$pane_count"); do
            worktree_path="${FACTORY_WORKTREE_DIR}/${SESSION_NAME}/agent-${i}"
            branch_name="${SESSION_NAME}-agent-${i}"
            if [[ ! -d "$worktree_path" ]]; then
                git -C "$repo_root" worktree add -b "$branch_name" "$worktree_path" "$current_branch" 2>/dev/null \
                    || log_warn "Worktree agent-${i} may already exist, skipping."
            fi
            FACTORY_PANE_WORKDIRS[$i]="$worktree_path"
        done
        log_ok "Worktrees created at ${FACTORY_WORKTREE_DIR}/${SESSION_NAME}/"
    fi
fi

# Helper for layout scripts: resolve workdir per pane
agent_workdir() {
    local pane_idx="$1"
    if [[ "$FACTORY_USE_WORKTREES" == "true" ]] && [[ -n "${FACTORY_PANE_WORKDIRS[$pane_idx]:-}" ]]; then
        echo "${FACTORY_PANE_WORKDIRS[$pane_idx]}"
    else
        echo "$FACTORY_PROJECT_DIR"
    fi
}
export -f agent_workdir

# Helper: start a claude agent in a tmux pane with role config
# Usage: start_factory_agent <pane_index> <role_name>
start_factory_agent() {
    local pane_idx="$1" role="$2"
    local model effort permission
    model=$(genie_select_model "$role")
    effort=$(genie_get_effort "$role")
    permission=$(genie_get_permission "$role")

    local workdir
    workdir=$(agent_workdir "$pane_idx")

    # Build system prompt from role file
    local role_prompt_file="${GENIE_LIB}/roles/${ROLE_PROMPTS[$role]:-}"
    local prompt_file="/tmp/genie-factory-prompt-${SESSION_NAME}-${pane_idx}.txt"
    {
        echo "You are the ${role} for Dark Factory session ${SESSION_NAME}."
        echo ""
        echo "Working directory: ${workdir}"
        echo "Follow the SAFe workflow. Create PRs with gh pr create, then enqueue with gh pr merge --auto --squash. Never merge directly."
        echo ""
        if [[ -n "$role_prompt_file" && -f "$role_prompt_file" ]]; then
            cat "$role_prompt_file"
        fi
    } > "$prompt_file"

    local claude_flags=""
    [[ "$FACTORY_AUTO_PERMISSIONS" == "true" ]] && claude_flags="--dangerously-skip-permissions"

    # Write launch script (avoids tmux quoting issues with multi-line prompts)
    local launch_script="/tmp/genie-factory-launch-${SESSION_NAME}-${pane_idx}.sh"
    cat > "$launch_script" <<EOSCRIPT
#!/bin/bash
cd "${workdir}"
PROMPT=\$(cat "${prompt_file}")
claude ${claude_flags} --model ${model} --effort ${effort} --permission-mode ${permission} --append-system-prompt "\$PROMPT"
EOSCRIPT
    chmod +x "$launch_script"

    local pane_target="${SESSION_NAME}:1.${pane_idx}"
    tmux send-keys -t "$pane_target" "bash ${launch_script}" Enter
    tmux select-pane -t "$pane_target" -T "${role}"
    log_v "  Pane ${pane_idx}: ${role} (model=${model}, effort=${effort})"
}
export -f start_factory_agent

# ── Export shared vars for layout scripts ──
export SESSION_NAME FACTORY_USE_WORKTREES FACTORY_WORKTREE_DIR FACTORY_PROJECT_DIR FACTORY_AUTO_PERMISSIONS
export GENIE_LIB

# ── Create tmux session ──
log_v "Creating tmux session: ${SESSION_NAME}"
tmux new-session -d -s "$SESSION_NAME"

# ── Source team layout (creates panes + starts agents) ──
log_v "Applying team layout: ${team_size}-team (${pane_count} panes)"
# shellcheck source=/dev/null
source "$layout_file"

# ── Set up logging ──
session_log_dir="${FACTORY_LOG_DIR}/${SESSION_NAME}"
safe_mkdir "$session_log_dir"

pane_list="$(tmux list-panes -t "$SESSION_NAME" -F '#{pane_index}:#{pane_title}')"
while IFS=: read -r pane_index pane_title; do
    log_name="${pane_title:-pane-${pane_index}}"
    log_name="$(echo "$log_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9_-')"
    tmux pipe-pane -t "${SESSION_NAME}:1.${pane_index}" \
        "bash ${HOME}/.hermes/scripts/filter.sh >> '${session_log_dir}/${log_name}.log' 2>/dev/null"
done <<< "$pane_list"

log_ok "Logging to ${session_log_dir}/"

# ── Status summary ──
echo ""
echo "========================================"
echo "  Dark Factory Session Started"
echo "========================================"
echo "  Session:    $SESSION_NAME"
echo "  Team size:  $team_size (${pane_count} agents)"
echo "  Panes:      $(tmux list-panes -t "$SESSION_NAME" | wc -l)"
echo "  Logs:       $session_log_dir/"
if [[ "$FACTORY_USE_WORKTREES" == "true" ]]; then
    echo "  Worktrees:  ${FACTORY_WORKTREE_DIR}/${SESSION_NAME}/"
fi
echo "========================================"
echo ""
echo "Commands:"
echo "  Attach:  genie factory attach ${SESSION_NAME}"
echo "  Status:  genie factory status"
echo "  Stop:    genie factory stop ${SESSION_NAME}"
echo ""

# ── Auto-attach ──
if [[ "$auto_attach" == "true" ]]; then
    exec tmux attach -t "$SESSION_NAME"
fi
