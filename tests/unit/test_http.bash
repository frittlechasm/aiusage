#!/usr/bin/env bash
# Exercise the real HTTP helper with a fake curl; never use live credentials.
source "$(dirname "$0")/../helpers/common.bash"

capture_dir=$(mktemp -d)
cleanup_http_test() {
  rm -rf "$capture_dir"
  _test_summary
}
trap cleanup_http_test EXIT

curl() {
  printf '%s\n' "$@" > "$capture_dir/args"
  cat > "$capture_dir/config"
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then
      printf '%s' "$2" > "$capture_dir/output-path"
      printf '{"ok":true}' > "$2"
      break
    fi
    shift
  done
  printf '%s' "${curl_test_status:-200}"
  return "${curl_test_exit:-0}"
}

secret_header='Authorization: Bearer synthetic-private-token'
secret_body=$'{"session":"synthetic-body","escaped":"a\\b\\"c"}\nsecond-line'
(
  set -euo pipefail
  http_json "https://example.test/usage" "$secret_body" "$secret_header"
  printf '%s\n%s' "$HTTP_STATUS" "$HTTP_BODY" > "$capture_dir/result"
)
assert_eq $'200\n{"ok":true}' "$(cat "$capture_dir/result")" "http_json: works in strict mode"
assert_not_contains "$(cat "$capture_dir/args")" "synthetic-private-token" "http_json: header absent from argv"
assert_not_contains "$(cat "$capture_dir/args")" "synthetic-body" "http_json: body absent from argv"
assert_contains "$(cat "$capture_dir/args")" "--config" "http_json: reads config from stdin"
assert_contains "$(cat "$capture_dir/config")" 'header = "Authorization: Bearer synthetic-private-token"' "http_json: sends header through config"
expected_body='data-raw = "{\"session\":\"synthetic-body\",\"escaped\":\"a\\b\\\"c\"}\nsecond-line"'
assert_contains "$(cat "$capture_dir/config")" "$expected_body" "http_json: escapes quotes, backslashes, and newlines"
assert_exit_1 "http_json: removes temporary response file" test -e "$(cat "$capture_dir/output-path")"

http_json "https://example.test/usage" "" "Accept: application/json"
assert_not_contains "$(cat "$capture_dir/config")" "data-raw" "http_json: empty body remains a GET"

curl_test_status=429
http_json "https://example.test/usage" "" "$secret_header"
assert_eq "429" "$HTTP_STATUS" "http_json: preserves HTTP error status"

curl_test_exit=7
http_json "https://example.test/usage" "" "$secret_header"
assert_eq "000" "$HTTP_STATUS" "http_json: network failure is isolated"
assert_exit_1 "http_json: failure removes temporary response file" test -e "$(cat "$capture_dir/output-path")"

exit "$((_FAIL > 0))"
