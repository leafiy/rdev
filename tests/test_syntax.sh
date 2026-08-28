#!/usr/bin/env bash
set -eu
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BASH_BIN="${RDEV_TEST_BASH:-bash}"
for f in "$ROOT/bin/rdev" "$ROOT/install.sh" "$ROOT"/tests/*.sh "$ROOT"/tests/fixtures/fake-*; do
  "$BASH_BIN" -n "$f"
done
# 禁止 bash 4+ 才有的语法，保证 macOS 自带 bash 3.2 也能跑
if grep -nE 'mapfile|readarray|declare -A|\$\{[A-Za-z_]+(,,|\^\^)\}|&>>' "$ROOT/bin/rdev" "$ROOT/install.sh"; then
  echo 'FAIL: 用到了 bash 3.2 不支持的语法' >&2
  exit 1
fi
printf 'Syntax tests passed.\n'
