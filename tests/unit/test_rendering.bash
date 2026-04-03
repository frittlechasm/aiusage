#!/usr/bin/env bash
# Unit tests: draw_bar, draw_unavailable, draw_error, draw_http_error, spinner_frame
# Colors are empty in non-TTY test context, making bar content predictable.
# shellcheck source=../helpers/common.bash
source "$(dirname "$0")/../helpers/common.bash"

# ── draw_bar ──────────────────────────────────────────────
# BAR_WIDTH=20; filled = percent * 20 / 100; empty = 20 - filled

out=$(draw_bar "5h" 0)
assert_contains "$out" "5h"                     "draw_bar 0%: shows label"
assert_contains "$out" "0%"                     "draw_bar 0%: shows percentage"
assert_contains "$out" "░░░░░░░░░░░░░░░░░░░░"  "draw_bar 0%: all 20 chars empty"

out=$(draw_bar "5h" 100)
assert_contains "$out" "100%"                   "draw_bar 100%: shows percentage"
assert_contains "$out" "████████████████████"  "draw_bar 100%: all 20 chars filled"

out=$(draw_bar "5h" 50)
assert_contains "$out" "50%"                    "draw_bar 50%: shows percentage"
assert_contains "$out" "██████████░░░░░░░░░░"  "draw_bar 50%: 10 filled + 10 empty"

out=$(draw_bar "Weekly" 30)
assert_contains "$out" "Weekly"                 "draw_bar: shows custom label"
assert_contains "$out" "30%"                    "draw_bar: shows 30%"
# 30% of 20 = 6 filled, 14 empty
assert_contains "$out" "██████░░░░░░░░░░░░░░"  "draw_bar 30%: 6 filled + 14 empty"

# Clamping
out=$(draw_bar "5h" -5)
assert_contains "$out" "0%"                     "draw_bar: negative clamped to 0"
assert_not_contains "$out" "-5"                 "draw_bar: negative value not shown"

out=$(draw_bar "5h" 150)
assert_contains "$out" "100%"                   "draw_bar: over 100 clamped to 100"
assert_contains "$out" "████████████████████"  "draw_bar over 100: all filled (clamped)"

# Decimal percent — truncated via ${percent%.*}
out=$(draw_bar "5h" "72.9")
assert_contains "$out" "72%"                    "draw_bar: decimal percent truncated"

out=$(draw_bar "Extra" "0.5")
assert_contains "$out" "0%"                     "draw_bar: fractional under 1% truncated to 0"

# ── draw_unavailable ──────────────────────────────────────

out=$(draw_unavailable "Weekly")
assert_contains "$out" "Weekly"                 "draw_unavailable: shows label"
assert_contains "$out" "--%"                    "draw_unavailable: shows --%"
assert_contains "$out" "░░░░░░░░░░░░░░░░░░░░"  "draw_unavailable: full empty bar"
assert_not_contains "$out" "█"                  "draw_unavailable: no filled chars"

out=$(draw_unavailable "5h")
assert_contains "$out" "5h"                     "draw_unavailable: shows different label"

# ── draw_error ────────────────────────────────────────────

out=$(draw_error "something went wrong")
assert_contains "$out" "error:"                 "draw_error: contains 'error:'"
assert_contains "$out" "something went wrong"   "draw_error: contains the message"

out=$(draw_error "")
assert_contains "$out" "error:"                 "draw_error: works with empty message"

# ── draw_http_error ───────────────────────────────────────

out=$(draw_http_error "401" "session expired")
assert_contains "$out" "session expired"        "draw_http_error 401: shows expired_msg"
assert_contains "$out" "error:"                 "draw_http_error 401: shows error prefix"

out=$(draw_http_error "403" "access denied")
assert_contains "$out" "access denied"          "draw_http_error 403: shows expired_msg"

out=$(draw_http_error "000" "ignored_msg")
assert_contains "$out" "network error"          "draw_http_error 000: network error message"
assert_not_contains "$out" "ignored_msg"        "draw_http_error 000: ignores expired_msg param"

out=$(draw_http_error "500" "ignored_msg")
assert_contains "$out" "HTTP 500"               "draw_http_error 500: shows HTTP status code"

out=$(draw_http_error "429" "ignored_msg")
assert_contains "$out" "HTTP 429"               "draw_http_error 429: shows HTTP status code"

out=$(draw_http_error "503" "ignored_msg")
assert_contains "$out" "HTTP 503"               "draw_http_error 503: shows HTTP status code"

# ── spinner_frame ─────────────────────────────────────────
# SPINNER_FRAMES=('|' '/' '-' '\')

assert_eq "|" "$(spinner_frame 0)"  "spinner_frame: frame 0 → |"
assert_eq "/" "$(spinner_frame 1)"  "spinner_frame: frame 1 → /"
assert_eq "-" "$(spinner_frame 2)"  "spinner_frame: frame 2 → -"
assert_eq '\' "$(spinner_frame 3)"  "spinner_frame: frame 3 → \\"
assert_eq "|" "$(spinner_frame 4)"  "spinner_frame: frame 4 wraps → |"
assert_eq "/" "$(spinner_frame 5)"  "spinner_frame: frame 5 wraps → /"
assert_eq "|" "$(spinner_frame 8)"  "spinner_frame: frame 8 wraps → |"
