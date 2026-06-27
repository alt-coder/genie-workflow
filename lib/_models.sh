#!/usr/bin/env bash
# ============================================================
# Model Selection v3 — settings.json driven + capability-aware
# ============================================================
# Reads ~/.claude/settings.json for tier→model mapping.
# Probes each model for capabilities (vision, context, tool-use).
# Enriches spawned Claude Code sessions with capability context.
#
# Usage: source ~/.hermes/scripts/lib/_models.sh
# ============================================================

CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
CAPABILITIES_CACHE="${HOME}/.hermes/model-capabilities.json"
CAPABILITIES_TTL=3600  # 1 hour before re-probe

# ─── Tier → Model (from settings.json) ───

load_tier_models() {
  if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    echo "sonnet"  # fallback
    return
  fi

  python3 -c "
import json, os
with open('$CLAUDE_SETTINGS') as f:
    s = json.load(f)
env = s.get('env', {})
print(env.get('ANTHROPIC_DEFAULT_OPUS_MODEL', 'opus'))
print(env.get('ANTHROPIC_DEFAULT_SONNET_MODEL', 'sonnet'))
print(env.get('ANTHROPIC_DEFAULT_HAIKU_MODEL', 'haiku'))
print(env.get('ANTHROPIC_BASE_URL', ''))
print(env.get('ANTHROPIC_API_KEY', ''))
" 2>/dev/null
}

TIER_MODELS=()
TIER_MODELS[0]=$(load_tier_models | sed -n '1p')  # opus tier
TIER_MODELS[1]=$(load_tier_models | sed -n '2p')  # sonnet tier
TIER_MODELS[2]=$(load_tier_models | sed -n '3p')  # haiku tier
API_BASE_URL=$(load_tier_models | sed -n '4p')
API_KEY=$(load_tier_models | sed -n '5p')

# Role → minimum tier (0=premium, 1=standard, 2=budget)
declare -A ROLE_MIN_TIER=(
  [system-architect]="0" [security-engineer]="0" [qas]="0" [architect]="0"
  [bsa]="1" [be-developer]="1" [fe-developer]="1" [data-engineer]="1"
  [tech-writer]="1" [tdm]="1" [implementor]="1" [synthesizer]="1"
  [tiebreaker]="1" [critic]="1" [learn-extract]="1" [reviewer]="1"
  [dpe]="2" [rte]="2" [tester]="2"
)

# Tier → effort
declare -A TIER_EFFORT=(["0"]="max" ["1"]="high" ["2"]="low")

# Tier → cost per 1K tokens (rough estimate)
declare -A TIER_COST=(["0"]="0.015" ["1"]="0.003" ["2"]="0.0005")

# ─── Complexity Keywords ───

COMPLEXITY_HIGH=(
  "auth" "oauth" "jwt" "sso" "migration" "migrate" "schema" "rollback"
  "security" "vulnerability" "injection" "xss" "csrf" "rls" "row.level"
  "encryption" "decrypt" "payment" "billing" "transaction"
  "race.condition" "deadlock" "concurrent" "atomic"
  "refactor" "restructure" "rewrite"
  "real.time" "websocket" "streaming" "performance" "optimize" "scale"
)

COMPLEXITY_LOW=(
  "typo" "spelling" "grammar" "config" "readme" "docs" "documentation"
  "minor" "simple" "trivial" "cosmetic" "bump" "rename" "extract"
  "add.test" "test.only"
)

# ─── Capability Probe ─────────────────────────────────────

probe_model_capabilities() {
  local model="$1"
  local base_url="${API_BASE_URL}"
  local key="${API_KEY}"

  # Check cache first
  if [[ -f "$CAPABILITIES_CACHE" ]]; then
    local cached
    cached=$(python3 -c "
import json, os, time
try:
    with open('$CAPABILITIES_CACHE') as f:
        db = json.load(f)
    entry = db.get('$model', {})
    age = time.time() - entry.get('ts', 0)
    if age < $CAPABILITIES_TTL and entry.get('probed'):
        print(json.dumps(entry))
except: pass
" 2>/dev/null)
    if [[ -n "$cached" ]]; then
      echo "$cached"
      return
    fi
  fi

  # Probe: 1. Does it respond? 2. Does it support vision?
  local has_vision="false"
  local has_tools="true"
  local context_window=200000
  local response_s=0
  local available="true"

  # Quick availability check
  local probe_resp
  probe_resp=$(curl -s --max-time 15 \
    -H "x-api-key: ${key}" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "{\"model\":\"${model}\",\"max_tokens\":5,\"messages\":[{\"role\":\"user\",\"content\":\"OK\"}]}" \
    "${base_url}/messages" 2>/dev/null || echo "")

  if [[ -z "$probe_resp" ]] || ! echo "$probe_resp" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    available="false"
  fi

  # Vision probe (small 1x1 PNG)
  if [[ "$available" == "true" ]]; then
    local vision_resp
    vision_resp=$(curl -s --max-time 20 \
      -H "x-api-key: ${key}" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d "{\"model\":\"${model}\",\"max_tokens\":5,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":\"image/png\",\"data\":\"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==\"}},{\"type\":\"text\",\"text\":\"OK\"}]}]}" \
      "${base_url}/messages" 2>/dev/null || echo "")

    if echo "$vision_resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('content','NO'))" 2>/dev/null | grep -qv 'NO\|ERROR'; then
      has_vision="true"
    fi
  fi

  # Build capability record
  local cap_json
  cap_json=$(python3 -c "
import json
print(json.dumps({
    'model': '$model',
    'available': '$available' == 'true',
    'has_vision': '$has_vision' == 'true',
    'has_tools': '$has_tools' == 'true',
    'context_window': $context_window,
    'probed': True,
    'ts': $(date +%s)
}))
")

  # Cache it
  python3 -c "
import json, os
db = {}
if os.path.exists('$CAPABILITIES_CACHE'):
    with open('$CAPABILITIES_CACHE') as f:
        try: db = json.load(f)
        except: pass
cap = json.loads('''$cap_json''')
db[cap['model']] = cap
os.makedirs(os.path.dirname('$CAPABILITIES_CACHE'), exist_ok=True)
with open('$CAPABILITIES_CACHE', 'w') as f:
    json.dump(db, f, indent=2)
"

  echo "$cap_json"
}

get_model_capabilities() {
  local model="$1"
  probe_model_capabilities "$model"
}

# ─── Intelligent Selection ─────────────────────────────────

genie_select_model() {
  local role="$1"
  local goal_desc="${2:-}"
  local goal_dir="${3:-}"

  local min_tier="${ROLE_MIN_TIER[$role]:-1}"
  local tier="$min_tier"  # start at role floor

  # Complexity bump: if task is complex, raise tier
  if [[ -n "$goal_desc" ]]; then
    local score=0
    for kw in "${COMPLEXITY_HIGH[@]}"; do
      if echo "$goal_desc" | grep -qi "$kw" 2>/dev/null; then
        score=$((score + 1))
      fi
    done
    if (( score >= 2 )); then
      tier=0  # premium for complex
    elif (( score >= 1 )); then
      tier=1  # standard
    fi
    # Enforce floor
    if (( tier > min_tier )); then
      tier=$min_tier
    fi
  fi

  # Budget gate (if budget tracker available)
  if [[ -n "$goal_dir" && -f "$goal_dir/goal-context.json" ]]; then
    local budget
    budget=$(python3 -c "
import json
with open('$goal_dir/goal-context.json') as f:
    d = json.load(f)
print(d.get('budget_remaining', 50))
" 2>/dev/null || echo 50)
    if (( $(awk "BEGIN {print ($budget < 5)}") )); then
      tier=2
    elif (( $(awk "BEGIN {print ($budget < 15 && $tier < 1)}") )); then
      tier=1
    fi
  fi

  # Map tier to actual model name
  local model="${TIER_MODELS[$tier]:-sonnet}"
  echo "$model"

  # Write metadata if goal_dir provided
  if [[ -n "$goal_dir" && -d "$goal_dir" ]]; then
    local effort="${TIER_EFFORT[$tier]:-high}"
    local cost="${TIER_COST[$tier]:-0.003}"
    local caps
    caps=$(get_model_capabilities "$model" 2>/dev/null || echo '{"has_vision":false,"has_tools":true,"context_window":200000}')

    python3 -c "
import json, os
caps = json.loads('''$caps''')
meta = {
    'role': '$role',
    'model': '$model',
    'effort': '$effort',
    'tier': $tier,
    'capabilities': caps,
    'estimated_cost': float($cost) * 8 * 3,
    'timestamp': '$(date -Iseconds)'
}
os.makedirs('$goal_dir', exist_ok=True)
with open('$goal_dir/.model-selection.json', 'w') as f:
    json.dump(meta, f, indent=2)
"
  fi
}

# ─── Session Enrichment ────────────────────────────────────

genie_enrich_session() {
  local role="$1"
  local goal_dir="$2"
  local sys_prompt="$3"

  if [[ ! -f "$goal_dir/.model-selection.json" ]]; then
    echo "$sys_prompt"
    return
  fi

  python3 -c "
import json
with open('$goal_dir/.model-selection.json') as f:
    meta = json.load(f)

caps = meta.get('capabilities', {})
enrichment = []

if not caps.get('has_vision', True):
    # Positive delegation: tell agent HOW to handle vision, not just 'don't'
    # Find vision-capable model from capabilities cache
    vision_model = 'sonnet'
    try:
        cache_path = '${HOME}/.hermes/model-capabilities.json'
        with open(cache_path) as cf:
            cache = json.load(cf)
        for m, c in cache.items():
            if c.get('has_vision', False) and c.get('available', True):
                if 'sonnet' in m.lower():
                    vision_model = m
                    break
                vision_model = m
    except:
        pass
    enrichment.append(f'You lack vision capability. For image/screenshot/diagram analysis: use @vision-analyst subagent (model: {vision_model}) to analyze images. Pass the image file path. Wait for text description, then proceed.')
if not caps.get('has_tools', True):
    enrichment.append('Model has limited tool support — prefer text-only reasoning.')
if caps.get('context_window', 200000) < 50000:
    enrichment.append(f'Model context window is {caps[\"context_window\"]} — keep context compact.')

if enrichment:
    print('\\n'.join(enrichment))
" 2>/dev/null
}

# ─── Backward-compatible wrappers ──────────────────────────

genie_get_effort() {
  local role="$1"
  local goal_dir="$2"

  if [[ -n "$goal_dir" && -f "$goal_dir/.model-selection.json" ]]; then
    python3 -c "import json; print(json.load(open('$goal_dir/.model-selection.json')).get('effort','high'))" 2>/dev/null && return
  fi

  local min_tier="${ROLE_MIN_TIER[$role]:-1}"
  echo "${TIER_EFFORT[$min_tier]:-high}"
}

genie_get_tools() {
  local role="$1"
  case "$role" in
    be-developer|fe-developer|data-engineer|implementor) echo "ALL" ;;
    architect|critic|synthesizer|tiebreaker|learn-extract|reviewer) echo "Read" ;;
    *) echo "Read,Bash" ;;
  esac
}

genie_get_permission() {
  local role="$1"
  case "$role" in
    architect|be-developer|fe-developer|data-engineer|dpe|tech-writer|qas|rte|tdm|implementor)
      echo "bypassPermissions" ;;
    *) echo "bypassPermissions" ;;
  esac
}

genie_estimate_cost() {
  local role="$1"
  local estimated_tokens="${2:-8000}"
  local goal_dir="$3"

  if [[ -n "$goal_dir" && -f "$goal_dir/.model-selection.json" ]]; then
    python3 -c "import json; print(json.load(open('$goal_dir/.model-selection.json')).get('estimated_cost','0.05'))" 2>/dev/null && return
  fi

  local min_tier="${ROLE_MIN_TIER[$role]:-1}"
  local cost_per_1k="${TIER_COST[$min_tier]:-0.003}"
  awk "BEGIN {printf \"%.4f\", ($estimated_tokens / 1000) * $cost_per_1k * 3}"
}

export -f genie_select_model genie_get_effort genie_get_tools genie_get_permission
export -f genie_estimate_cost genie_enrich_session
export -f probe_model_capabilities get_model_capabilities
