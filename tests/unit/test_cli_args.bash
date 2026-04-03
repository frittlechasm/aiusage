#!/usr/bin/env bash
# Unit tests: provider_is_known, provider_label, provider_list_contains,
# provider_unavailable_message, and CLI argument parsing (subprocess).
# shellcheck source=../helpers/common.bash
source "$(dirname "$0")/../helpers/common.bash"

# ── provider_is_known ─────────────────────────────────────

assert_exit_0 "provider_is_known: claude"    provider_is_known "claude"
assert_exit_0 "provider_is_known: codex"     provider_is_known "codex"
assert_exit_0 "provider_is_known: cursor"    provider_is_known "cursor"
assert_exit_0 "provider_is_known: gemini"    provider_is_known "gemini"
assert_exit_0 "provider_is_known: jetbrains" provider_is_known "jetbrains"
assert_exit_0 "provider_is_known: copilot"   provider_is_known "copilot"
assert_exit_1 "provider_is_known: openai"    provider_is_known "openai"
assert_exit_1 "provider_is_known: foobar"    provider_is_known "foobar"
assert_exit_1 "provider_is_known: empty"     provider_is_known ""
assert_exit_1 "provider_is_known: CLAUDE uppercase" provider_is_known "CLAUDE"

# ── provider_label ────────────────────────────────────────

assert_eq "Claude"    "$(provider_label 'claude')"    "provider_label: claude"
assert_eq "Codex"     "$(provider_label 'codex')"     "provider_label: codex"
assert_eq "Cursor"    "$(provider_label 'cursor')"    "provider_label: cursor"
assert_eq "Gemini"    "$(provider_label 'gemini')"    "provider_label: gemini"
assert_eq "JetBrains" "$(provider_label 'jetbrains')" "provider_label: jetbrains"
assert_eq "Copilot"   "$(provider_label 'copilot')"   "provider_label: copilot"

# ── provider_list_contains ────────────────────────────────

assert_exit_0 "list_contains: item in middle"  provider_list_contains "foo" "bar" "foo" "baz"
assert_exit_0 "list_contains: item at start"   provider_list_contains "bar" "bar" "foo" "baz"
assert_exit_0 "list_contains: item at end"     provider_list_contains "baz" "bar" "foo" "baz"
assert_exit_0 "list_contains: single match"    provider_list_contains "x" "x"
assert_exit_1 "list_contains: item absent"     provider_list_contains "foo" "bar" "baz"
assert_exit_1 "list_contains: empty list"      provider_list_contains "foo"

# ── provider_unavailable_message ──────────────────────────

out=$(provider_unavailable_message "claude")
assert_contains "$out" "claude"     "unavailable_message: claude mentions provider"

out=$(provider_unavailable_message "cursor")
assert_contains "$out" "CURSOR_COOKIE" "unavailable_message: cursor mentions env var"

out=$(provider_unavailable_message "copilot")
assert_contains "$out" "COPILOT_GITHUB_TOKEN" "unavailable_message: copilot mentions env var"

# ── CLI: help flags (subprocess) ──────────────────────────

out=$(bash "$AIUSAGE_SCRIPT" --help 2>&1); code=$?
assert_eq "0" "$code"           "--help: exits 0"
assert_contains "$out" "Usage:" "--help: shows usage header"
assert_contains "$out" "claude" "--help: lists providers"

out=$(bash "$AIUSAGE_SCRIPT" -h 2>&1); code=$?
assert_eq "0" "$code"           "-h: exits 0"
assert_contains "$out" "Usage:" "-h: shows usage header"

out=$(bash "$AIUSAGE_SCRIPT" help 2>&1); code=$?
assert_eq "0" "$code"           "help: exits 0"
assert_contains "$out" "Usage:" "help: shows usage header"

# An exported test-only environment variable must not disable normal CLI execution.
out=$(env AIUSAGE_SOURCED=1 bash "$AIUSAGE_SCRIPT" --help 2>&1); code=$?
assert_eq "0" "$code"           "AIUSAGE_SOURCED env: --help still exits 0"
assert_contains "$out" "Usage:" "AIUSAGE_SOURCED env: --help still shows usage header"

# ── CLI: unknown provider (subprocess) ────────────────────

bash "$AIUSAGE_SCRIPT" notaprovider >/dev/null 2>&1; code=$?
assert_eq "1" "$code"                             "unknown provider: exits 1"

err=$(bash "$AIUSAGE_SCRIPT" notaprovider 2>&1 >/dev/null) || true
assert_contains     "$err" "Unknown provider"     "unknown provider: error message"
assert_contains     "$err" "notaprovider"         "unknown provider: names the bad provider"
assert_contains     "$err" "Usage:"               "unknown provider: shows usage hint"

# ── CLI: known providers parse without hitting provider backends ──

run_named_providers() { return 0; }
run_all_parallel() { return 0; }

for p in claude codex cursor gemini jetbrains copilot; do
  err=$(run_from_args "$p" 2>&1); code=$?
  assert_eq "0" "$code" "known provider '$p': exits 0"
  assert_not_contains "$err" "Unknown provider" "known provider '$p': not flagged as unknown"
done
