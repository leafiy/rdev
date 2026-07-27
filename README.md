# rdev

[![test](https://github.com/leafiy/rdev/actions/workflows/test.yml/badge.svg)](https://github.com/leafiy/rdev/actions/workflows/test.yml)

在你自己的终端里管理可恢复的远程开发会话。

`rdev` 提供一个简单的主机与工作区菜单，通过 SSH 连接远端，并使用轻量的
`dtach` 保持远端 shell 存活。网络中断后自动重连；重新打开同一个工作区时，回到
原来的 shell。它不会打开新的终端窗口，也不依赖 Mosh、tmux 或 WezTerm。

> Persistent remote shells in the terminal you already use. SSH for transport,
> dtach for session persistence, and no extra terminal window.

## 特性

- 使用当前终端：支持 Otty、Terminal.app、iTerm2、Kitty、Ghostty 等。
- 持久工作区：SSH 断开后，远端 shell 和其中运行的程序继续存在。
- 自动重连：网络切换或临时断网后自动重新附加。
- 原生终端交互：鼠标选择、滚轮、剪贴板、字体、配色和链接均由当前终端处理。
- 主机菜单：保存多个节点、SSH 端口、密钥和跳板机配置。
- 工作区菜单：每个节点可创建多个命名会话。
- 自动安装：远端缺少 `dtach` 时可在首次连接时安装。
- 配置隔离：所有文件都位于 `~/.config/rdev`，不修改 `~/.ssh/config`。
- 兼容 Bash 3.2：可直接运行在 macOS 自带 Bash 上。

## 工作方式

```text
当前终端 -> SSH -> dtach -> 远端登录 shell
```

`dtach` 只负责让远端进程脱离 SSH 连接继续运行，不解释终端输入和输出。因此，
rdev 不会捕获鼠标，也不会引入 tmux copy-mode 一类的额外交互状态。

连接意外中断时：

1. 远端 `dtach` 会话继续运行；
2. rdev 等待 `reconnect_delay` 秒；
3. SSH 恢复后自动附加到同一个 shell。

正常执行 `exit` 时，会话结束，rdev 不会重连。

## 安装

### 从 GitHub 安装

```bash
git clone https://github.com/leafiy/rdev.git
cd rdev
./install.sh
```

### 一行安装

```bash
curl -fsSL https://raw.githubusercontent.com/leafiy/rdev/main/install.sh | bash
```

默认安装位置：

```text
~/.local/bin/rdev
```

如果 `~/.local/bin` 不在 `PATH` 中：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### 本机依赖

- Bash 3.2 或更高版本；
- OpenSSH；
- 标准 `awk`、`sed`、`cksum` 工具。

本机不需要安装 `dtach`。它只运行在远端。

## 快速开始

### 添加节点

```bash
rdev add "Build server" 10.0.0.8 --user developer
```

指定 SSH 端口、私钥和跳板机：

```bash
rdev add "Devbox" devbox.example.com \
  --user root \
  --port 2224 \
  --identity ~/.ssh/id_ed25519 \
  --proxy-jump bastion
```

也可以进入交互式添加流程：

```bash
rdev add
```

### 打开远程工作区

```bash
rdev
```

依次选择：

1. 远程节点；
2. 已有工作区，或创建新的命名工作区。

SSH 会直接占用当前终端，不会打开其他应用或窗口。

### 恢复上次工作区

```bash
rdev resume
```

## 会话控制

| 操作 | 结果 |
| --- | --- |
| `exit` | 结束远端 shell 和对应工作区 |
| `Ctrl-\` | 从 dtach 分离，但保留远端 shell |
| `Ctrl-C` | 停止正在等待的自动重连 |
| `rdev resume` | 重新进入上次节点和工作区 |

## 命令

```text
rdev                         打开节点与工作区菜单
rdev resume                  恢复上次远程工作区
rdev menu                    打开节点与工作区菜单
rdev add [NAME HOST] [...]   添加节点；不带参数时使用交互模式
rdev list                    列出节点
rdev remove ID|NUMBER        删除节点
rdev edit                    编辑节点配置
rdev config                  显示配置文件路径
rdev doctor                  检查本机依赖
rdev version                 显示版本
rdev help                    显示帮助
```

查看添加节点的全部参数：

```bash
rdev add --help
```

## 配置

所有状态都保存在：

```text
~/.config/rdev/config            通用设置
~/.config/rdev/nodes.conf        节点定义
~/.config/rdev/ssh_config        rdev 专用 SSH 配置
~/.config/rdev/workspaces.conf   已知工作区
~/.config/rdev/last-connection   上次节点和工作区
~/.config/rdev/control/          OpenSSH ControlMaster socket
```

### 通用设置

```ini
auto_install_remote=yes
connect_timeout=10
reconnect_delay=2
```

| 设置 | 说明 |
| --- | --- |
| `auto_install_remote` | 远端缺少 dtach 时是否自动安装 |
| `connect_timeout` | SSH 连接超时秒数 |
| `reconnect_delay` | 意外断线后的重连等待秒数 |

设置 `auto_install_remote=no` 可以禁止修改远端软件包。

### 节点格式

```text
id|label|host|user|ssh_port|identity_file|proxy_jump
```

示例：

```text
work|Work server|10.0.0.8|developer|22||
devbox|Devbox|devbox.example.com|root|2224|~/.ssh/id_ed25519|bastion
```

通常应使用 `rdev add` 管理节点，而不是直接编辑此文件。

## 远端自动安装

首次连接时，如果远端没有 `dtach`，rdev 支持使用以下包管理器安装：

- Debian / Ubuntu：`apt-get`；
- Fedora / RHEL：`dnf`；
- Arch Linux：`pacman`；
- openSUSE：`zypper`；
- Alpine Linux：`apk`；
- macOS / Linuxbrew：`brew`。

自动安装需要远端 root 权限或可用的 `sudo`。

## 滚动历史说明

`dtach` 会保存远端进程和 shell 命令历史，但不会维护独立的服务器端屏幕回滚缓冲区。

- 当前终端窗口已经接收的内容仍保留在该终端的 scrollback 中；
- 重新连接时可以恢复正在运行的程序和当前画面；
- 新终端无法重建断线前所有已经输出的屏幕内容。

这是使用任意本机终端、同时不引入 tmux/WezTerm 终端协议的取舍。

## 从旧版本升级

重新执行：

```bash
./install.sh
```

rdev 0.2 的旧节点格式会自动迁移，并保留备份：

```text
nodes.conf.pre-dtach.TIMESTAMP
```

旧的 Mosh、tmux 或 WezTerm 进程不会被停止或删除；rdev 0.4 只是不再使用它们。

## 安全

- SSH 负责认证、主机密钥检查、私钥和跳板机；
- rdev 不修改 `~/.ssh/config`；
- 节点、工作区和状态文件权限为 `0600`；
- 远端 dtach 会话目录权限为 `0700`；
- SSH 参数以数组传递，节点字段会经过格式校验；
- 可关闭远端自动安装。

## 开发与测试

```bash
./tests/test_syntax.sh
./tests/test_cli.sh
./tests/test_active_connection.sh
./tests/test_session_listing.sh
./tests/test_auto_install.sh
```

测试覆盖：

- Bash 语法；
- CLI 与旧配置迁移；
- 当前终端连接；
- 意外断线重连与正常退出；
- 工作区菜单；
- 远端 dtach 自动安装。

CI 在 Ubuntu 和 macOS 上运行。

## 卸载

保留配置：

```bash
./uninstall.sh
```

同时删除 `~/.config/rdev`：

```bash
./uninstall.sh --purge
```

## License

MIT
