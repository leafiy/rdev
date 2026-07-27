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
  "$ROOT/tests/test_auto_install.sh"

printf 'Syntax tests passed.\n'
