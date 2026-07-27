#!/usr/bin/env bash

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/rdev-workspace-test.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM

run_rdev() {
  RDEV_CONFIG_DIR="$TEMP/config" "$ROOT/bin/rdev" "$@"
}

run_rdev add "Build server" 192.0.2.10 --id build --user deploy >/dev/null
printf 'build|existing-work\nbuild|incident\n' >> "$TEMP/config/workspaces.conf"
printf '1\nq\nq\n' | run_rdev > "$TEMP/menu.out"

grep -q 'existing-work' "$TEMP/menu.out"
grep -q 'incident' "$TEMP/menu.out"

printf 'Workspace listing test passed.\n'
