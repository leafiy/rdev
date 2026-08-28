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
# bash 3.2 会把紧跟在 $VAR 后面的多字节字符的首字节当成变量名的一部分（macOS 上实测），
# 变量后面直接跟中文标点时必须写成 ${VAR}
if LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~[:space:]]' "$ROOT/bin/rdev" "$ROOT/install.sh"; then
  echo 'FAIL: $VAR 后面直接跟了多字节字符，请改成 ${VAR}' >&2
  exit 1
fi
printf 'Syntax tests passed.\n'
