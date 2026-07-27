#!/usr/bin/env bash

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/rdev-dtach-install.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM
REMOTE_BIN="$TEMP/remote-home/.local/bin"
mkdir -p "$TEMP/bin" "$REMOTE_BIN" "$TEMP/config"

cat > "$REMOTE_BIN/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = "-u" ] && { printf '0\n'; exit 0; }
exit 2
EOF
cat > "$REMOTE_BIN/env" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  case "$1" in *=*) shift ;; *) break ;; esac
done
exec "$@"
EOF
cat > "$REMOTE_BIN/apt-get" <<'EOF'
#!/bin/sh
remote_bin=${0%/*}
state=${remote_bin%/remote-home/.local/bin}
printf '%s\n' "$*" >> "$state/remote-install-calls"
case "$*" in
  'install -y -qq dtach')
    cat > "$remote_bin/dtach" <<'INNER'
#!/bin/sh
exit 0
INNER
    /bin/chmod 755 "$remote_bin/dtach"
    ;;
esac
EOF

cat > "$TEMP/bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -eu
case " $* " in
  *' rdev_auto_install='*)
    cat > "$RDEV_FAKE_STATE/remote-prepare"
    HOME="$RDEV_FAKE_STATE/remote-home" \
    PATH="$RDEV_FAKE_STATE/remote-home/.local/bin" \
    rdev_auto_install=yes \
      /bin/sh "$RDEV_FAKE_STATE/remote-prepare"
    ;;
  *' rdev_session='*)
    printf '%s\n' "$*" > "$RDEV_FAKE_STATE/attach-call"
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$TEMP/bin/ssh" "$REMOTE_BIN/id" "$REMOTE_BIN/env" "$REMOTE_BIN/apt-get"

RDEV_CONFIG_DIR="$TEMP/config" "$ROOT/bin/rdev" add Test 192.0.2.10 --id test >/dev/null
RDEV_CONFIG_DIR="$TEMP/config" \
RDEV_SSH_BIN="$TEMP/bin/ssh" \
RDEV_FAKE_STATE="$TEMP" \
  "$ROOT/bin/rdev" <<'EOF' > "$TEMP/menu.out"
1
1
work
EOF

grep -q '^update -qq$' "$TEMP/remote-install-calls"
grep -q '^install -y -qq dtach$' "$TEMP/remote-install-calls"
test -x "$REMOTE_BIN/dtach"
grep -q 'rdev_session=s[0-9]* exec sh -c' "$TEMP/attach-call"

printf 'Remote dtach auto-install test passed.\n'
