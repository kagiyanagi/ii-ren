"""Claude Code behind the sidebar: the user's own `claude`, in stream-json mode.

This is the subprocess protocol the Claude Agent SDK speaks (its
_internal/query.py and transport/subprocess_cli.py), spoken directly so the shell
needs no Python package: user turns go in on stdin as JSON lines, the CLI's
messages come back on stdout, and both sides send `control_request`s -- the CLI
to ask permission (`can_use_tool`, because of `--permission-prompt-tool stdio`),
us to interrupt, switch model or mode, or read the plan's limits (`get_usage`).

The binary is run unmodified and signs in on its own, so usage is the user's plan.
ANTHROPIC_API_KEY is dropped from its environment for the same reason: with it
set the CLI would bill the API instead.

Sessions are the CLI's own: `--session-id` for a new one, `--resume` for an old
one, and the history list reads the transcripts it keeps under
~/.claude/projects/<cwd>, the same files and the same reading the SDK's
list_sessions does. Retry and undo restart the CLI at an earlier message
(`--resume-session-at`), which is how the SDK rewinds a conversation.
"""
import asyncio
import base64
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import time
import uuid

from bridge import (HOME, LIMITS_GAP, BridgeError, MissingAgent, desktop_server, effort_label, epoch, first_string, limit_window,
                    load_state, one_line, persona, save_state)

# Read-only desktop tools need no approval in any mode; clicking and IPC calls do.
DESKTOP_READ_ONLY = ("screenshot", "windows", "see", "ipc_show")

# Claude Code's tools under the names the sidebar's tool rows know how to draw.
TOOL_NAMES = {
    "Bash": "bash", "BashOutput": "bash", "Read": "read_file", "Write": "write_file",
    "Edit": "edit_file", "MultiEdit": "edit_file", "NotebookEdit": "edit_file",
    "Grep": "grep_search", "Glob": "find_by_name", "LS": "list_dir",
    "WebSearch": "web_search", "WebFetch": "fetch_url", "Task": "invoke_subagent",
    "Agent": "invoke_subagent", "TodoWrite": "manage_task", "AskUserQuestion": "ask_question",
    "ToolSearch": "load_tools",
}

MODES = {"manual": "default", "smart": "auto", "off": "bypassPermissions"}

# "Default" in either picker is not a model or a level of its own: it is no pin at
# all -- no --model / --effort -- so Claude Code's own settings decide, exactly as
# in a terminal. Its label says what those settings resolve to (get_settings).
EFFORT_NOTES = {
    "low": "Quickest answers, least thinking",
    "medium": "Balanced speed and depth",
    "high": "Thinks harder on tricky work",
    "xhigh": "Thinks longer still",
    "max": "As long as it needs: slowest, and uses the most of your plan",
}

# Plan limits, from the CLI's own `get_usage` (what its /usage shows).
PLANS = {"pro": "Claude Pro", "max": "Claude Max", "team": "Claude Team", "enterprise": "Claude Enterprise"}
LIMIT_KINDS = {"session": ("5-hour", 300), "weekly_all": ("Weekly", 10080)}
# The streamed rate_limit_event's windows, by the id get_usage gives them.
EVENT_WINDOWS = {"five_hour": "session", "seven_day": "weekly_all"}


def claude_limits(body: dict, current: str = "") -> dict:
    """`get_usage`'s answer as the sidebar's limits. `current` is the model in use:
    a weekly window scoped to another model does not limit it."""
    plan = PLANS.get(body.get("subscription_type") or "", "")
    limits = body.get("rate_limits") or {}
    out = {"plan": plan, "windows": [], "notes": [], "checked_at": int(time.time())}
    if not body.get("rate_limits_available") or not limits:
        out["notes"].append("This login has no plan limits (an API key, Bedrock or Vertex is billed instead).")
        return out
    rows = limits.get("limits")
    if isinstance(rows, list) and rows:
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get("percent"), (int, float)):
                continue
            kind = row.get("kind") or ""
            model = (((row.get("scope") or {}).get("model") or {}).get("display_name") or "").strip()
            label, minutes = LIMIT_KINDS.get(kind, ("", 10080 if row.get("group") == "weekly" else 0))
            if not label:
                label = f"Weekly · {model}" if kind == "weekly_scoped" and model else kind.replace("_", " ").capitalize()
            wid = f"{kind}:{model}" if model else kind
            out["windows"].append(limit_window(wid, label, row["percent"], epoch(row.get("resets_at")), minutes,
                                               counts=not model or model.lower() in current.lower()))
    else:  # an older CLI: the fixed windows, then the per-model weekly ones
        for key, (wid, label, minutes) in {"five_hour": ("session", "5-hour", 300), "seven_day": ("weekly_all", "Weekly", 10080)}.items():
            window = limits.get(key) or {}
            if isinstance(window.get("utilization"), (int, float)):
                out["windows"].append(limit_window(wid, label, window["utilization"], epoch(window.get("resets_at")), minutes))
        for row in limits.get("model_scoped") or []:
            model = (row.get("display_name") or "").strip()
            if model and isinstance(row.get("utilization"), (int, float)):
                out["windows"].append(limit_window(f"weekly_scoped:{model}", f"Weekly · {model}", row["utilization"],
                                                   epoch(row.get("resets_at")), 10080, counts=model.lower() in current.lower()))
    extra = limits.get("extra_usage") or {}
    if extra.get("is_enabled") and isinstance(extra.get("utilization"), (int, float)):
        out["notes"].append(f"Extra usage: {round(extra['utilization'])}% of this month's credits used.")
    return out


_SKIP_PROMPT = re.compile(r"^(?:<local-command-stdout>|<local-command-caveat>|<session-start-hook>|<tick>|<goal>|\[Request interrupted by user[^\]]*\])")
_COMMAND_NAME = re.compile(r"<command-name>(.*?)</command-name>")
_COMMAND_ARGS = re.compile(r"<command-args>(.*?)</command-args>", re.S)
_USER_LINE = re.compile(r'"type"\s*:\s*"user"')


def tool_name(name: str) -> str:
    if name.startswith("mcp__"):
        return name.split("__", 2)[-1]
    return TOOL_NAMES.get(name, name)


def tool_context(name: str, args: dict) -> str:
    """The one line a tool row and the status line show for a call."""
    if name == "Bash":
        return one_line(args.get("description") or args.get("command") or "")
    for key in ("file_path", "path", "url", "query", "pattern", "description", "prompt"):
        if isinstance(args.get(key), str) and args[key].strip():
            return one_line(args[key])
    return first_string(args)


def result_text(content) -> str:
    """A tool_result's content -- a string, or text and image blocks -- as text."""
    if isinstance(content, str):
        return content
    parts = []
    for block in content or []:
        if isinstance(block, dict):
            if block.get("type") == "text":
                parts.append(block.get("text") or "")
            elif block.get("type") == "image":
                parts.append("[image]")
    return "\n".join(parts)


def approval_text(name: str, args: dict, title: str) -> tuple[str, str]:
    """(description, command) for the approval card: what it is, then the thing itself."""
    if name == "Bash":
        return (args.get("description") or "Run a command"), args.get("command") or ""
    if name in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        return ("Change a file" if name != "Write" else "Write a file"), args.get("file_path") or args.get("notebook_path") or ""
    if name == "WebFetch":
        return "Open a web page", args.get("url") or ""
    if name.startswith("mcp__"):
        server, _, tool = name[5:].partition("__")
        return f"{tool} ({server})", json.dumps(args, ensure_ascii=False, indent=1) if args else ""
    return (title or name), json.dumps(args, ensure_ascii=False, indent=1) if args else ""


# ── Transcripts on disk ──────────────────────────────────────────────────────


def _js_hash(text: str) -> str:
    """The CLI's 32-bit string hash in base 36, for over-long directory names."""
    h = 0
    for ch in text:
        h = ((h << 5) - h + ord(ch)) & 0xFFFFFFFF
    if h >= 0x80000000:
        h -= 0x100000000
    h = abs(h)
    digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    out = ""
    while h:
        out = digits[h % 36] + out
        h //= 36
    return out or "0"


def project_dir(cwd: str = HOME) -> str:
    config = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
    name = re.sub(r"[^a-zA-Z0-9]", "-", cwd)
    if len(name) > 200:
        name = f"{name[:200]}-{_js_hash(cwd)}"
    return os.path.join(config, "projects", name)


def _entries(path: str) -> list[dict]:
    entries = []
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if isinstance(entry, dict) and isinstance(entry.get("uuid"), str):
                    entries.append(entry)
    except OSError:
        pass
    return entries


def chain(entries: list[dict], leaf: str = "") -> list[dict]:
    """The conversation as it stands: the newest main-line leaf, walked back to
    the root. A rewind branches the file, so file order alone would replay turns
    that were undone (sessions.py _build_conversation_chain). `leaf` pins the end
    to a given message instead -- a rewind nothing has been said after yet."""
    by_id = {e["uuid"]: e for e in entries}
    order = {e["uuid"]: i for i, e in enumerate(entries)}
    parents = {e.get("parentUuid") for e in entries if e.get("parentUuid")}
    leaves = []
    for terminal in (e for e in entries if e["uuid"] not in parents):
        cur, seen = terminal, set()
        while cur is not None and cur["uuid"] not in seen:
            seen.add(cur["uuid"])
            if cur.get("type") in ("user", "assistant"):
                leaves.append(cur)
                break
            cur = by_id.get(cur.get("parentUuid") or "")
    main = [e for e in leaves if not e.get("isSidechain") and not e.get("isMeta") and not e.get("teamName")]
    pool = main or leaves
    if not pool:
        return []
    cur = by_id.get(leaf) or max(pool, key=lambda e: order[e["uuid"]])
    out, seen = [], set()
    while cur is not None and cur["uuid"] not in seen:
        seen.add(cur["uuid"])
        out.append(cur)
        cur = by_id.get(cur.get("parentUuid") or "")
    out.reverse()
    return [e for e in out if e.get("type") in ("user", "assistant") and not e.get("isMeta") and not e.get("isSidechain")]


def prompt_text(entry: dict) -> str | None:
    """A user entry's typed text, or None for a tool result or the CLI's own notes."""
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, str):
        texts = [content]
    elif isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return None
        texts = [b.get("text") or "" for b in content if isinstance(b, dict) and b.get("type") == "text"]
    else:
        return None
    text = "\n".join(texts).strip()
    command = _COMMAND_NAME.search(text)
    if command:
        args = _COMMAND_ARGS.search(text)
        return f"{command.group(1)} {args.group(1).strip() if args else ''}".strip()
    if not text or _SKIP_PROMPT.match(text) or entry.get("isCompactSummary"):
        return None
    return text


def transcript(entries: list[dict], keep: int = 300, leaf: str = "") -> tuple[list[dict], int]:
    """Rows for the sidebar's restore: user and assistant text, tool calls as rows."""
    rows = []
    for entry in chain(entries, leaf):
        if entry["type"] == "user":
            text = prompt_text(entry)
            if text is not None:
                rows.append({"role": "user", "text": text})
            continue
        for block in (entry.get("message") or {}).get("content") or []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "text" and (block.get("text") or "").strip():
                rows.append({"role": "assistant", "text": block["text"]})
            elif block.get("type") == "tool_use":
                args = block.get("input") or {}
                rows.append({"role": "tool", "name": tool_name(block.get("name") or ""), "context": tool_context(block.get("name") or "", args), "args": args})
    omitted = max(0, len(rows) - keep)
    return rows[omitted:], omitted


def _head_tail(path: str, size: int = 65536) -> tuple[str, str]:
    with open(path, "rb") as f:
        head = f.read(size).decode("utf-8", "replace")
        f.seek(0, os.SEEK_END)
        end = f.tell()
        f.seek(max(0, end - size))
        tail = f.read().decode("utf-8", "replace")
    return head, tail


def _last_field(text: str, key: str) -> str:
    found = re.findall(r'"%s"\s*:\s*"((?:[^"\\]|\\.)*)"' % re.escape(key), text)
    if not found:
        return ""
    try:
        return json.loads(f'"{found[-1]}"')
    except ValueError:
        return found[-1]


def session_summary(path: str) -> dict | None:
    """One history row from a transcript's head and tail, without parsing it all."""
    try:
        head, tail = _head_tail(path)
        mtime = os.path.getmtime(path)
    except OSError:
        return None
    first = head.split("\n", 1)[0]
    if re.search(r'"isSidechain"\s*:\s*true', first):
        return None
    first_prompt = ""
    for line in head.split("\n"):
        # Cheap filters before parsing; the CLI writes compact JSON, but nothing
        # promises it, so whitespace around the colon is allowed (as the SDK does).
        if not _USER_LINE.search(line) or '"tool_result"' in line or re.search(r'"isMeta"\s*:\s*true', line):
            continue
        try:
            text = prompt_text(json.loads(line))
        except ValueError:
            continue
        if text:
            first_prompt = one_line(text)
            break
    title = (_last_field(tail, "customTitle") or _last_field(head, "customTitle")
             or _last_field(tail, "aiTitle") or _last_field(head, "aiTitle") or first_prompt)
    if not title:
        return None
    started = mtime
    stamp = re.search(r'"timestamp"\s*:\s*"([^"]+)"', head)
    if stamp:
        try:
            from datetime import datetime
            started = datetime.fromisoformat(stamp.group(1).replace("Z", "+00:00")).timestamp()
        except ValueError:
            pass
    return {"id": os.path.basename(path)[:-6], "title": title, "preview": first_prompt,
            "started_at": started, "updated_at": mtime, "source": "claude"}


# ── Backend ──────────────────────────────────────────────────────────────────


class ClaudeBackend:
    def __init__(self, bridge):
        self.bridge = bridge
        self.state = load_state("claude")
        self.binary = ""
        self.proc = None
        self.session_id = ""
        self.init = {}
        self._reader = None
        self._next = 1
        self._pending = {}    # our control request id -> Future
        self._asking = {}     # the CLI's control request id -> Task
        self._streamed = set()  # assistant message ids whose text arrived as deltas
        self._tool_times = {}
        self._interrupting = False
        self._compacting = None
        self._stderr = []
        self._message = None
        self._limits = None     # the last get_usage, as the sidebar's limits
        self._limits_at = 0.0
        self._limits_ask = None # a get_usage in flight, shared by whoever asks meanwhile
        # What Claude Code's own settings pick when the sidebar pins nothing.
        self.cli_defaults = {}

    # ── Lifecycle ──

    async def start(self) -> dict:
        self.binary = shutil.which("claude") or ""
        if not self.binary:
            raise MissingAgent("Claude Code is not installed (no `claude` on PATH)")
        status = await asyncio.to_thread(subprocess.run, [self.binary, "auth", "status"], capture_output=True, text=True, timeout=30)
        try:
            logged_in = bool(json.loads(status.stdout or "{}").get("loggedIn"))
        except ValueError:
            logged_in = status.returncode == 0
        if not logged_in:
            raise BridgeError("Claude Code is signed out. Run `claude` in a terminal and log in, then reopen this tab.")
        return {"retry": True, "undo": True, "clarify": True, "slash": True, "images": True, "models": True,
                "screen": True, "effort": True, "limits": True, "name": "Claude Code"}

    async def stop(self) -> None:
        await self._close_proc()

    def _env(self) -> dict:
        env = dict(os.environ)
        for key in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"):
            env.pop(key, None)
        return env

    def _mode(self) -> str:
        mode = self.state.get("mode") or "smart"
        flag = MODES.get(mode, "default")
        if flag == "auto" and not self._model_entry().get("supportsAutoMode", True):
            flag = "acceptEdits"  # Smart without the auto classifier: edits pass, commands ask
        return flag

    async def _spawn(self, resume: str = "", at: str = "") -> None:
        await self._close_proc()
        servers = {"desktop": dict(type="stdio", **desktop_server())}
        args = [self.binary, "--output-format", "stream-json", "--verbose", "--input-format", "stream-json",
                "--include-partial-messages", "--permission-prompt-tool", "stdio",
                "--permission-mode", self._mode(), "--allow-dangerously-skip-permissions",
                "--setting-sources=user,project,local",
                "--mcp-config", json.dumps({"mcpServers": servers}),
                "--allowedTools", ",".join(f"mcp__desktop__{t}" for t in DESKTOP_READ_ONLY)]
        note = persona()
        if note:
            args += ["--append-system-prompt", note]
        if self.state.get("model"):
            args += ["--model", self.state["model"]]
        if self._effort():
            args += ["--effort", self._effort()]
        if resume:
            args.append(f"--resume={resume}")
            if at:
                args.append(f"--resume-session-at={at}")
        else:
            args.append(f"--session-id={self.session_id}")
        self._stderr = []
        self.proc = await asyncio.create_subprocess_exec(
            *args, cwd=HOME, env=self._env(), stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE, limit=32 * 1024 * 1024)
        self._reader = asyncio.create_task(self._read(self.proc))
        asyncio.create_task(self._read_stderr(self.proc))
        try:
            self.init = await self._control({"subtype": "initialize", "hooks": None}, timeout=90)
        except BridgeError:
            detail = " ".join(self._stderr[-3:]).strip()
            raise BridgeError(f"Claude Code did not start{': ' + detail if detail else ''}")
        try:
            effective = (await self._control({"subtype": "get_settings"})).get("effective") or {}
            self.cli_defaults = {"model": effective.get("model") or "", "effort": effective.get("effortLevel") or ""}
        except BridgeError:
            self.cli_defaults = {}

    async def _close_proc(self) -> None:
        proc, self.proc = self.proc, None
        for future in self._pending.values():
            if not future.done():
                future.set_exception(BridgeError("Claude Code stopped"))
        self._pending = {}
        for task in self._asking.values():
            task.cancel()
        self._asking = {}
        if proc is None or proc.returncode is not None:
            return
        try:
            proc.stdin.close()
            await asyncio.wait_for(proc.wait(), 3)
        except (asyncio.TimeoutError, OSError, ConnectionError):
            proc.terminate()
            try:
                await asyncio.wait_for(proc.wait(), 3)
            except asyncio.TimeoutError:
                proc.kill()

    async def _write(self, frame: dict) -> None:
        if self.proc is None or self.proc.returncode is not None:
            raise BridgeError("Claude Code is not running")
        self.proc.stdin.write((json.dumps(frame, ensure_ascii=False) + "\n").encode())
        await self.proc.stdin.drain()

    async def _control(self, request: dict, timeout: float = 30) -> dict:
        rid = f"req_{self._next}_{uuid.uuid4().hex[:8]}"
        self._next += 1
        future = asyncio.get_running_loop().create_future()
        self._pending[rid] = future
        await self._write({"type": "control_request", "request_id": rid, "request": request})
        try:
            return await asyncio.wait_for(future, timeout)
        except asyncio.TimeoutError:
            raise BridgeError(f"Claude Code did not answer {request.get('subtype')}")
        finally:
            self._pending.pop(rid, None)

    # ── Reading ──

    async def _read_stderr(self, proc) -> None:
        while True:
            line = await proc.stderr.readline()
            if not line:
                return
            text = line.decode("utf-8", "replace").strip()
            if text:
                self._stderr = (self._stderr + [text])[-20:]
                print(f"[claude] {text}", file=sys.stderr, flush=True)

    async def _read(self, proc) -> None:
        run = self.bridge.run
        while True:
            line = await proc.stdout.readline()
            if not line:
                break
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            try:
                self._dispatch(msg)
            except Exception as e:  # a frame we misread must not stop the stream
                print(f"[claude] could not handle {msg.get('type')}: {e}", file=sys.stderr, flush=True)
        await proc.wait()
        if proc is self.proc:
            self.proc = None
            if run.active:
                detail = " ".join(self._stderr[-2:]).strip()
                run.finish(error=f"Claude Code stopped (exit {proc.returncode}){': ' + detail if detail else ''}")

    def _dispatch(self, msg: dict) -> None:
        kind = msg.get("type")
        run = self.bridge.run
        if kind == "control_response":
            response = msg.get("response") or {}
            future = self._pending.get(response.get("request_id"))
            if future and not future.done():
                if response.get("subtype") == "error":
                    future.set_exception(BridgeError(response.get("error") or "Claude Code refused"))
                else:
                    future.set_result(response.get("response") or {})
            return
        if kind == "control_request":
            rid = msg.get("request_id")
            task = asyncio.create_task(self._answer(rid, msg.get("request") or {}))
            self._asking[rid] = task
            task.add_done_callback(lambda _t, rid=rid: self._asking.pop(rid, None))
            return
        if kind == "control_cancel_request":
            task = self._asking.pop(msg.get("request_id"), None)
            if task:
                task.cancel()
            return
        if kind == "system":
            if msg.get("subtype") == "init" and msg.get("session_id"):
                self.session_id = msg["session_id"]
                self.bridge.event("session.info", self.info())
            elif msg.get("subtype") == "compact_boundary" and not self._compacting:
                self.bridge.event("notice", {"message": "Claude Code folded the conversation to make room."})
            return
        if kind == "rate_limit_event":
            self._rate_limit(msg.get("rate_limit_info") or {})
            return
        if self._compacting is not None:
            if kind == "result" and not self._compacting.done():
                self._compacting.set_result(msg)
            return
        if kind == "stream_event":
            if msg.get("parent_tool_use_id"):
                return
            event = msg.get("event") or {}
            etype = event.get("type")
            if etype == "message_start":
                self._message = (event.get("message") or {}).get("id")
            elif etype == "content_block_start":
                block = event.get("content_block") or {}
                if block.get("type") == "thinking":
                    run.status("Thinking…")
                elif block.get("type") == "tool_use":
                    self.bridge.event("tool.generating", {"name": tool_name(block.get("name") or "")})
            elif etype == "content_block_delta":
                delta = event.get("delta") or {}
                if delta.get("type") == "text_delta":
                    self._streamed.add(self._message)
                    run.text(delta.get("text") or "")
            return
        if kind == "assistant":
            message = msg.get("message") or {}
            if msg.get("parent_tool_use_id"):
                for block in message.get("content") or []:
                    if isinstance(block, dict) and block.get("type") == "tool_use":
                        run.status(f"Subagent: {tool_context(block.get('name') or '', block.get('input') or {}) or tool_name(block.get('name') or '')}")
                return
            for block in message.get("content") or []:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "text" and message.get("id") not in self._streamed:
                    run.text(block.get("text") or "")
                elif block.get("type") == "tool_use":
                    name = block.get("name") or ""
                    args = block.get("input") or {}
                    self._tool_times[block.get("id")] = time.monotonic()
                    run.tool_start(block.get("id") or "", tool_name(name), tool_context(name, args), args)
            return
        if kind == "user":
            if msg.get("parent_tool_use_id"):
                return
            content = (msg.get("message") or {}).get("content")
            for block in content if isinstance(content, list) else []:
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    tid = block.get("tool_use_id") or ""
                    text = result_text(block.get("content"))
                    started = self._tool_times.pop(tid, None)
                    run.tool_complete(tid, {"error": text or "failed"} if block.get("is_error") else text,
                                      time.monotonic() - started if started else 0.0)
            return
        if kind == "result":
            interrupted, self._interrupting = self._interrupting, False
            self._streamed.clear()
            if msg.get("is_error") and not interrupted:
                errors = msg.get("errors") or []
                run.finish(error=one_line(msg.get("result") or (errors[0] if errors else "") or "Claude Code reported an error", 400))
            else:
                run.finish("interrupted" if interrupted else "complete")
            asyncio.create_task(self._refresh_limits())
            self.bridge.event("sessions.changed", {})

    async def _answer(self, rid: str, request: dict) -> None:
        """A permission request from the CLI: the approval card, or for
        AskUserQuestion the question card. Cancelled if the CLI stops waiting."""
        if request.get("subtype") != "can_use_tool":
            await self._reply(rid, error=f"unsupported request {request.get('subtype')}")
            return
        name = request.get("tool_name") or ""
        args = request.get("input") or {}
        if name == "AskUserQuestion":
            questions = [{"id": q.get("question") or str(i), "question": (q.get("question") or "").strip(),
                          "choices": [o.get("label") for o in q.get("options") or [] if o.get("label")],
                          "multi": bool(q.get("multiSelect"))} for i, q in enumerate(args.get("questions") or [])]
            answers = await self.bridge.clarify(questions) if questions else {}
            await self._reply(rid, {"behavior": "allow", "updatedInput": dict(args, answers=answers)})
            return
        description, command = approval_text(name, args, request.get("title") or request.get("display_name") or "")
        choice = await self.bridge.approve(description, command)
        if choice == "deny":
            await self._reply(rid, {"behavior": "deny", "message": "The user declined this."})
            return
        answer = {"behavior": "allow", "updatedInput": args}
        if choice in ("session", "always"):
            rules = [dict(s, destination="session") for s in request.get("permission_suggestions") or []]
            if not rules:
                content = args.get("command") if name == "Bash" else None
                rules = [{"type": "addRules", "rules": [{"toolName": name, "ruleContent": content}],
                          "behavior": "allow", "destination": "session"}]
            answer["updatedPermissions"] = rules
        await self._reply(rid, answer)

    async def _reply(self, rid: str, response: dict | None = None, error: str = "") -> None:
        if error:
            body = {"subtype": "error", "request_id": rid, "error": error}
        else:
            body = {"subtype": "success", "request_id": rid, "response": response or {}}
        try:
            await self._write({"type": "control_response", "response": body})
        except BridgeError:
            pass

    # ── Plan limits ──

    async def limits(self, refresh: bool, force: bool = False) -> dict:
        """See bridge.py "Plan limits". `force` is the after-turn ask, never skipped."""
        recent = time.monotonic() - self._limits_at < LIMITS_GAP
        if self._limits is not None and not force and (not refresh or recent):
            return self._limits
        if self.proc is None:
            return self._limits or {"plan": "", "windows": [], "notes": ["Claude Code reports its limits once a chat is open."], "checked_at": 0}
        if self._limits_ask is None or self._limits_ask.done():
            self._limits_ask = asyncio.ensure_future(self._ask_limits())
        return await asyncio.shield(self._limits_ask)

    async def _ask_limits(self) -> dict:
        try:
            body = await self._control({"subtype": "get_usage", "skip_behaviors": True})
        except BridgeError as e:
            if self._limits is not None:
                return self._limits
            raise BridgeError(f"Claude Code did not report its limits: {e}")
        self._limits = claude_limits(body, self.info()["model"])
        self._limits_at = time.monotonic()
        self.bridge.event("usage.limits", self._limits)
        return self._limits

    async def _refresh_limits(self) -> None:
        try:
            await self.limits(True, force=True)
        except BridgeError:
            pass

    def _rate_limit(self, info: dict) -> None:
        """The CLI's rate_limit_event, mid-turn: the 5-hour and weekly windows as the
        API's own headers last put them (0-1 here, 0-100 in get_usage)."""
        if self._limits is None:
            asyncio.create_task(self._refresh_limits())
            return
        changed = False
        for key, value in (info.get("unifiedWindows") or {}).items():
            wid = EVENT_WINDOWS.get(key)
            window = next((w for w in self._limits["windows"] if w["id"] == wid), None)
            if window is None or not isinstance((value or {}).get("utilization"), (int, float)):
                continue
            window["used"] = max(0, min(100, round(value["utilization"] * 100)))
            window["resets_at"] = int(value.get("resetsAt") or window["resets_at"])
            changed = True
        if changed:
            self._limits["checked_at"] = int(time.time())
            self.bridge.event("usage.limits", self._limits)

    # ── Sessions ──

    def _find(self, want: str) -> dict:
        return next((e for e in self.init.get("models") or [] if want and want in (e.get("value"), e.get("resolvedModel"))), {})

    def _model_entry(self) -> dict:
        """The model that actually answers: the sidebar's pin, else the one Claude
        Code's settings name, else its account default."""
        return self._find(self.state.get("model") or "") or self._find(self.cli_defaults.get("model") or "") or self._find("default")

    def _label(self, entry: dict) -> str:
        """A model as the picker and the chip name it. The CLI's "default" entry is
        the sidebar's "no pin", named by what Claude Code's settings resolve to --
        "Default (recommended)" says nothing about what answers."""
        if entry.get("value") == "default":
            configured = self._find(self.cli_defaults.get("model") or "")
            name = configured.get("displayName") if configured and configured.get("value") != "default" else entry.get("description")
            return f"{name or 'Claude'} (default)"
        return entry.get("displayName") or entry.get("value") or ""

    def _effort(self) -> str:
        """The pinned level, if the current model takes it; "" means no pin."""
        level = self.state.get("effort") or ""
        return level if level in (self._model_entry().get("supportedEffortLevels") or []) else ""

    def _efforts(self, entry: dict) -> list[dict]:
        levels = (entry.get("supportedEffortLevels") or []) if entry.get("supportsEffort") else []
        if not levels:
            return []
        own = self.cli_defaults.get("effort") or ""
        default = {"id": "default", "label": "Default",
                   "description": f"Claude Code's own setting: {effort_label(own)}" if own else "Whatever Claude Code picks for this model"}
        return [default] + [{"id": level, "label": effort_label(level), "description": EFFORT_NOTES.get(level, "")} for level in levels]

    def info(self) -> dict:
        entry = self._find(self.state.get("model") or "") or self._find("default")
        return {"model": self._label(entry) or self.state.get("model") or "Claude",
                "provider": "claude", "approval_mode": self.state.get("mode") or "smart", "cwd": HOME,
                "effort": (self._effort() or "default") if self._efforts(self._model_entry()) else ""}

    async def create_session(self) -> dict:
        self.session_id = str(uuid.uuid4())
        await self._spawn()
        return {"session_id": self.session_id, "stored_session_id": self.session_id, "info": self.info()}

    def _rewound_to(self, sid: str) -> str:
        """Where an undo left `sid`, while the CLI has written nothing since.

        `--resume-session-at` only takes effect in the CLI's memory: the transcript
        keeps the dropped turns until the next message branches past them. Until
        then the undo is remembered here, or reopening the chat would bring back
        exactly what was undone."""
        mark = (self.state.get("rewinds") or {}).get(sid)
        path = os.path.join(project_dir(), f"{sid}.jsonl")
        try:
            if mark and os.path.getmtime(path) <= mark["mtime"] + 0.001:
                return mark["at"]
        except OSError:
            pass
        if mark:
            self.state["rewinds"].pop(sid, None)
            save_state("claude", self.state)
        return ""

    async def resume_session(self, sid: str) -> dict:
        path = os.path.join(project_dir(), f"{sid}.jsonl")
        if not os.path.isfile(path):
            raise BridgeError("That conversation is gone")
        self.session_id = sid
        at = self._rewound_to(sid)
        await self._spawn(resume=sid, at=at)
        rows, omitted = transcript(_entries(path), leaf=at)
        return {"session_id": sid, "stored_session_id": sid, "info": self.info(),
                "messages": rows, "messages_omitted": omitted}

    async def close_session(self) -> None:
        await self._close_proc()

    async def list_sessions(self, limit: int) -> list[dict]:
        folder = project_dir()
        try:
            names = [n for n in os.listdir(folder) if n.endswith(".jsonl")]
        except OSError:
            return []
        paths = sorted((os.path.join(folder, n) for n in names), key=lambda p: os.path.getmtime(p), reverse=True)
        rows = []
        for path in paths:
            row = session_summary(path)
            if row:
                rows.append(row)
            if len(rows) >= limit:
                break
        return rows

    async def delete_session(self, sid: str) -> None:
        if not re.fullmatch(r"[0-9a-fA-F-]{36}", sid or ""):
            raise BridgeError("Not a conversation id")
        if sid == self.session_id:
            await self._close_proc()
        path = os.path.join(project_dir(), f"{sid}.jsonl")
        try:
            os.unlink(path)
        except FileNotFoundError:
            raise BridgeError("That conversation is already gone")
        shutil.rmtree(os.path.join(project_dir(), sid), ignore_errors=True)

    # ── Turns ──

    async def submit(self, text: str, images: list[str]) -> str:
        # Mid-reply, the CLI queues the message and answers it as the next turn.
        queued = self.bridge.run.active
        content = [{"type": "text", "text": text}] if text else []
        for path in images:
            media = mimetypes.guess_type(path)[0] or "image/png"
            with open(path, "rb") as f:
                content.append({"type": "image", "source": {"type": "base64", "media_type": media, "data": base64.b64encode(f.read()).decode()}})
        await self._send_turn(content)
        return "queued" if queued else "streaming"

    async def _send_turn(self, content) -> None:
        if self.proc is None or self.proc.returncode is not None:
            # Gone since the last turn (it died, or a resume is pending): pick the
            # same conversation back up rather than starting a blank one.
            exists = os.path.isfile(os.path.join(project_dir(), f"{self.session_id}.jsonl"))
            await self._spawn(resume=self.session_id if exists else "", at=self._rewound_to(self.session_id) if exists else "")
        self._interrupting = False
        self.bridge.run.begin()
        await self._write({"type": "user", "message": {"role": "user", "content": content},
                           "parent_tool_use_id": None, "session_id": self.session_id})

    async def interrupt(self) -> None:
        if self.proc is None:
            return
        self._interrupting = True
        try:
            await self._control({"subtype": "interrupt"}, timeout=10)
        except BridgeError:
            pass

    async def rewind(self, turns: int, resend: bool) -> str:
        """Drop the last `turns` requests and what answered them; with `resend`,
        ask the first of them again (retry). Returns its text, for an edit."""
        path = os.path.join(project_dir(), f"{self.session_id}.jsonl")
        prompts = [e for e in chain(_entries(path), self._rewound_to(self.session_id)) if e["type"] == "user" and prompt_text(e) is not None]
        if len(prompts) < turns:
            raise BridgeError("Nothing that far back to undo")
        target = prompts[-turns]
        text = prompt_text(target) or ""
        content = (target.get("message") or {}).get("content")
        at = target.get("parentUuid") or ""
        if at:
            await self._spawn(resume=self.session_id, at=at)
            self.state.setdefault("rewinds", {})[self.session_id] = {"at": at, "mtime": os.path.getmtime(path)}
            save_state("claude", self.state)
        else:
            # The very first request: there is nothing to resume at, so the
            # conversation starts over rather than keeping a turn it was asked to drop.
            await self._close_proc()
            try:
                os.unlink(path)
            except OSError:
                pass
            self.session_id = str(uuid.uuid4())
            await self._spawn()
            self.bridge.event("session.info", self.info())
        self.bridge.event("sessions.changed", {})
        if resend:
            await self._send_turn(content if content else [{"type": "text", "text": text}])
        return text

    async def compact(self, focus: str) -> str:
        if self.proc is None:
            raise BridgeError("Nothing to fold yet")
        self._compacting = asyncio.get_running_loop().create_future()
        try:
            await self._write({"type": "user", "message": {"role": "user", "content": f"/compact {focus}".strip()},
                               "parent_tool_use_id": None, "session_id": self.session_id})
            result = await asyncio.wait_for(self._compacting, 600)
        finally:
            self._compacting = None
        if result.get("is_error"):
            raise BridgeError(one_line(result.get("result") or "Could not fold this conversation", 300))
        return "Folded this conversation."

    # ── Settings ──

    async def models(self) -> dict:
        entries = self.init.get("models") or []
        def answering(e):  # the "no pin" row answers with the model the settings name
            return (self._find(self.cli_defaults.get("model") or "") or e) if e.get("value") == "default" else e
        return {"providers": [{"slug": "claude", "name": "Claude Code", "models": [self._label(e) for e in entries],
                               "capabilities": {self._label(e): {"reasoning": bool(answering(e).get("supportsEffort")), "efforts": self._efforts(answering(e))} for e in entries}}],
                "model": self.info()["model"], "provider": "claude"}

    async def set_model(self, name: str) -> None:
        entry = next((e for e in self.init.get("models") or [] if name in (self._label(e), e.get("displayName"), e.get("value"))), None)
        value = entry.get("value") if entry else name
        if not value:
            raise BridgeError("Which model?")
        if self.proc is not None:
            await self._control({"subtype": "set_model", "model": None if value == "default" else value})
        self.state["model"] = "" if value == "default" else value
        save_state("claude", self.state)
        # A level the new model does not take falls back to its default (_effort);
        # the CLI has to be told, or it would keep the old model's level.
        if self.proc is not None and self._efforts(self._model_entry()):
            await self._control({"subtype": "apply_flag_settings", "settings": {"effortLevel": self._effort() or None}})

    async def set_effort(self, level: str) -> None:
        entry = self._model_entry()
        allowed = [e["id"] for e in self._efforts(entry)]
        if level not in allowed:
            raise BridgeError(f"{self._label(entry) or 'This model'} has no {effort_label(level).lower()} effort")
        self.state["effort"] = "" if level == "default" else level
        save_state("claude", self.state)
        # apply_flag_settings is the CLI's own live switch (what /effort uses), so
        # the chat carries on with its context instead of restarting.
        if self.proc is not None:
            await self._control({"subtype": "apply_flag_settings", "settings": {"effortLevel": self._effort() or None}})

    async def set_approval_mode(self, mode: str) -> None:
        self.state["mode"] = mode
        save_state("claude", self.state)
        if self.proc is not None:
            await self._control({"subtype": "set_permission_mode", "mode": self._mode()})

    def slash_commands(self) -> list[dict]:
        return [{"text": c.get("name"), "display": f"/{c.get('name')}", "meta": one_line(c.get("description") or "", 120), "kind": "command"}
                for c in self.init.get("commands") or [] if c.get("name")]

    async def slash(self, line: str) -> dict:
        base, _, arg = line.lstrip("/").partition(" ")
        if base == "model":
            if not arg.strip():
                return {"output": f"Model: {self.info()['model']}"}
            await self.set_model(arg.strip())
            self.bridge.event("session.info", self.info())
            return {"output": f"Model: {self.info()['model']}"}
        if base == "compact":
            return {"output": await self.compact(arg.strip())}
        if base == "effort":
            if arg.strip():
                await self.set_effort(arg.strip().lower())
                self.bridge.event("session.info", self.info())
            level = self.info()["effort"]
            return {"output": f"Effort: {effort_label(level) if level else 'not adjustable'}"}
        # Everything else -- the CLI's own commands, skills, custom commands -- is
        # the CLI's to run: it takes them as an ordinary turn.
        return {"send": True}
