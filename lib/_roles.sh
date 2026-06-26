#!/usr/bin/env bash
# ============================================================
# Unified Role Config v1 — 15 roles (genie + SAFe)
# Sources _models.sh for cost/selection helpers, extends rosters.
# ============================================================
source "${HOME}/.hermes/scripts/lib/_models.sh"

# Role -> model (opus=deep reasoning, sonnet=fast capable, haiku=cheap fast)
declare -A ROLE_MODELS=(
  [architect]="opus"
  [bsa]="sonnet"
  [system-architect]="opus"
  [be-developer]="sonnet"
  [fe-developer]="sonnet"
  [data-engineer]="sonnet"
  [dpe]="haiku"
  [tech-writer]="sonnet"
  [qas]="opus"
  [security-engineer]="opus"
  [rte]="haiku"
  [tdm]="sonnet"
  [implementor]="sonnet"
  [reviewer]="opus"
  [tester]="haiku"
  [critic]="sonnet"
  [synthesizer]="sonnet"
  [tiebreaker]="sonnet"
  [learn-extract]="sonnet"
)

# Role -> effort
declare -A ROLE_EFFORTS=(
  [architect]="max"
  [bsa]="high"
  [system-architect]="max"
  [be-developer]="high"
  [fe-developer]="high"
  [data-engineer]="high"
  [dpe]="low"
  [tech-writer]="high"
  [qas]="high"
  [security-engineer]="high"
  [rte]="low"
  [tdm]="high"
  [implementor]="high"
  [reviewer]="high"
  [tester]="low"
  [critic]="high"
  [synthesizer]="high"
  [tiebreaker]="high"
  [learn-extract]="high"
)

# Role -> claude --allowedTools (comma-sep, or ALL)
declare -A ROLE_TOOLS=(
  [architect]="Read,Bash"
  [bsa]="Read,Bash"
  [system-architect]="Read,Bash"
  [be-developer]="ALL"
  [fe-developer]="ALL"
  [data-engineer]="ALL"
  [dpe]="Read,Bash"
  [tech-writer]="Read,Write,Edit,Bash"
  [qas]="Read,Bash"
  [security-engineer]="Read,Bash"
  [rte]="Read,Bash"
  [tdm]="Read,Bash"
  [implementor]="ALL"
  [reviewer]="Read"
  [tester]="Read,Bash"
  [critic]="Read"
  [synthesizer]="Read"
  [tiebreaker]="Read"
  [learn-extract]="Read"
)

# Role -> permission mode (acceptEdits=read+write, Read=read-only)
declare -A ROLE_PERMISSIONS=(
  [architect]="acceptEdits"
  [bsa]="acceptEdits"
  [system-architect]="Read"
  [be-developer]="acceptEdits"
  [fe-developer]="acceptEdits"
  [data-engineer]="acceptEdits"
  [dpe]="acceptEdits"
  [tech-writer]="acceptEdits"
  [qas]="acceptEdits"
  [security-engineer]="Read"
  [rte]="acceptEdits"
  [tdm]="acceptEdits"
  [implementor]="acceptEdits"
  [reviewer]="Read"
  [tester]="acceptEdits"
  [critic]="Read"
  [synthesizer]="Read"
  [tiebreaker]="Read"
  [learn-extract]="Read"
)

# Role -> prompt file (relative to lib/roles/)
declare -A ROLE_PROMPTS=(
  [bsa]="bsa.md"
  [system-architect]="system-architect.md"
  [be-developer]="be-developer.md"
  [fe-developer]="fe-developer.md"
  [data-engineer]="data-engineer.md"
  [dpe]="dpe.md"
  [tech-writer]="tech-writer.md"
  [qas]="qas.md"
  [security-engineer]="security-engineer.md"
  [rte]="rte.md"
  [tdm]="tdm.md"
)

# Independence gates — never collapsible, never same session as implementer
is_independence_gate() {
  case "$1" in
    qas|security-engineer) return 0 ;;
    *) return 1 ;;
  esac
}

# Complexity triggers for mandatory System Architect review (SAFe v1.1 / 9R-321)
# Returns 0 if trigger matched, 1 otherwise. Args: <file_or_dir>
check_complexity_triggers() {
  local target="$1"
  local triggered=0
  while IFS= read -r -d '' f; do
    local lines
    lines=$(wc -l < "$f" 2>/dev/null || echo 0)
    local ext="${f##*.}"
    case "$ext" in
      sh) (( lines > 100 )) && { log_warn "Complexity trigger: $f ($lines lines, bash>100)"; triggered=1; } ;;
      ts|tsx|js|mjs|jsx) (( lines > 200 )) && { log_warn "Complexity trigger: $f ($lines lines, TS/JS>200)"; triggered=1; } ;;
      yml|yaml) [[ "$f" == *".github/workflows/"* || "$f" == *".gitlab-ci"* ]] && { log_warn "Complexity trigger: CI/CD workflow $f"; triggered=1; } ;;
      tf|json) [[ "$ext" == "tf" || "$f" == *"terraform"* ]] && { log_warn "Complexity trigger: IaC $f"; triggered=1; } ;;
    esac
  done < <(find "$target" -type f \( -name '*.sh' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.mjs' -o -name '*.jsx' -o -name '*.yml' -o -name '*.yaml' -o -name '*.tf' \) -print0 2>/dev/null)
  return $triggered
}

export -f is_independence_gate check_complexity_triggers
