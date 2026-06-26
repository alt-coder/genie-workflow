#!/usr/bin/env bash
# Model configuration and selection for Genie Pipeline v7
# Usage: source ~/.hermes/scripts/lib/_models.sh

# Fallback tiers
MODEL_TIER_1="sonnet"      # primary
MODEL_TIER_2="opus"        # fallback
MODEL_TIER_3="haiku"       # emergency

# Role -> model mappings
declare -A ROLE_MODELS=(
  [architect]="opus"
  [implementor]="sonnet"
  [reviewer]="opus"
  [tester]="haiku"
  [critic]="sonnet"
  [synthesizer]="sonnet"
  [tiebreaker]="sonnet"
  [learn-extract]="sonnet"
)

declare -A ROLE_EFFORTS=(
  [architect]="max"
  [implementor]="high"
  [reviewer]="high"
  [tester]="low"
  [critic]="high"
  [synthesizer]="high"
  [tiebreaker]="high"
  [learn-extract]="high"
)

declare -A ROLE_TOOLS=(
  [architect]="Read,Bash"
  [implementor]="ALL"
  [reviewer]="Read"
  [tester]="Read,Bash"
  [critic]="Read"
  [synthesizer]="Read"
  [tiebreaker]="Read"
  [learn-extract]="Read"
)

declare -A ROLE_PERMISSIONS=(
  [architect]="acceptEdits"
  [implementor]="acceptEdits"
  [reviewer]="Read"
  [tester]="acceptEdits"
  [critic]="Read"
  [synthesizer]="Read"
  [tiebreaker]="Read"
  [learn-extract]="Read"
)

# Token limits per model
declare -A MODEL_TOKEN_LIMITS=(
  ["opus"]=200000
  ["sonnet"]=200000
  ["haiku"]=200000
)

# Cost per 1K tokens (input + output avg)
declare -A MODEL_COSTS=(
  ["opus"]=0.015
  ["sonnet"]=0.003
  ["haiku"]=0.00025
)

# Select model with fallback
genie_select_model() {
  local role="$1"
  local preferred="${2:-}"
  
  if [[ -n "$preferred" ]] && command -v claude &>/dev/null; then
    # Test if model is available (claude --model will error if invalid)
    if claude --model "$preferred" --help &>/dev/null 2>&1; then
      echo "$preferred"
      return 0
    fi
  fi
  
  # Use role default
  local model="${ROLE_MODELS[$role]:-sonnet}"
  echo "$model"
}

# Get effort for role
genie_get_effort() {
  local role="$1"
  echo "${ROLE_EFFORTS[$role]:-medium}"
}

# Get tools for role
genie_get_tools() {
  local role="$1"
  echo "${ROLE_TOOLS[$role]:-ALL}"
}

# Get permission mode for role
genie_get_permission() {
  local role="$1"
  echo "${ROLE_PERMISSIONS[$role]:-acceptEdits}"
}

# Estimate token cost for a task
genie_estimate_cost() {
  local role="$1"
  local estimated_tokens="${2:-8000}"
  local model
  model=$(genie_select_model "$role")
  local cost_per_1k="${MODEL_COSTS[$model]:-0.003}"
  
  # output is ~2x input on average
  local total_tokens=$((estimated_tokens * 3))
  local cost
  cost=$(awk "BEGIN {printf \"%.4f\", ($total_tokens / 1000) * $cost_per_1k}")
  echo "$cost"
}

export -f genie_select_model genie_get_effort genie_get_tools genie_get_permission genie_estimate_cost
