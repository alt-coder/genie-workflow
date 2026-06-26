#!/usr/bin/env bash
set -euo pipefail
source "${HOME}/.hermes/scripts/lib/_common.sh"

# ============================================================
# Pattern Discovery v1 — SAFe mandate + Zettelkasten cross-session
# Searches: specs/, codebase, session history, Obsidian learnings
# Output: staging/<goal_id>/context/pattern-discovery.md
# ============================================================

usage() { echo "Usage: $0 <goal_desc> <goal_dir> [project_dir]" >&2; exit 1; }
[[ $# -ge 2 ]] || usage

goal_desc="$1"
goal_dir="$2"
project_dir="${3:-.}"
context_dir="${goal_dir}/context"
safe_mkdir "$context_dir"

out="${context_dir}/pattern-discovery.md"
keywords=$(echo "$goal_desc" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '\n' | grep -v '^$' | head -10)

{
  echo "---"
  echo "title: Pattern Discovery"
  echo "goal: \"${goal_desc}\""
  echo "generated: $(date -Iseconds)"
  echo "---"
  echo ""
  echo "# Pattern Discovery"
  echo ""
  echo "Keywords: $(echo "$keywords" | tr '\n' ' ')"
  echo ""

  # --- 1. Specs directory (SAFe) ---
  echo "## 1. Past Specs"
  echo ""
  if [[ -d "${project_dir}/specs" ]]; then
    found=0
    for kw in $keywords; do
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        echo "- [[$(basename "$f" .md)]] — matched \`$kw\`"
        found=1
      done < <(grep -rl "$kw" "${project_dir}/specs/" 2>/dev/null | head -5)
    done
    [[ $found -eq 0 ]] && echo "_No matching specs found._"
  else
    echo "_No specs/ directory in project._"
  fi
  echo ""

  # --- 2. Codebase patterns (SAFe) ---
  echo "## 2. Codebase Patterns"
  echo ""
  if [[ -d "$project_dir" ]]; then
    found=0
    for kw in $keywords; do
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "- \`$line\`"
        found=1
      done < <(grep -rn "$kw" "${project_dir}/" --include='*.ts' --include='*.tsx' --include='*.js' --include='*.py' --include='*.sh' -l 2>/dev/null | grep -v node_modules | head -3)
    done
    [[ $found -eq 0 ]] && echo "_No matching codebase patterns._"
  else
    echo "_No project directory._"
  fi
  echo ""

  # --- 3. Session history (SAFe) ---
  echo "## 3. Session History"
  echo ""
  session_dir="${HOME}/.claude/todos"
  if [[ -d "$session_dir" ]]; then
    found=0
    for kw in $keywords; do
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        echo "- $(basename "$f") — matched \`$kw\`"
        found=1
      done < <(grep -rl "$kw" "$session_dir" 2>/dev/null | head -3)
    done
    [[ $found -eq 0 ]] && echo "_No matching session history._"
  else
    echo "_No ~/.claude/todos/ directory._"
  fi
  echo ""

  # --- 4. Zettelkasten learnings (NEW — cross-session compounding) ---
  echo "## 4. Zettelkasten Learnings (Cross-Session)"
  echo ""
  learnings_dir="${VAULT_DIR}/20-learnings"
  if [[ -d "$learnings_dir" ]]; then
    found=0
    for kw in $keywords; do
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        # Extract title + first insight line
        title=$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^# //')
        tags=$(grep -m1 '^tags:' "$f" 2>/dev/null || echo "")
        echo "- [[$(basename "$f" .md)]] — ${title} ${tags}"
        found=1
      done < <(grep -rl "$kw" "$learnings_dir" --include='*.md' 2>/dev/null | head -5)
    done
    [[ $found -eq 0 ]] && echo "_No matching learnings found. (First run for this domain — no prior knowledge to compound on.)_"
  else
    echo "_No Obsidian learnings directory yet. Will be populated after first goal completes._"
  fi
  echo ""

  echo "---"
  echo "_Pattern discovery complete. All downstream agents read this file for prior-work context._"
} > "$out"

log_ok "Pattern discovery written: $out"
