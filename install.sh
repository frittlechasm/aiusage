#!/usr/bin/env sh
set -eu

AIUSAGE_INSTALL_URL="${AIUSAGE_INSTALL_URL:-https://raw.githubusercontent.com/frittlechasm/aiusage/main/aiusage}"
AIUSAGE_INSTALL_SOURCE="${AIUSAGE_INSTALL_SOURCE:-$AIUSAGE_INSTALL_URL}"

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Options:
  --dir DIR           Install aiusage into DIR
  --source PATH|URL   Install from a local file or URL
  --no-path-update    Do not add the install directory to a shell profile

Environment:
  AIUSAGE_INSTALL_DIR     Default install directory
  AIUSAGE_INSTALL_SOURCE  Local file or URL to install from
  AIUSAGE_INSTALL_URL     Default download URL
  AIUSAGE_NO_PATH_UPDATE  Set to 1 to skip shell profile updates
EOF
}

default_install_dir() {
  if [ -n "${AIUSAGE_INSTALL_DIR:-}" ]; then
    printf "%s" "$AIUSAGE_INSTALL_DIR"
    return 0
  fi

  printf "%s" "${HOME:-.}/.local/bin"
}

profile_files() {
  case "${SHELL:-}" in
    */zsh)
      printf "%s\n" "${HOME:-.}/.zshrc"
      printf "%s\n" "${HOME:-.}/.zprofile"
      ;;
    */bash) printf "%s\n" "${HOME:-.}/.bashrc" ;;
    *) printf "%s\n" "${HOME:-.}/.profile" ;;
  esac
}

path_has_dir() {
  case ":${PATH:-}:" in
    *":$1:"*) return 0 ;;
    *) return 1 ;;
  esac
}

required_dependency_install_hint() {
  if [ "$(uname -s 2>/dev/null || true)" = "Darwin" ]; then
    cat <<'EOF'
Install missing dependencies with:
  brew install curl jq
EOF
    return 0
  fi

  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      debian | ubuntu | linuxmint | pop)
        cat <<'EOF'
Install missing dependencies with:
  sudo apt-get update && sudo apt-get install -y curl jq
EOF
        return 0
        ;;
      fedora)
        cat <<'EOF'
Install missing dependencies with:
  sudo dnf install curl jq
EOF
        return 0
        ;;
      rhel | centos | rocky | almalinux)
        cat <<'EOF'
Install missing dependencies with:
  sudo dnf install curl jq
EOF
        return 0
        ;;
      arch | manjaro)
        cat <<'EOF'
Install missing dependencies with:
  sudo pacman -S curl jq
EOF
        return 0
        ;;
      opensuse* | suse)
        cat <<'EOF'
Install missing dependencies with:
  sudo zypper install curl jq
EOF
        return 0
        ;;
    esac
  fi

  cat <<'EOF'
Install missing dependencies with your OS package manager:
  curl jq
EOF
}

check_required_dependencies() {
  missing=""

  for dep in curl jq; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      if [ -n "$missing" ]; then
        missing="$missing $dep"
      else
        missing="$dep"
      fi
    fi
  done

  [ -z "$missing" ] && return 0

  case "$missing" in
    *" "*) printf "aiusage install: missing required dependencies: %s\n\n" "$missing" >&2 ;;
    *) printf "aiusage install: missing required dependency: %s\n\n" "$missing" >&2 ;;
  esac
  required_dependency_install_hint >&2
  return 1
}

copy_source() {
  source_path="$1"
  dest_path="$2"

  case "$source_path" in
    http://* | https://*)
      if ! command -v curl >/dev/null 2>&1; then
        printf "aiusage install: curl is required to download %s\n" "$source_path" >&2
        return 1
      fi
      curl -fsSL "$source_path" -o "$dest_path"
      ;;
    *)
      if [ ! -f "$source_path" ]; then
        printf "aiusage install: source not found: %s\n" "$source_path" >&2
        return 1
      fi
      cp "$source_path" "$dest_path"
      ;;
  esac
}

update_path() {
  install_dir="$1"

  if path_has_dir "$install_dir"; then
    printf "aiusage install: %s is already on PATH\n" "$install_dir"
    return 0
  fi

  if [ -z "${HOME:-}" ]; then
    printf "aiusage install: add %s to PATH to run aiusage from any terminal\n" "$install_dir"
    return 0
  fi

  profile_files | while IFS= read -r profile; do
    mkdir -p "$(dirname "$profile")"
    touch "$profile"

    if grep -F "export PATH=\"$install_dir:\$PATH\"" "$profile" >/dev/null 2>&1; then
      printf "aiusage install: %s already updates PATH\n" "$profile"
    else
      {
        printf "\n# aiusage\n"
        printf "export PATH=\"%s:\$PATH\"\n" "$install_dir"
      } >>"$profile"
      printf "aiusage install: added %s to PATH in %s\n" "$install_dir" "$profile"
    fi
  done

  printf "aiusage install: restart your shell or run: export PATH=\"%s:\$PATH\"\n" "$install_dir"
}

install_dir=$(default_install_dir)
source_path="$AIUSAGE_INSTALL_SOURCE"
update_shell_path=1

if [ "${AIUSAGE_NO_PATH_UPDATE:-}" = "1" ]; then
  update_shell_path=0
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)
      shift
      [ "$#" -gt 0 ] || { printf "aiusage install: --dir requires a value\n" >&2; exit 1; }
      install_dir="$1"
      ;;
    --dir=*)
      install_dir=${1#--dir=}
      ;;
    --source)
      shift
      [ "$#" -gt 0 ] || { printf "aiusage install: --source requires a value\n" >&2; exit 1; }
      source_path="$1"
      ;;
    --source=*)
      source_path=${1#--source=}
      ;;
    --no-path-update)
      update_shell_path=0
      ;;
    -h | --help | help)
      usage
      exit 0
      ;;
    *)
      printf "aiusage install: unknown option: %s\n\n" "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [ -z "$install_dir" ]; then
  printf "aiusage install: install directory is empty\n" >&2
  exit 1
fi

check_required_dependencies

mkdir -p "$install_dir"
dest="$install_dir/aiusage"
copy_source "$source_path" "$dest"
chmod 755 "$dest"

printf "aiusage install: installed %s\n" "$dest"
if [ "$update_shell_path" -eq 1 ]; then
  update_path "$install_dir"
else
  printf "aiusage install: add %s to PATH to run aiusage from any terminal\n" "$install_dir"
fi
