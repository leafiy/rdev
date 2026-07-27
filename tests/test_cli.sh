#!/usr/bin/env bash

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/rdev-test.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM

run_rdev() {
  RDEV_CONFIG_DIR="$TEMP/config" \
    "$ROOT/bin/rdev" "$@"
}

run_rdev version | grep -q '^rdev 0.4.0$'
run_rdev list | grep -q '^No nodes configured\.$'
grep -q '^auto_install_remote=yes$' "$TEMP/config/config"
grep -q '^connect_timeout=10$' "$TEMP/config/config"
grep -q '^reconnect_delay=2$' "$TEMP/config/config"
run_rdev resume | grep -q '^No previous remote workspace is available\.$'

run_rdev add "Build server" 10.20.30.40 \
  --id build \
  --user deploy \
  --port 2224 \
  --identity "$HOME/.ssh/id_ed25519" \
  --proxy-jump bastion

grep -q "^build|Build server|10.20.30.40|deploy|2224|$HOME/.ssh/id_ed25519|bastion$" "$TEMP/config/nodes.conf"
run_rdev list | grep -q 'deploy@10.20.30.40:2224'

if run_rdev add Duplicate 127.0.0.1 --id build >/dev/null 2>&1; then
  printf 'duplicate ID was accepted\n' >&2
  exit 1
fi
if run_rdev add Mosh 127.0.0.1 --mosh >/dev/null 2>&1; then
  printf 'removed Mosh option was accepted\n' >&2
  exit 1
fi

run_rdev remove build | grep -q '^Removed node: build$'
run_rdev list | grep -q '^No nodes configured\.$'

cat > "$TEMP/config/nodes.conf" <<'EOF'
# id|label|host|user|ssh_port|transport|tmux_socket|identity_file|proxy_jump|mosh_udp_port_or_range
legacy|Legacy node|legacy.example.com|root|2202|mosh|rdev-legacy|~/.ssh/id_ed25519|bastion|60000:60010
EOF
run_rdev version >/dev/null
grep -q '^legacy|Legacy node|legacy.example.com|root|2202|~/.ssh/id_ed25519|bastion$' "$TEMP/config/nodes.conf"
set -- "$TEMP"/config/nodes.conf.pre-dtach.*
test -e "$1"

RDEV_CONFIG_DIR="$TEMP/install/config" RDEV_BIN_DIR="$TEMP/install/bin" "$ROOT/install.sh" >/dev/null
test -x "$TEMP/install/bin/rdev"

printf 'CLI tests passed.\n'
