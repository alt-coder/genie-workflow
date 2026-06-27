#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Common library for Genie Pipeline v7
# ============================================================

readonly GENIE_VERSION="7.0.0"
readonly GENIE_DIR="${HOME}/.hermes/scripts"
readonly GENIE_LIB="${GENIE_DIR}/lib"
readonly STAGING_DIR="${HOME}/.hermes/staging"
readonly VAULT_DIR="${OBSIDIAN_VAULT_PATH:-${HOME}/Documents/Obsidian Vault}"
readonly BUDGET_DEFAULT=50.0
readonly WAITFOR_TTL=300
readonly BLOCKED_MINUTES_CAP=120
readonly CONTEXT_WINDOW_SOFT=120000
readonly CONTEXT_WINDOW_HARD=180000

# Colors (only if TTY)
if [[ -t 1 ]]; then
  readonly C_RED='\033[0;31m'
  readonly C_GREEN='\033[0;32m'
  readonly C_YELLOW='\033[1;33m'
  readonly C_CYAN='\033[0;36m'
  readonly C_VIOLET='\033[0;35m'
  readonly C_RESET='\033[0m'
else
  readonly C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_VIOLET='' C_RESET=''
fi

log_info()  { echo -e "${C_CYAN}[INFO]${C_RESET} $*" >&2; }
log_warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*" >&2; }
log_error() { echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2; }
log_ok()    { echo -e "${C_GREEN}[OK]${C_RESET} $*" >&2; }
log_v()     { echo -e "${C_VIOLET}[GENIE]${C_RESET} $*" >&2; }

# Generate safe goal ID from timestamp + slug
gen_goal_id() {
  local title="${1:-untitled}"
  local slug
  slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-$//')
  echo "$(date +%Y%m%d-%H%M%S)-${slug:0:40}"
}

# Validate path is within allowed directories
validate_path() {
  local path="$1"
  local abs
  abs=$(realpath -m "$path" 2>/dev/null || readlink -f "$path" 2>/dev/null || echo "$path")
  case "$abs" in
    "${STAGING_DIR}"*|"${VAULT_DIR}"*|"/tmp/genie"*) return 0 ;;
    *) log_error "Path outside allowed dirs: $abs"; return 1 ;;
  esac
}

# Safe mkdir with validation
safe_mkdir() {
  local dir="$1"
  validate_path "$dir" || return 1
  mkdir -p "$dir"
}

# Check if tmux session exists
tmux_has_session() {
  tmux has-session -t "$1" 2>/dev/null
}

# Wait-for with TTL (avoids deadlock)
waitfor_with_ttl() {
  local channel="$1"
  local ttl="${2:-$WAITFOR_TTL}"
  local start
  start=$(date +%s)
  
  log_info "Waiting for channel: $channel (TTL: ${ttl}s)"
  
  while true; do
    if tmux wait-for -S "$channel" 2>/dev/null; then
      return 0
    fi
    
    local now
    now=$(date +%s)
    if (( now - start >= ttl )); then
      log_warn "wait-for timeout on channel: $channel"
      return 1
    fi
    sleep 2
  done
}

# Send signal to wait-for channel
signal_waitfor() {
  local channel="$1"
  tmux wait-for -S "$channel" 2>/dev/null || true
}

# Write JSON completion marker
write_completion_marker() {
  local goal_dir="$1"
  local role="$2"
  local status="$3"
  local exit_code="${4:-0}"
  local marker_file="${goal_dir}/completion-markers/${role}.done.json"
  
  safe_mkdir "$(dirname "$marker_file")"
  
  cat > "$marker_file" <<EOF
{"status":"${status}","exit_code":${exit_code},"timestamp":"$(date -Iseconds)","role":"${role}"}
EOF
}

# Read completion marker
read_completion_marker() {
  local marker_file="$1"
  if [[ -f "$marker_file" ]]; then
    cat "$marker_file"
  else
    echo '{"status":"pending","exit_code":-1}'
  fi
}

# Check if all markers for a phase are done
phase_done() {
  local goal_dir="$1"
  shift
  for role in "$@"; do
    local marker="${goal_dir}/completion-markers/${role}.done.json"
    local status
    status=$(read_completion_marker "$marker" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
    if [[ "$status" != "done" ]]; then
      return 1
    fi
  done
  return 0
}

# Cleanup function — kills orphaned tmux sessions + worktrees on failure exit
genie_cleanup() {
  local goal_dir="${1:-}"
  local exit_code=$?
  local goal_id
  goal_id=$(basename "$goal_dir" 2>/dev/null || echo "")

  log_info "Cleanup (exit=$exit_code) for: ${goal_id:-unknown}"

  # Success exit: leave worktrees for merge/inspection
  [[ $exit_code -eq 0 ]] && return 0

  # Failure exit: kill orphaned tmux sessions for this goal
  if [[ -n "$goal_id" ]]; then
    local sessions
    sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${goal_id}-" || true)
    for sess in $sessions; do
      tmux kill-session -t "$sess" 2>/dev/null || true
      log_warn "Killed orphaned session: $sess"
    done

    # Remove orphaned git worktrees
    local worktree_base="${HOME}/.hermes/worktrees/${goal_id}"
    if [[ -d "$worktree_base" ]]; then
      local project_dir
      project_dir=$(python3 -c "import json; print(json.load(open('${goal_dir}/goal-context.json')).get('project_dir','.'))" 2>/dev/null || echo ".")
      if git -C "$project_dir" rev-parse --git-dir &>/dev/null 2>&1; then
        git -C "$project_dir" worktree prune 2>/dev/null || true
      fi
      for wt in "$worktree_base"/*; do
        [[ -d "$wt" ]] || continue
        git worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
      done
      rmdir "$worktree_base" 2>/dev/null || true
      log_warn "Cleaned worktrees: $worktree_base"
    fi
  fi

  # Crash dump
  if [[ -n "$goal_dir" && -d "$goal_dir/raw-logs" ]]; then
    local dump="${goal_dir}/raw-logs/crash-$(date +%s).log"
    echo "Crash dump at $(date -Iseconds) (exit: $exit_code)" > "$dump"
    echo "Goal dir: $goal_dir" >> "$dump"
  fi
}

# Install EXIT trap for cleanup (EXIT fires on normal + signal-induced exit)
trap_cleanup() {
  local goal_dir="$1"
  trap 'genie_cleanup "'"${goal_dir}"'"' EXIT
}

# Export all functions for sourcing
export -f log_info log_warn log_error log_ok log_v
export -f gen_goal_id validate_path safe_mkdir
export -f tmux_has_session waitfor_with_ttl signal_waitfor
export -f write_completion_marker read_completion_marker phase_done
export -f genie_cleanup trap_cleanup
