"""Codex behind the sidebar: the user's own `codex app-server`, over JSON-RPC.

app-server is how OpenAI's own clients drive Codex, and it signs in with the
user's ChatGPT login by itself -- nothing here touches auth.json. Field names
follow `codex app-server generate-json-schema` (v2); the protocol is marked
experimental, so anything unrecognised is ignored rather than trusted.

The desktop tools are handed over as an MCP server through `-c mcp_servers.*`
overrides, so the user's config.toml is never edited, and live web search is
turned on the same way.

Approval modes:
  manual   untrusted   -- asks before anything not known to be safe
  smart    on-request  -- works in a writable sandbox, asks to step outside it
  off      never       -- full access, never asks
"""
import asyncio
import json
import os
import shutil
import sys
import time

from bridge import (HOME, BridgeError, MissingAgent, desktop_server, effort_label, first_string, limit_window, load_state, one_line,
                    persona, save_state, window_label)

POLICIES = {
    "manual": ("untrusted", {"type": "workspaceWrite", "networkAccess": True}),
    "smart": ("on-request", {"type": "workspaceWrite", "networkAccess": True}),
    "off": ("never", {"type": "dangerFullAccess"}),
}
SANDBOX_MODES = {"workspaceWrite": "workspace-write", "dangerFullAccess": "danger-full-access"}

DECISIONS = {"once": "accept", "session": "acceptForSession", "always": "acceptForSession", "deny": "decline"}


# Codex starts MCP servers with a scrubbed environment, and without these the
# desktop tools cannot find the compositor, the screen or the shell's IPC socket.
DESKTOP_ENV = ("PATH", "HOME", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE",
               "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP", "DBUS_SESSION_BUS_ADDRESS", "YDOTOOL_SOCKET")


LIMITS_EVERY = 30  # seconds an answer stands before the button asks again


def codex_limits(snapshot: dict, credits: dict | None = None) -> dict:
    """A RateLimitSnapshot (`account/rateLimits/read`) as the sidebar's limits.
    `primary`/`secondary` are positions, not lengths: the length is the window's
    own `windowDurationMins`, else what the plan has (T3 Code's reading: paid
    plans a 5-hour and a weekly window, Free and Go one monthly allowance)."""
    plan_type = snapshot.get("planType") or ""
    out = {"plan": f"ChatGPT {plan_type.capitalize()}" if plan_type else "", "windows": [], "notes": [], "checked_at": int(time.time())}
    monthly = plan_type in ("free", "go")
    for wid, fallback in (("primary", 43200 if monthly else 300), ("secondary", 10080)):
        window = snapshot.get(wid) or {}
        if not isinstance(window.get("usedPercent"), (int, float)):
            continue
        minutes = window.get("windowDurationMins") or fallback
        out["windows"].append(limit_window(wid, window_label(minutes), window["usedPercent"], window.get("resetsAt") or 0, minutes))
    if snapshot.get("rateLimitReachedType"):
        out["notes"].append("Limit reached: Codex answers again once the window resets.")
    count = (credits or {}).get("availableCount") or 0
    if count:
        out["notes"].append(f"{count} free limit reset{'s' if count != 1 else ''} available in Codex.")
    return out


def merge_limits(previous: dict | None, update: dict) -> dict | None:
    """`account/rateLimits/updated` is partial: a field it leaves out keeps what was
    seen before. Another limit's snapshot (a model-specific one) is not the plan's."""
    if update.get("limitId") and update["limitId"] != "codex":
        return previous
    return dict(previous or {}, **{k: v for k, v in update.items() if v is not None})


def _toml(value) -> str:
    """A -c override value. JSON strings and arrays of strings are valid TOML; a
    table is written inline."""
    if isinstance(value, dict):
        return "{" + ", ".join(f"{key}={json.dumps(item)}" for key, item in value.items()) + "}"
    return json.dumps(value)


def item_tool(item: dict) -> tuple[str, str, dict] | None:
    """(name, context, args) for an item the sidebar shows as a tool row."""
    kind = item.get("type")
    if kind == "commandExecution":
        command = item.get("command") or ""
        return "command_execution", one_line(command), {"command": command, "cwd": item.get("cwd") or ""}
    if kind == "fileChange":
        changes = item.get("changes") or []
        paths = [c.get("path") or "" for c in changes]
        diff = "\n".join(c.get("diff") or "" for c in changes)
        return "patch", one_line(", ".join(os.path.basename(p) for p in paths)), {"path": paths[0] if len(paths) == 1 else ", ".join(paths), "diff": diff}
    if kind in ("mcpToolCall", "dynamicToolCall"):
        args = item.get("arguments") if isinstance(item.get("arguments"), dict) else {}
        return item.get("tool") or "tool", first_string(args), args
    if kind == "webSearch":
        query = item.get("query") or ""
        return "web_search", one_line(query), {"query": query}
    if kind == "imageView":
        return "view_file", item.get("path") or "", {"path": item.get("path") or ""}
    if kind == "collabAgentToolCall":
        prompt = item.get("prompt") or ""
        return "invoke_subagent", one_line(prompt or item.get("tool") or ""), {"prompt": prompt}
    return None


def item_result(item: dict):
    """What a finished tool item handed back, in the shapes the tool row reads."""
    kind = item.get("type")
    status = item.get("status") or ""
    if kind == "commandExecution":
        if status == "declined":
            return {"error": "Declined"}
        return {"output": item.get("aggregatedOutput") or "", "exit_code": item.get("exitCode")}
    if kind == "fileChange":
        return {"error": f"Not applied ({status})"} if status in ("failed", "declined") else "Applied"
    if kind in ("mcpToolCall", "dynamicToolCall"):
        if item.get("error"):
            error = item["error"]
            return {"error": error.get("message") if isinstance(error, dict) else str(error)}
        result = item.get("result") or {}
        blocks = result.get("content") if isinstance(result, dict) else item.get("contentItems")
        texts = [b.get("text") or "" for b in blocks or [] if isinstance(b, dict) and b.get("type") in ("text", "inputText")]
        return "\n".join(texts) if texts else json.dumps(result, ensure_ascii=False)[:4000]
    if kind == "webSearch":
        return json.dumps(item.get("results") or item.get("action") or {}, ensure_ascii=False, indent=1)[:4000]
    return status or "Done"


def user_text(item: dict) -> str:
    return "\n".join(c.get("text") or "" for c in item.get("content") or [] if isinstance(c, dict) and c.get("type") == "text").strip()


def turn_rows(turns: list[dict], keep: int = 300) -> tuple[list[dict], int]:
    """A stored thread as the sidebar's restore rows."""
    rows = []
    for turn in turns or []:
        for item in turn.get("items") or []:
            kind = item.get("type")
            if kind == "userMessage":
                text = user_text(item)
                if text:
                    rows.append({"role": "user", "text": text})
            elif kind == "agentMessage" and (item.get("text") or "").strip():
                rows.append({"role": "assistant", "text": item["text"]})
            else:
                tool = item_tool(item)
                if tool:
                    rows.append({"role": "tool", "name": tool[0], "context": tool[1], "args": tool[2]})
    omitted = max(0, len(rows) - keep)
    return rows[omitted:], omitted


class CodexBackend:
    def __init__(self, bridge):
        self.bridge = bridge
        self.state = load_state("codex")
        self.proc = None
        self.thread_id = ""
        self.turn_id = ""
        self._next = 1
        self._pending = {}
        self._asking = {}       # server request id -> Task
        self._items = {}        # item id -> (item, started monotonic)
        self._deltas = set()    # agent message ids that streamed
        self._models = []
        self._compacting = None
        self._stderr = []
        self._rate = None       # the plan's RateLimitSnapshot, merged across updates
        self._reset_credits = None
        self._rate_at = 0.0
        # What config.toml picks when the sidebar pins nothing (config/read).
        self.cli_defaults = {}

    # ── Lifecycle ──

    async def start(self) -> dict:
        binary = shutil.which("codex")
        if not binary:
            raise MissingAgent("Codex is not installed (no `codex` on PATH)")
        tools = desktop_server()
        args = [binary, "app-server",
                "-c", f"mcp_servers.desktop.command={_toml(tools['command'])}",
                "-c", f"mcp_servers.desktop.args={_toml(tools['args'])}",
                "-c", f"mcp_servers.desktop.env={_toml({k: os.environ[k] for k in DESKTOP_ENV if os.environ.get(k)})}",
                "-c", 'web_search="live"']
        self.proc = await asyncio.create_subprocess_exec(
            *args, cwd=HOME, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE, limit=32 * 1024 * 1024)
        asyncio.create_task(self._read(self.proc))
        asyncio.create_task(self._read_stderr(self.proc))
        await self._call("initialize", {"clientInfo": {"name": "ii_sidebar", "title": "ii sidebar", "version": "1"},
                                        "capabilities": {"experimentalApi": True}}, timeout=60)
        await self._notify("initialized")
        account = await self._call("account/read", {})
        if account.get("account") is None and account.get("requiresOpenaiAuth", True):
            raise BridgeError("Codex is signed out. Run `codex login` in a terminal, then reopen this tab.")
        await self._read_defaults()
        # No clarify: Codex's request_user_input only exists in its Plan mode, so in
        # the sidebar it asks in plain text and the reply box is the answer.
        return {"retry": True, "undo": True, "clarify": False, "slash": True, "images": True, "models": True,
                "screen": True, "effort": True, "limits": True, "name": "Codex"}

    async def stop(self) -> None:
        proc, self.proc = self.proc, None
        if proc is None or proc.returncode is not None:
            return
        try:
            proc.stdin.close()
            await asyncio.wait_for(proc.wait(), 3)
        except (asyncio.TimeoutError, OSError, ConnectionError):
            proc.terminate()

    async def _send(self, frame: dict) -> None:
        if self.proc is None or self.proc.returncode is not None:
            raise BridgeError("Codex is not running")
        self.proc.stdin.write((json.dumps(frame, ensure_ascii=False) + "\n").encode())
        await self.proc.stdin.drain()

    async def _call(self, method: str, params: dict, timeout: float = 60) -> dict:
        rid = self._next
        self._next += 1
        future = asyncio.get_running_loop().create_future()
        self._pending[rid] = future
        await self._send({"id": rid, "method": method, "params": params})
        try:
            return await asyncio.wait_for(future, timeout)
        except asyncio.TimeoutError:
            raise BridgeError(f"Codex did not answer {method}")
        finally:
            self._pending.pop(rid, None)

    async def _notify(self, method: str, params: dict | None = None) -> None:
        frame = {"method": method}
        if params is not None:
            frame["params"] = params
        await self._send(frame)

    async def _read_stderr(self, proc) -> None:
        while True:
            line = await proc.stderr.readline()
            if not line:
                return
            text = line.decode("utf-8", "replace").strip()
            if text:
                self._stderr = (self._stderr + [text])[-20:]
                print(f"[codex] {text}", file=sys.stderr, flush=True)

    async def _read(self, proc) -> None:
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
                print(f"[codex] could not handle {msg.get('method')}: {e}", file=sys.stderr, flush=True)
        await proc.wait()
        for future in self._pending.values():
            if not future.done():
                future.set_exception(BridgeError("Codex stopped"))
        if proc is self.proc:
            self.proc = None
            self.bridge.run.finish(error=f"Codex stopped (exit {proc.returncode})")
            # Nothing works without app-server; exiting lets the shell restart us.
            os._exit(1)

    def _dispatch(self, msg: dict) -> None:
        if "id" in msg and "method" not in msg:
            future = self._pending.get(msg["id"])
            if future and not future.done():
                if msg.get("error"):
                    future.set_exception(BridgeError((msg["error"] or {}).get("message") or "Codex refused"))
                else:
                    future.set_result(msg.get("result") or {})
            return
        method = msg.get("method") or ""
        params = msg.get("params") or {}
        if "id" in msg:
            task = asyncio.create_task(self._answer(msg["id"], method, params))
            self._asking[msg["id"]] = task
            task.add_done_callback(lambda _t, rid=msg["id"]: self._asking.pop(rid, None))
            return
        if params.get("threadId") and self.thread_id and params["threadId"] != self.thread_id:
            return  # another thread's news (a subagent's, or a closed chat's)
        self._notification(method, params)

    def _notification(self, method: str, params: dict) -> None:
        run = self.bridge.run
        if method == "turn/started":
            self.turn_id = (params.get("turn") or {}).get("id") or self.turn_id
            run.begin()
        elif method == "item/started":
            item = params.get("item") or {}
            self._items[item.get("id")] = (item, time.monotonic())
            kind = item.get("type")
            if kind == "reasoning":
                run.status("Thinking…")
            elif kind == "contextCompaction":
                run.status("Folding the conversation…")
            else:
                tool = item_tool(item)
                if tool:
                    run.tool_start(item.get("id") or "", *tool)
        elif method == "item/agentMessage/delta":
            self._deltas.add(params.get("itemId"))
            run.text(params.get("delta") or "")
        elif method == "item/completed":
            item = params.get("item") or {}
            started = self._items.pop(item.get("id"), (None, None))[1]
            if item.get("type") == "agentMessage":
                if item.get("id") not in self._deltas:
                    run.text(item.get("text") or "")
            elif item.get("type") == "contextCompaction":
                if self._compacting and not self._compacting.done():
                    self._compacting.set_result(True)
            elif item_tool(item):
                duration = (item.get("durationMs") or 0) / 1000 or (time.monotonic() - started if started else 0.0)
                run.tool_complete(item.get("id") or "", item_result(item), duration)
        elif method == "turn/completed":
            turn = params.get("turn") or {}
            self.turn_id = ""
            self._deltas.clear()
            status = turn.get("status")
            if status == "failed":
                run.finish(error=((turn.get("error") or {}).get("message")) or "Codex could not finish that")
            else:
                run.finish("interrupted" if status == "interrupted" else "complete")
            self.bridge.event("sessions.changed", {})
        elif method == "thread/name/updated":
            self.bridge.event("session.title", {"title": params.get("threadName") or ""})
            self.bridge.event("sessions.changed", {})
        elif method == "thread/compacted":
            if self._compacting and not self._compacting.done():
                self._compacting.set_result(True)
        elif method == "account/rateLimits/updated":
            self._rate = merge_limits(self._rate, params.get("rateLimits") or {})
            if self._rate:
                self.bridge.event("usage.limits", codex_limits(self._rate, self._reset_credits))
        elif method == "serverRequest/resolved":
            task = self._asking.pop(params.get("requestId"), None)
            if task:
                task.cancel()
        elif method == "error":
            error = params.get("error") or {}
            if params.get("willRetry"):
                run.status(f"Retrying: {one_line(error.get('message') or '', 80)}")

    async def _answer(self, rid, method: str, params: dict) -> None:
        """Codex asking the user something; cancelled if it stops waiting."""
        try:
            result = await self._decide(method, params)
        except BridgeError as e:
            await self._send({"id": rid, "error": {"code": -32601, "message": str(e)}})
            return
        await self._send({"id": rid, "result": result})

    async def _decide(self, method: str, params: dict) -> dict:
        if method == "item/commandExecution/requestApproval":
            command = params.get("command") or ""
            choice = await self.bridge.approve(params.get("reason") or "Run a command", command if isinstance(command, str) else " ".join(command))
            return {"decision": DECISIONS.get(choice, "decline")}
        if method == "item/fileChange/requestApproval":
            item = self._items.get(params.get("itemId"), ({}, None))[0]
            paths = [c.get("path") or "" for c in item.get("changes") or []]
            choice = await self.bridge.approve(params.get("reason") or "Change files", "\n".join(paths))
            return {"decision": DECISIONS.get(choice, "decline")}
        if method == "item/permissions/requestApproval":
            choice = await self.bridge.approve(params.get("reason") or "Allow more access", json.dumps(params.get("permissions") or {}, indent=1))
            if choice == "deny":
                return {"permissions": {}}
            return {"permissions": params.get("permissions") or {}, "scope": "session" if choice == "session" else "turn"}
        if method == "mcpServer/elicitation/request":
            message = params.get("message") or f"{params.get('serverName') or 'A tool'} wants to go ahead"
            choice = await self.bridge.approve(message, params.get("serverName") or "")
            return {"action": "decline"} if choice == "deny" else {"action": "accept", "content": {}}
        if method == "item/tool/requestUserInput":
            questions = [{"id": q.get("id") or str(i),
                          "question": f"{q.get('header')}: {q.get('question')}" if q.get("header") and q.get("header") not in (q.get("question") or "") else (q.get("question") or ""),
                          "choices": [o.get("label") for o in q.get("options") or [] if isinstance(o, dict) and o.get("label")]}
                         for i, q in enumerate(params.get("questions") or [])]
            answers = await self.bridge.clarify(questions) if questions else {}
            return {"answers": {qid: {"answers": [a for a in (answer.split(", ") if answer else [])]} for qid, answer in answers.items()}}
        if method == "currentTime/read":
            return {"currentTimeAt": int(time.time())}
        raise BridgeError(f"{method} is not handled by the sidebar")

    # ── Sessions ──

    def _policy(self) -> tuple[str, dict]:
        return POLICIES.get(self.state.get("mode") or "smart", POLICIES["smart"])

    # "Default" in either picker is no pin at all: no model or effort is sent, so
    # config.toml decides, exactly as in a terminal. Its label says what that is.

    def _find(self, want: str) -> dict:
        return next((m for m in self._models if want and want in (m.get("model"), m.get("id"))), {})

    def _configured(self) -> dict:
        """The model config.toml names, else Codex's own default."""
        return self._find(self.cli_defaults.get("model") or "") or next((m for m in self._models if m.get("isDefault")), {})

    def _model_entry(self) -> dict:
        """The model that actually answers: the sidebar's pin, else config.toml's."""
        return self._find(self.state.get("model") or "") or self._configured()

    def _default_label(self) -> str:
        entry = self._configured()
        return f"{entry.get('displayName') or entry.get('model') or self.cli_defaults.get('model') or 'Codex'} (default)"

    def _efforts(self, entry: dict) -> list[dict]:
        levels, notes = [], {}
        for option in entry.get("supportedReasoningEfforts") or []:
            level = option.get("reasoningEffort") if isinstance(option, dict) else option
            if level:
                levels.append(level)
                notes[level] = (option.get("description") if isinstance(option, dict) else "") or ""
        if not levels:
            return []
        own = self._own_effort(entry)
        source = "Codex's own setting" if own == self.cli_defaults.get("effort") else "This model's default"
        return [{"id": "default", "label": "Default", "description": f"{source}: {effort_label(own)}" if own else "Codex's own setting"}] + \
            [{"id": level, "label": effort_label(level), "description": notes[level]} for level in levels]

    def _own_effort(self, entry: dict) -> str:
        """What Codex uses with nothing pinned: config.toml's level if this model
        takes it, else the model's default."""
        levels = [o.get("reasoningEffort") if isinstance(o, dict) else o for o in entry.get("supportedReasoningEfforts") or []]
        own = self.cli_defaults.get("effort") or ""
        return own if own in levels else (entry.get("defaultReasoningEffort") or "")

    def _effort(self) -> str:
        """The pinned level, if this model takes it; "" means no pin."""
        level = self.state.get("effort") or ""
        return level if level in [e["id"] for e in self._efforts(self._model_entry()) if e["id"] != "default"] else ""

    def _model_name(self) -> str:
        if not self.state.get("model"):
            return self._default_label()
        entry = self._model_entry()
        return entry.get("displayName") or entry.get("model") or self.state["model"]

    def info(self) -> dict:
        return {"model": self._model_name(), "provider": "codex",
                "approval_mode": self.state.get("mode") or "smart", "cwd": HOME,
                "effort": (self._effort() or "default") if self._efforts(self._model_entry()) else ""}

    def _thread_params(self) -> dict:
        approval, sandbox = self._policy()
        params = {"cwd": HOME, "approvalPolicy": approval, "sandbox": SANDBOX_MODES[sandbox["type"]]}
        note = persona()
        if note:
            params["developerInstructions"] = note
        if self.state.get("model"):
            params["model"] = self.state["model"]
        return params

    async def _read_defaults(self) -> None:
        """config.toml's model and effort, read per chat so an edit there applies to
        the next one, as it would in a terminal."""
        try:
            config = (await self._call("config/read", {})).get("config") or {}
            self.cli_defaults = {"model": config.get("model") or "", "effort": config.get("model_reasoning_effort") or ""}
        except BridgeError:
            self.cli_defaults = {}

    async def _load_models(self) -> None:
        if self._models:
            return
        try:
            listed = await self._call("model/list", {})
            self._models = [m for m in listed.get("data") or [] if not m.get("hidden")]
        except BridgeError:
            self._models = []

    async def create_session(self) -> dict:
        await self._read_defaults()
        await self._load_models()
        result = await self._call("thread/start", self._thread_params())
        self.thread_id = (result.get("thread") or {}).get("id") or ""
        return {"session_id": self.thread_id, "stored_session_id": self.thread_id, "info": self.info()}

    async def resume_session(self, sid: str) -> dict:
        await self._load_models()
        params = dict(self._thread_params(), threadId=sid)
        await self._call("thread/resume", params)
        self.thread_id = sid
        read = await self._call("thread/read", {"threadId": sid, "includeTurns": True})
        rows, omitted = turn_rows((read.get("thread") or {}).get("turns") or [])
        return {"session_id": sid, "stored_session_id": sid, "info": self.info(), "messages": rows, "messages_omitted": omitted}

    async def close_session(self) -> None:
        if self.turn_id:
            await self.interrupt()
        self.thread_id = ""

    async def list_sessions(self, limit: int) -> list[dict]:
        listed = await self._call("thread/list", {"limit": limit, "sortKey": "updated_at", "cwd": HOME})
        rows, seen = [], set()
        for thread in listed.get("data") or []:
            # The list can name one thread more than once (seen live after a
            # revert); the history sheet keys rows on the id, so each goes once.
            if thread.get("parentThreadId") or thread.get("id") in seen:
                continue  # a subagent's thread, not a conversation -- or a repeat
            seen.add(thread.get("id"))
            rows.append({"id": thread.get("id"), "title": thread.get("name") or one_line(thread.get("preview") or ""),
                         "preview": thread.get("preview") or "", "started_at": thread.get("createdAt") or 0,
                         "updated_at": thread.get("updatedAt") or 0, "source": "codex"})
        return rows

    async def delete_session(self, sid: str) -> None:
        if sid == self.thread_id:
            await self.close_session()
        await self._call("thread/delete", {"threadId": sid})

    # ── Turns ──

    async def submit(self, text: str, images: list[str]) -> str:
        if not self.thread_id:
            await self.create_session()
        items = [{"type": "text", "text": text, "text_elements": []}] + [{"type": "localImage", "path": p} for p in images]
        # A second turn/start mid-reply is refused; steering hands the message to the
        # turn already running, which is what typing into a live answer means.
        if self.turn_id:
            try:
                await self._call("turn/steer", {"threadId": self.thread_id, "expectedTurnId": self.turn_id, "input": items})
                return "steered"
            except BridgeError:
                pass  # it ended in between: start a turn of its own
        await self._start_turn(items)
        return "streaming"

    async def _start_turn(self, items: list[dict]) -> None:
        approval, sandbox = self._policy()
        params = {"threadId": self.thread_id, "input": items, "approvalPolicy": approval, "sandboxPolicy": sandbox}
        if self.state.get("model"):
            params["model"] = self.state["model"]
        if self._effort():
            params["effort"] = self._effort()
        self.bridge.run.begin()
        result = await self._call("turn/start", params)
        self.turn_id = (result.get("turn") or {}).get("id") or self.turn_id

    async def interrupt(self) -> None:
        if not (self.thread_id and self.turn_id):
            return
        try:
            await self._call("turn/interrupt", {"threadId": self.thread_id, "turnId": self.turn_id}, timeout=15)
        except BridgeError:
            pass

    async def rewind(self, turns: int, resend: bool) -> str:
        """Drop the last `turns` requests (thread/revert keeps the history before
        one turn); with `resend`, ask the first of them again. Returns its text.
        Like Codex's own revert this rewinds the conversation, not files on disk."""
        read = await self._call("thread/read", {"threadId": self.thread_id, "includeTurns": True})
        asked = []
        for turn in (read.get("thread") or {}).get("turns") or []:
            user = next((i for i in turn.get("items") or [] if i.get("type") == "userMessage"), None)
            if user:
                asked.append((turn.get("id"), user))
        if len(asked) < turns:
            raise BridgeError("Nothing that far back to undo")
        turn_id, user = asked[-turns]
        await self._call("thread/revert", {"threadId": self.thread_id, "beforeTurnId": turn_id})
        self.bridge.event("sessions.changed", {})
        if resend:
            await self._start_turn(user.get("content") or [{"type": "text", "text": user_text(user), "text_elements": []}])
        return user_text(user)

    async def compact(self, focus: str) -> str:
        if not self.thread_id:
            raise BridgeError("Nothing to fold yet")
        self._compacting = asyncio.get_running_loop().create_future()
        try:
            await self._call("thread/compact/start", {"threadId": self.thread_id})
            await asyncio.wait_for(self._compacting, 600)
        finally:
            self._compacting = None
        return "Folded this conversation."

    async def limits(self, refresh: bool) -> dict:
        if self._rate is None or (refresh and time.monotonic() - self._rate_at > LIMITS_EVERY):
            try:
                read = await self._call("account/rateLimits/read", None, timeout=30)
            except BridgeError as e:
                if self._rate is None:
                    raise BridgeError(f"Codex did not report its limits: {e}")
            else:
                by_id = read.get("rateLimitsByLimitId") or {}
                self._rate = by_id.get("codex") or read.get("rateLimits") or {}
                self._reset_credits = read.get("rateLimitResetCredits")
                self._rate_at = time.monotonic()
        return codex_limits(self._rate or {}, self._reset_credits)

    # ── Settings ──

    async def models(self) -> dict:
        await self._load_models()
        configured = self._configured()
        names = [self._default_label()] + [m.get("displayName") or m.get("model") for m in self._models]
        caps = {(m.get("displayName") or m.get("model")): {"reasoning": bool(m.get("supportedReasoningEfforts")), "efforts": self._efforts(m)} for m in self._models}
        caps[self._default_label()] = {"reasoning": bool(configured.get("supportedReasoningEfforts")), "efforts": self._efforts(configured)}
        return {"providers": [{"slug": "codex", "name": "Codex", "models": names, "capabilities": caps}],
                "model": self._model_name(), "provider": "codex"}

    async def set_model(self, name: str) -> None:
        await self._load_models()
        if name in (self._default_label(), "default"):
            self.state["model"] = ""  # back to config.toml's
        else:
            entry = next((m for m in self._models if name in (m.get("displayName"), m.get("model"), m.get("id"))), None)
            if entry is None:
                raise BridgeError(f"Codex has no model called {name}")
            self.state["model"] = entry.get("model") or entry.get("id")
        save_state("codex", self.state)
        if self.thread_id:
            # The effort goes along: a pin the new model lacks falls back to Default.
            entry = self._model_entry()
            update = {"threadId": self.thread_id, "model": entry.get("model") or self.cli_defaults.get("model")}
            effort = self._effort() or self._own_effort(entry)
            if effort:
                update["effort"] = effort
            await self._call("thread/settings/update", update)

    async def set_effort(self, level: str) -> None:
        await self._load_models()
        entry = self._model_entry()
        if level not in [e["id"] for e in self._efforts(entry)]:
            raise BridgeError(f"{self._model_name()} has no {effort_label(level).lower()} effort")
        self.state["effort"] = "" if level == "default" else level
        save_state("codex", self.state)
        if self.thread_id:
            # A live thread keeps its level until told, so Default is sent as what
            # it resolves to rather than as nothing.
            await self._call("thread/settings/update", {"threadId": self.thread_id, "effort": self._effort() or self._own_effort(entry)})

    async def set_approval_mode(self, mode: str) -> None:
        self.state["mode"] = mode
        save_state("codex", self.state)
        if self.thread_id:
            approval, sandbox = self._policy()
            await self._call("thread/settings/update", {"threadId": self.thread_id, "approvalPolicy": approval, "sandboxPolicy": sandbox})

    def slash_commands(self) -> list[dict]:
        return [{"text": "compact", "display": "/compact", "meta": "Fold the conversation to free up context", "kind": "command"},
                {"text": "model", "display": "/model", "meta": "Show or switch the model", "kind": "command"},
                {"text": "effort", "display": "/effort", "meta": "Show or switch the reasoning effort", "kind": "command"}]

    async def slash(self, line: str) -> dict:
        base, _, arg = line.lstrip("/").partition(" ")
        if base == "model":
            if arg.strip():
                await self.set_model(arg.strip())
                self.bridge.event("session.info", self.info())
            return {"output": f"Model: {self._model_name()}"}
        if base == "compact":
            return {"output": await self.compact(arg.strip())}
        if base == "effort":
            if arg.strip():
                await self.set_effort(arg.strip().lower())
                self.bridge.event("session.info", self.info())
            entry = self._model_entry()
            level = self._effort() or self._own_effort(entry)
            return {"output": f"Effort: {effort_label(level) if level else 'not adjustable'}{'' if self._effort() else ' (default)'}"}
        raise BridgeError(f"Codex has no /{base} here")
