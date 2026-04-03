#!/usr/bin/env bash
# Mock helpers for overriding external dependencies in integration tests.
# Source this after common.bash in integration test files.

# set_http_response <status> <body>
# Override http_json to return a fixed response without making network calls.
# Uses globals so the values are visible to subshells spawned by command substitution.
# The override persists for the current test file; call it before each fetch test.
_MOCK_HTTP_STATUS=""
_MOCK_HTTP_BODY=""
set_http_response() {
  _MOCK_HTTP_STATUS="$1"
  _MOCK_HTTP_BODY="$2"
  http_json() {
    HTTP_STATUS="$_MOCK_HTTP_STATUS"
    HTTP_BODY="$_MOCK_HTTP_BODY"
  }
}

# with_tmp_home <command...>
# Run a command with HOME set to a fresh temp directory. Restores HOME after.
_MOCK_TMP_HOME=""
make_tmp_home() {
  _MOCK_TMP_HOME=$(mktemp -d)
  printf "%s" "$_MOCK_TMP_HOME"
}
cleanup_tmp_home() {
  [[ -n "$_MOCK_TMP_HOME" ]] && rm -rf "$_MOCK_TMP_HOME"
  _MOCK_TMP_HOME=""
}

# Cross-platform file permission check: outputs octal mode (e.g. "600")
file_perms() {
  stat -f "%OLp" "$1" 2>/dev/null || stat -c "%a" "$1" 2>/dev/null
}
