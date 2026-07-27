#!/usr/bin/env bash

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/rdev-dtach-connection.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM
mkdir -p "$TEMP/bin" "$TEMP/config"

cat > "$TEMP/bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$RDEV_FAKE_STATE/ssh-calls"
case " $* " in
  *' rdev_auto_install='*)
    cat > "$RDEV_FAKE_STATE/remote-prepare"
    exit 0
    ;;
  *' rdev_session='*)
    printf '%s\n' "$*" >> "$RDEV_FAKE_STATE/attach-calls"
    count=0
    [ ! -r "$RDEV_FAKE_STATE/attach-count" ] || count="$(cat "$RDEV_FAKE_STATE/attach-count")"
    count=$((count + 1))
    printf '%s\n' "$count" > "$RDEV_FAKE_STATE/attach-count"
    [ "$count" -ne 1 ] || exit 255
    exit 0
    ;;
esac
exit 2
EOF
chmod +x "$TEMP/bin/ssh"

run_rdev() {
  RDEV_CONFIG_DIR="$TEMP/config" \
  RDEV_SSH_BIN="$TEMP/bin/ssh" \
  RDEV_FAKE_STATE="$TEMP" \
    "$ROOT/bin/rdev" "$@"
}

run_rdev add "Build server" build-alias \
  --id build --user deploy --port 2224 \
  --identity "/tmp/key'one" --proxy-jump bastion >/dev/null
cat > "$TEMP/config/config" <<'EOF'
# rdev settings
auto_install_remote=yes
connect_timeout=10
reconnect_delay=0
EOF

printf '1\n1\nwork\n' | run_rdev > "$TEMP/menu.out" 2> "$TEMP/menu.err"

grep -q 'rdev_auto_install=yes exec sh -s$' "$TEMP/ssh-calls"
grep -q 'apt-get install -y -qq dtach' "$TEMP/remote-prepare"
grep -q -- "-p 2224 -l deploy .* -i /tmp/key'one -J bastion .*build-alias rdev_session=s[0-9]* exec sh -c" "$TEMP/attach-calls"
grep -q 'exec dtach -A' "$TEMP/attach-calls"
grep -q 'Disconnected; reconnecting in 0s' "$TEMP/menu.err"
test "$(cat "$TEMP/attach-count")" -eq 2
test "$(sed -n 's/.*rdev_session=\(s[0-9][0-9]*\).*/\1/p' "$TEMP/attach-calls" | sort -u | wc -l | tr -d ' ')" -eq 1
grep -q '^build|work$' "$TEMP/config/workspaces.conf"
grep -q '^build|work$' "$TEMP/config/last-connection"

run_rdev resume > "$TEMP/resume.out"
test "$(cat "$TEMP/attach-count")" -eq 3
test "$(sed -n 's/.*rdev_session=\(s[0-9][0-9]*\).*/\1/p' "$TEMP/attach-calls" | sort -u | wc -l | tr -d ' ')" -eq 1

printf 'Current-terminal connection test passed.\n'
