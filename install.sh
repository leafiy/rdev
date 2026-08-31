#!/usr/bin/env bash
# rdev 一键安装：在你自己的电脑上运行，把远程服务器配置好。本机不安装任何东西。
#
#   curl -fsSL https://leafiy.github.io/rdev/install.sh | bash
#   （地址留空 = 配置当前这台机器）
#   curl -fsSL https://leafiy.github.io/rdev/install.sh | bash -s -- user@host
#   curl -fsSL https://leafiy.github.io/rdev/install.sh | bash -s -- user@host:2222 -i ~/.ssh/id_ed25519
#   curl -fsSL https://leafiy.github.io/rdev/install.sh | bash -s -- --here        # 已经在服务器里
#   curl -fsSL https://leafiy.github.io/rdev/install.sh | bash -s -- --uninstall user@host
#
# 兼容 macOS 自带的 bash 3.2。
set -e

REPO="${RDEV_REPO:-leafiy/rdev}"
REF="${RDEV_REF:-main}"
RAW_BASE="${RDEV_RAW_BASE:-https://raw.githubusercontent.com/$REPO/$REF}"
SHPOOL_VERSION="${RDEV_SHPOOL_VERSION:-v0.11.3}"
SHPOOL_RELEASES="${RDEV_SHPOOL_RELEASES:-https://github.com/shell-pool/shpool/releases/download}"
SSH_BIN="${RDEV_SSH:-ssh}"

MODE=install
TARGET=""
PORT=""
IDENTITY=""
JUMP=""
LOCAL_ARCHIVE=""
CONNECT=ask
EXTRA_SSH=()
TMP_DIR=""
CTL_DIR=""
CTL_SOCK=""
HOST=""
SSH_OPTS=()

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_BOLD=$'\033[1m' C_DIM=$'\033[2m' C_GREEN=$'\033[32m' C_RED=$'\033[31m' C_RESET=$'\033[0m'
else
  C_BOLD='' C_DIM='' C_GREEN='' C_RED='' C_RESET=''
fi

say()  { printf '%s\n' "$*" >&2; }
step() { printf '%s▸ %s%s\n' "$C_BOLD" "$*" "$C_RESET" >&2; }
note() { printf '  %s\n' "$*" >&2; }
die()  { printf '%s错误：%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

usage() {
  cat <<EOF >&2
rdev 一键安装 · 让远程 shell 和里面的 agent 在 SSH 断线后继续运行
https://github.com/$REPO

用法：
  install.sh [目标] [选项]

目标：
  [用户@]主机[:端口]      例如 root@1.2.3.4、dev@box:2222、或 ~/.ssh/config 里的别名
                         不给目标时会交互式询问

选项：
  -p 端口                SSH 端口
  -i 私钥                SSH 私钥文件
  -J 跳板机              ProxyJump
  --archive 文件         用本地的 shpool 压缩包（离线安装）
  --no-connect           配置完成后不询问是否立即连接
  --here                 在当前这台机器上安装（你已经在服务器里）
  --uninstall            从远程机器移除 rdev
  -- 其余参数            原样传给 ssh
EOF
}

close_ctl() {
  [ -n "$CTL_SOCK" ] || return 0
  [ -n "$HOST" ] && "$SSH_BIN" -o ControlPath="$CTL_SOCK" -O exit "$HOST" >/dev/null 2>&1 || true
  rm -rf "$CTL_DIR"
  CTL_DIR="" CTL_SOCK=""
  return 0
}

# 兜底：任何走 tty 的 ssh（交互登录、卸载确认）都可能因 ControlMaster/mux 的已知问题在退出后
# 没把本机终端从 raw 模式还原。进入这些步骤前存一份终端状态，收尾时还原并复位常见的终端模式，
# 尽量避免脚本退出后终端仍处于异常模式。
TTY_SAVED=""
tty_save() {
  # /dev/tty 存在不代表当前进程有控制终端（CI、非交互 ssh 都可能没有）。
  # 先重定向 stderr，连打开 /dev/tty 失败的诊断也一起静默。
  TTY_SAVED="$(stty -g 2>/dev/null </dev/tty)" || TTY_SAVED=""
  return 0
}
tty_restore() {
  [ -n "$TTY_SAVED" ] || return 0
  # 收尾尽力恢复；即使终端已经断开，也不能覆盖安装结果或中断临时文件清理。
  stty "$TTY_SAVED" 2>/dev/null </dev/tty || true
  # 结束同步输出 / 备用屏 / 各种鼠标模式 / 焦点·括号粘贴，显示光标、清样式、字符集回 ASCII
  printf '\033[?2026l\033[?1047l\033[?1000l\033[?1002l\033[?1003l\033[?1006l\033[?1004l\033[?2004l\033[?25h\033(B\017\033[m' 2>/dev/null >/dev/tty || true
  return 0
}

cleanup() {
  close_ctl
  tty_restore
  [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
  return 0
}
trap cleanup EXIT HUP INT TERM

has_tty() { { : </dev/tty; } >/dev/null 2>&1; }

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -p) PORT="${2:-}"; shift ;;
      -p*) PORT="${1#-p}" ;;
      -i) IDENTITY="${2:-}"; shift ;;
      -J) JUMP="${2:-}"; shift ;;
      --archive) LOCAL_ARCHIVE="${2:-}"; shift ;;
      --archive=*) LOCAL_ARCHIVE="${1#*=}" ;;
      --no-connect) CONNECT=no ;;
      --here) MODE=here ;;
      --uninstall) MODE=uninstall ;;
      --) shift; while [ "$#" -gt 0 ]; do EXTRA_SSH+=("$1"); shift; done; break ;;
      -*) die "未知选项：$1（用 -- 分隔可把参数原样传给 ssh）" ;;
      *)
        [ -z "$TARGET" ] || die "只需要一个目标，多余的参数：$1"
        TARGET="$1"
        ;;
    esac
    shift
  done
}

ask_target() {  # $1 = here：允许留空，表示配置当前这台机器
  has_tty || die '没有终端可以交互。请把目标写在命令里：... | bash -s -- user@host'
  printf '\n  %srdev%s · 让远程 shell 和里面的 agent 在 SSH 断线后继续运行\n\n' "$C_BOLD" "$C_RESET" >/dev/tty
  printf '  输入远程 SSH 地址（例：root@1.2.3.4、dev@box:2222，或 ~/.ssh/config 里的别名）\n' >/dev/tty
  [ "${1:-}" = here ] && printf '  已经在服务器里？直接回车，配置当前这台机器\n' >/dev/tty
  printf '  > ' >/dev/tty
  IFS= read -r TARGET </dev/tty
  printf '\n' >/dev/tty
  [ -n "$TARGET" ] || [ "${1:-}" = here ] || die '没有输入目标。'
}

# 把 [用户@]主机[:端口] / ssh://用户@主机:端口 拆成 HOST 和 PORT
parse_target() {
  local t="$TARGET"
  t="${t#ssh://}"
  t="${t%/}"
  case "$t" in
    \[*\]:*) PORT="${PORT:-${t##*:}}"; t="${t%:*}" ;;   # [ipv6]:port
    *:*:*) ;;                                           # 裸 IPv6，不拆端口
    *:*) PORT="${PORT:-${t##*:}}"; t="${t%:*}" ;;
  esac
  HOST="$t"
  [ -n "$HOST" ] || die "无法理解目标：$TARGET"
  case "$PORT" in ''|*[!0-9]*) [ -z "$PORT" ] || die "端口不合法：$PORT" ;; esac
}

build_ssh_opts() {
  # Unix socket 路径上限约 104 字节；macOS 的 TMPDIR (/var/folders/…/T/) 太长，
  # 所以控制 socket 单独放在 /tmp 下的短目录里，文件名也保持最短。
  CTL_DIR="$(mktemp -d /tmp/rdev.XXXXXX 2>/dev/null)" || CTL_DIR="$(mktemp -d "$TMP_DIR/c.XXXXXX")"
  chmod 700 "$CTL_DIR"
  CTL_SOCK="$CTL_DIR/s"
  # LogLevel=ERROR：不打印 "Connection to … closed." / "Permanently added …" 之类的提示，
  # 但登录失败、主机密钥变化等错误照常显示，首次连接的密钥确认也照常询问。
  SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$CTL_SOCK" -o ControlPersist=180 -o ServerAliveInterval=15 -o LogLevel=ERROR)
  [ -n "$PORT" ] && SSH_OPTS+=(-p "$PORT")
  [ -n "$IDENTITY" ] && SSH_OPTS+=(-i "$IDENTITY")
  [ -n "$JUMP" ] && SSH_OPTS+=(-J "$JUMP")
  [ "${#EXTRA_SSH[@]}" -gt 0 ] && SSH_OPTS+=("${EXTRA_SSH[@]}")
  return 0
}

# 不占用 stdin 的远程命令
remote() {
  "$SSH_BIN" -n "${SSH_OPTS[@]}" "$HOST" "$@"
}

# 把本地文件推到远程路径（远程路径以 $HOME 起头的 shell 表达式）
push_file() {
  local local_path="$1" remote_expr="$2" mode="${3:-644}"
  "$SSH_BIN" "${SSH_OPTS[@]}" "$HOST" \
    "set -e; d=\$(dirname \"$remote_expr\"); mkdir -p \"\$d\"; cat > \"$remote_expr.part\"; chmod $mode \"$remote_expr.part\"; mv \"$remote_expr.part\" \"$remote_expr\"" \
    < "$local_path"
}

download() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 2 -o "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$out" "$url"
  else
    die '本机需要 curl 或 wget。'
  fi
}

# 找到 bin/rdev：优先用仓库里的（从 checkout 运行时），否则从 GitHub 下载
locate_payload() {
  local here
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$here/bin/rdev" ]; then
      PAYLOAD="$here/bin/rdev"
      return 0
    fi
  fi
  PAYLOAD="$TMP_DIR/rdev"
  step "下载 rdev（${REF}）"
  download "$RAW_BASE/bin/rdev" "$PAYLOAD" || die "下载失败：$RAW_BASE/bin/rdev"
  grep -q 'RDEV_VERSION=' "$PAYLOAD" || die '下载到的 rdev 内容不对。'
}

shpool_asset_for() {
  local os="$1" arch="$2"
  case "$arch" in
    x86_64|amd64) arch=x86_64 ;;
    aarch64|arm64) arch=aarch64 ;;
    *) return 1 ;;
  esac
  case "$os" in
    Linux) printf 'shpool-%s-unknown-linux-musl.tar.gz' "$arch" ;;
    Darwin) [ "$arch" = aarch64 ] || return 1; printf 'shpool-aarch64-apple-darwin.tar.gz' ;;
    *) return 1 ;;
  esac
}

mode_here() {
  local bin_dir="${RDEV_BIN_DIR:-$HOME/.local/bin}"
  locate_payload
  step "安装 rdev → $bin_dir/rdev"
  mkdir -p "$bin_dir"
  install -m 755 "$PAYLOAD" "$bin_dir/rdev"
  rm -rf "$TMP_DIR"; TMP_DIR=""
  if [ -n "$LOCAL_ARCHIVE" ]; then
    exec "$bin_dir/rdev" setup --archive "$LOCAL_ARCHIVE"
  fi
  exec "$bin_dir/rdev" setup
}

mode_uninstall() {
  [ -n "$TARGET" ] || ask_target
  parse_target
  build_ssh_opts
  step "从 $HOST 移除 rdev"
  if has_tty; then
    "$SSH_BIN" -t "${SSH_OPTS[@]}" "$HOST" '"$HOME/.local/bin/rdev" uninstall' </dev/tty
  else
    remote '"$HOME/.local/bin/rdev" uninstall --yes'
  fi
}

mode_install() {
  local info os arch remote_home archive asset setup_cmd rc answer

  if [ -z "$TARGET" ]; then
    ask_target here
    if [ -z "$TARGET" ]; then
      say '没有输入地址，配置当前这台机器。'
      mode_here
      return
    fi
  fi
  parse_target
  build_ssh_opts
  locate_payload

  step "连接 $HOST${PORT:+（端口 ${PORT}）}"
  if ! info="$(remote 'uname -s; uname -m; printf "%s\n" "$HOME"; command -v bash >/dev/null 2>&1 && printf "bash-ok\n"')"; then
    die "连不上 ${HOST}。请先确认 ssh ${PORT:+-p $PORT }$HOST 能正常登录。"
  fi
  os="$(printf '%s\n' "$info" | sed -n 1p)"
  arch="$(printf '%s\n' "$info" | sed -n 2p)"
  remote_home="$(printf '%s\n' "$info" | sed -n 3p)"
  printf '%s\n' "$info" | grep -q '^bash-ok$' || die '远程机器上没有 bash，rdev 需要 bash（会话本身可以用任意 shell）。'
  note "$os $arch · 家目录 $remote_home"

  step '推送 rdev → ~/.local/bin/rdev'
  push_file "$PAYLOAD" '$HOME/.local/bin/rdev' 755

  # 在本机下载 shpool 再推过去：服务器不需要能访问 GitHub。
  archive=""
  if [ -n "$LOCAL_ARCHIVE" ]; then
    [ -f "$LOCAL_ARCHIVE" ] || die "找不到文件：$LOCAL_ARCHIVE"
    archive="$LOCAL_ARCHIVE"
  elif asset="$(shpool_asset_for "$os" "$arch")"; then
    step "下载 shpool ${SHPOOL_VERSION}（${asset}）"
    archive="$TMP_DIR/$asset"
    if ! download "$SHPOOL_RELEASES/$SHPOOL_VERSION/$asset" "$archive"; then
      note '本机下载失败，改由远程机器自己下载。'
      archive=""
    fi
  else
    note "没有 $os/$arch 的预编译包，远程机器需要已安装 shpool（brew / cargo install shpool）。"
  fi

  setup_cmd='"$HOME/.local/bin/rdev" setup --brief'
  if [ -n "$archive" ]; then
    step '推送 shpool → ~/.local/share/rdev/shpool.tar.gz'
    push_file "$archive" '$HOME/.local/share/rdev/shpool.tar.gz' 644
    setup_cmd="$setup_cmd"' --archive "$HOME/.local/share/rdev/shpool.tar.gz"'
  fi

  # 不要用 ssh -t：setup 只是打印结果、不读输入。而 -t 会在本机终端进入 raw 模式
  # （关掉 OPOST），配合 ControlMaster 复用连接时 ssh 常常无法在退出后还原，导致后面
  # 所有输出「阶梯状」错行、终端卡死。用普通（无 tty）连接即可，本机终端保持正常。
  step '配置远程机器'
  rc=0
  remote "$setup_cmd" || rc=$?
  [ "$rc" -eq 0 ] || die "远程配置失败（退出码 ${rc}）。可以登录后运行 rdev doctor 查看。"

  printf '\n%s✓ 完成。%s以后照常 ssh：\n\n    ssh %s%s\n\n' "$C_GREEN" "$C_RESET" "${PORT:+-p $PORT }" "$HOST" >&2
  note '登录后会看到会话菜单：回车恢复上次会话，n 新建，q 进入普通 shell。'
  note '会话里按 Ctrl-Space Ctrl-q 离开但不结束；直接关窗口或断网也一样，agent 继续跑。'

  if [ "$CONNECT" = ask ] && has_tty; then
    printf '\n现在就连上去试试？[Y/n] ' >/dev/tty
    IFS= read -r answer </dev/tty || answer=n
    case "$answer" in
      n|N) ;;
      *)
        close_ctl
        set +e
        if [ -n "$PORT" ]; then
          "$SSH_BIN" -p "$PORT" ${IDENTITY:+-i "$IDENTITY"} ${JUMP:+-J "$JUMP"} ${EXTRA_SSH[@]+"${EXTRA_SSH[@]}"} "$HOST" </dev/tty
        else
          "$SSH_BIN" ${IDENTITY:+-i "$IDENTITY"} ${JUMP:+-J "$JUMP"} ${EXTRA_SSH[@]+"${EXTRA_SSH[@]}"} "$HOST" </dev/tty
        fi
        ;;
    esac
  fi
}

main() {
  parse_args "$@"
  tty_save
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rdev-install.XXXXXX")"
  case "$MODE" in
    here) mode_here ;;
    uninstall) mode_uninstall ;;
    install) mode_install ;;
  esac
}

main "$@"
