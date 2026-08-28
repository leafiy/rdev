#!/usr/bin/env bash
# install.sh：解析目标、推送文件、在“远程”执行 setup（ssh 用假的，命令在本地执行）
. "$(dirname -- "$0")/lib.sh"
unset RDEV_SHPOOL_BIN

export FAKE_REMOTE_HOME="$WORK/remote-home"
export FAKE_SSH_LOG="$WORK/ssh.log"
export RDEV_SSH="$ROOT/tests/fixtures/fake-ssh"
mkdir -p "$FAKE_REMOTE_HOME"
printf '# remote zshrc\n' > "$FAKE_REMOTE_HOME/.zshrc"

archive="$WORK/shpool.tar.gz"
make_fake_archive "$archive"

out="$("$BASH_BIN" "$ROOT/install.sh" 'dev@box.example:2222' -i "$WORK/key" --archive "$archive" --no-connect 2>&1 </dev/null)"
assert_contains "$out" '完成' 'install 输出'
assert_contains "$out" 'ssh -p 2222 dev@box.example' '连接提示'

log="$(cat "$FAKE_SSH_LOG")"
assert_contains "$log" '-p 2222' 'ssh 端口'
assert_contains "$log" "-i $WORK/key" 'ssh 私钥'
assert_contains "$log" 'ControlMaster=auto' 'ssh 复用连接'
assert_contains "$log" 'dev@box.example' 'ssh 主机'
assert_not_contains "$log" 'box.example:2222' '端口不应留在主机名里'

[ -x "$FAKE_REMOTE_HOME/.local/bin/rdev" ] || { echo 'FAIL: 远程没有收到 rdev' >&2; exit 1; }
cmp -s "$ROOT/bin/rdev" "$FAKE_REMOTE_HOME/.local/bin/rdev" || { echo 'FAIL: 推送的 rdev 内容不一致' >&2; exit 1; }
[ -x "$FAKE_REMOTE_HOME/.local/share/rdev/bin/shpool" ] || { echo 'FAIL: 远程没有安装 shpool' >&2; exit 1; }
[ -f "$FAKE_REMOTE_HOME/.config/rdev/shpool.toml" ] || { echo 'FAIL: 远程没有生成配置' >&2; exit 1; }
assert_contains "$(cat "$FAKE_REMOTE_HOME/.zshrc")" '# >>> rdev >>>' '远程 .zshrc 钩子'
[ ! -e "$FAKE_REMOTE_HOME/.local/share/rdev/shpool.tar.gz" ] || { echo 'FAIL: 推送的压缩包没有清理' >&2; exit 1; }

# ssh:// 形式与别名
: > "$FAKE_SSH_LOG"
"$BASH_BIN" "$ROOT/install.sh" 'ssh://root@10.0.0.8:2200' --archive "$archive" --no-connect >/dev/null 2>&1 </dev/null
assert_contains "$(cat "$FAKE_SSH_LOG")" '-p 2200' 'ssh:// 端口'
assert_contains "$(cat "$FAKE_SSH_LOG")" 'root@10.0.0.8' 'ssh:// 主机'

# --here：在本机安装
: > "$FAKE_SSH_LOG"
"$BASH_BIN" "$ROOT/install.sh" --here --archive "$archive" >/dev/null 2>&1 </dev/null
[ -x "$HOME/.local/bin/rdev" ] || { echo 'FAIL: --here 没有安装 rdev' >&2; exit 1; }
[ ! -s "$FAKE_SSH_LOG" ] || { echo 'FAIL: --here 不该调用 ssh' >&2; exit 1; }

# 没有目标且没有终端 → 报错而不是卡住
rc=0
"$BASH_BIN" "$ROOT/install.sh" --no-connect >/dev/null 2>&1 </dev/null || rc=$?
[ "$rc" -ne 0 ] || { echo 'FAIL: 无目标时应报错' >&2; exit 1; }

printf 'Install tests passed.\n'
