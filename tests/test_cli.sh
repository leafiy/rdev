#!/usr/bin/env bash

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/rdev-test.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM

run_rdev() {
  RDEV_CONFIG_DIR="$TEMP/config" \
  RDEV_RUNTIME_DIR="$ROOT/lib" \
  "$ROOT/bin/rdev" "$@"
}

run_rdev version | grep -q '^rdev 0.2.0$'
run_rdev list | grep -q '^No nodes configured\.$'
! grep -q '^auto_resume=' "$TEMP/config/config"
grep -q '^mosh_predict=always$' "$TEMP/config/config"
run_rdev resume | grep -q '^No interrupted rdev session is waiting to be restored\.$'

run_rdev add "Build server" 10.20.30.40 \
  --id build \
  --user deploy \
  --port 2224 \
  --mosh \
  --socket rdev-build \
  --identity "$HOME/.ssh/id_ed25519" \
  --proxy-jump bastion \
  --mosh-port 60000:60010

grep -q '^build|Build server|10.20.30.40|deploy|2224|mosh|rdev-build|' "$TEMP/config/nodes.conf"
run_rdev list | grep -q 'deploy@10.20.30.40:2224'

if run_rdev add Duplicate 127.0.0.1 --id build >/dev/null 2>&1; then
  printf 'duplicate ID was accepted\n' >&2
  exit 1
fi

run_rdev remove build | grep -q '^Removed node: build$'
run_rdev list | grep -q '^No nodes configured\.$'

printf 'missing|rdev-missing|work|0\n' > "$TEMP/config/recovery.d/missing--work.state"
run_rdev resume | grep -q '^No interrupted rdev session is waiting to be restored\.$'
test ! -e "$TEMP/config/recovery.d/missing--work.state"

cat > "$TEMP/config/ssh_config" <<'EOF'
Host rdev-legacy
  HostName 192.0.2.10
  User root
  Port 2202
EOF
cat > "$TEMP/config/nodes.conf" <<'EOF'
# legacy
Legacy node|rdev-legacy|rdev-legacy|ssh
EOF

run_rdev version >/dev/null
grep -q '^legacy|Legacy node|rdev-legacy|root|2202|ssh|rdev-legacy|||$' "$TEMP/config/nodes.conf"
test -n "$(find "$TEMP/config" -name 'nodes.conf.legacy.*' -print -quit)"

RDEV_BIN_DIR="$TEMP/install/bin" \
RDEV_DATA_DIR="$TEMP/install/data" \
  "$ROOT/install.sh" >/dev/null
test -x "$TEMP/install/bin/rdev"

printf 'CLI tests passed.\n'
