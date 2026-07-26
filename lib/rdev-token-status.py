import glob
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
from pathlib import Path


HOME = os.path.expanduser("~")
CACHE_VERSION = 4
CACHE_PATH = f"/tmp/rdev-token-aggregate-{os.getuid()}.json"
SEARCH_DIRS = [
    os.path.join(HOME, ".local/bin"),
    os.path.join(HOME, ".bun/bin"),
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
]
TOOLS = {
    "omp": (["omp"], ".omp/agent/sessions/**/*.jsonl"),
    "pi": (["pi"], ".pi/agent/sessions/**/*.jsonl"),
    "codex": (["codex"], ".codex/sessions/**/*.jsonl"),
    "claude": (["claude"], ".claude/projects/**/*.jsonl"),
    "opencode": (["opencode"], None),
}


def executable_exists(names):
    for name in names:
        if shutil.which(name):
            return True
        for directory in SEARCH_DIRS:
            if os.access(os.path.join(directory, name), os.X_OK):
                return True
    return False


def process_tree(root_pid):
    try:
        output = subprocess.check_output(
            ["ps", "-axo", "pid=,ppid=,command="],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=1,
        )
    except Exception:
        return []
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
    return [(pid, command) for pid, command in rows if pid in wanted]


def has_command(text, name):
    return re.search(r"(^|[/\s])" + re.escape(name) + r"(?:\s|$)", text) is not None


def detect_active_agent(processes):
    text = "\n".join(command for _, command in processes).lower()
    if has_command(text, "omp") or "oh-my-pi" in text:
        return "omp"
    if "pi-coding-agent" in text or has_command(text, "pi"):
        return "pi"
    if has_command(text, "opencode"):
        return "opencode"
    if has_command(text, "codex"):
        return "codex"
    if has_command(text, "claude"):
        return "claude"
    return None


def open_session_file(processes, marker):
    for pid, _ in processes:
        fd_dir = Path(f"/proc/{pid}/fd")
        if not fd_dir.is_dir():
            continue
        try:
            descriptors = list(fd_dir.iterdir())
        except Exception:
            continue
        for descriptor in descriptors:
            try:
                path = str(descriptor.resolve())
            except Exception:
                continue
            if marker in path and path.endswith(".jsonl"):
                return os.path.realpath(path)

    lsof = shutil.which("lsof")
    if lsof:
        for pid, _ in processes:
            try:
                output = subprocess.check_output(
                    [lsof, "-a", "-p", str(pid), "-Fn"],
                    text=True,
                    stderr=subprocess.DEVNULL,
                    timeout=0.5,
                )
            except Exception:
                continue
            for line in output.splitlines():
                if line.startswith("n"):
                    path = line[1:]
                    if marker in path and path.endswith(".jsonl"):
                        return os.path.realpath(path)
    return None


def number(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else 0


def usage_total(usage):
    if not isinstance(usage, dict):
        return 0
    return sum(
        number(usage.get(key))
        for key in (
            "input_tokens",
            "output_tokens",
            "cache_creation_input_tokens",
            "cache_read_input_tokens",
        )
    )


def parse_line(tool, item, total, current):
    if not isinstance(item, dict):
        return total, current
    if tool in ("omp", "pi"):
        message = item.get("message") or {}
        if not isinstance(message, dict):
            return total, current
        usage = message.get("usage") or {}
        used = usage.get("totalTokens") if isinstance(usage, dict) else None
        if isinstance(used, (int, float)):
            total += used
            current = used
        snapshot = message.get("contextSnapshot") or {}
        if isinstance(snapshot, dict):
            context = number(snapshot.get("promptTokens")) + number(
                snapshot.get("nonMessageTokens")
            )
            if context:
                current = context
    elif tool == "codex":
        payload = item.get("payload") or {}
        info = payload.get("info") or {} if isinstance(payload, dict) else {}
        if not isinstance(info, dict):
            return total, current
        total_usage = info.get("total_token_usage") or {}
        last_usage = info.get("last_token_usage") or {}
        reported_total = (
            total_usage.get("total_tokens") if isinstance(total_usage, dict) else None
        )
        reported_current = (
            last_usage.get("total_tokens") if isinstance(last_usage, dict) else None
        )
        if isinstance(reported_total, (int, float)):
            total = reported_total
        if isinstance(reported_current, (int, float)):
            current = reported_current
    elif tool == "claude":
        message = item.get("message") or {}
        usage = message.get("usage") or {} if isinstance(message, dict) else {}
        used = usage_total(usage)
        if used:
            total += used
            current = used
    return total, current


def load_cache():
    try:
        with open(CACHE_PATH) as handle:
            cache = json.load(handle)
        if cache.get("version") == CACHE_VERSION and isinstance(cache.get("files"), dict):
            return cache
    except Exception:
        pass
    return {"version": CACHE_VERSION, "files": {}}


def save_cache(files, tool_totals, last_full_scan):
    try:
        temporary = CACHE_PATH + f".{os.getpid()}"
        with open(temporary, "w") as handle:
            json.dump(
                {
                    "version": CACHE_VERSION,
                    "files": files,
                    "tool_totals": tool_totals,
                    "last_full_scan": last_full_scan,
                },
                handle,
            )
        os.replace(temporary, CACHE_PATH)
    except Exception:
        pass


def scan_jsonl(path, tool, previous):
    real_path = os.path.realpath(path)
    try:
        stat = os.stat(real_path)
    except OSError:
        return None
    same_file = (
        isinstance(previous, dict)
        and previous.get("tool") == tool
        and previous.get("device") == stat.st_dev
        and previous.get("inode") == stat.st_ino
    )
    unchanged = (
        same_file
        and previous.get("size") == stat.st_size
        and previous.get("mtime_ns") == stat.st_mtime_ns
    )
    if unchanged:
        return previous

    can_continue = same_file and 0 <= previous.get("size", -1) < stat.st_size
    offset = previous.get("size", 0) if can_continue else 0
    total = number(previous.get("total")) if can_continue else 0
    current = number(previous.get("current")) if can_continue else 0
    try:
        with open(real_path, "r", encoding="utf-8", errors="ignore") as handle:
            handle.seek(offset)
            for line in handle:
                try:
                    total, current = parse_line(tool, json.loads(line), total, current)
                except Exception:
                    continue
    except OSError:
        return None
    return {
        "tool": tool,
        "device": stat.st_dev,
        "inode": stat.st_ino,
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
        "total": total,
        "current": current,
    }


def aggregate_files(tool, relative_pattern, old_files, new_files):
    pattern = os.path.join(HOME, relative_pattern)
    paths = [path for path in glob.glob(pattern, recursive=True) if os.path.isfile(path)]
    total = 0
    entries = {}
    for path in paths:
        real_path = os.path.realpath(path)
        entry = scan_jsonl(real_path, tool, old_files.get(real_path))
        if not entry:
            continue
        new_files[real_path] = entry
        entries[real_path] = entry
        total += number(entry.get("total"))
    return total, entries, paths


def opencode_tokens(active):
    database = os.path.join(HOME, ".local/share/opencode/opencode.db")
    if not os.path.isfile(database):
        return 0, 0
    try:
        connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True, timeout=0.3)
        columns = [row[1] for row in connection.execute('pragma table_info("session")')]
        token_columns = [name for name in columns if name.startswith("tokens_")]
        total = 0
        if token_columns:
            expression = " + ".join(f'COALESCE("{name}", 0)' for name in token_columns)
            row = connection.execute(f'SELECT SUM({expression}) FROM session').fetchone()
            total = number(row[0]) if row else 0
        else:
            for row in connection.execute("SELECT data FROM message"):
                try:
                    tokens = json.loads(row[0]).get("tokens") or {}
                    total += number(tokens.get("total"))
                except Exception:
                    pass

        current = 0
        if active:
            for row in connection.execute(
                "SELECT data FROM message ORDER BY time_updated DESC LIMIT 200"
            ):
                try:
                    tokens = json.loads(row[0]).get("tokens") or {}
                except Exception:
                    continue
                if not isinstance(tokens, dict):
                    continue
                if number(tokens.get("total")):
                    current = number(tokens.get("total"))
                    break
                cache = tokens.get("cache") or {}
                current = sum(
                    number(tokens.get(key)) for key in ("input", "output", "reasoning")
                ) + sum(number(cache.get(key)) for key in ("read", "write"))
                if current:
                    break
        connection.close()
        return total, current
    except Exception:
        return 0, 0


def newest_path(paths):
    try:
        return os.path.realpath(max(paths, key=os.path.getmtime)) if paths else None
    except Exception:
        return None


def compact(value):
    if value >= 1_000_000_000:
        return f"{value / 1_000_000_000:.1f}B"
    if value >= 1_000_000:
        return f"{value / 1_000_000:.1f}M"
    if value >= 1_000:
        return f"{value / 1_000:.1f}k"
    return str(int(value))


def main():
    try:
        pane_pid = int(sys.argv[1])
    except (IndexError, ValueError):
        return

    installed = {
        tool for tool, (commands, _) in TOOLS.items() if executable_exists(commands)
    }
    processes = process_tree(pane_pid)
    active = detect_active_agent(processes)
    cache = load_cache()
    old_files = cache.get("files", {})
    cached_totals = cache.get("tool_totals", {})
    file_tools = {
        tool for tool, (_, pattern) in TOOLS.items() if tool in installed and pattern
    }
    cache_is_fresh = (
        time.time() - number(cache.get("last_full_scan")) < 60
        and file_tools.issubset(cached_totals)
    )
    new_files = dict(old_files) if cache_is_fresh else {}
    tool_totals = dict(cached_totals) if cache_is_fresh else {}
    last_full_scan = number(cache.get("last_full_scan")) if cache_is_fresh else time.time()
    entries_by_tool = {}
    paths_by_tool = {}

    if cache_is_fresh:
        for tool in file_tools:
            entries = {
                path: entry
                for path, entry in old_files.items()
                if isinstance(entry, dict) and entry.get("tool") == tool
            }
            entries_by_tool[tool] = entries
            paths_by_tool[tool] = list(entries)
    else:
        for tool, (_, pattern) in TOOLS.items():
            if tool not in installed or pattern is None:
                continue
            tool_total, entries, paths = aggregate_files(
                tool, pattern, old_files, new_files
            )
            tool_totals[tool] = tool_total
            entries_by_tool[tool] = entries
            paths_by_tool[tool] = paths

    if active in file_tools:
        markers = {
            "omp": "/.omp/agent/sessions/",
            "pi": "/.pi/agent/sessions/",
            "codex": "/.codex/sessions/",
            "claude": "/.claude/projects/",
        }
        source = open_session_file(processes, markers[active])
        if not source:
            known_paths = paths_by_tool.get(active, [])
            source = newest_path(known_paths)
            if not source:
                pattern = TOOLS[active][1]
                candidates = glob.glob(os.path.join(HOME, pattern), recursive=True)
                source = newest_path([path for path in candidates if os.path.isfile(path)])
        if source:
            real_source = os.path.realpath(source)
            previous = old_files.get(real_source)
            entry = scan_jsonl(real_source, active, previous)
            if entry:
                previous_total = number(previous.get("total")) if isinstance(previous, dict) else 0
                tool_totals[active] = (
                    number(tool_totals.get(active))
                    + number(entry.get("total"))
                    - previous_total
                )
                new_files[real_source] = entry
                entries_by_tool.setdefault(active, {})[real_source] = entry
                if real_source not in paths_by_tool.setdefault(active, []):
                    paths_by_tool[active].append(real_source)

    total = sum(number(tool_totals.get(tool)) for tool in file_tools)

    open_current = 0
    if "opencode" in installed:
        open_total, open_current = opencode_tokens(active == "opencode")
        total += open_total

    save_cache(new_files, tool_totals, last_full_scan)

    current = 0
    if active == "opencode":
        current = open_current
    elif active in entries_by_tool:
        markers = {
            "omp": "/.omp/agent/sessions/",
            "pi": "/.pi/agent/sessions/",
            "codex": "/.codex/sessions/",
            "claude": "/.claude/projects/",
        }
        source = open_session_file(processes, markers[active]) or newest_path(
            paths_by_tool.get(active, [])
        )
        if source:
            entry = entries_by_tool[active].get(os.path.realpath(source))
            if entry:
                current = number(entry.get("current"))

    total_text = compact(total) if installed else "--"
    current_text = compact(current) if active and current else "--"
    print(f"Token 总 {total_text} · 当前对话 {current_text}", end="")


if __name__ == "__main__":
    main()
