#!/usr/bin/env bash

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/rdev-active-test.XXXXXX")"
FIRST_PID=""

cleanup() {
  touch "$TEMP/release-first-attach" 2>/dev/null || true
  if [ -n "$FIRST_PID" ]; then
    wait "$FIRST_PID" 2>/dev/null || true
  fi
  rm -rf "$TEMP"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TEMP/bin" "$TEMP/config"

cat > "$TEMP/bin/ssh" <<'EOF'
#!/usr/bin/env bash

set -eu

printf '%s\n' "$*" >> "$RDEV_FAKE_STATE/ssh-calls"

case "$*" in
  *list-sessions*)
    exit 0
    ;;
  *attach-session*)
    if mkdir "$RDEV_FAKE_STATE/first-attach.lock" 2>/dev/null; then
      touch "$RDEV_FAKE_STATE/first-attach-ready"
      while [ ! -e "$RDEV_FAKE_STATE/release-first-attach" ]; do
        sleep 0.05
      done
    fi
    exit 0
    ;;
  *has-session*)
    exit 0
    ;;
esac

cat >/dev/null || true
EOF
chmod +x "$TEMP/bin/ssh"

run_rdev() {
  RDEV_CONFIG_DIR="$TEMP/config" \
  RDEV_RUNTIME_DIR="$ROOT/lib" \
  RDEV_SSH_BIN="$TEMP/bin/ssh" \
  RDEV_FAKE_STATE="$TEMP" \
  "$ROOT/bin/rdev" "$@"
}

run_rdev add "Build server" 192.0.2.10 --id build --user deploy >/dev/null

printf '1\n1\nwork\n' | run_rdev >"$TEMP/first.out" 2>&1 &
FIRST_PID=$!

attempt=0
while [ ! -e "$TEMP/first-attach-ready" ]; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 100 ]; then
    printf 'first rdev connection did not reach tmux attach\n' >&2
    sed -n '1,160p' "$TEMP/first.out" >&2
    sed -n '1,160p' "$TEMP/ssh-calls" >&2
    exit 1
  fi
  sleep 0.05
done

printf 'q\n' | run_rdev >"$TEMP/second.out" 2>&1

if grep -q 'Restoring' "$TEMP/second.out"; then
  printf 'a second terminal auto-attached the active tmux session\n' >&2
  exit 1
fi
grep -q 'Select a node' "$TEMP/second.out"

RECOVERY_FILE="$(find "$TEMP/config/recovery.d" -name '*.state' -print -quit)"
test -n "$RECOVERY_FILE"
OWNER_PID="$(awk -F'|' '{ print $5 }' "$RECOVERY_FILE")"
test -n "$OWNER_PID"
kill -9 "$OWNER_PID"
wait "$FIRST_PID" 2>/dev/null || true
FIRST_PID=""

printf 'q\n' | run_rdev >"$TEMP/third.out" 2>&1
if grep -q 'Restoring' "$TEMP/third.out"; then
  printf 'a normal launch auto-resumed a crashed connection\n' >&2
  exit 1
fi
grep -q 'Select a node' "$TEMP/third.out"

run_rdev resume >"$TEMP/resume.out" 2>&1
grep -q 'Restoring' "$TEMP/resume.out"

printf 'build|rdev-build|legacy|0\n' > \
  "$TEMP/config/recovery.d/build--legacy.state"
run_rdev resume >"$TEMP/legacy.out" 2>&1
grep -q 'Restoring' "$TEMP/legacy.out"

touch "$TEMP/release-first-attach"

printf 'Active connection test passed.\n'
