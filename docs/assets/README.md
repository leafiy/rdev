# 宣传页素材

首屏已接入 20 秒真实 Kaku 演示：SSH 新建会话 → 远程 AI agent 执行 → 断开连接 → 选回原会话 → 任务继续完成。

- `demo.mp4`：1920×1200，30fps，20秒，少量操作音效。
- `demo-silent.mp4`：画面相同，无音轨。
- `demo-poster.jpg`：从本版视频开场提取的封面。

视频中的终端来自真实窗口录屏；断线段两栏为说明图，4→10步来自同一次测试在SSH断开期间的实际进度采样，不是实时计数。24步计时任务实际约184秒，等待已剪短。服务器没有重启。

音效采用 [Mixkit SFX Free License](https://mixkit.co/license/#sfxFree)：[Air zoom vacuum](https://assets.mixkit.co/active_storage/sfx/2608/2608-preview.mp3)、[On or off light switch tap](https://assets.mixkit.co/active_storage/sfx/2585/2585-preview.mp3)、[Mechanical typewriter single hit](https://assets.mixkit.co/active_storage/sfx/1382/1382-preview.mp3)、[Typewriter soft hit](https://assets.mixkit.co/active_storage/sfx/1366/1366-preview.mp3)。无背景音乐。

## 后续素材位

`docs/index.html` 里预留了几个素材位，把文件放进这个目录并按 `index.html` 里的 HTML 注释替换即可。

| 文件 | 用在哪 | 建议 |
| --- | --- | --- |
| `reconnect.gif`（或 `.mp4`） | “看起来是这样”顶部大图 | 断线重连全过程，宽 1600px 左右 |
| `menu.png` | “看起来是这样”左下 | ssh 登录后的会话菜单 |
| `agent.png` | “看起来是这样”右下 | 重连后 Claude Code / Codex 还在原地 |

录屏时把终端字号调大一点（14 px 以上），深色主题更容易看清。
