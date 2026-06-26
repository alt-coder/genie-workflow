#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# factory-stop.sh — Gracefully stop a Dark Factory session
# Ctrl-C all panes → wait 30s → force kill → cleanup worktrees → archive logs
# Usage: genie factory stop [session-name]
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh"

CONFIG_DIR="${HOME}/.hermes/factory"

# Source config for paths
if [[ -f "${CONFIG_DIR}/env" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_DIR}/env"
fi

FACTORY_LOG_DIR="${FACTORY_LOG_DIR:-${CONFIG_DIR}/logs}"
FACTORY_USE_WORKTREES="${FACTORY_USE_WORKTREES:-true}"
FACTORY_WORKTREE_DIR="${FACTORY_WORKTREE_DIR:-${CONFIG_DIR}/worktrees}"

# ── Determine session name ──
SESSION_NAME="${1:-}"

if [[ -z "$SESSION_NAME" ]]; then
    sessions="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^factory-' || true)"
    if [[ -z "$sessions" ]]; then
        log_error "No dark factory sessions found."
        exit 1
    fi
    echo "Running factory sessions:"
    echo "$sessions" | nl -ba
    echo ""
    if [[ -t 0 ]]; then
        read -rp "Enter session name to stop: " SESSION_NAME
    else
        log_error "Pass session name as argument: genie factory stop <session>"
        exit 1
    fi
fi

if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log_error "Session '${SESSION_NAME}' does not exist."
    exit 1
fi

log_v "Stopping session: ${SESSION_NAME}"

# ── Ctrl-C all panes ──
pane_ids="$(tmux list-panes -t "$SESSION_NAME" -F '#{pane_id}')"
for pane_id in $pane_ids; do
    tmux send-keys -t "$pane_id" C-c 2>/dev/null || true
done

log_v "Sent interrupt to all panes. Waiting for graceful shutdown..."

# ── Wait up to 30s for graceful exit ──
timeout=30
elapsed=0
while [[ $elapsed -lt $timeout ]]; do
    still_running=false
    for pane_id in $pane_ids; do
        pane_pid="$(tmux display-message -t "$pane_id" -p '#{pane_pid}' 2>/dev/null || true)"
        if [[ -n "$pane_pid" ]] && pgrep -P "$pane_pid" -f "claude" &>/dev/null; then
            still_running=true
            break
        fi
    done
    if [[ "$still_running" != true ]]; then
        log_ok "All agents stopped gracefully."
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

if [[ $elapsed -ge $timeout ]]; then
    log_warn "Timeout reached. Force-killing remaining panes."
fi

# ── Force kill ──
for pane_id in $pane_ids; do
    tmux send-keys -t "$pane_id" C-c 2>/dev/null || true
done
sleep 1
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
log_v "Session '${SESSION_NAME}' terminated."

# ── Cleanup worktrees ──
if [[ "$FACTORY_USE_WORKTREES" == "true" ]]; then
    worktree_session_dir="${FACTORY_WORKTREE_DIR}/${SESSION_NAME}"
    if [[ -d "$worktree_session_dir" ]]; then
        log_v "Cleaning up worktrees..."
        repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
        if [[ -n "$repo_root" ]]; then
            for wt_dir in "$worktree_session_dir"/agent-*; do
                [[ -d "$wt_dir" ]] && git -C "$repo_root" worktree remove "$wt_dir" --force 2>/dev/null || true
            done
        fi
        rmdir "$worktree_session_dir" 2>/dev/null || true
        log_ok "Worktrees cleaned up."
    fi
fi

# ── Archive logs ──
session_log_dir="${FACTORY_LOG_DIR}/${SESSION_NAME}"
archive_dir="${FACTORY_LOG_DIR}/archive"
if [[ -d "$session_log_dir" ]]; then
    safe_mkdir "$archive_dir"
    mv "$session_log_dir" "$archive_dir/" 2>/dev/null || true
    log_ok "Logs archived to ${archive_dir}/${SESSION_NAME}/"
fi

# ── Cleanup temp scripts ──
rm -f /tmp/genie-factory-prompt-${SESSION_NAME}-*.txt 2>/dev/null || true
rm -f /tmp/genie-factory-launch-${SESSION_NAME}-*.sh 2>/dev/null || true

echo ""
echo "========================================"
echo "  Dark Factory Session Stopped"
echo "========================================"
echo "  Session:   ${SESSION_NAME}"
echo "  Logs:      ${archive_dir}/${SESSION_NAME}/"
echo "========================================"
