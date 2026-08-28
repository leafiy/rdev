#!/usr/bin/env bash
# 会话菜单：列表解析、选择、新建、退出码
. "$(dirname -- "$0")/lib.sh"

# list：按最近连接时间倒序，附带状态
out="$(rdev list)"
assert_eq "$(printf '%s\n' "$out" | awk -F'\t' '{ print $1 }' | tr '\n' ' ')" "anna work latte " "list 顺序"
assert_contains "$out" 'Attached' 'list'
assert_contains "$out" 'Disconnected' 'list'

# 菜单：选 2 → attach work；假 shpool 立刻返回且会话仍存在 → 回到菜单，stdin 结束 → 退出码 10
: > "$FAKE_SHPOOL_LOG"
rc=0
out="$(printf '2\n' | rdev 2>&1)" || rc=$?
assert_eq "$rc" 10 '菜单退出码（回到普通 shell）'
assert_contains "$out" 'rdev ·' '菜单标题'
assert_contains "$out" 'work' '菜单列表'
assert_contains "$out" '可恢复' '菜单状态'
assert_contains "$out" '选择即接管' '已连接状态'
assert_contains "$(cat "$FAKE_SHPOOL_LOG")" 'attach -f -- work' 'shpool 调用'
# socket 与配置文件应显式传给 shpool
assert_contains "$(cat "$FAKE_SHPOOL_LOG")" "-s $HOME/.local/run/rdev/shpool.socket -c $HOME/.config/rdev/shpool.toml" 'shpool 全局参数'

# 回车 → 恢复最近的“可恢复”会话（work，而不是已连接的 anna）
: > "$FAKE_SHPOOL_LOG"
printf '\n' | rdev >/dev/null 2>&1 || true
assert_contains "$(cat "$FAKE_SHPOOL_LOG")" 'attach -f -- work' '回车默认恢复'

# 输入名称 → 新建
: > "$FAKE_SHPOOL_LOG"
printf 'feature-x\n' | rdev >/dev/null 2>&1 || true
assert_contains "$(cat "$FAKE_SHPOOL_LOG")" 'attach -f -- feature-x' '按名称新建'

# 非法名称不会被传给 shpool
: > "$FAKE_SHPOOL_LOG"
printf 'bad name\nq\n' | rdev >/dev/null 2>&1 || true
assert_not_contains "$(cat "$FAKE_SHPOOL_LOG")" 'attach' '非法名称'

# q → 10
rc=0
printf 'q\n' | rdev >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 10 'q 的退出码'

# k 1 + y → kill anna
: > "$FAKE_SHPOOL_LOG"
printf 'k 1\ny\nq\n' | rdev >/dev/null 2>&1 || true
assert_contains "$(cat "$FAKE_SHPOOL_LOG")" 'kill -- anna' '删除会话'

# 直达：attach 一个不存在的会话，返回后列表里没有它 → 视为会话结束 → 退出码 0
: > "$FAKE_SHPOOL_LOG"
rc=0
rdev attach fresh >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 0 'attach 结束后的退出码'
assert_contains "$(cat "$FAKE_SHPOOL_LOG")" 'attach -f -- fresh' '直达 attach'

# attach 立刻失败 → 退出码 1（钩子会保留普通 shell）
rc=0
FAKE_ATTACH_RC=3 rdev attach broken >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 1 'attach 失败的退出码'

# 已在会话内时拒绝再进
rc=0
SHPOOL_SESSION_NAME=anna rdev >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 1 '会话内运行 rdev'

# 默认配置会自动生成
assert_contains "$(cat "$HOME/.config/rdev/shpool.toml")" 'session_restore_mode = "simple"' 'shpool.toml'
assert_contains "$(cat "$HOME/.config/rdev/shpool.toml")" 'prompt_prefix = ""' 'shpool.toml'

printf 'Menu tests passed.\n'
