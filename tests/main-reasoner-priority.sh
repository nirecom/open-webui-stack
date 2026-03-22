#!/usr/bin/env bash
# Validate litellm/config.yaml model routing with fallback-based strategy.
# Uses only standard tools (grep, awk) — no Python dependencies required.

set -euo pipefail

CONFIG="$(cd "$(dirname "$0")/.." && pwd)/litellm/config.yaml"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Extract api_base for a given model_name
get_api_base() {
    local name="$1"
    awk -v name="$name" '
        /^[[:space:]]*- model_name:/ { in_block = ($NF == name) }
        in_block && /api_base:/ { print $NF; in_block = 0 }
    ' "$CONFIG"
}

# Extract a litellm_params field value for a given model_name
get_param() {
    local name="$1" field="$2"
    awk -v name="$name" -v field="$field:" '
        /^[[:space:]]*- model_name:/ { in_block = ($NF == name) }
        in_block && $1 == field { print $NF; in_block = 0 }
    ' "$CONFIG"
}

# Extract fallback list for a model group from litellm_settings.fallbacks
get_fallbacks() {
    local group="$1"
    grep -A1 "\"*$group\"*:" "$CONFIG" | grep -o '\[.*\]' | head -1
}

echo "=== Normal cases ==="

# Reasoner primary uses local (Win GPU)
base=$(get_api_base "reasoner")
[[ "$base" == *"LLAMA_SERVER_URL"* ]] && pass "reasoner primary uses LLAMA_SERVER_URL" \
                                        || fail "reasoner primary expected LLAMA_SERVER_URL, got $base"

# Reasoner-portable uses portable (Mac)
base=$(get_api_base "reasoner-portable")
[[ "$base" == *"PORTABLE_LLM_SERVER_URL"* ]] && pass "reasoner-portable uses PORTABLE_LLM_SERVER_URL" \
                                                || fail "reasoner-portable expected PORTABLE_LLM_SERVER_URL, got $base"

# Reasoner-cloud uses cloud API key
key=$(get_param "reasoner-cloud" "api_key")
[[ "$key" == *"CLOUD_API_KEY"* ]] && pass "reasoner-cloud uses CLOUD_API_KEY" \
                                    || fail "reasoner-cloud expected CLOUD_API_KEY, got $key"

# Judge primary uses local (Win GPU)
base=$(get_api_base "judge")
[[ "$base" == *"LLAMA_SERVER_URL"* ]] && pass "judge primary uses LLAMA_SERVER_URL" \
                                        || fail "judge primary expected LLAMA_SERVER_URL, got $base"

# Judge-portable uses portable (Mac)
base=$(get_api_base "judge-portable")
[[ "$base" == *"PORTABLE_LLM_SERVER_URL"* ]] && pass "judge-portable uses PORTABLE_LLM_SERVER_URL" \
                                                || fail "judge-portable expected PORTABLE_LLM_SERVER_URL, got $base"

# Judge-cloud uses cloud API key
key=$(get_param "judge-cloud" "api_key")
[[ "$key" == *"CLOUD_API_KEY"* ]] && pass "judge-cloud uses CLOUD_API_KEY" \
                                    || fail "judge-cloud expected CLOUD_API_KEY, got $key"

# Fallbacks: reasoner chain
fb=$(get_fallbacks "reasoner")
[[ "$fb" == *"reasoner-portable"* && "$fb" == *"reasoner-cloud"* ]] \
    && pass "reasoner fallbacks: [reasoner-portable, reasoner-cloud]" \
    || fail "reasoner fallbacks unexpected: $fb"

# Fallbacks: judge chain
fb=$(get_fallbacks "judge")
[[ "$fb" == *"judge-portable"* && "$fb" == *"judge-cloud"* ]] \
    && pass "judge fallbacks: [judge-portable, judge-cloud]" \
    || fail "judge fallbacks unexpected: $fb"

echo ""
echo "=== Error cases ==="

# Config must have model_list
grep -q "^model_list:" "$CONFIG" && pass "model_list key exists" \
                                  || fail "model_list key not found"

# No order fields (fallback-based, not order-based)
order_count=$(grep -c "order:" "$CONFIG" || true)
[[ "$order_count" == "0" ]] && pass "No order fields present (fallback-based)" \
                              || fail "Found $order_count order fields, expected 0"

# Every deployment has a model field
entries=$(grep -c "model_name:" "$CONFIG")
models=$(grep -c "model: " "$CONFIG")
[[ "$models" -ge "$entries" ]] && pass "All $entries entries have model field" \
                                 || fail "$entries model entries but only $models have model"

echo ""
echo "=== Edge cases ==="

# Reasoner timeout is 120s (long inference)
r_timeout=$(get_param "reasoner" "timeout")
[[ "$r_timeout" == "120" ]] && pass "reasoner timeout is 120s" \
                              || fail "reasoner timeout expected 120, got $r_timeout"

# Reasoner timeout differs from judge timeout
j_timeout=$(get_param "judge" "timeout")
[[ "$r_timeout" != "$j_timeout" ]] && pass "reasoner timeout ($r_timeout) != judge timeout ($j_timeout)" \
                                     || fail "reasoner and judge have same timeout: $r_timeout"

# Judge-portable max_parallel_requests < judge
j_mpr=$(get_param "judge" "max_parallel_requests")
jp_mpr=$(get_param "judge-portable" "max_parallel_requests")
[[ "$jp_mpr" -lt "$j_mpr" ]] && pass "judge-portable max_parallel ($jp_mpr) < judge ($j_mpr)" \
                                || fail "judge-portable max_parallel ($jp_mpr) not less than judge ($j_mpr)"

# num_retries is 0
retries=$(grep "num_retries:" "$CONFIG" | awk '{print $2}')
[[ "$retries" == "0" ]] && pass "num_retries is 0" \
                          || fail "num_retries expected 0, got $retries"

# Fallback targets reference existing model_names
all_names=$(grep "model_name:" "$CONFIG" | awk '{print $NF}')
fallback_targets=$(sed -n '/fallbacks:/,$ s/.*"\([a-z-]*\)".*/\1/p' "$CONFIG" | sort -u)
fb_missing=""
for target in $fallback_targets; do
    echo "$all_names" | grep -qx "$target" || fb_missing="$fb_missing $target"
done
[[ -z "$fb_missing" ]] && pass "All fallback targets exist in model_list" \
                         || fail "Fallback targets not in model_list:$fb_missing"

# All timeout values are positive integers
bad_timeouts=$(grep "timeout:" "$CONFIG" | awk '{print $2}' | grep -vE '^[1-9][0-9]*$' || true)
[[ -z "$bad_timeouts" ]] && pass "All timeout values are positive integers" \
                           || fail "Invalid timeout values: $bad_timeouts"

# Required router_settings keys exist
for key in enable_pre_call_checks num_retries timeout cooldown_time; do
    grep -q "$key:" "$CONFIG" && pass "router_settings has $key" \
                                || fail "router_settings missing $key"
done

echo ""
echo "--- Results: $PASS passed, $FAIL failed ---"
[[ "$FAIL" -eq 0 ]]
