#!/usr/bin/env bash
set -euo pipefail
source "${HOME}/.hermes/scripts/lib/_common.sh"
source "${HOME}/.hermes/scripts/lib/_models.sh"

genie_extract_learnings() {
    local goal_id="$1"
    local goal_dir="$2"
    
    log_info "Extracting Zettelkasten learnings for: $goal_id"
    
    # Budget check for learn-extract
    local est_cost
    est_cost=$(genie_estimate_cost "learn-extract" 4000)
    if ! python3 "${GENIE_DIR}/budget_tracker.py" check "$goal_id" --estimate "$est_cost"; then
        log_warn "Budget exhausted. Skipping learning extraction."
        return 1
    fi
    
    # Gather source material
    local sources=""
    for f in "${goal_dir}"/agent-*.md; do
        [[ -f "$f" ]] || continue
        sources="${sources}\n\n=== $(basename "$f") ===\n$(head -100 "$f")"
    done
    
    # Extract via Claude Code -p
    local extract_prompt="Read the following session outputs and extract 1-3 atomic Zettelkasten learnings. Each learning must be: one concept, actionable, linked to source. Output as JSON array: [{\"title\":\"...\",\"insight\":\"...\",\"tags\":[\"...\"],\"source\":\"...\"}]"
    
    local learnings_json
    learnings_json=$(echo -e "$extract_prompt\n$sources" | claude -p --model sonnet --effort high 2>/dev/null | tail -1)
    
    # Parse and write
    local count=0
    local learning_dir="${VAULT_DIR}/20-learnings"
    safe_mkdir "$learning_dir"
    
    # Try to parse as JSON
    if echo "$learnings_json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        local items
        items=$(echo "$learnings_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
        
        for i in $(seq 0 $((items - 1))); do
            local title insight tags source
            title=$(echo "$learnings_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('title','untitled'))")
            insight=$(echo "$learnings_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('insight','')))"
            tags=$(echo "$learnings_json" | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin)[$i].get('tags',[]))))")
            source=$(echo "$learnings_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('source','')))"
            
            local lid="$(date +%Y%m%d)-$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-40)"
            local lfile="${learning_dir}/${lid}.md"
            
            cat > "$lfile" <<EOF
---
id: "${lid}"
title: "${title}"
date: "$(date -Iseconds)"
tags:
$(for t in $tags; do echo "  - \"$t\""; done)
source_goal: "${goal_id}"
confidence: high
---

# ${title}

## Atomic Insight
${insight}

## Context
- Source: ${source}
- Goal: [[${goal_id}]]

## Tags
$(for t in $tags; do echo "#${t}"; done)
EOF
            count=$((count + 1))
            log_ok "Learning: ${lid}"
        done
    else
        log_warn "Failed to parse learnings JSON. Saving raw output."
        echo "$learnings_json" > "${goal_dir}/raw-logs/learnings-raw-$(date +%s).txt"
    fi
    
    # Record cost
    python3 "${GENIE_DIR}/budget_tracker.py" record "$goal_id" --cost "$est_cost" --phase "learn-extract"
    
    log_ok "Extracted ${count} learnings to ${learning_dir}"
    
    # Update MOC
    local moc="${VAULT_DIR}/40-meta/moc-sessions.md"
    if ! grep -q "$goal_id" "$moc" 2>/dev/null; then
        echo "- [[${goal_id}]] — $(date +%Y-%m-%d)" >> "$moc"
    fi
}

# Main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        log_error "Usage: $0 <goal_id> <goal_dir>"
        exit 1
    fi
    genie_extract_learnings "$@"
fi
