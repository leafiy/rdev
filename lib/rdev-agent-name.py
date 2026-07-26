import re
import subprocess
import sys


def process_tree(root_pid):
    try:
        output = subprocess.check_output(
            ["ps", "-axo", "pid=,ppid=,command="],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return ""

    rows = []
    children = {}
    for line in output.splitlines():
        match = re.match(r"\s*(\d+)\s+(\d+)\s+(.*)", line)
        if not match:
            continue
        pid, ppid = int(match.group(1)), int(match.group(2))
        command = match.group(3)
        rows.append((pid, command))
        children.setdefault(ppid, []).append(pid)

    wanted = {root_pid}
    queue = [root_pid]
    while queue:
        for child in children.get(queue.pop(), []):
            if child not in wanted:
                wanted.add(child)
                queue.append(child)
    return "\n".join(command for pid, command in rows if pid in wanted).lower()


def has_command(text, name):
    return re.search(r"(^|[/\s])" + re.escape(name) + r"(?:\s|$)", text) is not None


def agent_name(text):
    if has_command(text, "omp") or "oh-my-pi" in text:
        return "OMP"
    if "pi-coding-agent" in text or has_command(text, "pi"):
        return "Pi"
    if has_command(text, "opencode"):
        return "OpenCode"
    if has_command(text, "codex"):
        return "Codex"
    if has_command(text, "claude"):
        return "Claude"
    if has_command(text, "antigravity"):
        return "Antigravity"
    if has_command(text, "gemini"):
        return "Gemini"
    if has_command(text, "qwen") or has_command(text, "qwen-code"):
        return "Qwen"
    if has_command(text, "amp"):
        return "Amp"
    if has_command(text, "aider"):
        return "Aider"
    if has_command(text, "goose"):
        return "Goose"
    if has_command(text, "copilot"):
        return "Copilot"
    if has_command(text, "crush"):
        return "Crush"
    if has_command(text, "kimi"):
        return "Kimi"
    return "Shell"


if len(sys.argv) == 2:
    try:
        text = process_tree(int(sys.argv[1]))
        if text:
            print(agent_name(text), end="")
    except Exception:
        pass
