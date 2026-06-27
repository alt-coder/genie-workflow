#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Merge Goal v2 — post-hoc merger with mtime-safe concatenation
# ============================================================
# v2 changes:
#   - Fixed: critic naming (critique→critic, final-critique→critic-final)
#   - Added: BSA spec, QAS verdict, SecEng, SysArch, RTE/PR sections
#   - Removed: stale v1 roles (tester, reviewer, decisions)
#   - Added: goal_desc in frontmatter, PR link extraction from RTE
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh"

genie_merge_goal() {
  local goal_dir="$1"
  local goal_id="$2"

  log_info "Merging goal: $goal_id"

  local merged_file="${VAULT_DIR}/10-goals/${goal_id}.md"
  safe_mkdir "$(dirname "$merged_file")"

  # Read goal description from context
  local goal_desc="Untitled Goal"
  if [[ -f "${goal_dir}/goal-context.json" ]]; then
    goal_desc=$(python3 -c "import json; print(json.load(open('${goal_dir}/goal-context.json')).get('description','Untitled Goal'))" 2>/dev/null || echo "Untitled Goal")
  fi

  # Check if merged file exists and is newer than all agent files
  if [[ -f "$merged_file" ]]; then
    local merged_mtime
    merged_mtime=$(stat -c %Y "$merged_file" 2>/dev/null || stat -f %m "$merged_file")
    local needs_merge=false

    for agent_file in "$goal_dir"/agent-*.md; do
      [[ -f "$agent_file" ]] || continue
      local agent_mtime
      agent_mtime=$(stat -c %Y "$agent_file" 2>/dev/null || stat -f %m "$agent_file")
      if [[ $agent_mtime -gt $merged_mtime ]]; then
        needs_merge=true
        break
      fi
    done

    if [[ "$needs_merge" == "false" ]]; then
      log_info "Merged file up to date. Skipping."
      echo "$merged_file"
      return 0
    fi
  fi

  # Helper: emit section if file exists
  emit_section() {
    local title="$1"
    local file="$2"
    if [[ -f "$file" ]] && [[ -s "$file" ]]; then
      echo "## ${title}"
      echo ""
      cat "$file"
      echo ""
    fi
  }

  # Helper: emit numbered sections (critic-1, critic-2, etc.)
  emit_numbered() {
    local title_prefix="$1"
    local pattern="$2"
    if ls "$goal_dir"/${pattern} 1>/dev/null 2>&1; then
      echo "## ${title_prefix}"
      echo ""
      for f in "$goal_dir"/${pattern}; do
        local n
        n=$(basename "$f" | sed -E 's/agent-[^-]+-([0-9]+)\.md/\1/')
        echo "### ${title_prefix} ${n}"
        echo ""
        cat "$f"
        echo ""
      done
    fi
  }

  # Build merged file
  {
    echo "---"
    echo "id: \"$goal_id\""
    echo "title: \"$goal_desc\""
    echo "status: merged"
    echo "merged_at: \"$(date -Iseconds)\""
    echo "---"
    echo ""
    echo "# Goal: $goal_id"
    echo ""
    echo "**Description:** ${goal_desc}"
    echo ""

    # Phase 1a: BSA Spec
    emit_section "BSA Spec" "${goal_dir}/agent-bsa.md"

    # Phase 1b: Critics (parallel)
    emit_numbered "Critique" "agent-critic-[0-9]*.md"

    # Phase 1b: Synthesizer
    emit_section "Synthesis" "${goal_dir}/agent-synthesizer.md"

    # Phase 1b: Architect Plan
    emit_section "Architect Plan" "${goal_dir}/agent-architect.md"

    # Phase 2: Implementation
    emit_section "Implementation" "${goal_dir}/agent-implementor.md"

    # Phase 3: QAS Verdict
    emit_section "QAS Verdict" "${goal_dir}/agent-qas.md"

    # Phase 4: System Architect Review (complexity-triggered)
    emit_section "System Architect Review" "${goal_dir}/agent-system-architect.md"

    # Phase 4: Security Engineer (security-sensitive)
    emit_section "Security Review" "${goal_dir}/agent-security-engineer.md"

    # Phase 5: Final Critique (post-build, holistic)
    emit_numbered "Final Critique" "agent-critic-final-[0-9]*.md"

    # Phase 6: RTE / PR
    emit_section "PR Creation" "${goal_dir}/agent-rte.md"

    # Tiebreaker (if exists)
    emit_section "Tiebreaker Decision" "${goal_dir}/agent-tiebreaker.md"

    # Status footer
    echo "---"
    echo ""
    echo "## Status"
    echo "- goal_id: $goal_id"
    echo "- merged: $(date -Iseconds)"
    echo "- description: $goal_desc"
    echo ""
  } > "$merged_file"

  log_ok "Merged to: $merged_file ($(wc -c < "$merged_file") bytes)"
  echo "$merged_file"
}

# Main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  goal_dir="${1:-}"
  goal_id="${2:-}"
  if [[ -z "$goal_dir" || -z "$goal_id" ]]; then
    log_error "Usage: $0 <goal_dir> <goal_id>"
    exit 1
  fi
  genie_merge_goal "$goal_dir" "$goal_id"
fi
