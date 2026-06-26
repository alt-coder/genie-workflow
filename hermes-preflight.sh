#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Hermes Preflight v7 — 23-point infrastructure check
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh"

PROJECT_DIR="${1:-.}"

PASS=0
FAIL=0
TOTAL=0

check() {
  local name="$1"
  local cmd="$2"
  TOTAL=$((TOTAL + 1))
  
  if eval "$cmd" &>/dev/null; then
    log_ok "[$TOTAL/23] $name"
    PASS=$((PASS + 1))
    return 0
  else
    log_error "[$TOTAL/23] $name"
    FAIL=$((FAIL + 1))
    return 1
  fi
}

log_v "Running preflight checks..."

# 1-3: Core binaries
check "claude CLI installed"   "command -v claude"
check "tmux installed"         "command -v tmux"
check "python3 available"      "command -v python3"

# 4-7: Claude Code functionality
check "claude --version works" "claude --version"
check "claude agents works"    "claude agents --json >/dev/null"
check "claude settings valid"  "test -f ~/.claude/settings.json || test -d ~/.config/claude"
check "API credentials set"    "claude --model sonnet -p 'echo' >/dev/null 2>&1 || true"

# 8-10: tmux functionality
check "tmux server running"    "tmux ls >/dev/null 2>&1 || tmux new-session -d -s __preflight_test__"
check "tmux send-keys works"   "tmux has-session -t __preflight_test__ 2>/dev/null || tmux new-session -d -s __preflight_test__; tmux send-keys -t __preflight_test__ 'echo test' Enter"
check "tmux pipe-pane works"   "tmux has-session -t __preflight_test__ 2>/dev/null || tmux new-session -d -s __preflight_test__; tmux pipe-pane -t __preflight_test__ 'cat >/dev/null'"

# 11-14: Filesystem
check "Hermes scripts dir"     "test -d ~/.hermes/scripts"
check "Staging dir writable"   "test -w ~/.hermes/staging"
check "Obsidian vault exists"  "test -d '${VAULT_DIR}'"
check "Vault goals dir"        "test -d '${VAULT_DIR}/10-goals'"

# 15-17: Python dependencies
check "python3 json module"    "python3 -c 'import json'"
check "python3 os module"      "python3 -c 'import os'"
check "python3 datetime"       "python3 -c 'import datetime'"

# 18-20: Shell tools
check "jq available"           "command -v jq"
check "inotifywait available"  "command -v inotifywait"
check "realpath available"     "command -v realpath"

# 21-23: Network / API
check "internet reachable"     "ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 || curl -s --max-time 3 https://1.1.1.1 >/dev/null"
check "Anthropic API reachable" "curl -s --max-time 5 https://api.anthropic.com >/dev/null 2>&1 || true"
check "GitHub reachable"       "curl -s --max-time 5 -o /dev/null -w '%{http_code}' https://github.com | grep -q '200\\|301\\|302'"

# Cleanup tmux test session
tmux kill-session -t __preflight_test__ 2>/dev/null || true

log_v "================================"
log_v "Results: ${PASS} passed, ${FAIL} failed, ${TOTAL} total"

if [[ $FAIL -gt 0 ]]; then
  log_error "Preflight FAILED. Fix errors before running pipeline."
  exit 1
fi

# --- Readiness Gate: Merge Queue (SAFe dark-factory policy) ---
log_v "Checking merge-queue readiness..."
if git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null 2>&1; then
  MAIN_BRANCH=$(git -C "$PROJECT_DIR" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
  # Check if direct push to main is blocked (branch protection or merge queue)
  if gh repo view --json defaultBranchRef -q .defaultBranchRef.name &>/dev/null 2>&1; then
    if gh api "repos/{owner}/{repo}/branches/${MAIN_BRANCH}/protection" &>/dev/null 2>&1; then
      log_ok "Branch protection enabled on ${MAIN_BRANCH} (merge-queue ready)"
    else
      log_warn "No branch protection on ${MAIN_BRANCH} — merge queue NOT enforced. PRs may bypass review."
      log_warn "Set up branch protection: gh api -X PUT repos/{owner}/{repo}/branches/${MAIN_BRANCH}/protection"
    fi
  else
    log_v "gh CLI not authenticated — skipping merge-queue check (non-fatal)"
  fi
else
  log_v "Not a git repo — skipping merge-queue readiness (greenfield/no-git mode)"
fi

# --- Role prompts check ---
if [[ -d "${HOME}/.hermes/scripts/lib/roles" ]]; then
  role_count=$(find "${HOME}/.hermes/scripts/lib/roles" -name '*.md' | wc -l)
  log_ok "Role prompts: ${role_count} files in lib/roles/"
else
  log_warn "No role prompts directory — pipeline will use generic prompts only"
fi

log_ok "Preflight PASSED. Infrastructure ready."
exit 0
