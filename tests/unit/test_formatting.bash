#!/usr/bin/env bash
# Unit tests: xml_unescape, format_remaining, duration_to_label, normalize_epoch
# shellcheck source=../helpers/common.bash
source "$(dirname "$0")/../helpers/common.bash"

# ── xml_unescape ──────────────────────────────────────────

assert_eq "a&b"      "$(xml_unescape 'a&amp;b')"          "xml_unescape: &amp;"
assert_eq "<"        "$(xml_unescape '&lt;')"              "xml_unescape: &lt;"
assert_eq ">"        "$(xml_unescape '&gt;')"              "xml_unescape: &gt;"
assert_eq '"'        "$(xml_unescape '&quot;')"            "xml_unescape: &quot;"
# bash ${var//&apos;/\'} replacement produces \' (backslash+apostrophe) not just '
assert_eq "\'"       "$(xml_unescape '&apos;')"            "xml_unescape: &apos; → \\'"
assert_eq "hello"    "$(xml_unescape 'hello')"             "xml_unescape: passthrough unchanged"
assert_eq ""         "$(xml_unescape '')"                  "xml_unescape: empty string"
assert_eq 'a<b>&c'   "$(xml_unescape 'a&lt;b&gt;&amp;c')" "xml_unescape: multiple entities"
assert_eq "&&"       "$(xml_unescape '&amp;&amp;')"        "xml_unescape: consecutive &amp;"

# ── format_remaining ──────────────────────────────────────

assert_eq "now"    "$(format_remaining 0)"       "format_remaining: 0 → now"
assert_eq "now"    "$(format_remaining -1)"      "format_remaining: negative → now"
assert_eq "now"    "$(format_remaining -100)"    "format_remaining: large negative → now"
assert_eq "1m"     "$(format_remaining 60)"      "format_remaining: 1 minute"
assert_eq "5m"     "$(format_remaining 300)"     "format_remaining: 5 minutes"
assert_eq "59m"    "$(format_remaining 3540)"    "format_remaining: 59 minutes"
assert_eq "1h 0m"  "$(format_remaining 3600)"    "format_remaining: exactly 1 hour"
assert_eq "1h 1m"  "$(format_remaining 3661)"    "format_remaining: 1h 1m"
assert_eq "2h 30m" "$(format_remaining 9000)"    "format_remaining: 2.5 hours"
assert_eq "23h 59m" "$(format_remaining 86340)"  "format_remaining: just under 1 day"
assert_eq "1d 0h"  "$(format_remaining 86400)"   "format_remaining: exactly 1 day"
assert_eq "1d 1h"  "$(format_remaining 90000)"   "format_remaining: 1 day 1 hour"
assert_eq "7d 0h"  "$(format_remaining 604800)"  "format_remaining: exactly 7 days"
assert_eq "unknown" "$(format_remaining '')"     "format_remaining: empty → unknown"

# ── duration_to_label ─────────────────────────────────────

assert_eq "1h"      "$(duration_to_label 'PT1H')"   "duration_to_label: PT1H"
assert_eq "5h"      "$(duration_to_label 'PT5H')"   "duration_to_label: PT5H"
assert_eq "1d"      "$(duration_to_label 'PT24H')"  "duration_to_label: PT24H → 1d"
assert_eq "2d"      "$(duration_to_label 'PT48H')"  "duration_to_label: PT48H → 2d"
assert_eq "1d"      "$(duration_to_label 'P1D')"    "duration_to_label: P1D"
assert_eq "7d"      "$(duration_to_label 'P7D')"    "duration_to_label: P7D"
assert_eq "30d"     "$(duration_to_label 'P30D')"   "duration_to_label: P30D"
assert_eq "Credits" "$(duration_to_label 'P1M')"    "duration_to_label: P1M → Credits (unsupported)"
assert_eq "Credits" "$(duration_to_label '')"       "duration_to_label: empty → Credits"
assert_eq "Credits" "$(duration_to_label 'UNKNOWN')" "duration_to_label: unknown → Credits"

# ── normalize_epoch (numeric inputs — ISO parsing is platform-dependent) ──

assert_eq "1748000000" "$(normalize_epoch '1748000000')"     "normalize_epoch: plain epoch"
assert_eq "1748000000" "$(normalize_epoch '1748000000000')"  "normalize_epoch: milliseconds → seconds"
assert_eq "1748000000" "$(normalize_epoch '1748000000.123')" "normalize_epoch: float truncated"
assert_eq "1000000000" "$(normalize_epoch '1000000000')"     "normalize_epoch: older epoch"
assert_eq ""           "$(normalize_epoch 'null')"           "normalize_epoch: null → empty"
assert_eq ""           "$(normalize_epoch '')"               "normalize_epoch: empty → empty"
# Threshold: strictly > 100_000_000_000 is treated as milliseconds (not >=)
assert_eq "100000000000" "$(normalize_epoch '100000000000')" "normalize_epoch: exactly at threshold (not converted)"
assert_eq "100000000"    "$(normalize_epoch '100000000001')" "normalize_epoch: just above threshold → ms→s"
