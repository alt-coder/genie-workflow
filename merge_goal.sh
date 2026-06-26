#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Merge Goal v7 — post-hoc merger with mtime-safe concatenation
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh"

genie_merge_goal() {
  local goal_dir="$1"
  local goal_id="$2"
  
  log_info "Merging goal: $goal_id"
  
  local merged_file="${VAULT_DIR}/10-goals/${goal_id}.md"
  safe_mkdir "$(dirname "$merged_file")"
  
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
  
  # Build merged file
  {
    echo "---"
    echo "id: \"$goal_id\""
    echo "title: \"$(grep -oP '(?<=^# ).*' "${goal_dir}/agent-architect.md" 2>/dev/null || echo "Untitled Goal")\""
    echo "status: merged"
    echo "merged_at: \"$(date -Iseconds)\""
    echo "---"
    echo ""
    echo "# Goal: $goal_id"
    echo ""
    
    # Phase 0: Plan (from architect)
    if [[ -f "${goal_dir}/agent-architect.md" ]]; then
      echo "## Plan"
      echo ""
      cat "${goal_dir}/agent-architect.md"
      echo ""
    fi
    
    # Phase 1: Critiques
    if ls "${goal_dir}"/agent-critique-*.md 1>/dev/null 2>&1; then
      echo "## Critiques"
      echo ""
      for critique in "${goal_dir}"/agent-critique-*.md; do
        local n
        n=$(basename "$critique" | sed 's/agent-critique-\([0-9]*\).md/\1/')
        echo "### Critique $n"
        echo ""
        cat "$critique"
        echo ""
      done
    fi
    
    # Phase 1b: Synthesizer
    if [[ -f "${goal_dir}/agent-synthesizer.md" ]]; then
      echo "## Synthesis"
      echo ""
      cat "${goal_dir}/agent-synthesizer.md"
      echo ""
    fi
    
    # Phase 1c: Tiebreaker (if exists)
    if [[ -f "${goal_dir}/agent-tiebreaker.md" ]]; then
      echo "## Tiebreaker Decision"
      echo ""
      cat "${goal_dir}/agent-tiebreaker.md"
      echo ""
    fi
    
    # Phase 2: Implementor
    if [[ -f "${goal_dir}/agent-implementor.md" ]]; then
      echo "## Implementation"
      echo ""
      cat "${goal_dir}/agent-implementor.md"
      echo ""
    fi
    
    # Phase 2: Tester
    if [[ -f "${goal_dir}/agent-tester.md" ]]; then
      echo "## Test Results"
      echo ""
      cat "${goal_dir}/agent-tester.md"
      echo ""
    fi
    
    # Phase 2: Reviewer
    if [[ -f "${goal_dir}/agent-reviewer.md" ]]; then
      echo "## Code Review"
      echo ""
      cat "${goal_dir}/agent-reviewer.md"
      echo ""
    fi
    
    # Phase 3: Final Critique
    if ls "${goal_dir}"/agent-final-critique-*.md 1>/dev/null 2>&1; then
      echo "## Final Critique"
      echo ""
      for critique in "${goal_dir}"/agent-final-critique-*.md; do
        local n
        n=$(basename "$critique" | sed 's/agent-final-critique-\([0-9]*\).md/\1/')
        echo "### Final Critique $n"
        echo ""
        cat "$critique"
        echo ""
      done
    fi
    
    # Phase 4: Decisions & Blockers
    if [[ -f "${goal_dir}/agent-decisions.md" ]]; then
      echo "## Decisions & Blocker Log"
      echo ""
      cat "${goal_dir}/agent-decisions.md"
      echo ""
    fi
    
    # Status
    echo "---"
    echo ""
    echo "## Status"
    echo "- goal_id: $goal_id"
    echo "- merged: $(date -Iseconds)"
    echo ""
  } > "$merged_file"
  
  log_ok "Merged to: $merged_file"
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
