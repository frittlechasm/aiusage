#!/usr/bin/env bash
# Unit tests: draw_bar, draw_unavailable, draw_error, draw_http_error
# Colors are empty in non-TTY test context, making bar content predictable.
# shellcheck source=../helpers/common.bash
source "$(dirname "$0")/../helpers/common.bash"

# ── draw_bar ──────────────────────────────────────────────
# BAR_WIDTH=20; filled = percent * 20 / 100; empty = 20 - filled

out=$(draw_bar "5h" 0)
assert_contains "$out" "5h"                     "draw_bar 0%: shows label"
assert_eq "0%" "$(printf '%s\n' "$out" | awk '{ print $NF }')" "draw_bar 0%: shows exact percentage"
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
assert_eq "0%" "$(printf '%s\n' "$out" | awk '{ print $NF }')" "draw_bar: negative clamped to 0"
assert_not_contains "$out" "-5"                 "draw_bar: negative value not shown"

out=$(draw_bar "5h" 150)
assert_contains "$out" "100%"                   "draw_bar: over 100 clamped to 100"
assert_contains "$out" "████████████████████"  "draw_bar over 100: all filled (clamped)"

# Decimal percent — truncated via ${percent%.*}
out=$(draw_bar "5h" "72.9")
assert_contains "$out" "72%"                    "draw_bar: decimal percent truncated"

out=$(draw_bar "Extra" "0.5")
assert_eq "0%" "$(printf '%s\n' "$out" | awk '{ print $NF }')" "draw_bar: fractional under 1% truncated to 0"

# Malformed percent from an API must render as 0%, not crash or evaluate.
out=$(draw_bar "5h" "abc")
assert_eq "0%" "$(printf '%s\n' "$out" | awk '{ print $NF }')" "draw_bar: non-numeric percent renders as 0"

out=$(
  set -e
  draw_bar "5h" '$(id)' >/dev/null
  printf "OK\n"
)
assert_contains "$out" "OK"                     "draw_bar: strict-mode survives expression-like input"

# Optional notes stay on the bar line.
out=$(draw_bar "Weekly" 30 "3 resets")
assert_contains "$out" "· 3 resets"             "draw_bar: shows an inline note"
assert_eq "1" "$(printf '%s\n' "$out" | awk 'END { print NR }')" "draw_bar: inline note adds no rows"

# ── draw_unavailable ──────────────────────────────────────

out=$(draw_unavailable "Weekly")
assert_contains "$out" "Weekly"                 "draw_unavailable: shows label"
assert_contains "$out" "--%"                    "draw_unavailable: shows --%"
assert_contains "$out" "░░░░░░░░░░░░░░░░░░░░"  "draw_unavailable: full empty bar"
assert_not_contains "$out" "█"                  "draw_unavailable: no filled chars"

out=$(draw_unavailable "5h")
assert_contains "$out" "5h"                     "draw_unavailable: shows different label"

out=$(draw_unavailable "Usage" "0 resets")
assert_contains "$out" "· 0 resets"             "draw_unavailable: shows an inline note"

# ── draw_banked_resets ───────────────────────────────────

out=$(draw_banked_resets "2" "10")
assert_contains "$out" "banked:"                "draw_banked_resets: uses a separate supporting line"
assert_contains "$out" "2 resets"               "draw_banked_resets: shows the inventory count"

out=$(draw_banked_resets "1" "10")
assert_contains "$out" "1 reset"                "draw_banked_resets: uses the singular label"
assert_not_contains "$out" "1 resets"            "draw_banked_resets: avoids plural for one"

out=$(draw_banked_resets "0" "10")
assert_contains "$out" "0 resets"               "draw_banked_resets: preserves an explicit zero"

out=$(draw_banked_resets "invalid" "10")
assert_eq "" "$out"                              "draw_banked_resets: omits invalid inventory data"

assert_eq "6" "$(codex_detail_label_width 0)"     "codex detail width: uses reset label without expiries"
assert_eq "10" "$(codex_detail_label_width 2)"   "codex detail width: fits a single-digit banked index"
assert_eq "11" "$(codex_detail_label_width 12)"  "codex detail width: grows for multiple index digits"

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

# ── wait_and_render_fetches ───────────────────────────────

# Regression: ((done_count++)) returns 1 when incrementing from zero, which
# aborted strict-mode runs as soon as the first provider completed.
out=$(
  set -e
  tmp_done=$(mktemp)
  printf 'done line\n' >"$tmp_done"
  tmp_pending=$(mktemp)
  sleep 0.25 & pending_pid=$!
  WAIT_LABELS=("Done" "Pending")
  WAIT_TMPS=("$tmp_done" "$tmp_pending")
  WAIT_PIDS=("$pending_pid")
  wait_and_render_fetches
  printf "COMPLETED\n"
  printf "PIDS_LEFT=%d\n" "${#WAIT_PIDS[@]}"
  rm -f "$tmp_done" "$tmp_pending"
)
assert_contains "$out" "COMPLETED"   "wait loop: survives first completion under set -e"
assert_contains "$out" "Done"        "wait loop: renders completed section"
assert_contains "$out" "done line"   "wait loop: renders worker output"
assert_contains "$out" "Pending"     "wait loop: renders pending section"
assert_contains "$out" "PIDS_LEFT=0" "wait loop: reaped PIDs dropped after wait"

# A worker that crashes under strict mode must render a failure line
# instead of a silently empty section.
out=$(
  set -e
  tmp=$(mktemp)
  ( exit 3 ) & pid=$!
  WAIT_LABELS=("Broken")
  WAIT_TMPS=("$tmp")
  WAIT_PIDS=("$pid")
  wait_and_render_fetches
  rm -f "$tmp"
)
assert_contains "$out" "Broken"              "wait loop: failed worker still shows heading"
assert_contains "$out" "provider check failed" "wait loop: failed worker renders error line"

# A worker that renders output and then crashes must not look successful.
out=$(
  set -e
  tmp=$(mktemp)
  ( echo "5h ██ 42%"; exit 3 ) >"$tmp" & pid=$!
  WAIT_LABELS=("Partial")
  WAIT_TMPS=("$tmp")
  WAIT_PIDS=("$pid")
  wait_and_render_fetches
  rm -f "$tmp"
)
assert_contains "$out" "42%"                 "wait loop: partial worker keeps its output"
assert_contains "$out" "provider check failed" "wait loop: partial worker flagged as failed"

# Worker stderr is captured into its section, not written over the spinner.
out=$(
  tmp=$(mktemp)
  ( echo "boom" >&2 ) >"$tmp" 2>&1 & pid=$!
  WAIT_LABELS=("Noisy")
  WAIT_TMPS=("$tmp")
  WAIT_PIDS=("$pid")
  wait_and_render_fetches
  rm -f "$tmp"
)
assert_contains "$out" "boom"                "wait loop: worker stderr lands in section"

# Full fetch lifecycle under strict mode: cleanup after the wait loop must
# tolerate the emptied PID list (empty array expansion errors on bash < 4.4).
out=$(
  set -eu
  tmp=$(mktemp)
  ( exit 0 ) & pid=$!
  WAIT_LABELS=("Tidy")
  WAIT_TMPS=("$tmp")
  WAIT_PIDS=("$pid")
  wait_and_render_fetches
  cleanup_running_fetches
  printf "CLEAN\n"
)
assert_contains "$out" "CLEAN" "wait loop: cleanup survives emptied PID list under set -u"
