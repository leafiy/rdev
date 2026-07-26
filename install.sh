#!/usr/bin/env bash

set -e

REPO="${RDEV_REPO:-leafiy/rdev}"
REF="${RDEV_REF:-main}"
BIN_DIR="${RDEV_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${RDEV_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/rdev}"
SOURCE_DIR=""
TEMP_DIR=""

cleanup() {
  [ -n "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT HUP INT TERM

usage() {
  cat <<'EOF'
Install rdev

Usage:
  ./install.sh
  curl -fsSL https://raw.githubusercontent.com/leafiy/rdev/main/install.sh | bash

Environment:
  RDEV_BIN_DIR   Executable directory (default: ~/.local/bin)
  RDEV_DATA_DIR  Runtime directory (default: ~/.local/share/rdev)
  RDEV_REF       Git branch or tag (default: main)
EOF
}

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
esac

if [ -n "${BASH_SOURCE[0]:-}" ] &&
   [ -f "$(dirname -- "${BASH_SOURCE[0]}")/bin/rdev" ] &&
   [ -f "$(dirname -- "${BASH_SOURCE[0]}")/lib/tmux.conf" ]; then
  SOURCE_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
else
  command -v curl >/dev/null 2>&1 || { printf 'curl is required.\n' >&2; exit 1; }
  command -v tar >/dev/null 2>&1 || { printf 'tar is required.\n' >&2; exit 1; }
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rdev-install.XXXXXX")"
  archive="$TEMP_DIR/rdev.tar.gz"
  printf 'Downloading rdev (%s)…\n' "$REF"
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/$REF.tar.gz" -o "$archive" ||
    curl -fsSL "https://github.com/$REPO/archive/refs/tags/$REF.tar.gz" -o "$archive"
  tar -xzf "$archive" -C "$TEMP_DIR"
  SOURCE_DIR="$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
fi

[ -f "$SOURCE_DIR/bin/rdev" ] || { printf 'Invalid rdev source package.\n' >&2; exit 1; }

mkdir -p "$BIN_DIR" "$DATA_DIR"
install -m 755 "$SOURCE_DIR/bin/rdev" "$BIN_DIR/rdev"
for file in rdev-agent-name rdev-agent-name.py rdev-token-status rdev-token-status.py tmux.conf; do
  mode=644
  case "$file" in rdev-agent-name|rdev-token-status) mode=755 ;; esac
  install -m "$mode" "$SOURCE_DIR/lib/$file" "$DATA_DIR/$file"
done

RDEV_RUNTIME_DIR="$DATA_DIR" "$BIN_DIR/rdev" version

printf '\nInstalled:\n  %s\n  %s\n' "$BIN_DIR/rdev" "$DATA_DIR"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    printf "\nAdd this directory to PATH:\n  export PATH=\"%s:\$PATH\"\n" "$BIN_DIR"
    ;;
esac
printf '\nGet started:\n  rdev add\n  rdev\n'
