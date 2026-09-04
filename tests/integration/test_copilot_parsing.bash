#!/usr/bin/env bash
# Focused integration tests for Copilot response parsing.
# shellcheck source=../helpers/common.bash
source "$(dirname "$0")/../helpers/common.bash"

_copilot_resolve_token() { printf 'fake-token'; }
http_json() {
  HTTP_STATUS="200"
  HTTP_BODY="$_copilot_response"
}

# Empty fields must retain their position so a later completions quota is not
# mistaken for premium or chat usage.
_copilot_response='{"copilot_plan":"individual","monthly_quotas":{"completions":2000},"limited_user_quotas":{"completions":1500},"limited_user_reset_date":"2026-08-01"}'
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "Completions" "fetch_copilot parsing: preserves later fields after empty values"
assert_contains "$out" "25%" "fetch_copilot parsing: derives aligned completions usage"
assert_not_contains "$out" "Premium" "fetch_copilot parsing: does not shift completions into premium"
assert_not_contains "$out" "Chat" "fetch_copilot parsing: does not shift completions into chat"

# API values still pass through the numeric validation used by rendering.
_copilot_response='{"copilot_plan":"copilot_pro","quota_snapshots":{"premium_interactions":{"percent_remaining":"70; exit 99","unlimited":false}}}'
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "Premium" "fetch_copilot parsing: keeps a present premium quota"
assert_contains "$out" "  0%" "fetch_copilot parsing: rejects a nonnumeric percentage"
assert_not_contains "$out" "70; exit 99" "fetch_copilot parsing: does not render an untrusted numeric value"

# A parse failure must remain fatal under the script's production strict mode.
strict_out=$(
  AIUSAGE_SCRIPT="$AIUSAGE_SCRIPT" bash -c '
    source "$AIUSAGE_SCRIPT"
    _copilot_resolve_token() { printf "fake-token"; }
    http_json() { HTTP_STATUS="200"; HTTP_BODY="{"; }
    fetch_copilot
  ' 2>&1
)
strict_status=$?
if ((strict_status != 0)); then
  pass "fetch_copilot parsing: preserves malformed JSON failure"
else
  fail "fetch_copilot parsing: preserves malformed JSON failure" "expected non-zero exit"
fi
assert_not_contains "$strict_out" "Plan" "fetch_copilot parsing: does not render malformed JSON as an unknown plan"
