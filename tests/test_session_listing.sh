#!/usr/bin/env bash

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/rdev-session-test.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM

mkdir -p "$TEMP/bin" "$TEMP/config"

cat > "$TEMP/bin/ssh" <<'EOF'
#!/usr/bin/env bash

set -eu

case "$*" in
  *list-sessions*)
    case "$*" in
      *'\|'*)
        printf 'existing-session|2|0\n'
        ;;
      *)
        # tmux prints "\t" in -F strings literally; it is not a tab escape.
        printf '%s\\t%s\\t%s\\t%s\n' \
          'rdev-build' 'existing-session' '2' '0'
        ;;
    esac
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
  "$ROOT/bin/rdev" "$@"
}

run_rdev add "Build server" 192.0.2.10 --id build --user deploy >/dev/null
printf '1\nq\n' | run_rdev >"$TEMP/menu.out" 2>&1

if ! grep -q 'existing-session  ·  2 window(s)' "$TEMP/menu.out"; then
  printf 'existing tmux session was missing from the session menu\n' >&2
  sed -n '1,160p' "$TEMP/menu.out" >&2
  exit 1
fi

printf 'Session listing test passed.\n'
