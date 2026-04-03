#!/usr/bin/env bash
# Test helpers and assertion framework for aiusage tests.
# Source this from a test script to load aiusage functions and assertion helpers.

# ── paths ─────────────────────────────────────────────────
_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIUSAGE_DIR="$(cd "$_HELPERS_DIR/../.." && pwd)"
AIUSAGE_SCRIPT="$AIUSAGE_DIR/aiusage"

# Source aiusage to expose its functions without executing the CLI entry point.
source "$AIUSAGE_SCRIPT"

# Disable strict mode inherited from aiusage so test assertions can call
# functions that intentionally return non-zero.
set +euo pipefail 2>/dev/null || true

# ── counters ──────────────────────────────────────────────
_PASS=0
_FAIL=0
_SKIP=0

# ── assertion helpers ─────────────────────────────────────

pass() {
  _PASS=$((_PASS + 1))
  printf "PASS %s\n" "$1"
}

fail() {
  _FAIL=$((_FAIL + 1))
  printf "FAIL %s: %s\n" "$1" "$2"
}

skip() {
  _SKIP=$((_SKIP + 1))
  printf "SKIP %s: %s\n" "$1" "${2:-}"
}

assert_eq() {
  local expected="$1" actual="$2" desc="${3:-assert_eq}"
  if [[ "$expected" == "$actual" ]]; then
    pass "$desc"
  else
    fail "$desc" "expected='$expected' got='$actual'"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" desc="${3:-assert_contains}"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc" "'$needle' not found in output"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" desc="${3:-assert_not_contains}"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc" "'$needle' unexpectedly found in output"
  fi
}

# assert_exit_0 <description> <command> [args...]
assert_exit_0() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc" "expected exit 0"
  fi
}

# assert_exit_1 <description> <command> [args...]
assert_exit_1() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    fail "$desc" "expected non-zero exit"
  else
    pass "$desc"
  fi
}

# ── summary ───────────────────────────────────────────────
_test_summary() {
  printf "\n  %d passed, %d failed" "$_PASS" "$_FAIL"
  ((_SKIP > 0)) && printf ", %d skipped" "$_SKIP"
  printf " in %s\n" "$(basename "$0")"
}

trap _test_summary EXIT
