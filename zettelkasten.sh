#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Zettelkasten Learning Extraction v2
# ============================================================
# v2 changes:
#   - Read FULL agent files (not head -100) for richer context
#   - Use hermes-spawn.sh for learn-extract (v2 interactive, not claude -p)
#   - Better error handling (no 2>/dev/null black holes)
#   - Fallback to claude -p if hermes-spawn fails
#   - Deduplicate: skip if learning with same title already exists
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh"
source "${HOME}/.hermes/scripts/lib/_models.sh"

genie_extract_learnings() {
    local goal_id="$1"
    local goal_dir="$2"

    log_info "Extracting Zettelkasten learnings for: $goal_id"

    # Budget check for learn-extract
    local est_cost
    est_cost=$(genie_estimate_cost "learn-extract" 6000)
    if ! python3 "${GENIE_DIR}/budget_tracker.py" check "$goal_id" --estimate "$est_cost"; then
        log_warn "Budget exhausted. Skipping learning extraction."
        return 1
    fi

    # Gather source material — FULL files, not truncated
    local sources=""
    local file_count=0
    for f in "${goal_dir}"/agent-*.md; do
        [[ -f "$f" ]] || continue
        # Only include non-empty files, cap at 2000 lines per file
        local content
        content=$(head -2000 "$f" 2>/dev/null || echo "")
        if [[ -n "$content" ]]; then
            sources="${sources}

=== $(basename "$f") ===
${content}"
            file_count=$((file_count + 1))
        fi
    done

    if [[ "$file_count" -eq 0 ]]; then
        log_warn "No agent output files found. Nothing to extract from."
        return 0
    fi

    log_info "Processing ${file_count} agent output files..."

    # Extract via Claude — prefer interactive spawn, fallback to -p
    local extract_prompt="Read the following session outputs from a multi-agent build pipeline and extract 1-3 atomic Zettelkasten learnings. Each learning must be: one concept, actionable, linked to source. Focus on: patterns that worked, bugs that were caught, architectural decisions, non-obvious gotchas. Output ONLY a JSON array, no markdown, no explanation:
[{\"title\":\"...\",\"insight\":\"...\",\"tags\":[\"...\"],\"source\":\"...\"}]

--- SESSION OUTPUTS ---
${sources}"

    local learnings_json=""
    local extract_temp="${goal_dir}/.learn-extract-prompt.txt"
    echo "$extract_prompt" > "$extract_temp"

    # Try hermes-spawn first (v2 interactive)
    local learn_session
    learn_session=$(bash "${GENIE_DIR}/hermes-spawn.sh" \
        "learn-extract" "$goal_id" "$goal_dir" "Extract Zettelkasten learnings" 2>&1) || {
        # Fallback: claude -p one-shot
        log_warn "hermes-spawn failed, falling back to claude -p"
        learnings_json=$(cat "$extract_temp" | claude -p --model sonnet --effort high 2>&1 | tail -1) || {
            log_error "Learning extraction failed (both spawn and fallback)"
            echo "$learnings_json" > "${goal_dir}/raw-logs/learnings-error-$(date +%s).txt" 2>/dev/null || true
            return 1
        }
    }

    # If we used hermes-spawn, read the output file
    if [[ -z "$learnings_json" ]] && [[ -f "${goal_dir}/agent-learn-extract.md" ]]; then
        learnings_json=$(cat "${goal_dir}/agent-learn-extract.md")
    fi

    # Clean up temp
    rm -f "$extract_temp" 2>/dev/null || true

    # Parse and write learnings
    local count=0
    local learning_dir="${VAULT_DIR}/20-learnings"
    safe_mkdir "$learning_dir"

    # Extract JSON from output (handle markdown code fences, prose around it)
    local clean_json
    clean_json=$(echo "$learnings_json" | python3 -c "
import sys, json, re
raw = sys.stdin.read()
# Try direct parse
try:
    json.loads(raw)
    print(raw.strip())
    sys.exit(0)
except:
    pass
# Try extracting JSON array from text
match = re.search(r'\[.*\]', raw, re.DOTALL)
if match:
    try:
        json.loads(match.group())
        print(match.group())
        sys.exit(0)
    except:
        pass
# Try removing markdown code fences
clean = re.sub(r'^\`\`\`(?:json)?\s*', '', raw, flags=re.MULTILINE)
clean = re.sub(r'\s*\`\`\`\$', '', clean, flags=re.MULTILINE)
try:
    json.loads(clean)
    print(clean.strip())
except:
    print('', end='')
" 2>/dev/null)

    if [[ -z "$clean_json" ]] || ! echo "$clean_json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        log_warn "Failed to parse learnings JSON. Saving raw output."
        safe_mkdir "${goal_dir}/raw-logs" 2>/dev/null || true
        echo "$learnings_json" > "${goal_dir}/raw-logs/learnings-raw-$(date +%s).txt"
        return 1
    fi

    # Write each learning as a Zettelkasten note
    local items
    items=$(echo "$clean_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

    for i in $(seq 0 $((items - 1))); do
        local title insight tags source
        title=$(echo "$clean_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('title','untitled'))")
        insight=$(echo "$clean_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('insight',''))")
        tags=$(echo "$clean_json" | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin)[$i].get('tags',[])))")
        source=$(echo "$clean_json" | python3 -c "import sys,json; print(json.load(sys.stdin)[$i].get('source',''))")

        local lid="$(date +%Y%m%d)-$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-40 | sed 's/-$//')"
        local lfile="${learning_dir}/${lid}.md"

        # Skip if learning with same ID already exists (dedup)
        if [[ -f "$lfile" ]]; then
            log_info "Learning ${lid} already exists. Skipping."
            continue
        fi

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

    # Record cost
    python3 "${GENIE_DIR}/budget_tracker.py" record "$goal_id" --cost "$est_cost" --phase "learn-extract" 2>/dev/null || true

    log_ok "Extracted ${count} learnings to ${learning_dir}"

    # Update learnings MOC
    local moc="${VAULT_DIR}/40-meta/moc-learnings.md"
    safe_mkdir "$(dirname "$moc")" 2>/dev/null || true
    if [[ "$count" -gt 0 ]] && ! grep -q "$goal_id" "$moc" 2>/dev/null; then
        echo "- [[${goal_id}]] — $(date +%Y-%m-%d) — ${count} learning(s)" >> "$moc"
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
