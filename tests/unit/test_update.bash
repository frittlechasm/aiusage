#!/usr/bin/env bash
# Unit tests: self-update command behavior.
# shellcheck source=../helpers/common.bash
source "$(dirname "$0")/../helpers/common.bash"

tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"; _test_summary' EXIT

mock_bin="$tmp_root/mock-bin"
mkdir -p "$mock_bin"

printf '%s\n' '#!/usr/bin/env sh' \
  'if [ "$1" = "-r" ]; then shift; fi' \
  'sed -n '\''s/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'\''' \
  >"$mock_bin/jq"

printf '%s\n' '#!/usr/bin/env sh' \
  'output=""' \
  'url=""' \
  'while [ "$#" -gt 0 ]; do' \
  '  case "$1" in' \
  '    -o) shift; output="$1" ;;' \
  '    http://*|https://*) url="$1" ;;' \
  '  esac' \
  '  shift' \
  'done' \
  'if [ -n "${MOCK_CURL_MARKER:-}" ]; then : >"$MOCK_CURL_MARKER"; fi' \
  'if [ "${MOCK_CURL_FAIL:-}" = "metadata" ] && [ -z "$output" ]; then exit 22; fi' \
  'if [ "${MOCK_CURL_FAIL:-}" = "download" ] && [ -n "$output" ]; then exit 22; fi' \
  'if [ -z "$output" ]; then' \
  '  printf '\''{"tag_name":"v%s"}'\'' "$MOCK_LATEST_VERSION"' \
  'else' \
  '  cp "$MOCK_UPDATE_SOURCE" "$output"' \
  'fi' \
  >"$mock_bin/curl"
chmod 755 "$mock_bin/jq" "$mock_bin/curl"
test_path="$mock_bin:/usr/bin:/bin"

make_versioned_script() {
  local version="$1" destination="$2"
  sed "s/^VERSION=\"[^\"]*\"/VERSION=\"$version\"/" "$AIUSAGE_SCRIPT" >"$destination"
  chmod 755 "$destination"
}

# ── version comparison ───────────────────────────────────

assert_exit_0 "version comparison: patch is newer" version_is_newer "0.2.1" "0.2.0"
assert_exit_0 "version comparison: minor is newer" version_is_newer "0.3.0" "0.2.9"
assert_exit_0 "version comparison: major is newer" version_is_newer "1.0.0" "0.99.99"
assert_exit_1 "version comparison: equal is not newer" version_is_newer "0.2.0" "0.2.0"
assert_exit_1 "version comparison: older is not newer" version_is_newer "0.1.9" "0.2.0"
assert_exit_1 "version comparison: malformed is not newer" version_is_newer "latest" "0.2.0"

# ── command validation ───────────────────────────────────

installed="$tmp_root/arguments/aiusage"
curl_marker="$tmp_root/curl-called"
mkdir -p "$(dirname "$installed")"
make_versioned_script "0.2.0" "$installed"

out=$(env PATH="$test_path" MOCK_CURL_MARKER="$curl_marker" bash "$installed" update --help 2>&1)
code=$?
assert_eq "0" "$code" "update help: exits 0"
assert_contains "$out" "Usage:" "update help: shows usage"
if [[ ! -e "$curl_marker" ]]; then
  pass "update help: does not access the network"
else
  fail "update help: does not access the network" "curl was called"
fi

out=$(env PATH="$test_path" MOCK_CURL_MARKER="$curl_marker" bash "$installed" update unexpected 2>&1)
code=$?
assert_eq "1" "$code" "update extra argument: exits 1"
assert_contains "$out" "no additional arguments" "update extra argument: reports invalid usage"
if [[ ! -e "$curl_marker" ]]; then
  pass "update extra argument: does not access the network"
else
  fail "update extra argument: does not access the network" "curl was called"
fi

out=$(env PATH="$test_path" MOCK_CURL_MARKER="$curl_marker" bash "$installed" claude update 2>&1)
code=$?
assert_eq "1" "$code" "update mixed with provider: exits 1"
assert_contains "$out" "standalone command" "update mixed with provider: reports invalid usage"
if [[ ! -e "$curl_marker" ]]; then
  pass "update mixed with provider: does not access the network"
else
  fail "update mixed with provider: does not access the network" "curl was called"
fi

# ── current release ──────────────────────────────────────

installed="$tmp_root/current/aiusage"
mkdir -p "$(dirname "$installed")"
make_versioned_script "0.2.0" "$installed"

out=$(env PATH="$test_path" MOCK_LATEST_VERSION="0.2.0" MOCK_UPDATE_SOURCE="$installed" \
  bash "$installed" update 2>&1)
code=$?
assert_eq "0" "$code" "update current: exits 0"
assert_contains "$out" "already up to date (0.2.0)" "update current: reports current version"

# ── newer release ────────────────────────────────────────

installed="$tmp_root/newer/aiusage"
download="$tmp_root/release-aiusage"
mkdir -p "$(dirname "$installed")"
make_versioned_script "0.2.0" "$installed"
make_versioned_script "0.2.1" "$download"

out=$(env PATH="$test_path" MOCK_LATEST_VERSION="0.2.1" MOCK_UPDATE_SOURCE="$download" \
  bash "$installed" update 2>&1)
code=$?
assert_eq "0" "$code" "update newer: exits 0"
assert_contains "$out" "updated 0.2.0 to 0.2.1" "update newer: reports version change"
assert_eq "aiusage 0.2.1" "$(env PATH="$test_path" bash "$installed" --version)" "update newer: replaces installed script"

# ── older release ────────────────────────────────────────

installed="$tmp_root/older/aiusage"
mkdir -p "$(dirname "$installed")"
make_versioned_script "0.3.0" "$installed"

out=$(env PATH="$test_path" MOCK_LATEST_VERSION="0.2.1" MOCK_UPDATE_SOURCE="$download" \
  bash "$installed" update 2>&1)
code=$?
assert_eq "0" "$code" "update older: exits 0"
assert_contains "$out" "installed version 0.3.0 is newer" "update older: refuses downgrade"
assert_eq "aiusage 0.3.0" "$(env PATH="$test_path" bash "$installed" --version)" "update older: preserves installed script"

# ── failed and invalid downloads ─────────────────────────

installed="$tmp_root/failure/aiusage"
invalid_download="$tmp_root/invalid-aiusage"
mkdir -p "$(dirname "$installed")"
make_versioned_script "0.2.0" "$installed"
printf '%s\n' '#!/usr/bin/env bash' 'VERSION="0.2.1"' 'this is not valid bash (' >"$invalid_download"

out=$(env PATH="$test_path" MOCK_LATEST_VERSION="0.2.1" MOCK_UPDATE_SOURCE="$download" MOCK_CURL_FAIL="download" \
  bash "$installed" update 2>&1); code=$?
assert_eq "1" "$code" "update download failure: exits 1"
assert_contains "$out" "could not download" "update download failure: reports error"
assert_eq "aiusage 0.2.0" "$(env PATH="$test_path" bash "$installed" --version)" "update download failure: preserves installed script"

out=$(env PATH="$test_path" MOCK_LATEST_VERSION="0.2.1" MOCK_UPDATE_SOURCE="$invalid_download" \
  bash "$installed" update 2>&1); code=$?
assert_eq "1" "$code" "update invalid download: exits 1"
assert_contains "$out" "failed validation" "update invalid download: reports error"
assert_eq "aiusage 0.2.0" "$(env PATH="$test_path" bash "$installed" --version)" "update invalid download: preserves installed script"
