#!/usr/bin/env bash
# Unit tests: installer command behavior.
# shellcheck source=../helpers/common.bash
source "$(dirname "$0")/../helpers/common.bash"

AIUSAGE_INSTALLER="$AIUSAGE_DIR/install.sh"
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"; _test_summary' EXIT

deps_bin="$tmp_root/deps-bin"
mkdir -p "$deps_bin"
printf '#!/usr/bin/env sh\nexit 0\n' >"$deps_bin/jq"
printf '#!/usr/bin/env sh\nexit 0\n' >"$deps_bin/curl"
chmod 755 "$deps_bin/jq" "$deps_bin/curl"
test_path="$deps_bin:/usr/bin:/bin"

# ── no-argument install path ──────────────────────────────

home_dir="$tmp_root/default-home"
mkdir -p "$home_dir"
default_dir="$home_dir/.local/bin"

out=$(env HOME="$home_dir" SHELL="/bin/bash" PATH="$test_path" AIUSAGE_INSTALL_SOURCE="$AIUSAGE_SCRIPT" \
  sh "$AIUSAGE_INSTALLER" 2>&1)
code=$?

assert_eq "0" "$code" "install default: exits 0"
assert_contains "$out" "installed $default_dir/aiusage" "install default: reports installed path"
assert_contains "$out" "added $default_dir to PATH in $home_dir/.bashrc" "install default: updates profile"

if [[ -x "$default_dir/aiusage" ]]; then
  pass "install default: creates executable"
else
  fail "install default: creates executable" "expected executable at $default_dir/aiusage"
fi

out=$(bash "$default_dir/aiusage" --help 2>&1)
code=$?
assert_eq "0" "$code" "installed script: --help exits 0"
assert_contains "$out" "Usage: aiusage" "installed script: --help works"

# ── explicit install dir without PATH update ──────────────

install_dir="$tmp_root/bin"
out=$(env PATH="$test_path" sh "$AIUSAGE_INSTALLER" --source "$AIUSAGE_SCRIPT" --dir "$install_dir" --no-path-update 2>&1)
code=$?

assert_eq "0" "$code" "install explicit: exits 0"
assert_contains "$out" "installed $install_dir/aiusage" "install explicit: reports installed path"
assert_contains "$out" "add $install_dir to PATH" "install explicit: reports PATH hint with --no-path-update"

# ── PATH profile update ───────────────────────────────────

home_dir="$tmp_root/path-home"
mkdir -p "$home_dir"
path_dir="$tmp_root/path-bin"

out=$(env HOME="$home_dir" SHELL="/bin/bash" PATH="$test_path" \
  sh "$AIUSAGE_INSTALLER" --source "$AIUSAGE_SCRIPT" --dir "$path_dir" 2>&1)
code=$?

assert_eq "0" "$code" "install: path update exits 0"
assert_contains "$out" "added $path_dir to PATH in $home_dir/.bashrc" "install: reports profile update"
assert_contains "$(cat "$home_dir/.bashrc")" "export PATH=\"$path_dir:\$PATH\"" "install: writes PATH export"

out=$(env HOME="$home_dir" SHELL="/bin/bash" PATH="$test_path" \
  sh "$AIUSAGE_INSTALLER" --source "$AIUSAGE_SCRIPT" --dir "$path_dir" 2>&1)
code=$?

assert_eq "0" "$code" "install: repeated path update exits 0"
assert_contains "$out" "already updates PATH" "install: repeated update is idempotent"

# ── zsh profile update ────────────────────────────────────

zsh_home="$tmp_root/zsh-home"
mkdir -p "$zsh_home"
zsh_dir="$tmp_root/zsh-bin"

out=$(env HOME="$zsh_home" SHELL="/bin/zsh" PATH="$test_path" \
  sh "$AIUSAGE_INSTALLER" --source "$AIUSAGE_SCRIPT" --dir "$zsh_dir" 2>&1)
code=$?

assert_eq "0" "$code" "install zsh: path update exits 0"
assert_contains "$out" "added $zsh_dir to PATH in $zsh_home/.zshrc" "install zsh: updates .zshrc"
assert_contains "$out" "added $zsh_dir to PATH in $zsh_home/.zprofile" "install zsh: updates .zprofile"
assert_contains "$(cat "$zsh_home/.zshrc")" "export PATH=\"$zsh_dir:\$PATH\"" "install zsh: writes .zshrc"
assert_contains "$(cat "$zsh_home/.zprofile")" "export PATH=\"$zsh_dir:\$PATH\"" "install zsh: writes .zprofile"

# ── invalid inputs ────────────────────────────────────────

env PATH="$test_path" sh "$AIUSAGE_INSTALLER" --source "$tmp_root/missing" --dir "$tmp_root/missing-bin" >/dev/null 2>&1
code=$?
assert_eq "1" "$code" "install: missing source exits 1"

out=$(env PATH="/bin" /bin/sh "$AIUSAGE_INSTALLER" --source "$AIUSAGE_SCRIPT" --dir "$tmp_root/no-deps-bin" 2>&1)
code=$?
assert_eq "1" "$code" "install: missing deps exits 1"
assert_contains "$out" "missing required dependencies" "install: missing deps reports dependency error"
assert_contains "$out" "Install missing dependencies" "install: missing deps prints install hint"

out=$(env PATH="$test_path" sh "$AIUSAGE_INSTALLER" --help 2>&1)
code=$?
assert_eq "0" "$code" "install --help: exits 0"
assert_contains "$out" "Usage: install.sh" "install --help: shows installer usage"
