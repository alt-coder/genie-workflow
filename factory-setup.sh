#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# factory-setup.sh — One-time Dark Factory environment setup
# Validates prereqs, creates config, checks merge-queue readiness.
# Usage: genie factory setup [--project-dir=.]
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh"
source "${HOME}/.hermes/scripts/lib/_roles.sh"

CONFIG_DIR="${HOME}/.hermes/factory"
PROJECT_DIR="${1:-.}"

die() { log_error "$*"; exit 1; }
warn() { log_warn "$*"; }

# ── 1: Prerequisites ──
log_v "Checking prerequisites..."
missing=()
for cmd in tmux claude git gh; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
done
[[ ${#missing[@]} -gt 0 ]] && die "Missing: ${missing[*]}. Install before setup."
log_ok "All prerequisites found."

# ── 2: Config dirs ──
log_v "Creating config at ${CONFIG_DIR}..."
safe_mkdir "${CONFIG_DIR}/logs"
safe_mkdir "${CONFIG_DIR}/worktrees"

# ── 3: Env template ──
ENV_FILE="${CONFIG_DIR}/env"
if [[ ! -f "$ENV_FILE" ]]; then
    cp "${GENIE_LIB}/factory-env.template" "$ENV_FILE"
    log_ok "Copied env template → ${ENV_FILE}"
    log_info "Edit it: $EDITOR $ENV_FILE"
else
    log_v "Config already exists, skipping."
fi

# ── 4: Merge-queue readiness gate ──
log_v "Verifying merge-queue readiness gate..."

if ! git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null 2>&1; then
    log_warn "Not a git repo — merge-queue gate skipped (greenfield/no-git mode)."
    log_warn "Dark factory will operate in no-PR mode."
    SKIP_MERGE_GATE=true
else
    SKIP_MERGE_GATE=false
    # shellcheck source=/dev/null
    [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
    MAIN_BRANCH="${FACTORY_MAIN_BRANCH:-main}"

    repo_slug="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||; s|\.git$||' || true)"
    if [[ -z "$repo_slug" ]]; then
        log_warn "No GitHub remote — merge-queue gate skipped."
        SKIP_MERGE_GATE=true
    fi
fi

if [[ "$SKIP_MERGE_GATE" == "false" ]]; then
    owner="${repo_slug%%/*}"
    repo="${repo_slug##*/}"

    merge_queue_required=false
    merge_queue_workflow=false

    # Method 1: rulesets API
    rulesets="$(gh api "repos/${owner}/${repo}/rulesets" 2>/dev/null || echo "[]")"
    ruleset_ids="$(echo "$rulesets" | python3 -c "
import sys, json
for rs in json.load(sys.stdin):
    print(rs.get('id', ''))
" 2>/dev/null || true)"

    for rs_id in $ruleset_ids; do
        [[ -z "$rs_id" ]] && continue
        rs_detail="$(gh api "repos/${owner}/${repo}/rulesets/${rs_id}" 2>/dev/null || echo "{}")"
        has_mq="$(echo "$rs_detail" | python3 -c "
import sys, json
d = json.load(sys.stdin)
rules = d.get('rules', [])
conditions = d.get('conditions', {})
ref_name = conditions.get('ref_name', {})
includes = ref_name.get('include', [])
branch_match = any('${MAIN_BRANCH}' in inc or inc == '~DEFAULT_BRANCH' for inc in includes)
has_merge_queue = any(r.get('type') == 'merge_queue' for r in rules)
print('yes' if (has_merge_queue and branch_match) else 'no')
" 2>/dev/null || echo "no")"
        if [[ "$has_mq" == "yes" ]]; then
            merge_queue_required=true
            log_ok "Merge queue ruleset found targeting '${MAIN_BRANCH}'."
            break
        fi
    done

    # Method 2: branch protection fallback
    if [[ "$merge_queue_required" != true ]]; then
        protection="$(gh api "repos/${owner}/${repo}/branches/${MAIN_BRANCH}/protection" 2>/dev/null || echo "{}")"
        has_mq_protection="$(echo "$protection" | python3 -c "
import sys, json
d = json.load(sys.stdin)
mq = d.get('required_merge_queue', None)
print('yes' if mq is not None else 'no')
" 2>/dev/null || echo "no")"
        if [[ "$has_mq_protection" == "yes" ]]; then
            merge_queue_required=true
            log_ok "Merge queue in branch protection on '${MAIN_BRANCH}'."
        fi
    fi

    # Check merge_group trigger in workflows
    workflow_dir="$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)/.github/workflows"
    if [[ -d "$workflow_dir" ]] && grep -rl 'merge_group' "$workflow_dir"/*.yml 2>/dev/null | head -1 >/dev/null 2>&1; then
        merge_queue_workflow=true
        log_ok "merge_group trigger found in workflows."
    fi

    if [[ "$merge_queue_required" != true ]] || [[ "$merge_queue_workflow" != true ]]; then
        echo ""
        echo "READINESS GATE FAILED"
        echo "Dark Factory requires merge queue enforcement for safe parallel merges."
        echo ""
        [[ "$merge_queue_required" != true ]] && echo "  - Enable merge queue on '${MAIN_BRANCH}' via rulesets or branch protection"
        [[ "$merge_queue_workflow" != true ]] && echo "  - Add 'merge_group' trigger to .github/workflows/"
        echo ""
        die "See: genie-pipeline SKILL.md → Merge Queue Policy"
    fi
fi

# ── 5: Agent teams env var ──
if [[ -z "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]]; then
    warn "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS not set."
    warn "Set it: export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
fi

# ── 6: Summary ──
echo ""
echo "========================================"
echo "  Dark Factory Setup Complete"
echo "========================================"
echo "  Config:     ${CONFIG_DIR}"
echo "  Logs:       ${CONFIG_DIR}/logs"
echo "  Worktrees:  ${CONFIG_DIR}/worktrees"
[[ "$SKIP_MERGE_GATE" == "false" ]] && echo "  Repo:       ${repo_slug}" && echo "  Branch:     ${MAIN_BRANCH}"
echo "  Roles:      11 SAFe prompts in lib/roles/"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Edit ${ENV_FILE} with your settings"
echo "  2. genie factory start <story|feature|epic> [ticket-id]"
