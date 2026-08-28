# 测试公共部分：由各个 test_*.sh source。
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="${RDEV_TEST_BASH:-bash}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/rdev-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FAKE_HOME="$WORK/home"
mkdir -p "$FAKE_HOME"

export HOME="$FAKE_HOME"
export XDG_CONFIG_HOME="$FAKE_HOME/.config"
export XDG_DATA_HOME="$FAKE_HOME/.local/share"
export FAKE_SHPOOL_LOG="$WORK/shpool.log"
export FAKE_SHPOOL_JSON="$ROOT/tests/fixtures/sessions.json"
export RDEV_SHPOOL_BIN="$ROOT/tests/fixtures/fake-shpool"
export NO_COLOR=1
unset SHPOOL_SESSION_NAME RDEV_HOOK_DONE

rdev() { "$BASH_BIN" "$ROOT/bin/rdev" "$@"; }

# 生成一个装着假 shpool 的 tar.gz，模拟 GitHub release 包
make_fake_archive() {
  local dir="$WORK/archive-src" out="$1"
  mkdir -p "$dir"
  cp "$ROOT/tests/fixtures/fake-shpool" "$dir/shpool"
  chmod 755 "$dir/shpool"
  tar -czf "$out" -C "$dir" shpool
}

assert_contains() {
  local haystack="$1" needle="$2" what="${3:-output}"
  if ! printf '%s' "$haystack" | grep -q -- "$needle"; then
    printf 'FAIL: %s 里找不到 "%s"\n---\n%s\n---\n' "$what" "$needle" "$haystack" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" what="${3:-output}"
  if printf '%s' "$haystack" | grep -q -- "$needle"; then
    printf 'FAIL: %s 里不应出现 "%s"\n---\n%s\n---\n' "$what" "$needle" "$haystack" >&2
    exit 1
  fi
}

assert_eq() {
  if [ "$1" != "$2" ]; then
    printf 'FAIL: %s：期望 "%s"，实际 "%s"\n' "${3:-value}" "$2" "$1" >&2
    exit 1
  fi
}

count_matches() {
  grep -c -- "$2" "$1" 2>/dev/null || true
}
