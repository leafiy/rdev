# rdev

Menu-driven remote development with SSH/Mosh + tmux. Pick a machine, pick a
tmux session, and keep working through network changes without remembering
connection commands or tmux shortcuts.

用菜单管理 SSH/Mosh + tmux 远程开发：选择主机、选择会话、直接工作。无需记忆
主机端口、tmux 命令或断线恢复步骤。

## Install / 安装

```sh
curl -fsSL https://raw.githubusercontent.com/leafiy/rdev/main/install.sh | bash
```

The installer places the executable in `~/.local/bin/rdev`, runtime helpers in
`~/.local/share/rdev`, and preserves all configuration during upgrades.

安装器会把程序放到 `~/.local/bin/rdev`，运行组件放到
`~/.local/share/rdev`；重复运行即可升级，不会覆盖节点配置。

If `~/.local/bin` is not already in `PATH`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## Quick start / 快速开始

Add a regular SSH node:

```sh
rdev add "Work server" server.example.com --user developer
```

Add a Devbox/container whose SSH service listens on port 2224 and use Mosh:

```sh
rdev add "Devbox" server.example.com --user root --port 2224 --mosh
```

Or let `rdev add` ask every question:

```sh
rdev add
```

Then open the menu:

```sh
rdev
```

On first connection, rdev can install `tmux`, `tar`, and `mosh-server` on the
remote node. It syncs only small runtime helpers into
`~/.cache/rdev/bin` on that node.

首次连接时，rdev 可以自动准备远端的 `tmux`、`tar` 和 `mosh-server`，并仅把
少量状态栏组件同步到远端的 `~/.cache/rdev/bin`。

## Commands / 命令

```text
rdev                         Open the node/tmux menu
rdev resume                  Restore an interrupted session now
rdev menu                    Open the menu without auto-resume
rdev add [NAME HOST] [...]   Add a node
rdev list                    List nodes
rdev remove ID|NUMBER        Remove a node
rdev edit                    Edit nodes.conf
rdev config                  Show all configuration paths
rdev doctor                  Check the local installation
rdev version                 Show the installed version
```

Useful `add` options:

```text
--user USER                  SSH user
--port PORT                  SSH port
--ssh / --mosh               Connection transport
--identity FILE              SSH private key
--proxy-jump HOST            SSH jump host
--socket NAME                Dedicated tmux socket
--mosh-port PORT[:PORT]      Published UDP port/range for a container
--id ID                      Stable node ID
```

Run `rdev add --help` for the complete reference.

## What it handles / 自动处理

- Separate SSH or Mosh transport per node.
- Dedicated tmux socket and session picker per node.
- New tmux sessions start from the remote account's `$HOME`.
- Mosh roaming and network recovery; SSH reconnect fallback when UDP is blocked.
- Automatic reattachment to the same tmux session after an SSH/Mosh disconnect.
- Crash-safe session recovery: if the terminal, launcher, or local computer
  stops unexpectedly, the next `rdev` launch resumes the interrupted session.
- No reconnect loop after a normal tmux exit.
- Mouse wheel scrollback, persistent text selection, clipboard support, and a
  tmux right-click menu.
- Dynamic window labels for OMP, Pi, OpenCode, Codex, Claude, Gemini, Qwen,
  Aider, Goose, Copilot, Crush, Kimi, and other supported agents.
- Total token history across supported installed agents; current-conversation
  tokens appear only while an agent is active.
- Remote-server date and time in the tmux status bar.

所有处理仅作用于 rdev 管理的连接和 tmux socket，不会修改或接管普通的
`ssh`、`mosh` 和其他终端会话。

## Independent configuration / 独立配置

rdev follows the XDG directory convention:

```text
~/.config/rdev/config       rdev behavior
~/.config/rdev/nodes.conf   node definitions
~/.config/rdev/ssh_config   optional rdev-only SSH options
~/.local/share/rdev/        installed runtime helpers
```

Override paths with `RDEV_CONFIG_DIR`, `RDEV_DATA_DIR`, or `RDEV_BIN_DIR`.
`rdev` never edits `~/.ssh/config`. Its own SSH config includes the user's
normal SSH config read-only, so existing keys, aliases, and jump hosts still
work.

Node file format:

```text
id|label|host|user|ssh_port|transport|tmux_socket|identity_file|proxy_jump|mosh_udp_port_or_range
```

Use `rdev add` instead of editing it manually. Existing pre-0.1 four-column
configurations are migrated automatically with a timestamped backup.

## Mosh and containers / Mosh 与容器

Mosh first uses SSH to launch `mosh-server`, then communicates over UDP. For a
container using host networking, an SSH port such as 2224 is enough:

```sh
rdev add "Devbox" host.example.com --user root --port 2224 --mosh
```

For a bridge-network container, publish both SSH/TCP and a Mosh UDP port or
range, then record that range:

```sh
rdev add "Devbox" host.example.com \
  --user root --port 2224 --mosh --mosh-port 60000:60010
```

The container runtime must map `60000-60010/udp` to the same ports in the
container. When Mosh cannot establish its UDP path, rdev automatically falls
back to SSH unless `auto_fallback_ssh=no` is set.

Mosh 会先通过 SSH 端口在容器内启动 `mosh-server`，再切换到 UDP。使用 host
网络的容器无需额外映射；bridge 网络容器需要同时映射一段 UDP 端口。

## Settings / 设置

`~/.config/rdev/config`:

```ini
auto_install_remote=yes
auto_fallback_ssh=yes
auto_resume=yes
connect_timeout=10
mosh_predict=adaptive
```

Set `auto_install_remote=no` when package installation must be managed
separately. Set `auto_resume=no` to always show the node menu first; `rdev
resume` can still restore an interrupted session manually.

## Session recovery / 会话恢复

While rdev is running, Mosh survives roaming, Wi-Fi changes, and temporary
network loss. SSH connections retry and reattach the same tmux session.

If the local terminal or rdev process disappears unexpectedly, rdev leaves a
small recovery record in `~/.config/rdev/recovery.d`. The next `rdev` launch
checks that the exact remote tmux session still exists and attaches it
automatically. Recovery records owned by another live local `rdev` process are
ignored, so opening a second terminal shows the node and tmux session menus.

正常退出、右键选择断开、tmux 会话结束或按 Ctrl-C 时会清理恢复记录，不会误触发
重连。关闭终端、电脑休眠、网络中断或 rdev 意外结束时会保留记录，下次启动自动
回到同一个远端 tmux 会话。

If the remote machine itself rebooted, its in-memory tmux server may be gone.
rdev removes the stale recovery record and returns to the menu instead of
creating an empty session with the old name.

## Upgrade and uninstall / 升级与卸载

Upgrade by running the install command again.

```sh
curl -fsSL https://raw.githubusercontent.com/leafiy/rdev/main/install.sh | bash
```

Remove the program but keep node configuration:

```sh
curl -fsSL https://raw.githubusercontent.com/leafiy/rdev/main/uninstall.sh | bash
```

To remove configuration too, download the repository and run:

```sh
./uninstall.sh --purge
```

## Development

```sh
./tests/test_syntax.sh
./tests/test_cli.sh
./tests/test_active_connection.sh
./install.sh
```

CI runs the syntax and CLI tests on both Ubuntu and macOS.

## License

MIT
