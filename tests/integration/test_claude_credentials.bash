#!/usr/bin/env bash
# Exercise credential selection in strict subprocesses without real credentials.
source "$(dirname "$0")/../helpers/common.bash"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; _test_summary' EXIT
mkdir -p "$tmp/.claude"
printf '%s' '{"claudeAiOauth":{"accessToken":"file-token"}}' > "$tmp/.claude/.credentials.json"

for scenario in keychain missing empty malformed linux; do
  out=$(HOME="$tmp" bash -c '
    source "$1"
    scenario="$2"
    OSTYPE=darwin
    expected=keychain-token
    [[ "$scenario" == keychain ]] || expected=file-token
    [[ "$scenario" != linux ]] || OSTYPE=linux-gnu
    macos_keychain_read() {
      case "$scenario" in
        keychain) printf "%s" "{\"claudeAiOauth\":{\"accessToken\":\"keychain-token\"}}" ;;
        missing) return 1 ;;
        empty) printf "%s" "{}" ;;
        malformed) printf "%s" "invalid JSON" ;;
        linux) echo unexpected-keychain-read >&2; return 1 ;;
      esac
    }
    http_json() {
      [[ "$3" == "Authorization: Bearer $expected" ]] || {
        echo wrong-credential >&2
        return 1
      }
      HTTP_STATUS=200
      HTTP_BODY="{\"five_hour\":{\"utilization\":42}}"
    }
    fetch_claude
  ' _ "$AIUSAGE_SCRIPT" "$scenario" 2>&1)
  code=$?
  assert_eq "0" "$code" "Claude credentials ($scenario): succeeds under strict mode"
  assert_contains "$out" "42%" "Claude credentials ($scenario): uses expected token"
  assert_not_contains "$out" "unexpected-keychain-read" "Claude credentials ($scenario): respects platform"
done

