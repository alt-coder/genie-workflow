# Bash Pitfalls — genie v1 Development

Bash traps discovered while building genie v1. All are general bash issues, not genie-specific.

## 1. Missing `declare -A` on Associative Arrays

**Symptom:** `unbound variable` error under `set -euo pipefail` when accessing an associative array element.

**Cause:** Bash requires `declare -A` before using associative array syntax. Without it, `arr[key]=value` is interpreted as a *indexed* array with a non-numeric key, which fails silently or errors under `set -u`.

**Bad:**
```bash
set -euo pipefail
MODEL_TOKEN_LIMITS=([sonnet]=200000 [opus]=200000)   # ← no declare -A
echo "${MODEL_TOKEN_LIMITS[sonnet]}"                  # ← unbound variable
```

**Fix:**
```bash
declare -A MODEL_TOKEN_LIMITS=([sonnet]=200000 [opus]=200000)
echo "${MODEL_TOKEN_LIMITS[sonnet]}"                  # ← works
```

**Rule:** Always use `declare -A` before any associative array assignment. Check existing scripts that use `arr=([k]=v)` syntax — if `declare -A` is missing, it's a latent bug under `set -u`.

**Actual occurrence:** `_models.sh` had `MODEL_TOKEN_LIMITS=` and `MODEL_COSTS=` without `declare -A`. Worked until `set -u` was enabled, then crashed. Fixed by adding `declare -A` prefix.

## 2. `readonly` Variable Conflicts in Sourced Files

**Symptom:** `bash: GENIE_DIR: readonly variable` when sourcing a shared lib that also defines the same variable.

**Cause:** `_common.sh` defines `readonly GENIE_DIR="${HOME}/.hermes/scripts"`. Any script that sources `_common.sh` AND also defines `GENIE_DIR` (even with the same value) triggers a readonly conflict.

**Bad:**
```bash
# _common.sh
readonly GENIE_DIR="${HOME}/.hermes/scripts"

# genie.sh (sources _common.sh)
readonly GENIE_DIR="${HOME}/.hermes/scripts"   # ← ERROR: readonly variable
source "${HOME}/.hermes/scripts/lib/_common.sh"
```

**Fix:** Define `readonly` variables in ONE place only (the shared lib). Sourcing scripts must NOT redefine them:

```bash
# genie.sh
source "${HOME}/.hermes/scripts/lib/_common.sh"
# Do NOT redefine GENIE_DIR — _common.sh owns it
```

**Rule:** When a shared lib defines `readonly` variables, sourcing scripts must never redefine those names. Audit all scripts that `source _common.sh` for duplicate `readonly` declarations.

**Actual occurrence:** `genie.sh` and `factory-start.sh` both had `readonly GENIE_DIR=...` that conflicted with `_common.sh`. Fixed by removing the duplicate definitions.

## 3. `git commit` Without Identity

**Symptom:** `fatal: empty ident name not allowed` when committing in a fresh repo.

**Cause:** Global `user.name` and `user.email` not set. `gh auth` sets up auth but not git identity.

**Fix:**
```bash
git config user.name "your-gh-username"
git config user.email "your-gh-username@users.noreply.github.com"
```

Use GitHub's noreply email to keep real email private. Set per-repo (not `--global`) if you want different identities per repo.

## 4. Genie Pipeline Spawn Failure (Cascading Bash Error)

**Symptom:** `hermes-spawn.sh: line N: syntax error near unexpected token '('` during Phase 1a (BSA spawn). The reported line (e.g. 118 — `Your working directory (git worktree): ${worktree_path}`) is a red herring. The real failure is usually upstream in `_models.sh` (sourced by `_roles.sh` → sourced by `hermes-spawn.sh`). The model selection functions (v2/v3) may fail due to:
- Missing `settings.json` fields (provider env vars) causing `genie_select_model` to error
- Python subprocess errors (model capability probing hitting API issues)
- Uninitialized variables from the selection chain propagating as syntax errors

**Bash confuses the line number** because the error originated in a sourced file, not the one listed.

**Workaround:** When genie fails at spawn, fall back to direct fix — manually apply the change and run tests. The user has accepted this pattern (2026-06-27 session: 9router combo vision bug fixed manually after genie spawn crashed). Re-attempt genie only if the selection scripts or settings.json have been repaired.

## 5. No Process-Level Lock → Concurrent Runs Corrupt State

**Symptom:** `[BUDGET] ERROR: Goal 20260627-131940 not initialized` — QAS phase blocked because `hermes-spawn.sh` passed a stale goal_id from a previous overlapping run to `budget_tracker.py check`.

**Cause:** `gen_goal_id()` uses `date +%Y%m%d-%H%M%S` + slug. Two runs started seconds apart get different IDs but share staging paths, tmux session namespace, and worktree base. The second run's agents can pick up the first run's goal_id from environment, stale files, or process table lookups.

**Fix:** `flock`-based exclusive lock in `genie.sh`:

```bash
local genie_lock="${STAGING_DIR}/.genie.lock"
exec 9>"$genie_lock"
if ! flock -n 9; then
    log_error "Another genie run is active. Use --force to override."
    exit 1
fi
echo $$ > "$genie_lock"
```

`flock -n` is non-blocking — returns immediately if lock held. fd 9 stays open for script lifetime; closing on exit releases lock automatically. `--force` flag skips lock for recovery.

**Rule:** Any long-running bash script that creates per-run directories with timestamp-based IDs MUST use `flock` to prevent concurrent execution. The lock file lives in the shared staging directory.

**Actual occurrence:** 2026-06-27 — two genie runs on CASOL-2 goal created goal_ids 131940 and 132240. QAS used 131940 (stale) instead of 132240 (current), budget tracker had no file for 131940, spawn blocked.

## 6. `trap_cleanup` Defined But Never Called → Orphaned Worktrees/Tmux

**Symptom:** 42 orphaned git worktrees + 7 zombie tmux sessions from failed/aborted genie runs. No cleanup on failure exit.

**Cause:** `_common.sh` defined `genie_cleanup()` and `trap_cleanup()` but `genie.sh` never called `trap_cleanup`. Additionally, `genie_cleanup` only wrote a crash dump — didn't kill tmux sessions or remove worktrees.

**Fix:** Two changes:

1. `genie.sh` now calls `trap_cleanup "$goal_dir"` after goal dir creation (after `safe_mkdir "${goal_dir}/context"`).

2. `genie_cleanup()` enhanced — captures `$?` (exit code), and on non-zero exit:
   - Kills all tmux sessions matching `${goal_id}-*`
   - Removes git worktrees under `~/.hermes/worktrees/${goal_id}/`
   - Runs `git worktree prune`
   - On zero exit: leaves everything for merge/inspection

```bash
genie_cleanup() {
  local goal_dir="${1:-}"
  local exit_code=$?
  local goal_id
  goal_id=$(basename "$goal_dir" 2>/dev/null || echo "")
  [[ $exit_code -eq 0 ]] && return 0  # success — leave for merge
  # failure — kill orphans:
  for sess in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${goal_id}-" || true); do
    tmux kill-session -t "$sess" 2>/dev/null || true
  done
  # ... worktree cleanup ...
}
```

**Rule:** Every bash script that spawns tmux sessions or git worktrees MUST install an EXIT trap that cleans them up on failure. The trap must capture `$?` to distinguish success (leave artifacts) from failure (kill orphans). Trap on `EXIT` only — it fires on both normal and signal-induced exit, avoiding double-fire from `EXIT INT TERM`.

**Actual occurrence:** 2026-06-27 — 42 worktrees + 7 zombie tmux sessions accumulated from multiple failed genie runs. Manual cleanup required: `pkill`, `tmux kill-session`, `git worktree remove --force`, `git branch -D`.
