#!/usr/bin/env python3
"""真实 shpool + PTY 回归；RDEV_TEST_SHPOOL 必须指向已安装的 shpool。"""
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import select
import shlex
import struct
import subprocess
import sys
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parent.parent
BASH = os.environ.get("RDEV_TEST_BASH", "/bin/bash")
SHPOOL = os.environ["RDEV_TEST_SHPOOL"]


class Terminal:
    def __init__(self, args, env, rows=24, cols=100):
        self.master, slave = os.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

        def controlling_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        self.process = subprocess.Popen(
            args, env=env, stdin=slave, stdout=slave, stderr=slave,
            preexec_fn=controlling_terminal,
        )
        os.close(slave)
        self.pending = b""

    def send(self, data):
        os.write(self.master, data)

    def expect(self, pattern):
        deadline = time.monotonic() + 10
        while True:
            match = re.search(pattern, self.pending)
            if match:
                result, self.pending = self.pending[:match.end()], self.pending[match.end():]
                return result
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(f"Missing {pattern!r}; terminal: {self.pending[-2000:]!r}")
            if select.select([self.master], [], [], remaining)[0]:
                try:
                    data = os.read(self.master, 65536)
                except OSError:
                    data = b""
                if not data:
                    raise AssertionError(f"Terminal exited: {self.pending[-2000:]!r}")
                self.pending += data

    def close(self):
        # macOS 上先关闭 master，避免 slave 退出时等待无人读取的终端输出。
        if self.master is not None:
            os.close(self.master)
            self.master = None
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)


def main():
    # 短 socket 路径，避免 macOS Unix socket 的路径长度限制。
    with tempfile.TemporaryDirectory(prefix="rdev-pty-", dir="/tmp") as directory:
        work = Path(directory)
        home = work / "home"
        home.mkdir()
        env = {k: v for k, v in os.environ.items() if not k.startswith("RDEV_")}
        for key in ("SHPOOL_SESSION_NAME", "SSH_TTY"):
            env.pop(key, None)
        env.update(
            HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
            XDG_DATA_HOME=str(home / ".local/share"), TERM="xterm-256color", NO_COLOR="1",
            RDEV_SHPOOL_BIN=SHPOOL, RDEV_CONFIG_DIR=str(work / "config"),
            RDEV_RUN_DIR=str(work / "run"), RDEV_SHPOOL_SOCKET=str(work / "run/sock"),
            RDEV_SHPOOL_CONFIG=str(work / "config/shpool.toml"),
        )
        rdev = [BASH, str(ROOT / "bin/rdev")]
        # 仅生成生产默认配置；假 shpool 不负责模拟恢复行为。
        subprocess.run(
            rdev + ["setup", "--no-hook", "--no-linger"], check=True,
            env=dict(env, RDEV_SHPOOL_BIN=str(ROOT / "tests/fixtures/fake-shpool"),
                     FAKE_SHPOOL_JSON=str(ROOT / "tests/fixtures/sessions.json"),
                     FAKE_SHPOOL_LOG=str(work / "setup.log")),
            stdout=subprocess.DEVNULL,
        )
        sp = [SHPOOL, "-s", env["RDEV_SHPOOL_SOCKET"], "-c", env["RDEV_SHPOOL_CONFIG"]]
        with open(work / "daemon.log", "wb") as log, contextlib.ExitStack() as cleanup:
            daemon = subprocess.Popen(sp + ["daemon"], env=env, stdout=log, stderr=log)

            def stop_daemon():
                daemon.terminate()
                daemon.wait(timeout=5)

            cleanup.callback(stop_daemon)
            deadline = time.monotonic() + 10
            while subprocess.run(sp + ["-D", "list"], env=env, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL).returncode:
                if daemon.poll() is not None or time.monotonic() > deadline:
                    raise AssertionError((work / "daemon.log").read_text())
                time.sleep(0.05)
            cleanup.callback(subprocess.run, sp + ["kill", "busy"], env=env,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)

            def terminal(args, **size):
                term = Terminal(args, env, **size)
                cleanup.callback(term.close)
                return term

            # 静默等待输入的前台任务不处理 SIGWINCH；没有恢复缓冲就无法重画。
            worker = work / "worker.py"
            worker.write_text(
                "import os\nfrom pathlib import Path\n"
                "for i in range(10000): print(f'HISTORY_{i:05d}')\n"
                "print(f'ACTIVE_{os.getpid()}_READY', flush=True)\n"
                "assert input() == 'finish', 'unexpected input injected on attach'\n"
                f"Path({str(work / 'finished')!r}).write_text(str(os.getpid()))\n"
            )
            original = terminal(sp + ["attach", "--dir", str(work), "--cmd",
                                     "/usr/bin/env HISTFILE=/dev/null /bin/bash --noprofile --norc",
                                     "busy"])
            original.expect(rb"[#$] ")
            original.send((shlex.join([sys.executable, str(worker)]) + "\n").encode())
            initial = original.expect(rb"ACTIVE_[0-9]+_READY")
            marker = re.search(rb"ACTIVE_([0-9]+)_READY", initial)
            pid = int(marker[1])

            def restored(term):
                output = term.expect(marker[0])
                assert b"HISTORY_09999" in output, output
                assert b"HISTORY_00000" not in output, "replayed full history"
                assert output.count(b"HISTORY_") <= 30, "restored more than one screen"
                os.kill(pid, 0)

            menu = terminal(rdev)
            menu.expect(rb"> ")
            menu.send(b"1\n")
            restored(menu)
            print("PASS: active-command takeover restores one screen without Ctrl+C")

            menu.send(b"\x00\x11")
            menu.expect(rb"> ")
            menu.close()
            # shpool 的客户端退出先于 Disconnected 状态发布；新连接在状态落定后登录。
            deadline = time.monotonic() + 10
            while True:
                listing = subprocess.run(sp + ["list", "--json"], env=env, check=True,
                                         capture_output=True, text=True)
                if json.loads(listing.stdout)["sessions"][0]["status"] == "Disconnected":
                    break
                assert time.monotonic() < deadline, listing.stdout
                time.sleep(0.05)
            resumed = terminal(rdev)
            resumed.expect(rb"> ")
            resumed.send(b"\n")
            restored(resumed)
            print("PASS: fresh-menu Enter restores the detached long-running task")

            direct = terminal(rdev + ["attach", "busy"], rows=30, cols=120)
            restored(direct)
            direct.send(b"finish\n")
            direct.expect(rb"[#$] ")
            assert (work / "finished").read_text() == str(pid)
            print("PASS: different-size direct attach preserves the task and accepts input")


if __name__ == "__main__":
    main()
