#!/usr/bin/env bash
# Validate litellm/config.yaml model routing priorities.
# Uses only standard tools (grep, awk) — no Python dependencies required.

set -euo pipefail

CONFIG="$(cd "$(dirname "$0")/.." && pwd)/litellm/config.yaml"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Extract order values for a model group.
# Outputs lines like: REASONER_LOCAL 1
get_orders() {
    local group="$1"
    awk -v group="$group" '
        /^[[:space:]]*- model_name:/ { in_group = ($NF == group); model = "" }
        in_group && /model:/ { model = $NF }
        in_group && /order:/ { print model, $NF; in_group = 0 }
    ' "$CONFIG"
}

echo "=== Normal cases ==="

# Reasoner: Win GPU (REASONER_LOCAL) should be order 1
order=$(get_orders "reasoner" | grep "REASONER_LOCAL" | awk '{print $2}')
[[ "$order" == "1" ]] && pass "Win GPU (reasoner_local) is order 1" \
                       || fail "Win GPU (reasoner_local) expected order 1, got $order"

# Reasoner: Mac (REASONER_PORTABLE) should be order 2
order=$(get_orders "reasoner" | grep "REASONER_PORTABLE" | awk '{print $2}')
[[ "$order" == "2" ]] && pass "Mac (reasoner_portable) is order 2" \
                       || fail "Mac (reasoner_portable) expected order 2, got $order"

# Reasoner: Cloud should be order 3
order=$(get_orders "reasoner" | grep "REASONER_CLOUD" | awk '{print $2}')
[[ "$order" == "3" ]] && pass "Cloud (reasoner_cloud) is order 3" \
                       || fail "Cloud (reasoner_cloud) expected order 3, got $order"

# Reasoner: exactly 3 deployments
count=$(get_orders "reasoner" | wc -l | tr -d ' ')
[[ "$count" == "3" ]] && pass "Reasoner has 3 deployments" \
                       || fail "Reasoner expected 3 deployments, got $count"

# Judge: local hosts are order 1
judge_order1=$(get_orders "judge" | awk '$2 == 1' | wc -l | tr -d ' ')
[[ "$judge_order1" == "2" ]] && pass "Judge has 2 local hosts at order 1" \
                              || fail "Judge expected 2 order-1 entries, got $judge_order1"

# Judge: cloud is order 2
judge_cloud=$(get_orders "judge" | grep "CLOUD" | awk '{print $2}')
[[ "$judge_cloud" == "2" ]] && pass "Judge cloud is order 2" \
                             || fail "Judge cloud expected order 2, got $judge_cloud"

echo ""
echo "=== Error cases ==="

# Config file must be valid YAML (basic structure check)
grep -q "^model_list:" "$CONFIG" && pass "model_list key exists" \
                                  || fail "model_list key not found"

# Every model entry must have an order field
entries=$(grep -c "model_name:" "$CONFIG")
orders=$(grep -c "order:" "$CONFIG")
[[ "$entries" == "$orders" ]] && pass "All $entries entries have order field" \
                               || fail "$entries model entries but only $orders have order"

# All order values must be positive integers
non_int=$(grep "order:" "$CONFIG" | awk '{print $2}' | grep -vE '^[1-9][0-9]*$' || true)
[[ -z "$non_int" ]] && pass "All order values are positive integers" \
                      || fail "Non-integer or non-positive order values: $non_int"

echo ""
echo "=== Edge cases ==="

# Reasoner: no duplicate order values
reasoner_orders=$(get_orders "reasoner" | awk '{print $2}' | sort)
reasoner_unique=$(echo "$reasoner_orders" | sort -u)
[[ "$reasoner_orders" == "$reasoner_unique" ]] && pass "Reasoner has no duplicate orders" \
                                                 || fail "Reasoner has duplicate order values"

# Reasoner: consecutive orders starting from 1
expected=$(printf '%s\n' 1 2 3)
[[ "$reasoner_orders" == "$expected" ]] && pass "Reasoner orders are consecutive 1,2,3" \
                                         || fail "Reasoner orders not consecutive: $(echo $reasoner_orders | tr '\n' ',')"

# Reasoner: lowest order starts at 1
first_order=$(get_orders "reasoner" | awk '{print $2}' | sort -n | head -1)
[[ "$first_order" == "1" ]] && pass "Reasoner lowest order starts at 1" \
                              || fail "Reasoner lowest order is $first_order, expected 1"

# Judge: lowest order starts at 1
first_judge=$(get_orders "judge" | awk '{print $2}' | sort -n | head -1)
[[ "$first_judge" == "1" ]] && pass "Judge lowest order starts at 1" \
                              || fail "Judge lowest order is $first_judge, expected 1"

echo ""
echo "--- Results: $PASS passed, $FAIL failed ---"
[[ "$FAIL" -eq 0 ]]
