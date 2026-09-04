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

# Cross-platform file permission check: outputs octal mode (e.g. "600")
file_perms() {
  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f "%OLp" "$1"
  else
    stat -c "%a" "$1"
  fi
}
