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
