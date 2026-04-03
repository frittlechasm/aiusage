#!/usr/bin/env bash
# Unit tests: calculate_percent, calculate_used_percent_from_remaining
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
