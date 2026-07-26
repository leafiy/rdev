#!/usr/bin/env bash

set -e

BIN_DIR="${RDEV_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${RDEV_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/rdev}"
CONFIG_DIR="${RDEV_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/rdev}"
PURGE="no"

case "${1:-}" in
  --purge) PURGE="yes" ;;
  --help|-h)
    printf 'Usage: ./uninstall.sh [--purge]\n\n--purge also deletes %s\n' "$CONFIG_DIR"
    exit 0
    ;;
  '') ;;
  *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

rm -f "$BIN_DIR/rdev"
rm -rf "$DATA_DIR"
if [ "$PURGE" = "yes" ]; then
  rm -rf "$CONFIG_DIR"
  printf 'Removed rdev and its configuration.\n'
else
  printf 'Removed rdev. Configuration preserved at %s\n' "$CONFIG_DIR"
fi
