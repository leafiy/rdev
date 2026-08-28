# rdev

[![test](https://github.com/leafiy/rdev/actions/workflows/test.yml/badge.svg)](https://github.com/leafiy/rdev/actions/workflows/test.yml)

**agent 远程开发时代，何必为了 agent 换掉你熟悉的终端工具。**

一行命令配置好服务器。之后照常 `ssh`，登录时看到会话菜单，回车恢复上次的 shell，里面的 Claude Code / Codex / OpenCode 还在原地跑。SSH 断了、合盖了、换网了都无所谓。本机不装任何东西。

> Keep your terminal. Keep your agent. One curl on your laptop makes any server resume your shell on the next `ssh`. Nothing to install locally.

宣传页：<https://leafiy.github.io/rdev/>

## 安装

在你自己的电脑上运行，按提示输入服务器地址（`user@host`、`user@host:2222` 或 `~/.ssh/config` 里的别名）：

```bash
curl -fsSL https://raw.githubusercontent.com/leafiy/rdev/main/install.sh | bash
```

直接指定目标：

```bash
curl -fsSL https://raw.githubusercontent.com/leafiy/rdev/main/install.sh | bash -s -- dev@box:2222 -i ~/.ssh/id_ed25519
```

已经在服务器里了：

```bash
curl -fsSL https://raw.githubusercontent.com/leafiy/rdev/main/install.sh | bash -s -- --here
```

脚本做的事：

1. 用 ssh 连到服务器，全程复用一条连接，密码只输一次。
2. 在本机下载 [shpool](https://github.com/shell-pool/shpool) 的静态二进制并推过去。服务器访问不了 GitHub 也没关系；不需要 root，不装系统包。
3. 写一份 shpool 配置到 `~/.config/rdev/shpool.toml`：不改提示符，重连只交还不回放。
4. 在 `~/.zshrc` / `~/.bashrc` 末尾加一段带标记的钩子，只在交互式 SSH 登录时弹菜单。`ssh host 命令`、scp、rsync、git、VS Code Remote 一律不受影响。

需要：本机有 `ssh` 和 `curl`（macOS、Linux、WSL）；服务器是 Linux x86_64 / arm64（或 Apple Silicon 的 macOS），登录 shell 为 zsh 或 bash。

## 用法

```text
$ ssh dev@box

rdev · box  3 个会话

   1) work     Claude Code 运行中 · 可恢复 · 2 分钟前
   2) infra    空闲 · 可恢复 · 3 小时前
   3) anna     Codex 运行中 · 已连接，选择即接管 · 刚刚

  回车 恢复 work · 数字 选择 · n 新建 · 直接输入名称 新建 · k 数字 删除 · q 普通 shell
  会话里按 Ctrl-Space Ctrl-q 可随时离开而不结束它。

>
```

| 想做什么 | 怎么做 |
| --- | --- |
| 恢复上次的会话 | 回车 |
| 新建会话 | `n`，或直接输入一个名称 |
| 从另一个终端接管 | 选一个“已连接”的会话 |
| 离开会话但不结束 | `Ctrl-Space` `Ctrl-q`，或者直接关窗口 |
| 结束会话 | 在会话里 `exit`，或菜单里 `k 编号` |
| 不进菜单，用普通 shell | `q` |
| 跳过菜单直达会话 | `ssh -t dev@box '~/.local/bin/rdev attach work'` |
| 完全不触发菜单登录 | `ssh -t dev@box 'RDEV_SKIP=1 exec $SHELL -l'` |

服务器上的命令：

```text
rdev                     会话菜单
rdev attach 名称         直接进入（不存在则新建）
rdev new [名称]          新建会话
rdev list                列出会话、状态、里面在跑的 agent
rdev detach [名称…]      让会话脱离当前终端（不结束）
rdev kill 名称…          结束会话
rdev setup               安装 / 更新（下载 shpool、写配置、加钩子）
rdev doctor              检查安装状态
rdev uninstall [--purge] 移除
```

## 它是怎么工作的

```text
你的终端  →  ssh  →  rdev 菜单  →  shpool 会话（shell + agent 常驻）
```

- **shpool** 是 Google 开源的会话保持工具，只做一件事：把 shell 从 SSH 连接里解耦。它不是终端复用器，不画窗格，不接管键盘鼠标，所以终端还是你的终端。
- **重连只交还不回放。** 重新连上后，终端被交还给原来的程序并收到 SIGWINCH，Claude Code 这类 TUI 会自己把界面画回来，不会错位、不会重复。断线前已经输出到你终端里的内容仍在你自己的回滚缓冲里，鼠标滚轮照常用。
- **登录钩子只在交互式 SSH 登录时触发**（`SSH_TTY` 存在、不在会话内、有终端），zsh 用 ZLE 的 `line-init` 钩子，等提示符就绪后再弹菜单，与 powerlevel10k instant prompt 等兼容。
- **守护进程按需拉起。** 服务器重启后第一次登录时 shpool 会自动启动守护进程，不依赖 systemd。有 `loginctl` 时会顺手开启 linger。

## 它改了什么

| 位置 | 内容 |
| --- | --- |
| `~/.local/bin/rdev` | 本程序（一个 bash 脚本） |
| `~/.local/share/rdev/bin/shpool` | 下载的 shpool 静态二进制（系统已有 shpool 时不下载） |
| `~/.config/rdev/shpool.toml` | shpool 配置，可随意修改，`rdev setup` 不会覆盖 |
| `~/.config/rdev/env` | 可选，覆盖 `RDEV_*` 变量（见下） |
| `~/.local/run/rdev/` | socket 与守护进程日志 |
| `~/.zshrc` / `~/.bashrc` | 末尾一段 `# >>> rdev >>> … # <<< rdev <<<` 钩子 |

不碰 sshd、`~/.ssh/config`，不需要 root。

### 可覆盖的变量

写在 `~/.config/rdev/env`（POSIX sh 语法）：

```sh
RDEV_SHPOOL_BIN=/usr/bin/shpool                  # 用指定的 shpool
RDEV_SHPOOL_SOCKET=/run/user/1000/shpool/shpool.socket   # 接入已有的 shpool 守护进程
RDEV_SHPOOL_CONFIG=~/.config/shpool/config.toml  # 用已有的 shpool 配置
RDEV_RUN_DIR=~/.local/run/rdev                   # socket 与日志目录
RDEV_SHPOOL_VERSION=v0.11.3                      # rdev setup 下载的版本
```

### 默认的 shpool 配置

```toml
prompt_prefix = ""                 # 不往提示符里塞会话名
session_restore_mode = "simple"    # 重连只交还并 SIGWINCH，不回放历史
output_spool_lines = 65535
vt100_output_spool_width = 240
```

想在新窗口重连时也看到最近的输出，可以把 `session_restore_mode` 改成 `"screen"` 或 `{ lines = 2000 }`；代价是 TUI 程序重连后可能出现重复画面。

## 常见问题

**和 tmux、mosh 有什么区别？** tmux 是终端复用器，会接管整个终端：窗格、前缀键、copy-mode、自己的鼠标处理。mosh 解决的是网络抖动和漫游，本身不保持会话，还要本机装客户端、服务器开 UDP。rdev 只做会话保持，本机零安装，走普通 ssh。

**服务器重启了会怎样？** 会话消失（和 tmux 一样）。之后第一次登录会自动拉起守护进程。

**多个终端能同时连同一个会话吗？** 同一时间一个会话只属于一个终端；选一个“已连接”的会话就会从原终端接管过来。想并行就多开会话。

**登录 shell 是 fish？** 目前只自动接管 zsh 和 bash。可以在 fish 的启动文件里自己调用 `~/.local/bin/rdev`：退出码 0 表示会话已结束，此时应退出登录 shell；退出码 10 表示用户选择了普通 shell。

**systemd 的 `KillUserProcesses=yes`？** 这会让注销时杀掉所有后台进程，任何会话保持工具都活不下来。把 `/etc/systemd/logind.conf` 里的它改成 `no`。`rdev doctor` 会提示。

**守护进程起不来？** 看 `~/.local/run/rdev/daemonized-shpool.log`，或运行 `rdev doctor`。

## 卸载

在服务器上：

```bash
rdev uninstall           # 保留 ~/.config/rdev
rdev uninstall --purge   # 连配置一起删
```

或在本机：

```bash
curl -fsSL https://raw.githubusercontent.com/leafiy/rdev/main/install.sh | bash -s -- --uninstall dev@box
```

正在运行的会话和守护进程不受影响，需要的话用 `shpool kill` 结束。

## 开发与测试

全部是 bash，兼容 macOS 自带的 bash 3.2。测试用假的 `shpool` 和 `ssh`，不需要网络：

```bash
tests/test_syntax.sh     # 语法与 bash 3.2 兼容性
tests/test_menu.sh       # 菜单、列表解析、退出码
tests/test_setup.sh      # setup / doctor / uninstall、钩子幂等
tests/test_install.sh    # 一键安装脚本（假 ssh 在本地执行远程命令）
```

CI 在 Ubuntu 和 macOS（`/bin/bash` 3.2）上运行。

宣传页在 `docs/index.html`，素材位说明见 `docs/assets/README.md`。

## License

MIT
