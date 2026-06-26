#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Skill Scan v7 — keyword matching + safety scoring (no regex malware)
# ============================================================

source "${HOME}/.hermes/scripts/lib/_common.sh"

SKILLS_DIR="${HOME}/.hermes/skills"
MAX_SKILLS=3

genie_skill_scan() {
  local goal="$1"
  local output_dir="$2"
  
  log_info "Scanning skills for goal: $goal"
  
  # Build keyword list from goal
  local keywords
  keywords=$(echo "$goal" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' ' ')
  
  # Score each skill
  local scored=()
  
  for skill_path in "$SKILLS_DIR"/*; do
    [[ -d "$skill_path" ]] || continue
    local skill_name
    skill_name=$(basename "$skill_path")
    
    # Read SKILL.md for keywords
    local skill_text=""
    if [[ -f "$skill_path/SKILL.md" ]]; then
      skill_text=$(cat "$skill_path/SKILL.md" | tr '[:upper:]' '[:lower:]' | head -200)
    fi
    
    # Simple relevance scoring
    local score=0
    for kw in $keywords; do
      # Skip short words
      [[ ${#kw} -ge 3 ]] || continue
      # Count occurrences
      local count
      count=$(echo "$skill_text" | grep -o "$kw" | wc -l)
      score=$((score + count))
    done
    
    # Safety scoring (AST-level: check for dangerous patterns in text)
    local safety_score=100
    
    # Pattern checks (lightweight text scan, not regex malware)
    if echo "$skill_text" | grep -qE 'eval\s*\(|exec\s*\(|os\.system|subprocess\.call|subprocess\.Popen'; then
      safety_score=$((safety_score - 30))
      log_warn "  $skill_name: contains eval/exec patterns (-30 safety)"
    fi
    if echo "$skill_text" | grep -qE 'curl.*\|.*bash|wget.*\|.*sh|base64.*-d|b64decode'; then
      safety_score=$((safety_score - 40))
      log_warn "  $skill_name: contains pipe-to-shell patterns (-40 safety)"
    fi
    if echo "$skill_text" | grep -qE 'import\s+pickle|import\s+ctypes|pickle\.loads'; then
      safety_score=$((safety_score - 20))
      log_warn "  $skill_name: contains pickle/ctypes (-20 safety)"
    fi
    
    # Skip if safety below threshold
    if [[ $safety_score -lt 50 ]]; then
      log_warn "  $skill_name: SKIPPED (safety score: $safety_score)"
      continue
    fi
    
    # Normalize score by safety
    local final_score=$((score * safety_score / 100))
    
    scored+=("$final_score:$skill_name:$skill_path")
  done
  
  # Sort by score descending, take top N
  local selected=()
  local count=0
  
  for item in $(printf '%s\n' "${scored[@]}" | sort -t':' -k1 -nr | head -$MAX_SKILLS); do
    IFS=':' read -r score name path <<< "$item"
    log_info "  Selected: $name (score: $score)"
    
    # Generate summary (first 15 lines of description)
    local summary=""
    if [[ -f "$path/SKILL.md" ]]; then
      summary=$(grep -A 20 "^## " "$path/SKILL.md" 2>/dev/null | head -15 || echo "No description")
    fi
    
    selected+=("$name")
    
    # Write summary to staging
    local summary_file="${output_dir}/skill-summaries/${name}.md"
    safe_mkdir "$(dirname "$summary_file")"
    cat > "$summary_file" <<EOF
## Skill: ${name}
Score: ${score}
Path: ${path}

${summary}
EOF
    
    count=$((count + 1))
  done
  
  log_info "Selected $count skills"
  
  # Write summary index
  local index_file="${output_dir}/skill-summaries/index.md"
  {
    echo "# Injected Skills"
    echo ""
    for name in "${selected[@]}"; do
      echo "- [[${name}]]"
    done
  } > "$index_file"
  
  echo "${selected[*]}"
}

# Main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  goal="${1:-}"
  output_dir="${2:-/tmp/genie-skills}"
  if [[ -z "$goal" ]]; then
    log_error "Usage: $0 'goal description' [output_dir]"
    exit 1
  fi
  genie_skill_scan "$goal" "$output_dir"
fi
