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
drag_binding="$(tmux -L "$SOCKET" list-keys -T root |
  awk '/MouseDrag1Pane/ { print; exit }')"
wheel_binding="$(tmux -L "$SOCKET" list-keys -T root |
  awk '/WheelUpPane/ { print; exit }')"
clipboard_option="$(tmux -L "$SOCKET" show-options -sv set-clipboard)"
terminal_overrides="$(tmux -L "$SOCKET" show-options -sv terminal-overrides)"
menu_binding="$(tmux -L "$SOCKET" list-keys -T root |
  awk '/MouseDown3Pane/ { print; exit }')"
status_interval="$(tmux -L "$SOCKET" show-options -gv status-interval)"

if [ "$status_interval" != "30" ]; then
  printf 'expensive status helpers refresh too often: %s second(s)\n' "$status_interval" >&2
  exit 1
fi

if [ "$clipboard_option" != "external" ]; then
  printf 'system clipboard export is disabled: %s\n' "$clipboard_option" >&2
  exit 1
fi
case "$terminal_overrides" in
  *'Ms='*) ;;
  *)
    printf 'OSC 52 clipboard capability is missing: %s\n' "$terminal_overrides" >&2
    exit 1
    ;;
esac
case "$menu_binding" in
  *paste-buffer*) ;;
  *)
    printf 'right-click menu cannot paste the copied buffer: %s\n' "$menu_binding" >&2
    exit 1
    ;;
esac


case "$drag_binding" in
  *'copy-mode -M'*) ;;
  *)
    printf 'mouse drag does not start text selection: %s\n' "$drag_binding" >&2
    exit 1
    ;;
esac
case "$drag_binding" in
  *mouse_any_flag*)
    printf 'mouse-aware applications would bypass text selection: %s\n' "$drag_binding" >&2
    exit 1
    ;;
esac

case "$wheel_binding" in
  *mouse_any_flag*'copy-mode -e'*) ;;
  *)
    printf 'unexpected WheelUpPane binding: %s\n' "$wheel_binding" >&2
    exit 1
    ;;
esac
case "$wheel_binding" in
  *alternate_on*)
    printf 'alternate-screen wheel events would be swallowed: %s\n' "$wheel_binding" >&2
    exit 1
    ;;
esac

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
