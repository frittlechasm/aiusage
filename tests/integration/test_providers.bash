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
_tmp=$(make_tmp_home)
HOME="$_tmp"
out=$(fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "not logged in"  "fetch_claude: no credentials → error"

# HTTP 200: both windows present
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.claude"
printf '{"claudeAiOauth":{"accessToken":"fake-token"}}' > "$_tmp/.claude/.credentials.json"
set_http_response "200" '{"five_hour":{"utilization":"50.0","reset_at":"2026-03-28T12:00:00Z"},"seven_day":{"utilization":"30.0","reset_at":"2026-04-04T00:00:00Z"}}'
HOME="$_tmp"
out=$(fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "5h"     "fetch_claude 200: shows 5h bar"
assert_contains "$out" "50%"    "fetch_claude 200: shows 50% utilization"
assert_contains "$out" "Weekly" "fetch_claude 200: shows weekly bar"
assert_contains "$out" "30%"    "fetch_claude 200: shows 30% utilization"
assert_not_contains "$out" "Fable" "fetch_claude 200: omits unavailable Fable limit"

# HTTP 200: current limits array without a Fable allowance
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.claude"
printf '{"claudeAiOauth":{"accessToken":"fake-token"}}' > "$_tmp/.claude/.credentials.json"
set_http_response "200" '{"five_hour":{"utilization":"50.0"},"seven_day":{"utilization":"30.0"},"limits":[{"kind":"session","group":"session","percent":50,"scope":null},{"kind":"weekly_all","group":"weekly","percent":30,"scope":null}]}'
HOME="$_tmp"
out=$(fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_not_contains "$out" "Fable" "fetch_claude 200: ignores unscoped current limits"

# HTTP 200: optional Fable weekly limit in the scoped limits array
_tmp=$(make_tmp_home)
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
HOME="$_ORIG_HOME"; cleanup_tmp_home
fable_line=$(printf '%s\n' "$out" | awk '$1 == "Fable"')
assert_contains "$fable_line" "0%" "fetch_claude 200: shows zero Fable usage"

# HTTP 401: session expired
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.claude"
printf '{"claudeAiOauth":{"accessToken":"fake-token"}}' > "$_tmp/.claude/.credentials.json"
set_http_response "401" ""
HOME="$_tmp"
out=$(fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "session expired" "fetch_claude 401: session expired message"

# HTTP 000: network error
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.claude"
printf '{"claudeAiOauth":{"accessToken":"fake-token"}}' > "$_tmp/.claude/.credentials.json"
set_http_response "000" ""
HOME="$_tmp"
out=$(fetch_claude 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "network error"   "fetch_claude 000: network error message"

# ── fetch_codex ───────────────────────────────────────────

# No credentials
_tmp=$(make_tmp_home)
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "not logged in"   "fetch_codex: no credentials → error"

# HTTP 200
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0"},"secondary_window":{"used_percent":"20.0"}}}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "5h"     "fetch_codex 200: shows 5h bar"
assert_contains "$out" "45%"    "fetch_codex 200: shows 45%"
assert_contains "$out" "Weekly" "fetch_codex 200: shows weekly bar"
assert_contains "$out" "20%"    "fetch_codex 200: shows 20%"
assert_not_contains "$out" " resets" "fetch_codex 200: omits unavailable banked reset data"

# HTTP 200 with banked reset inventory; applicable count is zero until a limit is reached.
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0"},"secondary_window":{"used_percent":"20.0"}},"rate_limit_reset_credits":{"available_count":3,"applicable_available_count":0}}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "· 3 resets" "fetch_codex banked resets: shows available inventory"
assert_not_contains "$out" "· 0 resets" "fetch_codex banked resets: ignores gated applicable count"
banked_count=$(printf '%s\n' "$out" | awk '/· 3 resets/ { count++ } END { print count + 0 }')
assert_eq "1" "$banked_count" "fetch_codex banked resets: shows inventory once"

# A single banked reset uses the singular label.
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0"}},"rate_limit_reset_credits":{"available_count":1,"applicable_available_count":0}}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "· 1 reset" "fetch_codex banked resets: uses singular label"
assert_not_contains "$out" "· 1 resets" "fetch_codex banked resets: avoids plural for one"

# An explicit zero remains visible instead of being treated as missing.
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0"}},"rate_limit_reset_credits":{"available_count":0,"applicable_available_count":0}}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "· 0 resets" "fetch_codex banked resets: shows explicit zero inventory"

# HTTP 200 with the temporary weekly-only response shape
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":4,"limit_window_seconds":604800,"reset_at":1784524085},"secondary_window":null},"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_bengalfox","rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":604800,"reset_at":1784601644},"secondary_window":null}}]}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "Weekly"  "fetch_codex weekly-only: labels the primary window from its duration"
assert_contains "$out" "4%"      "fetch_codex weekly-only: shows weekly usage"
assert_not_contains "$out" "  5h" "fetch_codex weekly-only: omits the absent 5h window"
assert_not_contains "$out" "100%" "fetch_codex weekly-only: does not parse reset timestamps as usage"
assert_contains "$out" "Spark Wk" "fetch_codex weekly-only: labels the Spark weekly window"
assert_not_contains "$out" "Spark 5h" "fetch_codex weekly-only: omits the absent Spark 5h window"
assert_not_contains "$out" "reset: --" "fetch_codex weekly-only: preserves reset timestamps after empty fields"

# HTTP 200 with optional Spark limits and account credits
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0","reset_at":"2026-03-28T12:00:00Z"},"secondary_window":{"used_percent":"20.0","reset_at":"2026-04-04T00:00:00Z"}},"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_spark","rate_limit":{"primary_window":{"used_percent":"15.0","reset_at":"2026-03-28T13:00:00Z"},"secondary_window":{"used_percent":"5.0","reset_at":"2026-04-05T00:00:00Z"}}}],"credits":{"has_credits":true,"balance":"12","unlimited":false}}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "Spark 5h" "fetch_codex 200: shows optional Spark 5h bar"
assert_contains "$out" "15%"      "fetch_codex 200: shows Spark 5h usage"
assert_contains "$out" "Spark Wk" "fetch_codex 200: shows optional Spark weekly bar"
assert_contains "$out" "5%"       "fetch_codex 200: shows Spark weekly usage"
assert_contains "$out" "Extra"    "fetch_codex 200: shows optional extra credits"
assert_contains "$out" "12 credits available" "fetch_codex 200: shows credit balance"

# HTTP 200 with assigned but exhausted account credits
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0"},"secondary_window":{"used_percent":"20.0"}},"credits":{"has_credits":true,"balance":"0","unlimited":false}}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "Extra" "fetch_codex 200: shows assigned extra credits with zero balance"
assert_contains "$out" "0 credits available" "fetch_codex 200: shows exhausted credit balance"

# HTTP 200 with Spark resets identical to primary resets keeps secondary section compact
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake","account_id":"fake-id"}}' > "$_tmp/.codex/auth.json"
set_http_response "200" '{"rate_limit":{"primary_window":{"used_percent":"45.0","reset_at":"2026-03-28T12:00:00Z"},"secondary_window":{"used_percent":"20.0","reset_at":"2026-04-04T00:00:00Z"}},"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","rate_limit":{"primary_window":{"used_percent":"15.0","reset_at":"2026-03-28T12:00:00Z"},"secondary_window":{"used_percent":"5.0","reset_at":"2026-04-04T00:00:00Z"}}}]}'
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
reset_count=$(printf '%s\n' "$out" | awk '/reset:/ { count++ } END { print count + 0 }')
assert_eq "2" "$reset_count" "fetch_codex 200: suppresses duplicate Spark reset lines"

# HTTP 401
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.codex"
printf '{"tokens":{"access_token":"fake"}}' > "$_tmp/.codex/auth.json"
set_http_response "401" ""
HOME="$_tmp"
out=$(fetch_codex 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "session expired" "fetch_codex 401: session expired message"

# ── fetch_cursor ──────────────────────────────────────────

# No cookie, no browser, no cache
unset CURSOR_COOKIE 2>/dev/null || true
get_cursor_cookie_from_browser() { return 1; }
_cursor_cache_read()              { return 1; }
out=$(fetch_cursor 2>&1) || true
assert_contains "$out" "no Cursor session" "fetch_cursor: no cookie → error"

# Success via CURSOR_COOKIE (modern usage-summary endpoint)
set_http_response "200" '{"individualUsage":{"plan":{"totalPercentUsed":"35.0"}},"billingCycleEnd":"2026-04-28T00:00:00Z"}'
CURSOR_COOKIE="fake-session-token"
out=$(fetch_cursor 2>&1) || true
unset CURSOR_COOKIE
assert_contains "$out" "Monthly" "fetch_cursor 200: shows Monthly bar"
assert_contains "$out" "35%"     "fetch_cursor 200: shows 35%"

# HTTP 401 with cookie (clears cache and shows error)
_cursor_cache_clear() { true; }  # no-op for test
set_http_response "401" ""
CURSOR_COOKIE="expired-token"
out=$(fetch_cursor 2>&1) || true
unset CURSOR_COOKIE
assert_contains "$out" "session expired" "fetch_cursor 401: session expired message"

# ── fetch_gemini ──────────────────────────────────────────

# No credentials file
_tmp=$(make_tmp_home)
HOME="$_tmp"
out=$(fetch_gemini 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "not logged in"   "fetch_gemini: no credentials → error"

# Expired token (expiry_date in milliseconds, far in the past)
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.gemini"
printf '{"access_token":"fake","expiry_date":1000}' > "$_tmp/.gemini/oauth_creds.json"
HOME="$_tmp"
out=$(fetch_gemini 2>&1) || true
HOME="$_ORIG_HOME"; cleanup_tmp_home
assert_contains "$out" "session expired" "fetch_gemini: expired token → error"

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
    <option name="quotaInfo" value="{&quot;current&quot;: 150, &quot;maximum&quot;: 1000, &quot;until&quot;: 1745000000}"/>
    <option name="nextRefill" value="{&quot;tariff&quot;: {&quot;duration&quot;: &quot;P30D&quot;}}"/>
  </component>
</application>
EOF
find_jetbrains_quota_file() { printf "%s" "$_jb_file"; }
out=$(fetch_jetbrains 2>&1) || true
rm -f "$_jb_file"
# Note: duration is extracted on a separate line from the @tsv output, so `read`
# stops at jq's trailing newline — duration is always empty → label falls back to "Credits"
assert_contains "$out" "Credits" "fetch_jetbrains: bar label (Credits — duration after jq newline)"
assert_contains "$out" "15%"     "fetch_jetbrains: shows 15% used (150/1000)"
assert_contains "$out" "150"  "fetch_jetbrains: shows credits used"
assert_contains "$out" "1000" "fetch_jetbrains: shows credits limit"

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
_tmp=$(make_tmp_home)
out=$(HOME="$_tmp" XDG_DATA_HOME= OPENCODE_GO_API_KEY= OPENCODE_API_KEY= fetch_opencode_go 2>&1) || true
rm -rf "$_tmp"
assert_contains "$out" "not logged in" "fetch_opencode_go: no key → error"

# Resolve the provider-specific key from OpenCode's default auth store.
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/.local/share/opencode"
printf '{"opencode-go":{"type":"api","key":"file-key"}}' >"$_tmp/.local/share/opencode/auth.json"
key=$(HOME="$_tmp" XDG_DATA_HOME= OPENCODE_GO_API_KEY= OPENCODE_API_KEY= _opencode_go_resolve_key)
rm -rf "$_tmp"
assert_eq "file-key" "$key" "opencode-go auth: reads default OpenCode auth store"

# Respect XDG_DATA_HOME and ignore credentials with the wrong auth type.
_tmp=$(make_tmp_home)
mkdir -p "$_tmp/xdg/opencode"
printf '{"opencode-go":{"type":"oauth","key":"wrong-type"}}' >"$_tmp/xdg/opencode/auth.json"
key=$(HOME="$_tmp" XDG_DATA_HOME="$_tmp/xdg" OPENCODE_GO_API_KEY= OPENCODE_API_KEY= _opencode_go_resolve_key) || true
assert_eq "" "$key" "opencode-go auth: rejects non-API credentials"
printf '{"opencode-go":{"type":"api","key":"xdg-key"}}' >"$_tmp/xdg/opencode/auth.json"
key=$(HOME="$_tmp" XDG_DATA_HOME="$_tmp/xdg" OPENCODE_GO_API_KEY= OPENCODE_API_KEY= _opencode_go_resolve_key)
rm -rf "$_tmp"
assert_eq "xdg-key" "$key" "opencode-go auth: respects XDG_DATA_HOME"

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
set_http_response "200" '{"usage":{"rolling":{"status":"ok","percent":5},"weekly":{"status":"ok","percent":10,"resetsAt":"2026-09-08T00:00:00Z"}}}'
out=$(
  set -e
  OPENCODE_GO_API_KEY="fake-key" OPENCODE_API_KEY= fetch_opencode_go 2>&1
) || true
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
_tmp=$(make_tmp_home)
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
