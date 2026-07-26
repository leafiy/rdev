#!/usr/bin/env bash

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
SOCKET="rdev-mouse-test-$$"

cleanup() {
  tmux -L "$SOCKET" kill-server 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

if ! command -v tmux >/dev/null 2>&1; then
  printf 'Mouse input test skipped: tmux is not installed locally.\n'
  exit 0
fi

tmux -L "$SOCKET" new-session -d -s mouse-test
tmux -L "$SOCKET" source-file "$ROOT/lib/tmux.conf"

binding="$(tmux -L "$SOCKET" list-keys -T copy-mode |
  awk '/MouseDragEnd1Pane/ { print; exit }')"
click_binding="$(tmux -L "$SOCKET" list-keys -T copy-mode |
  awk '/MouseDown1Pane/ { print; exit }')"

tmux -L "$SOCKET" copy-mode -t mouse-test
tmux -L "$SOCKET" send-keys -t mouse-test -X begin-selection
case "$binding" in
  *copy-selection-and-cancel*)
    tmux -L "$SOCKET" send-keys -t mouse-test -X copy-selection-and-cancel
    ;;
  *copy-selection-no-clear*)
    tmux -L "$SOCKET" send-keys -t mouse-test -X copy-selection-no-clear
    ;;
  *)
    printf 'unexpected MouseDragEnd1Pane binding: %s\n' "$binding" >&2
    exit 1
    ;;
esac

if [ "$(tmux -L "$SOCKET" display-message -p -t mouse-test '#{pane_in_mode}')" != "0" ]; then
  printf 'mouse selection left the pane in copy mode, blocking keyboard input\n' >&2
  exit 1
fi

tmux -L "$SOCKET" copy-mode -t mouse-test
case "$click_binding" in
  *'send-keys -X cancel'*)
    tmux -L "$SOCKET" send-keys -t mouse-test -X cancel
    ;;
  *)
    tmux -L "$SOCKET" select-pane -t mouse-test
    ;;
esac

if [ "$(tmux -L "$SOCKET" display-message -p -t mouse-test '#{pane_in_mode}')" != "0" ]; then
  printf 'mouse click left the pane in copy mode, blocking keyboard input\n' >&2
  exit 1
fi

printf 'Mouse input test passed.\n'
