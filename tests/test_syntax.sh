#!/usr/bin/env bash

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
bash -n \
  "$ROOT/bin/rdev" \
  "$ROOT/install.sh" \
  "$ROOT/uninstall.sh" \
  "$ROOT/tests/test_cli.sh" \
  "$ROOT/tests/test_active_connection.sh" \
  "$ROOT/tests/test_session_listing.sh" \
  "$ROOT/tests/test_mouse_input.sh"

if command -v python3 >/dev/null 2>&1; then
  python3 -m py_compile "$ROOT/lib/rdev-agent-name.py" "$ROOT/lib/rdev-token-status.py"
fi

printf 'Syntax tests passed.\n'
