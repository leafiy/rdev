#!/usr/bin/env bash
# rdev setup / doctor / uninstall：安装 shpool、写配置、shell 钩子可重复、可移除
. "$(dirname -- "$0")/lib.sh"
unset RDEV_SHPOOL_BIN

archive="$WORK/shpool.tar.gz"
make_fake_archive "$archive"
printf '# 原有内容\nexport FOO=1\n' > "$HOME/.zshrc"
printf '# bash 原有内容\n' > "$HOME/.bashrc"

out="$(rdev setup --archive "$archive" --no-linger 2>&1)"
assert_contains "$out" '完成' 'setup 输出'
[ -x "$HOME/.local/share/rdev/bin/shpool" ] || { echo 'FAIL: shpool 没有安装到 ~/.local/share/rdev/bin' >&2; exit 1; }
[ -f "$HOME/.config/rdev/shpool.toml" ] || { echo 'FAIL: 没有生成 shpool.toml' >&2; exit 1; }
assert_contains "$(cat "$HOME/.zshrc")" 'export FOO=1' '.zshrc 原内容'
assert_contains "$(cat "$HOME/.zshrc")" 'add-zle-hook-widget line-init _rdev_line_init' '.zshrc 钩子'
assert_contains "$(cat "$HOME/.bashrc")" 'shopt -s huponexit' '.bashrc 钩子'
assert_contains "$(cat "$HOME/.bashrc")" "$HOME/.local/bin/rdev" '.bashrc 钩子路径'

# 钩子语法必须能被对应 shell 解析
if command -v zsh >/dev/null 2>&1; then zsh -n "$HOME/.zshrc"; fi
"$BASH_BIN" -n "$HOME/.bashrc"

# 再跑一次：钩子不会重复
rdev setup --archive "$archive" --no-linger >/dev/null 2>&1
assert_eq "$(count_matches "$HOME/.zshrc" '^# >>> rdev >>>')" 1 '.zshrc 钩子数量'
assert_eq "$(count_matches "$HOME/.bashrc" '^# >>> rdev >>>')" 1 '.bashrc 钩子数量'

# 用户改过的配置不会被覆盖
printf 'prompt_prefix = "x"\n' > "$HOME/.config/rdev/shpool.toml"
rdev setup --no-linger >/dev/null 2>&1
assert_contains "$(cat "$HOME/.config/rdev/shpool.toml")" 'prompt_prefix = "x"' '保留配置'
rdev setup --no-linger --reset-config >/dev/null 2>&1
assert_contains "$(cat "$HOME/.config/rdev/shpool.toml")" 'session_restore_mode = "simple"' '重置配置'

# 钩子在非 SSH 环境下不做任何事（source 时不能退出 shell）
( unset SSH_TTY; "$BASH_BIN" -ic 'source "$HOME/.bashrc"; echo still-here' ) 2>/dev/null | grep -q still-here \
  || { echo 'FAIL: 非 SSH 环境下 .bashrc 钩子不该触发' >&2; exit 1; }

# doctor
out="$(rdev doctor 2>&1)"
assert_contains "$out" 'shpool：' 'doctor'
assert_contains "$out" '钩子：' 'doctor 钩子'

# uninstall：钩子移除，原内容保留，配置默认保留
mkdir -p "$HOME/.local/bin" && cp "$ROOT/bin/rdev" "$HOME/.local/bin/rdev"
rdev uninstall --yes >/dev/null 2>&1
assert_not_contains "$(cat "$HOME/.zshrc")" 'rdev' '.zshrc 卸载后'
assert_contains "$(cat "$HOME/.zshrc")" 'export FOO=1' '.zshrc 卸载后原内容'
[ ! -e "$HOME/.local/share/rdev" ] || { echo 'FAIL: 卸载后 ~/.local/share/rdev 仍存在' >&2; exit 1; }
[ ! -e "$HOME/.local/bin/rdev" ] || { echo 'FAIL: 卸载后 ~/.local/bin/rdev 仍存在' >&2; exit 1; }
[ -f "$HOME/.config/rdev/shpool.toml" ] || { echo 'FAIL: 卸载不该删除配置' >&2; exit 1; }

printf 'Setup tests passed.\n'
