# 宣传页素材

首屏已接入 20 秒真实 Kaku 演示：SSH 新建会话 → 远程 AI agent 执行 → 断开连接 → 选回原会话 → 任务继续完成。

- `demo.mp4`：1920×1200，30fps，20秒，少量操作音效。
- `demo-silent.mp4`：画面相同，无音轨。
- `demo-poster.jpg`：从本版视频开场提取的封面。

视频中的终端来自真实窗口录屏；断线段两栏为说明图，4→10步来自同一次测试在SSH断开期间的实际进度采样，不是实时计数。24步计时任务实际约184秒，等待已剪短。服务器没有重启。

音效采用 [Mixkit SFX Free License](https://mixkit.co/license/#sfxFree)：[Air zoom vacuum](https://assets.mixkit.co/active_storage/sfx/2608/2608-preview.mp3)、[On or off light switch tap](https://assets.mixkit.co/active_storage/sfx/2585/2585-preview.mp3)、[Mechanical typewriter single hit](https://assets.mixkit.co/active_storage/sfx/1382/1382-preview.mp3)、[Typewriter soft hit](https://assets.mixkit.co/active_storage/sfx/1366/1366-preview.mp3)。无背景音乐。

## 实录截图

页面下方三组截图均取自与视频相同的 Kaku 原生窗口录屏，只做截帧和裁切，不重绘终端文字。已去除 Ubuntu 登录提示、登录 IP 和无关区域。页面中的标题、图注在截图外呈现。图片使用 PNG 保留终端文字清晰度，可点击放大。

| 文件 | 画面 | 原始录屏时间点 |
| --- | --- | --- |
| `disconnect.png` | SSH 已断开 | 首段开始后 355 秒 |
| `reconnect.png` | 再次输入同一条 ssh 命令 | 402 秒 |
| `menu.png` | 原会话标为可恢复 | 438 秒 |
| `agent-running.png` | 重连后仍在执行同一任务 | 452 秒 |
| `agent.png` | 原任务完成 24 步并保存结果 | 573 秒 |

截图中的 `rdev-omp` 是实录中的原生会话名，不是面向观众的工具说明；网页文案统一称为“远程 AI agent”。断线期间第 4 步到第 10 步的数据来自同次测试的进度日志采样。最后的 24 步结果是该任务随后完成的结果，不宣称断线期间已全部完成。服务器没有重启。
