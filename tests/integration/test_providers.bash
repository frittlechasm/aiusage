#!/usr/bin/env bash
# Integration tests: fetch_* functions with mocked HTTP responses.
# Each test sets up fake credentials/files and overrides http_json to avoid
# real network calls.
# shellcheck source=../helpers/common.bash
source "$(dirname "$0")/../helpers/common.bash"
source "$(dirname "$0")/../helpers/mock_setup.bash"

_ORIG_HOME="$HOME"

# ── fetch_claude ──────────────────────────────────────────

# No credentials file and no keychain entry
_tmp=$(mktemp -d)
HOME="$_tmp"
out=$(macos_keychain_read() { return 1; }; fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "not logged in"  "fetch_claude: no credentials → error"

# HTTP 200: both windows present
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.claude"
printf '{"claudeAiOauth":{"accessToken":"fake-token"}}' > "$_tmp/.claude/.credentials.json"
set_http_response "200" '{"five_hour":{"utilization":"50.0","reset_at":"2026-03-28T12:00:00Z"},"seven_day":{"utilization":"30.0","reset_at":"2026-04-04T00:00:00Z"}}'
HOME="$_tmp"
out=$(fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "5h"     "fetch_claude 200: shows 5h bar"
assert_contains "$out" "50%"    "fetch_claude 200: shows 50% utilization"
assert_contains "$out" "Weekly" "fetch_claude 200: shows weekly bar"
assert_contains "$out" "30%"    "fetch_claude 200: shows 30% utilization"
assert_not_contains "$out" "Fable" "fetch_claude 200: omits unavailable Fable limit"

# HTTP 200: current limits array without a Fable allowance
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.claude"
printf '{"claudeAiOauth":{"accessToken":"fake-token"}}' > "$_tmp/.claude/.credentials.json"
set_http_response "200" '{"five_hour":{"utilization":"50.0"},"seven_day":{"utilization":"30.0"},"limits":[{"kind":"session","group":"session","percent":95,"scope":null},{"kind":"weekly_all","group":"weekly","percent":90,"scope":null}]}'
HOME="$_tmp"
out=$(fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_not_contains "$out" "Fable" "fetch_claude 200: ignores unscoped current limits"
five_hour_line=$(printf '%s\n' "$out" | awk '$1 == "5h"')
weekly_line=$(printf '%s\n' "$out" | awk '$1 == "Weekly"')
assert_contains "$five_hour_line" "50%" "fetch_claude flat fields: take precedence over structured session"
assert_contains "$weekly_line" "30%" "fetch_claude flat fields: take precedence over structured weekly"

# Structured limits are the fallback when flat usage windows are absent.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.claude"
printf '{"claudeAiOauth":{"accessToken":"fake-token"}}' > "$_tmp/.claude/.credentials.json"
set_http_response "200" '{"limits":[{"kind":"session","utilization":42,"resetsAt":"2026-07-25T12:00:00Z"},{"kind":"weekly_all","percent":31,"resets_at":"2026-07-30T00:00:00Z"},{"kind":"weekly_scoped","utilization":17,"resetsAt":"2026-07-30T00:00:00Z","scope":{"model":{"displayName":"Claude 3.5 Fable"}}}]}'
HOME="$_tmp"
out=$(fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
five_hour_line=$(printf '%s\n' "$out" | awk '$1 == "5h"')
weekly_line=$(printf '%s\n' "$out" | awk '$1 == "Weekly"')
fable_line=$(printf '%s\n' "$out" | awk '$1 == "Fable"')
assert_contains "$five_hour_line" "42%" "fetch_claude structured limits: reads session utilization"
assert_contains "$weekly_line" "31%" "fetch_claude structured limits: reads weekly percent"
assert_contains "$fable_line" "17%" "fetch_claude structured limits: reads Fable utilization"
assert_not_contains "$out" "reset: --" "fetch_claude structured limits: reads reset aliases"

# Camel-case flat windows remain compatible with newer response spellings.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.claude"
printf '{"claudeAiOauth":{"accessToken":"fake-token"}}' > "$_tmp/.claude/.credentials.json"
set_http_response "200" '{"fiveHour":{"utilization":22,"resetsAt":"2026-07-25T12:00:00Z"},"sevenDay":{"utilization":44,"resetsAt":"2026-07-30T00:00:00Z"}}'
HOME="$_tmp"
out=$(fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
five_hour_line=$(printf '%s\n' "$out" | awk '$1 == "5h"')
weekly_line=$(printf '%s\n' "$out" | awk '$1 == "Weekly"')
assert_contains "$five_hour_line" "22%" "fetch_claude flat aliases: reads fiveHour"
assert_contains "$weekly_line" "44%" "fetch_claude flat aliases: reads sevenDay"
assert_not_contains "$out" "reset: --" "fetch_claude flat aliases: reads resetsAt"

# Malformed flat windows must not suppress valid structured limits.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.claude"
printf '{"claudeAiOauth":{"accessToken":"fake-token"}}' > "$_tmp/.claude/.credentials.json"
set_http_response "200" '{"five_hour":"invalid","seven_day":[],"limits":[{"kind":"session","percent":18},{"kind":"weekly_all","percent":27}]}'
HOME="$_tmp"
out=$(fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "18%" "fetch_claude malformed flat windows: preserves structured session"
assert_contains "$out" "27%" "fetch_claude malformed flat windows: preserves structured weekly"

# HTTP 200: optional Fable weekly limit in the scoped limits array
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.claude"
printf '{"claudeAiOauth":{"accessToken":"fake-token"}}' > "$_tmp/.claude/.credentials.json"
set_http_response "200" '{"five_hour":{"utilization":"50.0","resets_at":"2026-07-25T12:00:00Z"},"seven_day":{"utilization":"30.0","resets_at":"2026-07-30T00:00:00Z"},"limits":[{"kind":"session","group":"session","percent":50,"resets_at":"2026-07-25T12:00:00Z","scope":"unexpected"},{"kind":"weekly_all","group":"weekly","percent":30,"resets_at":"2026-07-30T00:00:00Z","scope":null},{"kind":"weekly_scoped","group":"weekly","percent":17,"resets_at":"2026-07-30T00:00:00Z","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}}]}'
HOME="$_tmp"
out=$(fetch_claude 2>&1) || true
assert_contains "$out" "Fable" "fetch_claude 200: shows optional Fable bar"
assert_contains "$out" "17%"   "fetch_claude 200: shows Fable usage"
reset_count=$(printf '%s\n' "$out" | awk '/reset:/ { count++ } END { print count + 0 }')
assert_eq "3" "$reset_count" "fetch_claude 200: shows the Fable reset"
assert_not_contains "$out" "reset: --" "fetch_claude 200: parses the Fable reset"

# A present Fable allowance remains visible when none of it has been used
set_http_response "200" '{"five_hour":{"utilization":"50.0"},"seven_day":{"utilization":"30.0"},"limits":[{"kind":"weekly_scoped","group":"weekly","percent":0,"resets_at":"2026-07-30T00:00:00Z","scope":{"model":{"display_name":"Claude Fable 5"}}}]}'
out=$(fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
fable_line=$(printf '%s\n' "$out" | awk '$1 == "Fable"')
assert_contains "$fable_line" "0%" "fetch_claude 200: shows zero Fable usage"

# HTTP 401: session expired
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.claude"
printf '{"claudeAiOauth":{"accessToken":"fake-token"}}' > "$_tmp/.claude/.credentials.json"
set_http_response "401" ""
HOME="$_tmp"
out=$(fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "session expired" "fetch_claude 401: session expired message"

# HTTP 000: network error
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.claude"
printf '{"claudeAiOauth":{"accessToken":"fake-token"}}' > "$_tmp/.claude/.credentials.json"
set_http_response "000" ""
HOME="$_tmp"
out=$(fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "network error"   "fetch_claude 000: network error message"

# ── fetch_codex ───────────────────────────────────────────

# No credentials
_tmp=$(mktemp -d)
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
spark_out=$(fetch_codex_spark 2>&1) || true
combined_out=$(fetch_codex_all 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "not logged in"   "fetch_codex: no credentials → error"
assert_contains "$spark_out" "not logged in" "fetch_codex_spark: no credentials → error"
assert_contains "$combined_out" "not logged in" "fetch_codex_all: no credentials → error"

# HTTP 200
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0"},"secondary_window":{"used_percent":"20.0"}}}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "5h"     "fetch_codex 200: shows 5h bar"
assert_contains "$out" "45%"    "fetch_codex 200: shows 45%"
assert_contains "$out" "Weekly" "fetch_codex 200: shows weekly bar"
assert_contains "$out" "20%"    "fetch_codex 200: shows 20%"
assert_not_contains "$out" "banked:" "fetch_codex 200: omits unavailable banked reset data"

# HTTP 200 with banked reset inventory; applicable count is zero until a limit is reached.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0"},"secondary_window":{"used_percent":"20.0"}},"rate_limit_reset_credits":{"available_count":3,"applicable_available_count":0}}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "banked: 3 resets" "fetch_codex banked resets: shows available inventory separately"
assert_not_contains "$out" "banked: 0 resets" "fetch_codex banked resets: ignores gated applicable count"
banked_count=$(printf '%s\n' "$out" | awk '/banked: 3 resets/ { count++ } END { print count + 0 }')
assert_eq "1" "$banked_count" "fetch_codex banked resets: shows inventory once"

# A single banked reset uses the singular label.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0"}},"rate_limit_reset_credits":{"available_count":1,"applicable_available_count":0}}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "banked: 1 reset" "fetch_codex banked resets: uses singular label"
assert_not_contains "$out" "banked: 1 resets" "fetch_codex banked resets: avoids plural for one"

# An explicit zero remains visible instead of being treated as missing.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0"}},"rate_limit_reset_credits":{"available_count":0,"applicable_available_count":0}}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "banked: 0 resets" "fetch_codex banked resets: shows explicit zero inventory"

# The detailed reset-credit response supplies every available expiry.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
_codex_now=$(date +%s)
_codex_first_expiry=$((_codex_now + 90060))
_codex_later_expiry=$((_codex_now + 180060))
_codex_spark_reset=$((_codex_now + 3600))
_codex_usage_body=$(printf '{"rate_limit":{"primary_window":{"used_percent":"45.0"}},"rate_limit_reset_credits":{"available_count":2},"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","rate_limit":{"primary_window":{"used_percent":5,"reset_at":%s}}}]}' "$_codex_spark_reset")
_codex_banked_body=$(printf '{"credits":[{"status":"available","expires_at":%s},{"status":"redeemed","expires_at":%s},{"status":"available","expires_at":%s}]}' \
  "$_codex_first_expiry" "$((_codex_now + 60))" "$_codex_later_expiry")
http_json() {
  case "$1" in
  */rate-limit-reset-credits)
    HTTP_STATUS="200"
    HTTP_BODY="$_codex_banked_body"
    ;;
  *)
    HTTP_STATUS="200"
    HTTP_BODY="$_codex_usage_body"
    ;;
  esac
}
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
spark_out=$(fetch_codex_spark 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "banked(1): $(format_epoch_local "$_codex_first_expiry") (1d 1h)" "fetch_codex banked expiry: shows the first available expiry"
assert_contains "$out" "banked(2): $(format_epoch_local "$_codex_later_expiry") (2d 2h)" "fetch_codex banked expiry: shows the second available expiry"
assert_not_contains "$out" "$(format_epoch_local "$((_codex_now + 60))")" "fetch_codex banked expiry: omits redeemed credits"
reset_line=$(printf '%s\n' "$out" | awk '/reset:/ { print; exit }')
first_banked_line=$(printf '%s\n' "$out" | awk '/banked\(1\):/ { print; exit }')
assert_contains "$reset_line" "reset:     --" "fetch_codex banked expiry: pads the reset label"
assert_contains "$first_banked_line" "banked(1): $(format_epoch_local "$_codex_first_expiry")" "fetch_codex banked expiry: aligns reset and banked values"
assert_not_contains "$out" "$(format_epoch_local "$_codex_spark_reset" "time")" "fetch_codex banked expiry: hides Spark from primary Codex output"
spark_reset_line=$(printf '%s\n' "$spark_out" | awk -v expected="$(format_epoch_local "$_codex_spark_reset" "time")" '/reset:/ && index($0, expected) { print; exit }')
assert_contains "$spark_reset_line" "reset: $(format_epoch_local "$_codex_spark_reset" "time")" "fetch_codex banked expiry: keeps a standalone Spark reset compact"
assert_not_contains "$spark_reset_line" "reset:     " "fetch_codex banked expiry: does not align Spark with the banked group"

# HTTP 200 with the temporary weekly-only response shape
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":4,"limit_window_seconds":604800,"reset_at":1784524085},"secondary_window":null},"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_bengalfox","rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":604800,"reset_at":1784601644},"secondary_window":null}}]}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
spark_out=$(fetch_codex_spark 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "Weekly"  "fetch_codex weekly-only: labels the primary window from its duration"
assert_contains "$out" "4%"      "fetch_codex weekly-only: shows weekly usage"
assert_not_contains "$out" "  5h" "fetch_codex weekly-only: omits the absent 5h window"
assert_not_contains "$out" "100%" "fetch_codex weekly-only: does not parse reset timestamps as usage"
assert_not_contains "$out" "0%" "fetch_codex weekly-only: hides Spark usage from primary output"
assert_contains "$spark_out" "Spark Wk" "fetch_codex_spark weekly-only: labels the Spark weekly window"
assert_contains "$spark_out" "0%" "fetch_codex_spark weekly-only: preserves zero usage"
assert_not_contains "$spark_out" "  5h" "fetch_codex_spark weekly-only: omits the absent Spark 5h window"
assert_not_contains "$spark_out" "4%" "fetch_codex_spark weekly-only: omits primary Codex usage"
assert_not_contains "$out" "reset: --" "fetch_codex weekly-only: preserves reset timestamps after empty fields"
assert_not_contains "$spark_out" "reset: --" "fetch_codex_spark weekly-only: preserves reset timestamps"

# Relative reset durations are resolved from one request-time reference epoch.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":45,"reset_at":2100000000,"reset_after_seconds":60},"secondary_window":{"used_percent":20,"reset_after_seconds":120}},"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","rate_limit":{"primary_window":{"used_percent":15,"resetAfterSeconds":90},"secondary_window":{"used_percent":5,"reset_after_seconds":150}}}]}'
out=$(
  date() {
    if [[ "$#" -eq 1 && "$1" == "+%s" ]]; then
      printf '2000000000\n'
    else
      command date "$@"
    fi
  }
  draw_reset() { printf 'reset_epoch=%s\n' "$1"; }
  HOME="$_tmp"
  fetch_codex 2>&1
  fetch_codex_spark 2>&1
) || true
rm -rf "$_tmp"
assert_contains "$out" "reset_epoch=2100000000" "fetch_codex relative resets: prefers absolute primary reset"
assert_not_contains "$out" "reset_epoch=2000000060" "fetch_codex relative resets: ignores primary fallback when absolute exists"
assert_contains "$out" "reset_epoch=2000000120" "fetch_codex relative resets: resolves secondary reset"
assert_contains "$out" "reset_epoch=2000000090" "fetch_codex relative resets: supports Spark camel-case reset"
assert_contains "$out" "reset_epoch=2000000150" "fetch_codex relative resets: resolves Spark secondary reset"

# HTTP 200 with optional Spark limits and account credits
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0","reset_at":"2026-03-28T12:00:00Z"},"secondary_window":{"used_percent":"20.0","reset_at":"2026-04-04T00:00:00Z"}},"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_spark","rate_limit":{"primary_window":{"used_percent":"15.0","reset_at":"2026-03-28T13:00:00Z"},"secondary_window":{"used_percent":"5.0","reset_at":"2026-04-05T00:00:00Z"}}}],"credits":{"has_credits":true,"balance":"12","unlimited":false}}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
spark_out=$(fetch_codex_spark 2>&1) || true
combined_out=$(fetch_codex_all 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_not_contains "$out" "15%" "fetch_codex 200: hides Spark usage"
assert_contains "$out" "Extra"    "fetch_codex 200: shows optional extra credits"
assert_contains "$out" "12 credits available" "fetch_codex 200: shows credit balance"
assert_contains "$spark_out" "Spark 5h" "fetch_codex_spark 200: shows Spark 5h bar"
assert_contains "$spark_out" "15%" "fetch_codex_spark 200: shows Spark 5h usage"
assert_contains "$spark_out" "Spark Wk" "fetch_codex_spark 200: shows Spark weekly bar"
assert_contains "$spark_out" "5%" "fetch_codex_spark 200: shows Spark weekly usage"
assert_not_contains "$spark_out" "Extra" "fetch_codex_spark 200: omits primary Codex credits"
assert_contains "$combined_out" "45%" "fetch_codex_all 200: shows primary Codex usage"
assert_contains "$combined_out" "Spark 5h" "fetch_codex_all 200: shows Spark in the Codex section"
assert_contains "$combined_out" "12 credits available" "fetch_codex_all 200: shows primary Codex credits"

# HTTP 200 with assigned but exhausted account credits
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0"},"secondary_window":{"used_percent":"20.0"}},"credits":{"has_credits":true,"balance":"0","unlimited":false}}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "Extra" "fetch_codex 200: shows assigned extra credits with zero balance"
assert_contains "$out" "0 credits available" "fetch_codex 200: shows exhausted credit balance"

# Spark-only output keeps resets even when their timestamps match primary Codex.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0","reset_at":"2026-03-28T12:00:00Z"},"secondary_window":{"used_percent":"20.0","reset_at":"2026-04-04T00:00:00Z"}},"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","rate_limit":{"primary_window":{"used_percent":"15.0","reset_at":"2026-03-28T12:00:00Z"},"secondary_window":{"used_percent":"5.0","reset_at":"2026-04-04T00:00:00Z"}}}]}'
HOME="$_tmp"
out=$(fetch_codex_spark 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
reset_count=$(printf '%s\n' "$out" | awk '/reset:/ { count++ } END { print count + 0 }')
assert_eq "2" "$reset_count" "fetch_codex_spark 200: keeps reset lines independent of hidden primary windows"

# A valid Codex response without Spark limits reports Spark as unavailable.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0"}}}'
HOME="$_tmp"
out=$(fetch_codex_spark 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "Spark usage data is unavailable" "fetch_codex_spark: reports missing Spark limits"

# HTTP 401
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake"}}' > "$_tmp/.codex/auth.json"
set_http_response "401" ""
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "session expired" "fetch_codex 401: session expired message"

# ── fetch_cursor ──────────────────────────────────────────

# No cookie, no browser, no cache
unset CURSOR_COOKIE 2>/dev/null || true
get_cursor_cookie_from_browser() { return 1; }
_cursor_cache_read()              { return 1; }
out=$(fetch_cursor 2>&1) || true
assert_contains "$out" "no Cursor session" "fetch_cursor: no cookie → error"

# Browser has a Cursor session but its cookie cannot be decrypted (exit 2)
get_cursor_cookie_from_browser() { return 2; }
out=$(fetch_cursor 2>&1) || true
assert_contains "$out" "keyring-encrypted" "fetch_cursor: undecryptable browser cookie → keyring message"
get_cursor_cookie_from_browser() { return 1; }

# Success via CURSOR_COOKIE (modern usage-summary endpoint)
set_http_response "200" '{"individualUsage":{"plan":{"totalPercentUsed":"35.0"}},"billingCycleEnd":"2026-04-28T00:00:00Z"}'
CURSOR_COOKIE="fake-session-token"
out=$(fetch_cursor 2>&1) || true
unset CURSOR_COOKIE
assert_contains "$out" "Monthly" "fetch_cursor 200: shows Monthly bar"
assert_contains "$out" "35%"     "fetch_cursor 200: shows 35%"

# Current plans expose separate Cursor and other-model pools.
set_http_response "200" '{"individualUsage":{"plan":{"autoPercentUsed":12,"apiPercentUsed":47,"totalPercentUsed":50}},"billingCycleEnd":"2026-04-28T00:00:00Z"}'
CURSOR_COOKIE="fake-session-token"
out=$(fetch_cursor 2>&1) || true
unset CURSOR_COOKIE
cursor_line=$(printf '%s\n' "$out" | grep "Cursor")
other_line=$(printf '%s\n' "$out" | grep "Other")
assert_contains "$cursor_line" "12%" "fetch_cursor pools: shows Cursor pool usage"
assert_contains "$other_line" "47%" "fetch_cursor pools: shows other-model pool usage"
assert_not_contains "$out" "Monthly" "fetch_cursor pools: omits aggregate plan usage"

# On-demand usage remains useful even when the plan percentage is absent.
set_http_response "200" '{"individualUsage":{"onDemand":{"enabled":true,"used":1250,"limit":5000}},"billingCycleEnd":"2026-04-28T00:00:00Z"}'
CURSOR_COOKIE="fake-session-token"
out=$(fetch_cursor 2>&1) || true
unset CURSOR_COOKIE
assert_contains "$out" "On-demand" "fetch_cursor on-demand: renders without plan percentage"
assert_contains "$out" "25%" "fetch_cursor on-demand: calculates usage percentage"
assert_contains "$out" '$12.50 / $50.00' "fetch_cursor on-demand: formats credit amounts"

# Enterprise responses can expose individual and team pools without plan data.
set_http_response "200" '{"membershipType":"enterprise","individualUsage":{"overall":{"enabled":true,"used":7100,"limit":10000}},"teamUsage":{"pooled":{"enabled":true,"used":3600000,"limit":60000000},"onDemand":{"enabled":true,"used":150000,"limit":500000}},"billingCycleEnd":"2026-04-28T00:00:00Z"}'
CURSOR_COOKIE="fake-session-token"
out=$(fetch_cursor 2>&1) || true
unset CURSOR_COOKIE
individual_line=$(printf '%s\n' "$out" | grep "Individual")
team_pool_line=$(printf '%s\n' "$out" | grep "Team pool")
team_extra_line=$(printf '%s\n' "$out" | grep "Team extra")
assert_contains "$individual_line" "71%" "fetch_cursor enterprise: shows individual usage"
assert_contains "$team_pool_line" "6%" "fetch_cursor enterprise: shows pooled team usage"
assert_contains "$team_extra_line" "30%" "fetch_cursor enterprise: shows team on-demand usage"

# Unlimited accounts have no finite meter but still report their plan state.
set_http_response "200" '{"membershipType":"ultra","isUnlimited":true}'
CURSOR_COOKIE="fake-session-token"
out=$(fetch_cursor 2>&1) || true
unset CURSOR_COOKIE
assert_contains "$out" "Plan" "fetch_cursor unlimited: shows plan label"
assert_contains "$out" "ultra · unlimited" "fetch_cursor unlimited: shows membership and state"

# A valid modern response is authoritative and must not fall through to legacy APIs.
set_http_response "200" '{"unexpected":true}'
CURSOR_COOKIE="fake-session-token"
out=$(fetch_cursor 2>&1) || true
unset CURSOR_COOKIE
assert_contains "$out" "usage data is unavailable" "fetch_cursor malformed modern response: reports unavailable data"
assert_not_contains "$out" "no premium request quota" "fetch_cursor malformed modern response: does not use legacy quota"

# An unavailable modern endpoint still falls back to the legacy request quota.
http_json() {
  case "$1" in
  */api/usage-summary)
    HTTP_STATUS="404"
    HTTP_BODY=""
    ;;
  */api/auth/me)
    HTTP_STATUS="200"
    HTTP_BODY='{"sub":"user-1"}'
    ;;
  */api/usage\?user=*)
    HTTP_STATUS="200"
    HTTP_BODY='{"gpt-4":{"numRequests":25,"maxRequestUsage":100}}'
    ;;
  esac
}
CURSOR_COOKIE="fake-session-token"
out=$(fetch_cursor 2>&1) || true
unset CURSOR_COOKIE
assert_contains "$out" "Monthly" "fetch_cursor legacy fallback: shows request quota"
assert_contains "$out" "25%" "fetch_cursor legacy fallback: calculates request usage"
assert_contains "$out" "25 / 100 requests" "fetch_cursor legacy fallback: shows request counts"

# HTTP 401 with cookie (clears cache and shows error)
_cursor_cache_clear() { true; }  # no-op for test
set_http_response "401" ""
CURSOR_COOKIE="expired-token"
out=$(fetch_cursor 2>&1) || true
unset CURSOR_COOKIE
assert_contains "$out" "session expired" "fetch_cursor 401: session expired message"

# ── fetch_gemini ──────────────────────────────────────────

# No credentials file
_tmp=$(mktemp -d)
HOME="$_tmp"
out=$(fetch_gemini 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "not logged in"   "fetch_gemini: no credentials → error"

# Expired token (expiry_date in milliseconds, far in the past)
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.gemini"
printf '{"access_token":"fake","expiry_date":1000}' > "$_tmp/.gemini/oauth_creds.json"
HOME="$_tmp"
out=$(fetch_gemini 2>&1) || true
HOME="$_ORIG_HOME"; rm -rf "$_tmp"
assert_contains "$out" "session expired" "fetch_gemini: expired token → error"

# The summary reset must come from the bucket that supplies the maximum usage.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.gemini"
printf '{"access_token":"fake","expiry_date":4102444800000}' > "$_tmp/.gemini/oauth_creds.json"
_gemini_quota_body='{"buckets":[{"modelId":"gemini-3-flash-preview","remainingFraction":0.2,"resetTime":"2030-01-02T00:00:00Z"},{"modelId":"gemini-3-pro-preview","remainingFraction":0.6,"resetTime":"2030-02-02T00:00:00Z"}]}'
http_json() {
  case "$1" in
  *:loadCodeAssist)
    HTTP_STATUS="200"
    HTTP_BODY='{"cloudaicompanionProject":"test-project"}'
    ;;
  *:retrieveUserQuota)
    HTTP_STATUS="200"
    HTTP_BODY="$_gemini_quota_body"
    ;;
  esac
}
out=$(
  draw_reset() { printf 'reset_epoch=%s\n' "$1"; }
  HOME="$_tmp"
  fetch_gemini 2>&1
) || true
assert_contains "$out" "80%" "fetch_gemini grouped buckets: shows maximum usage"
assert_contains "$out" "reset_epoch=1893542400" "fetch_gemini grouped buckets: uses reset from maximum bucket"
assert_not_contains "$out" "reset_epoch=1896220800" "fetch_gemini grouped buckets: ignores reset from lower-usage bucket"

# The Daily summary applies the same pairing across different label groups.
_gemini_quota_body='{"buckets":[{"modelId":"gemini-2.5-flash","remainingFraction":0.2,"resetTime":"2030-01-02T00:00:00Z"},{"modelId":"gemini-2.5-pro","remainingFraction":0.6,"resetTime":"2030-02-02T00:00:00Z"}]}'
out=$(
  draw_reset() { printf 'reset_epoch=%s\n' "$1"; }
  HOME="$_tmp"
  fetch_gemini 2>&1
) || true
rm -rf "$_tmp"
assert_contains "$out" "Flash 80%" "fetch_gemini summary: keeps grouped Flash usage"
assert_contains "$out" "Pro 40%" "fetch_gemini summary: keeps grouped Pro usage"
assert_contains "$out" "reset_epoch=1893542400" "fetch_gemini summary: uses reset from maximum group"
assert_not_contains "$out" "reset_epoch=1896220800" "fetch_gemini summary: ignores reset from lower-usage group"

# ── fetch_jetbrains ───────────────────────────────────────

# No quota file
find_jetbrains_quota_file() { printf ""; }
out=$(fetch_jetbrains 2>&1) || true
assert_contains "$out" "no JetBrains AI quota file found" "fetch_jetbrains: no file → error"

# With valid quota XML file (sleep 0.25 is inside fetch_jetbrains — expected)
_jb_file=$(mktemp)
cat > "$_jb_file" << 'EOF'
<application>
  <component name="AIAssistantQuotaManager2">
    <option name="quotaInfo" value="{&quot;current&quot;: 150000, &quot;maximum&quot;: 1000000, &quot;topUpQuota&quot;: {&quot;current&quot;: 250000, &quot;maximum&quot;: 1000000}}"/>
    <option name="nextRefill" value="{&quot;tariff&quot;: {&quot;duration&quot;: &quot;P30D&quot;}}"/>
  </component>
</application>
EOF
find_jetbrains_quota_file() { printf "%s" "$_jb_file"; }
out=$(fetch_jetbrains 2>&1) || true
rm -f "$_jb_file"
assert_contains "$out" "30d"         "fetch_jetbrains: labels the tariff duration"
assert_contains "$out" "15%"         "fetch_jetbrains: shows 15% tariff usage"
assert_contains "$out" "1.5 / 10"    "fetch_jetbrains: converts raw tariff quota to credits"
assert_contains "$out" "Top-up"      "fetch_jetbrains: shows top-up usage"
assert_contains "$out" "25%"         "fetch_jetbrains: shows 25% top-up usage"
assert_contains "$out" "2.5 / 10"    "fetch_jetbrains: converts raw top-up quota to credits"
assert_not_contains "$out" "1000000" "fetch_jetbrains: hides raw quota units"

# Accounts without purchased top-ups omit the optional top-up section.
_jb_file=$(mktemp)
cat > "$_jb_file" << 'EOF'
<application>
  <component name="AIAssistantQuotaManager2">
    <option name="quotaInfo" value="{&quot;current&quot;: 150000, &quot;maximum&quot;: 1000000, &quot;until&quot;: 1745000000}"/>
    <option name="nextRefill" value="{&quot;tariff&quot;: {&quot;duration&quot;: &quot;P30D&quot;}}"/>
  </component>
</application>
EOF
find_jetbrains_quota_file() { printf "%s" "$_jb_file"; }
out=$(fetch_jetbrains 2>&1) || true
rm -f "$_jb_file"
assert_not_contains "$out" "Top-up" "fetch_jetbrains: omits unavailable top-up quota"

# ── fetch_copilot ─────────────────────────────────────────

# No token (override all resolution paths)
unset COPILOT_GITHUB_TOKEN 2>/dev/null || true
_copilot_resolve_token() { return 1; }
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "not logged in"   "fetch_copilot: no token → error"

# Legacy request-based plan: percent_remaining=70 → 30% used for Premium.
set_http_response "200" '{"copilot_plan":"copilot_pro","quota_snapshots":{"premium_interactions":{"percent_remaining":70.0,"unlimited":false},"chat":{"percent_remaining":80.0,"unlimited":false}},"quota_reset_date":"2026-04-01"}'
_copilot_resolve_token() { printf "fake-token"; }
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "Premium"    "fetch_copilot legacy: shows Premium bar"
assert_contains "$out" "30%"        "fetch_copilot legacy: Premium 30% used (100-70)"
assert_contains "$out" "Chat"       "fetch_copilot legacy: shows Chat bar"
assert_contains "$out" "20%"        "fetch_copilot legacy: Chat 20% used (100-80)"
assert_not_contains "$out" "AI Credits" "fetch_copilot legacy: does not relabel requests as credits"

# Token-based plan: the premium_interactions snapshot represents AI Credits.
set_http_response "200" '{"copilot_plan":"copilot_pro","token_based_billing":true,"quota_reset_date_utc":"2026-08-01T00:00:00Z","quota_snapshots":{"premium_interactions":{"entitlement":1500,"quota_remaining":1125,"remaining":1125,"percent_remaining":75.0,"unlimited":false,"overage_count":0,"overage_permitted":true},"chat":{"unlimited":true},"completions":{"unlimited":true}}}'
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "AI Credits"       "fetch_copilot credits: shows AI Credits bar"
assert_contains "$out" "25%"              "fetch_copilot credits: shows 25% used"
assert_contains "$out" "375 / 1500 credits" "fetch_copilot credits: shows consumed and included credits"
assert_not_contains "$out" "Premium"      "fetch_copilot credits: hides legacy Premium label"
assert_not_contains "$out" "Chat"         "fetch_copilot credits: hides unlimited Chat quota"
assert_not_contains "$out" "reset: --"    "fetch_copilot credits: parses quota_reset_date_utc"

# Date-only *_utc reset values must be anchored to UTC, not treated as local time.
set_http_response "200" '{"copilot_plan":"copilot_pro","token_based_billing":true,"quota_reset_date_utc":"2026-09-01","quota_snapshots":{"premium_interactions":{"entitlement":1500,"quota_remaining":750,"remaining":750,"percent_remaining":50.0,"unlimited":false}}}'
out=$(fetch_copilot 2>&1) || true
assert_not_contains "$out" "reset: --"   "fetch_copilot credits: parses date-only utc reset"

# Credits can exceed the included entitlement without double-counting a negative balance.
set_http_response "200" '{"copilot_plan":"copilot_pro","token_based_billing":true,"quota_snapshots":{"premium_interactions":{"entitlement":1500,"quota_remaining":-25,"remaining":-25,"percent_remaining":0,"unlimited":false,"overage_count":25,"overage_permitted":true,"quota_reset_at":1785542400}}}'
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "100%"               "fetch_copilot credits overage: clamps bar at 100%"
assert_contains "$out" "1525 / 1500 credits" "fetch_copilot credits overage: includes overage consumption"
assert_not_contains "$out" "reset: --"       "fetch_copilot credits overage: parses snapshot reset epoch"

# Fractional model usage is rounded without exposing floating-point artifacts.
set_http_response "200" '{"copilot_plan":"copilot_pro","token_based_billing":true,"quota_snapshots":{"premium_interactions":{"entitlement":300,"quota_remaining":287.4,"remaining":287.4,"percent_remaining":95.8,"unlimited":false,"overage_count":0}}}'
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "12.6 / 300 credits"   "fetch_copilot credits: formats fractional consumption"
assert_not_contains "$out" "12.600000000000"  "fetch_copilot credits: hides floating-point artifacts"

# An empty legacy premium_models object must not shadow premium_interactions.
set_http_response "200" '{"copilot_plan":"copilot_pro","quota_snapshots":{"premium_models":{},"premium_interactions":{"token_based_billing":true,"entitlement":1500,"quota_remaining":1125,"percent_remaining":75,"unlimited":false}}}'
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "AI Credits" "fetch_copilot snapshot selection: skips empty premium_models"
assert_contains "$out" "25%" "fetch_copilot snapshot selection: reads premium_interactions usage"
assert_contains "$out" "375 / 1500 credits" "fetch_copilot snapshot selection: reads premium_interactions credits"

# When both snapshots contain data, premium_interactions is authoritative.
set_http_response "200" '{"copilot_plan":"copilot_pro","quota_snapshots":{"premium_models":{"token_based_billing":false,"entitlement":100,"quota_remaining":90,"percent_remaining":90,"unlimited":false},"premium_interactions":{"token_based_billing":true,"entitlement":500,"quota_remaining":300,"percent_remaining":60,"unlimited":false}}}'
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "AI Credits" "fetch_copilot snapshot selection: prefers premium_interactions billing mode"
assert_contains "$out" "40%" "fetch_copilot snapshot selection: prefers premium_interactions percentage"
assert_contains "$out" "200 / 500 credits" "fetch_copilot snapshot selection: prefers premium_interactions amounts"

# An explicit root billing mode takes precedence over the selected snapshot.
set_http_response "200" '{"copilot_plan":"copilot_pro","token_based_billing":false,"quota_snapshots":{"premium_interactions":{"token_based_billing":true,"percent_remaining":60,"unlimited":false}}}'
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "Premium" "fetch_copilot billing mode: preserves explicit root false"
assert_not_contains "$out" "AI Credits" "fetch_copilot billing mode: ignores snapshot true when root is false"

# Some clients expose the credits quota as premium_models with a snapshot flag.
set_http_response "200" '{"copilot_plan":"copilot_pro_plus","quota_reset_date_utc":"","quota_snapshots":{"premium_models":{"token_based_billing":true,"entitlement":7000,"quota_remaining":5250,"remaining":5250,"percent_remaining":75,"unlimited":false,"overage_count":0,"quota_reset_at":1785542400}}}'
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "AI Credits"          "fetch_copilot premium_models: detects snapshot billing flag"
assert_contains "$out" "25%"                 "fetch_copilot premium_models: shows used percentage"
assert_contains "$out" "1750 / 7000 credits" "fetch_copilot premium_models: shows credit consumption"
assert_not_contains "$out" "reset: --"        "fetch_copilot premium_models: skips empty reset fields"

# Free/limited plans expose Chat and Completions rather than premium usage.
set_http_response "200" '{"copilot_plan":"individual","quota_snapshots":{"chat":{"entitlement":50,"remaining":40,"percent_remaining":80,"unlimited":false},"completions":{"entitlement":2000,"remaining":1500,"percent_remaining":75,"unlimited":false}},"limited_user_reset_date":"2026-08-01"}'
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "Chat"        "fetch_copilot limited snapshots: shows Chat"
assert_contains "$out" "20%"         "fetch_copilot limited snapshots: shows Chat usage"
assert_contains "$out" "Completions" "fetch_copilot limited snapshots: shows Completions"
assert_contains "$out" "25%"         "fetch_copilot limited snapshots: shows Completions usage"
assert_not_contains "$out" "Premium" "fetch_copilot limited snapshots: does not mislabel completions"

# Legacy limited-user fallback still uses monthly entitlement and remaining counts.
set_http_response "200" '{"copilot_plan":"individual","monthly_quotas":{"chat":50,"completions":2000},"limited_user_quotas":{"chat":40,"completions":1500},"limited_user_reset_date":"2026-08-01"}'
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "Completions" "fetch_copilot limited fallback: labels Completions correctly"
assert_contains "$out" "25%"         "fetch_copilot limited fallback: derives Completions usage"
assert_not_contains "$out" "Premium" "fetch_copilot limited fallback: does not use Premium label"

# Unlimited or organization-managed plans without trackable quotas show the plan.
set_http_response "200" '{"copilot_plan":"business","access_type_sku":"copilot_business","token_based_billing":true,"quota_snapshots":{"premium_interactions":{"unlimited":true}}}'
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "Plan"             "fetch_copilot unlimited: shows plan fallback"
assert_contains "$out" "copilot business" "fetch_copilot unlimited: formats plan SKU"
assert_not_contains "$out" "AI Credits"   "fetch_copilot unlimited: omits meaningless quota bar"

# HTTP 401
set_http_response "401" ""
_copilot_resolve_token() { printf "expired-token"; }
_copilot_cache_clear() { true; }  # no-op for test
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "session expired" "fetch_copilot 401: session expired message"

# HTTP 000
set_http_response "000" ""
_copilot_resolve_token() { printf "fake-token"; }
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "network error"   "fetch_copilot 000: network error message"

# ── fetch_opencode_go ───────────────────────────────────────

# No environment key or OpenCode auth entry.
_tmp=$(mktemp -d)
out=$(HOME="$_tmp" XDG_DATA_HOME= OPENCODE_GO_API_KEY= OPENCODE_API_KEY= fetch_opencode_go 2>&1) || true
rm -rf "$_tmp"
assert_contains "$out" "not logged in" "fetch_opencode_go: no key → error"

# Resolve the provider-specific key from OpenCode's default auth store.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.local/share/opencode"
printf '{"opencode-go":{"type":"api","key":"file-key"}}' >"$_tmp/.local/share/opencode/auth.json"
key=$(HOME="$_tmp" XDG_DATA_HOME= OPENCODE_GO_API_KEY= OPENCODE_API_KEY= _opencode_go_resolve_key)
rm -rf "$_tmp"
assert_eq "file-key" "$key" "opencode-go auth: reads default OpenCode auth store"

# Respect XDG_DATA_HOME and ignore credentials with the wrong auth type.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/xdg/opencode"
printf '{"opencode-go":{"type":"oauth","key":"wrong-type"}}' >"$_tmp/xdg/opencode/auth.json"
key=$(HOME="$_tmp" XDG_DATA_HOME="$_tmp/xdg" OPENCODE_GO_API_KEY= OPENCODE_API_KEY= _opencode_go_resolve_key) || true
assert_eq "" "$key" "opencode-go auth: rejects non-API credentials"
printf '{"opencode-go":{"type":"api","key":"xdg-key"}}' >"$_tmp/xdg/opencode/auth.json"
key=$(HOME="$_tmp" XDG_DATA_HOME="$_tmp/xdg" OPENCODE_GO_API_KEY= OPENCODE_API_KEY= _opencode_go_resolve_key)
rm -rf "$_tmp"
assert_eq "xdg-key" "$key" "opencode-go auth: respects XDG_DATA_HOME"

# `opencode auth login` stores the API key under the "opencode" provider id.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.local/share/opencode"
printf '{"anthropic":{"type":"oauth"},"opencode":{"type":"api","key":"login-key"}}' >"$_tmp/.local/share/opencode/auth.json"
key=$(HOME="$_tmp" XDG_DATA_HOME= OPENCODE_GO_API_KEY= OPENCODE_API_KEY= _opencode_go_resolve_key)
assert_eq "login-key" "$key" "opencode-go auth: reads the generic opencode login entry"

# A dedicated opencode-go entry wins over the generic one.
printf '{"opencode-go":{"type":"api","key":"go-key"},"opencode":{"type":"api","key":"login-key"}}' >"$_tmp/.local/share/opencode/auth.json"
key=$(HOME="$_tmp" XDG_DATA_HOME= OPENCODE_GO_API_KEY= OPENCODE_API_KEY= _opencode_go_resolve_key)
assert_eq "go-key" "$key" "opencode-go auth: dedicated entry takes precedence over login entry"

# A broken dedicated entry must not shadow a valid generic one.
printf '{"opencode-go":{"type":"api","key":""},"opencode":{"type":"api","key":"login-key"}}' >"$_tmp/.local/share/opencode/auth.json"
key=$(HOME="$_tmp" XDG_DATA_HOME= OPENCODE_GO_API_KEY= OPENCODE_API_KEY= _opencode_go_resolve_key)
assert_eq "login-key" "$key" "opencode-go auth: empty dedicated key falls back to login entry"
printf '{"opencode-go":"not-an-object","opencode":{"type":"api","key":"login-key"}}' >"$_tmp/.local/share/opencode/auth.json"
key=$(HOME="$_tmp" XDG_DATA_HOME= OPENCODE_GO_API_KEY= OPENCODE_API_KEY= _opencode_go_resolve_key)
assert_eq "login-key" "$key" "opencode-go auth: non-object dedicated entry falls back to login entry"
rm -rf "$_tmp"

# The provider-specific environment variable wins over the official shared name.
key=$(OPENCODE_GO_API_KEY="specific-key" OPENCODE_API_KEY="shared-key" _opencode_go_resolve_key)
assert_eq "specific-key" "$key" "opencode-go auth: provider-specific env key takes precedence"
key=$(OPENCODE_GO_API_KEY= OPENCODE_API_KEY="shared-key" _opencode_go_resolve_key)
assert_eq "shared-key" "$key" "opencode-go auth: supports OPENCODE_API_KEY"

# Request contract: public endpoint with Bearer authentication.
_capture=$(mktemp)
http_json() {
  printf '%s\n' "$@" >"$_capture"
  HTTP_STATUS="200"
  HTTP_BODY='{"usage":{"rolling":{"percent":12,"resetsAt":"2026-09-01T02:00:00Z"}}}'
}
out=$(OPENCODE_GO_API_KEY="fake-key" OPENCODE_API_KEY= fetch_opencode_go 2>&1) || true
request=$(<"$_capture")
rm -f "$_capture"
assert_contains "$request" "https://opencode.ai/zen/go/v1/usage" "fetch_opencode_go request: uses public usage endpoint"
assert_contains "$request" "Authorization: Bearer fake-key" "fetch_opencode_go request: sends Bearer key"
assert_contains "$out" "5h" "fetch_opencode_go request: renders response"

# All authoritative windows are rendered, including an explicit zero.
set_http_response "200" '{"usage":{"rolling":{"status":"ok","percent":12.5,"resetsAt":"2026-09-01T02:00:00Z"},"weekly":{"status":"ok","percent":47,"resetsAt":"2026-09-08T00:00:00Z"},"monthly":{"status":"ok","percent":0,"resetsAt":"2026-10-01T00:00:00Z"}},"useBalance":false}'
out=$(OPENCODE_GO_API_KEY="fake-key" OPENCODE_API_KEY= fetch_opencode_go 2>&1) || true
assert_contains "$out" "5h"      "fetch_opencode_go 200: shows rolling 5h bar"
assert_contains "$out" "12%"     "fetch_opencode_go 200: shows rolling usage"
assert_contains "$out" "Weekly"  "fetch_opencode_go 200: shows weekly bar"
assert_contains "$out" "47%"     "fetch_opencode_go 200: shows weekly usage"
assert_contains "$out" "Monthly" "fetch_opencode_go 200: shows monthly bar"
assert_contains "$out" "0%"      "fetch_opencode_go 200: preserves zero usage"
assert_not_contains "$out" "reset: --" "fetch_opencode_go 200: renders API reset timestamps"

# Optional windows stay aligned: a missing window is omitted, not padded.
set_http_response "200" '{"usage":{"rolling":{"percent":9,"resetsAt":"2026-09-01T02:00:00Z"},"monthly":{"percent":31,"resetsAt":"2026-10-01T00:00:00Z"}}}'
out=$(OPENCODE_GO_API_KEY="fake-key" OPENCODE_API_KEY= fetch_opencode_go 2>&1) || true
assert_contains "$out" "5h" "fetch_opencode_go partial: keeps rolling window"
assert_not_contains "$out" "Weekly" "fetch_opencode_go partial: omits missing weekly window"
assert_contains "$out" "Monthly" "fetch_opencode_go partial: keeps monthly window aligned"
assert_contains "$out" "31%" "fetch_opencode_go partial: shows monthly usage"

# Undocumented response shapes are ignored rather than guessed at.
set_http_response "200" '{"rollingUsage":{"usagePercent":9,"resetInSec":1200}}'
out=$(OPENCODE_GO_API_KEY="fake-key" OPENCODE_API_KEY= fetch_opencode_go 2>&1) || true
assert_contains "$out" "usage data is unavailable" "fetch_opencode_go legacy shape: ignored"

# A rate-limited window still shows its percent, with the state surfaced.
set_http_response "200" '{"usage":{"rolling":{"status":"rate-limited","percent":100,"resetsAt":"2026-09-01T02:00:00Z"},"weekly":{"status":"ok","percent":10,"resetsAt":"2026-09-08T00:00:00Z"}}}'
out=$(OPENCODE_GO_API_KEY="fake-key" OPENCODE_API_KEY= fetch_opencode_go 2>&1) || true
assert_contains "$out" "5h" "fetch_opencode_go rate-limited: keeps rolling window"
assert_contains "$out" "100%" "fetch_opencode_go rate-limited: shows rolling usage"
assert_contains "$out" "rate limited" "fetch_opencode_go rate-limited: surfaces the status"
weekly_line=$(printf '%s\n' "$out" | grep "Weekly")
assert_contains "$weekly_line" "Weekly" "fetch_opencode_go rate-limited: weekly window present"
assert_not_contains "$weekly_line" "rate limited" "fetch_opencode_go rate-limited: ok windows stay unannotated"

# A window without a usable reset does not abort the remaining windows.
# Runs under explicit errexit because production invokes fetches with set -e.
# No '|| true' here: it would put the substitution in an errexit-ignored
# context, making the inner 'set -e' inert on bash >= 4.4.
set_http_response "200" '{"usage":{"rolling":{"status":"ok","percent":5},"weekly":{"status":"ok","percent":10,"resetsAt":"2026-09-08T00:00:00Z"}}}'
out=$(
  set -e
  OPENCODE_GO_API_KEY="fake-key" OPENCODE_API_KEY= fetch_opencode_go 2>&1
)
assert_contains "$out" "5h" "fetch_opencode_go missing reset: keeps rolling window"
assert_contains "$out" "Weekly" "fetch_opencode_go missing reset: later windows still render"
assert_not_contains "$out" "reset: --" "fetch_opencode_go missing reset: omits unknown reset line"

# Authentication, network, and response-shape errors are distinct.
# 401 with a key from the environment points at the environment variable.
set_http_response "401" ""
out=$(OPENCODE_GO_API_KEY="expired-key" OPENCODE_API_KEY= fetch_opencode_go 2>&1) || true
assert_contains "$out" "API key is invalid" "fetch_opencode_go 401: invalid key message"
assert_contains "$out" "OPENCODE_GO_API_KEY" "fetch_opencode_go 401 env key: names the environment variable"

# 401 with no environment key points at opencode auth login.
_tmp=$(mktemp -d)
mkdir -p "$_tmp/.local/share/opencode"
printf '{"opencode-go":{"type":"api","key":"file-key"}}' >"$_tmp/.local/share/opencode/auth.json"
out=$(HOME="$_tmp" XDG_DATA_HOME= OPENCODE_GO_API_KEY= OPENCODE_API_KEY= fetch_opencode_go 2>&1) || true
rm -rf "$_tmp"
assert_contains "$out" "API key is invalid" "fetch_opencode_go 401 file key: invalid key message"
assert_contains "$out" "opencode auth login" "fetch_opencode_go 401 file key: names re-login"

set_http_response "403" ""
out=$(OPENCODE_GO_API_KEY="fake-key" OPENCODE_API_KEY= fetch_opencode_go 2>&1) || true
assert_contains "$out" "no OpenCode Go subscription" "fetch_opencode_go 403: subscription message"

set_http_response "000" ""
out=$(OPENCODE_GO_API_KEY="fake-key" OPENCODE_API_KEY= fetch_opencode_go 2>&1) || true
assert_contains "$out" "network error" "fetch_opencode_go 000: network error message"

set_http_response "200" ''
out=$(OPENCODE_GO_API_KEY="fake-key" OPENCODE_API_KEY= fetch_opencode_go 2>&1) || true
assert_contains "$out" "usage data is unavailable" "fetch_opencode_go empty 200: unavailable, not HTTP failure"
assert_not_contains "$out" "HTTP 200" "fetch_opencode_go empty 200: no contradictory status message"

set_http_response "200" '{"unexpected":true}'
out=$(OPENCODE_GO_API_KEY="fake-key" OPENCODE_API_KEY= fetch_opencode_go 2>&1) || true
assert_contains "$out" "usage data is unavailable" "fetch_opencode_go malformed 200: response-shape error"
