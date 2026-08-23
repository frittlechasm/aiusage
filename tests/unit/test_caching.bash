#!/usr/bin/env bash
# Unit tests: linux_secure_cache_write, linux_ttl_cache_read
# shellcheck source=../helpers/common.bash
source "$(dirname "$0")/../helpers/common.bash"
source "$(dirname "$0")/../helpers/mock_setup.bash"

# ── linux_secure_cache_write (cross-platform) ─────────────

tmp_dir=$(mktemp -d)
cache_file="$tmp_dir/subdir/test_cache"

linux_secure_cache_write "$cache_file" "secret_value"
assert_eq "secret_value" "$(cat "$cache_file")"                "secure_write: stores value"
assert_eq "600"          "$(file_perms "$cache_file")"         "secure_write: 0600 permissions"

# Overwrite updates content but keeps permissions
linux_secure_cache_write "$cache_file" "updated_value"
assert_eq "updated_value" "$(cat "$cache_file")"               "secure_write: overwrites existing"
assert_eq "600"           "$(file_perms "$cache_file")"        "secure_write: permissions preserved on overwrite"

# Works with nested directories
deep_file="$tmp_dir/a/b/c/deep_cache"
linux_secure_cache_write "$deep_file" "nested"
assert_eq "nested" "$(cat "$deep_file")"                       "secure_write: creates nested dirs"

rm -rf "$tmp_dir"

# ── linux_secure_cache_write: symlink safety ──────────────

tmp_dir=$(mktemp -d)
victim="$tmp_dir/victim"
printf "original" >"$victim"
ln -s "$victim" "$tmp_dir/link"

linux_secure_cache_write "$tmp_dir/link" "secret_value"
assert_eq "original"    "$(cat "$victim")"                "secure_write: symlink target untouched"
assert_exit_1 "secure_write: symlink replaced, not followed" test -L "$tmp_dir/link"
assert_eq "secret_value" "$(cat "$tmp_dir/link")"         "secure_write: value at original path"
assert_eq "600"          "$(file_perms "$tmp_dir/link")"  "secure_write: replaced file keeps 0600"

rm -rf "$tmp_dir"

# ── linux_ttl_cache_read (Linux only) ─────────────────────

if [[ "$(uname)" != "Linux" ]]; then
  skip "ttl_read: within-TTL hit"          "Linux-only (stat -c %Y)"
  skip "ttl_read: missing file returns empty" "Linux-only (stat -c %Y)"
  skip "ttl_read: TTL=0 always expired"    "Linux-only (stat -c %Y)"
  skip "ttl_read: expired file is deleted" "Linux-only (stat -c %Y)"
else
  tmp_cache=$(mktemp)
  printf "cached_data" > "$tmp_cache"

  result=$(linux_ttl_cache_read "$tmp_cache" 3600)
  assert_eq "cached_data" "$result"              "ttl_read: returns content within TTL"

  # Missing file returns empty / non-zero
  rm -f "$tmp_cache"
  result=$(linux_ttl_cache_read "$tmp_cache" 3600) || true
  assert_eq "" "$result"                         "ttl_read: missing file returns empty"

  # TTL=0 means every file is immediately expired
  tmp_cache2=$(mktemp)
  printf "stale" > "$tmp_cache2"
  result=$(linux_ttl_cache_read "$tmp_cache2" 0) || true
  assert_eq "" "$result"                         "ttl_read: TTL=0 always expired"
  assert_exit_1 "ttl_read: expired file is deleted" test -f "$tmp_cache2"
fi

# ── file_mtime (cross-platform) ───────────────────────────

tmp_mt=$(mktemp)
mt=$(file_mtime "$tmp_mt")
now=$(date +%s)
case "$mt" in
  '' | *[!0-9]*)
    fail "file_mtime: returns numeric mtime" "got='$mt'"
    ;;
  *)
    if ((mt >= now - 60 && mt <= now + 60)); then
      pass "file_mtime: returns numeric mtime"
    else
      fail "file_mtime: returns numeric mtime" "mtime=$mt now=$now"
    fi
    ;;
esac
assert_eq "0" "$(file_mtime "$tmp_dir/nonexistent")" "file_mtime: missing file → 0"
rm -f "$tmp_mt"

# ── macos_keychain_clear output ───────────────────────────

keychain_output=$(
  exec 2>&1
  security() {
    printf 'deleted keychain metadata\n'
    printf 'security diagnostic\n' >&2
  }
  macos_keychain_clear "aiusage-test-session"
)
assert_eq "" "$keychain_output" "keychain_clear: suppresses security command output"

# ── find_jetbrains_quota_file ─────────────────────────────

fake_home=$(mktemp -d)
quota_xml="$fake_home/.config/JetBrains/proj/options/AIAssistantQuotaManager2.xml"
mkdir -p "$(dirname "$quota_xml")"
printf 'x' >"$quota_xml"

found=$(
  set -e
  HOME="$fake_home" find_jetbrains_quota_file
)
assert_contains "$found" "AIAssistantQuotaManager2.xml" "jetbrains_quota: finds quota file under fake HOME"

rm -rf "$fake_home"

# ── _cursor_cookie_firefox: WAL-aware snapshot ────────────

if command -v sqlite3 >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  ff_home=$(mktemp -d)
  if [[ "$OSTYPE" == darwin* ]]; then
    prof_root="$ff_home/Library/Application Support/Firefox/Profiles"
  else
    prof_root="$ff_home/.mozilla/firefox"
  fi
  prof="$prof_root/abc123.default-release"
  mkdir -p "$prof"

  # Commit the cookie but exit without closing the connection, so the
  # committed row exists only in cookies.sqlite-wal.
  python3 - "$prof" <<'PY' || true
import sqlite3, sys, os
prof = sys.argv[1]
conn = sqlite3.connect(prof + "/cookies.sqlite")
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("CREATE TABLE moz_cookies(host TEXT, name TEXT, value TEXT)")
conn.execute("INSERT INTO moz_cookies VALUES ('https://cursor.com','WorkosCursorSessionToken','wal-token')")
conn.commit()
assert os.path.exists(prof + "/cookies.sqlite-wal"), "wal file missing after commit"
os._exit(0)
PY

  if [[ -f "$prof/cookies.sqlite-wal" ]]; then
    val=$(HOME="$ff_home" _cursor_cookie_firefox)
    assert_eq "wal-token" "$val" "cursor_firefox: recovers cookie committed only to WAL"
  else
    skip "cursor_firefox: WAL-only cookie recovered" "sqlite checkpointed the WAL on its own"
  fi

  rm -rf "$ff_home"
else
  skip "cursor_firefox: WAL-aware snapshot" "requires sqlite3 and python3"
fi
