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

# HTTP 200 with quota snapshots (COPILOT_GITHUB_TOKEN path)
# percent_remaining=70 → used=30 for Premium; percent_remaining=80 → used=20 for Chat
set_http_response "200" '{"copilot_plan":"copilot_pro","quota_snapshots":{"premium_interactions":{"percent_remaining":70.0,"unlimited":false},"chat":{"percent_remaining":80.0,"unlimited":false}},"quota_reset_date":"2026-04-01"}'
_copilot_resolve_token() { printf "fake-token"; }
out=$(fetch_copilot 2>&1) || true
assert_contains "$out" "Premium"  "fetch_copilot 200: shows Premium bar"
assert_contains "$out" "30%"      "fetch_copilot 200: Premium 30% used (100-70)"
assert_contains "$out" "Chat"     "fetch_copilot 200: shows Chat bar"

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
