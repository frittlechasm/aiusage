#!/usr/bin/env bash
# Unit tests: calculate_percent, calculate_used_percent_from_remaining,
# numeric_or, percent_remaining_of
# shellcheck source=../helpers/common.bash
source "$(dirname "$0")/../helpers/common.bash"

# ── calculate_percent ─────────────────────────────────────

assert_eq "50"  "$(calculate_percent 50 100)"    "calculate_percent: 50/100 = 50"
assert_eq "0"   "$(calculate_percent 0 100)"     "calculate_percent: 0/100 = 0"
assert_eq "100" "$(calculate_percent 100 100)"   "calculate_percent: 100/100 = 100"
assert_eq "33"  "$(calculate_percent 1 3)"       "calculate_percent: 1/3 rounds down to 33"
assert_eq "67"  "$(calculate_percent 2 3)"       "calculate_percent: 2/3 rounds to 67"
assert_eq "25"  "$(calculate_percent 25 100)"    "calculate_percent: 25/100 = 25"
assert_eq "0"   "$(calculate_percent 0 0)"       "calculate_percent: 0/0 uses default fallback (0)"
assert_eq "42"  "$(calculate_percent 0 0 42)"    "calculate_percent: 0/0 uses custom fallback"
assert_eq "150" "$(calculate_percent 150 100)"   "calculate_percent: over 100 not clamped (rendering clamps)"
assert_eq "1"   "$(calculate_percent 1 100)"     "calculate_percent: 1/100 = 1"

# ── calculate_used_percent_from_remaining ─────────────────

assert_eq "50"  "$(calculate_used_percent_from_remaining 50)"       "used_from_remaining: 50 remaining → 50 used"
assert_eq "100" "$(calculate_used_percent_from_remaining 0)"        "used_from_remaining: 0 remaining → 100 used"
assert_eq "0"   "$(calculate_used_percent_from_remaining 100)"      "used_from_remaining: 100 remaining → 0 used"
assert_eq "75"  "$(calculate_used_percent_from_remaining 25)"       "used_from_remaining: 25 remaining → 75 used"
assert_eq "30"  "$(calculate_used_percent_from_remaining 70)"       "used_from_remaining: 70 remaining → 30 used"
assert_eq "7"   "$(calculate_used_percent_from_remaining 'null' 7)" "used_from_remaining: null uses fallback"
assert_eq "9"   "$(calculate_used_percent_from_remaining '' 9)"     "used_from_remaining: empty uses fallback"
assert_eq "0"   "$(calculate_used_percent_from_remaining 'null')"   "used_from_remaining: null uses default fallback (0)"
assert_eq "0"   "$(calculate_used_percent_from_remaining '')"       "used_from_remaining: empty uses default fallback (0)"

# ── numeric_or ────────────────────────────────────────────

assert_eq "5"    "$(numeric_or 5 9)"          "numeric_or: integer passes through"
assert_eq "72.5" "$(numeric_or 72.5 9)"       "numeric_or: decimal passes through"
assert_eq "-3"   "$(numeric_or -3 9)"         "numeric_or: negative integer passes through"
assert_eq "-1.5" "$(numeric_or -1.5 9)"       "numeric_or: negative decimal passes through"
assert_eq "9"    "$(numeric_or abc 9)"        "numeric_or: garbage uses fallback"
assert_eq "9"    "$(numeric_or '' 9)"         "numeric_or: empty uses fallback"
assert_eq "0"    "$(numeric_or 'null')"       "numeric_or: null uses default fallback (0)"
assert_eq ""     "$(numeric_or abc '')"       "numeric_or: empty fallback stays empty"
assert_eq "8"    "$(numeric_or 08 9)"         "numeric_or: leading zeros stripped (octal-safe)"
assert_eq "-9.5" "$(numeric_or -09.5 9)"      "numeric_or: leading zeros stripped on negatives"
assert_eq "0"    "$(numeric_or 00 9)"         "numeric_or: bare zero stays zero"

# ── percent_remaining_of ──────────────────────────────────

assert_eq "50.0" "$(percent_remaining_of 100 50)"     "percent_remaining_of: half remaining"
assert_eq "0.0"  "$(percent_remaining_of 100 0)"      "percent_remaining_of: none remaining"
assert_eq ""     "$(percent_remaining_of 0 50)"       "percent_remaining_of: zero entitlement → empty"
assert_eq ""     "$(percent_remaining_of abc def)"    "percent_remaining_of: garbage inputs → empty"

# ── copilot_expand_reset ──────────────────────────────────

assert_eq "2026-09-01T00:00:00Z" "$(copilot_expand_reset utc 2026-09-01)"  "expand_reset: date-only utc anchored to UTC"
assert_eq "2026-09-01T00:00:00"  "$(copilot_expand_reset local 2026-09-01)" "expand_reset: date-only local stays naive"
assert_eq "2026-09-01T10:30:00Z" "$(copilot_expand_reset utc '2026-09-01T10:30:00Z')" "expand_reset: datetime passes through"
assert_eq ""                     "$(copilot_expand_reset utc '')"   "expand_reset: empty passes through"

# ── strict-mode safety for untrusted values ───────────────
# Production invokes these helpers under set -euo pipefail; malformed API
# strings must fall back instead of crashing or evaluating as expressions.

out=$(
  set -e
  calculate_percent "abc" ";system(\"echo pwned\")" "7" >/dev/null
  calculate_used_percent_from_remaining '$(id)' "4" >/dev/null
  percent_remaining_of '`id`' 'x' >/dev/null
  printf "OK\n"
)
assert_contains "$out" "OK" "untrusted input: strict-mode helpers survive malformed values"
assert_eq "7"  "$(calculate_percent 'abc' 'def' 7)"   "calculate_percent: non-numeric operands use fallback"
assert_eq "8"  "$(calculate_used_percent_from_remaining 'abc' 8)" "used_from_remaining: non-numeric uses fallback"
