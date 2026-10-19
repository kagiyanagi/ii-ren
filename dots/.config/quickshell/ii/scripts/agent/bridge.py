#!/usr/bin/env python3
"""The left sidebar's agent connector: Claude Code, Codex or Antigravity behind one protocol.

The sidebar (services/AgentService.qml) is only a client, and so is this. The agent
is whichever official program the user has signed in to; this process starts it,
speaks its protocol, and speaks the sidebar's back. Nothing here reads, copies or
forwards a login -- the program keeps its own, which is the only way its plan's
limits apply.

  claude       `claude` in stream-json mode, the subprocess protocol the Agent SDK
               drives (claude_backend.py)
  codex        `codex app-server`, JSON-RPC (codex_backend.py)
  antigravity  Google's Antigravity ACP server over the Agent Client Protocol
               (antigravity_backend.py): Google's program for other apps to drive,
               not the `agy` CLI, which Google does not allow wrapping

Standard library only: the sidebar needs nothing installed beyond the agent itself.

Wire, one JSON object per line:
  shell -> bridge   {"id", "method", "params"}                     a request
  bridge -> shell   {"id", "result"} | {"id", "error"}              its answer
  bridge -> shell   {"method": "event", "params": {"type", "payload"}}
  bridge -> shell   {"id", "method": "approval" | "clarify", "params"}
  shell -> bridge   {"id", "result"}                                its answer

Every request is answered, error or not: the shell holds a callback per id and
has no timeout. Events never carry an id, or the shell would read them as answers.

Usage: bridge.py claude|codex|antigravity
"""
import asyncio
import json
import os
import re
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.expanduser("~")
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "quickshell", "agent")

APPROVAL_MODES = ("manual", "smart", "off")

# Reasoning effort as the picker names it. The ids are the CLIs' own; anything a
# CLI adds later still shows, under its id capitalised.
EFFORT_LABELS = {"none": "None", "minimal": "Minimal", "low": "Low", "medium": "Medium", "high": "High",
                 "xhigh": "Extra high", "max": "Max", "ultra": "Ultra"}


def effort_label(level: str) -> str:
    return EFFORT_LABELS.get(level, level.replace("_", " ").capitalize())


class MissingAgent(Exception):
    """The CLI is not installed: nothing to retry, so the shell stops and says so."""


class BridgeError(Exception):
    """A request that failed in a way worth showing the user verbatim."""

    def __init__(self, message: str, code: int = -32000):
        super().__init__(message)
        self.code = code


# ── Wire ─────────────────────────────────────────────────────────────────────


class Wire:
    """The shell's end: frames out on stdout, its answers to our questions in."""

    def __init__(self, out=None):
        self.out = out or sys.stdout
        self._next = 1
        self._asked = {}  # our request id -> Future

    def _send(self, frame: dict) -> None:
        self.out.write(json.dumps(frame, ensure_ascii=False) + "\n")
        self.out.flush()

    def respond(self, rid, result) -> None:
        self._send({"jsonrpc": "2.0", "id": rid, "result": result if result is not None else {}})

    def fail(self, rid, message: str, code: int = -32000) -> None:
        self._send({"jsonrpc": "2.0", "id": rid, "error": {"code": code, "message": message}})

    def event(self, kind: str, payload: dict | None = None) -> None:
        self._send({"jsonrpc": "2.0", "method": "event", "params": {"type": kind, "payload": payload or {}}})

    def ask(self, method: str, params: dict) -> tuple[str, asyncio.Future]:
        """Put a question to the user. The future settles with the shell's answer."""
        rid = f"br-{self._next}"
        self._next += 1
        future = asyncio.get_running_loop().create_future()
        self._asked[rid] = future
        self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        return rid, future

    def answered(self, frame: dict) -> bool:
        """Settle the question `frame` answers; False when it answers nothing of ours."""
        future = self._asked.pop(frame.get("id"), None)
        if future is None:
            return False
        if not future.done():
            future.set_result(frame.get("result") or {})
        return True

    def settle(self, rid: str, result: dict) -> None:
        """Answer a question without a reply frame (a batch of clarify locks)."""
        future = self._asked.pop(rid, None)
        if future is not None and not future.done():
            future.set_result(result)

    def withdraw(self, rid: str) -> None:
        """The agent stopped waiting: take the card down and forget the question."""
        future = self._asked.pop(rid, None)
        if future is not None and not future.done():
            future.cancel()
        self.event("request.cancel", {"id": rid})


# ── Run ──────────────────────────────────────────────────────────────────────


class Run:
    """One answer, translated into the sidebar's per-model-turn events.

    The sidebar folds a whole answer into one card, but it expects the agent's
    loop in steps: message.start, the text, the tool rows, message.complete -- and
    then the next step, which reopens the same card. A step that ends having
    called tools is mid-run, so it does not notify; only the one that ends in
    plain text does. Neither CLI reports steps that way, so they are inferred
    here: text arriving after a tool call is the start of the next step.

    A tool.complete can only land while a step is open (the shell updates the
    streaming card), so one arriving between steps reopens it first.
    """

    def __init__(self, emit):
        self.emit = emit  # (type, payload) -> None
        self.open = False
        self.used_tools = False
        self.active = False

    def begin(self) -> None:
        self.active = True

    def _open(self) -> None:
        if self.open:
            return
        self.open = True
        self.used_tools = False
        self.active = True
        self.emit("message.start", {})

    def text(self, delta: str) -> None:
        if not delta:
            return
        if self.open and self.used_tools:
            self.emit("message.complete", {"text": ""})
            self.open = False
        self._open()
        self.emit("message.delta", {"text": delta})

    def status(self, text: str) -> None:
        self.emit("status.update", {"text": text})

    def tool_start(self, tool_id: str, name: str, context: str, args: dict) -> None:
        self._open()
        self.used_tools = True
        self.emit("tool.start", {"tool_id": tool_id, "name": name, "context": context, "args": args})

    def tool_complete(self, tool_id: str, result, duration: float = 0.0) -> None:
        self._open()
        self.emit("tool.complete", {"tool_id": tool_id, "result": result, "duration_s": round(duration, 3)})

    def finish(self, status: str = "complete", error: str = "") -> None:
        """The answer is over. `error` fails the card; an interrupted one just ends."""
        if not self.active:
            return
        if error:
            self.open = self.active = False
            self.emit("error", {"message": error})
            return
        if not self.open:
            self._open()
        self.emit("message.complete", {"text": "", "status": status})
        self.open = self.active = False


# ── Shared helpers ───────────────────────────────────────────────────────────


def load_state(backend: str) -> dict:
    """What this agent was last set to (model, approval mode), across restarts."""
    try:
        with open(os.path.join(STATE_DIR, f"{backend}.json"), encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(backend: str, state: dict) -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    path = os.path.join(STATE_DIR, f"{backend}.json")
    with open(path + ".tmp", "w", encoding="utf-8") as f:
        json.dump(state, f)
    os.replace(path + ".tmp", path)


def persona() -> str:
    """The note that tells the agent where it lives. Short on purpose: the CLI
    already brings its own full system prompt, and this rides on top of it."""
    try:
        with open(os.path.join(HERE, "prompt.md"), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def desktop_server() -> dict:
    """How either CLI starts the desktop tools (desktop_mcp.py), as an MCP stdio server."""
    return {"command": sys.executable or "python3", "args": [os.path.join(HERE, "desktop_mcp.py")]}


_FILE_REF = re.compile(r"@(file|folder):(\"[^\"\n]+\"|`[^`\n]+`|'[^'\n]+'|\S+)")


def plain_refs(text: str) -> str:
    """`@file:x` and `@folder:x` chips as the plain paths a model reads.

    The chips stay in the transcript as typed; only what reaches the model is
    rewritten. Neither CLI expands these tokens in a programmatic prompt, so a
    path is what they act on -- both read files with their own tools."""
    def swap(match):
        path = match.group(2).strip("\"'`")
        return f"{path}/" if match.group(1) == "folder" and not path.endswith("/") else path
    return _FILE_REF.sub(swap, text)


def first_string(args: dict) -> str:
    for value in (args or {}).values():
        if isinstance(value, str) and value.strip():
            return value.strip().splitlines()[0][:200]
    return ""


def one_line(text: str, limit: int = 200) -> str:
    text = " ".join((text or "").split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


# ── Plan limits ──────────────────────────────────────────────────────────────
#
# What the sidebar's usage button shows: the plan's own windows (5-hour, weekly),
# as each agent reports them about itself -- Claude Code's `get_usage`, Codex's
# `account/rateLimits/read`, Antigravity's `/usage`. Never read from a login.
#
#   {"plan": "Claude Team", "windows": [window, ...], "notes": [str], "checked_at": epoch s}
#   window: {"id", "group", "label", "used": 0-100, "resets_at": epoch s or 0,
#            "minutes": window length or 0, "counts": whether it limits the model in use}


def window_label(minutes: int) -> str:
    """A window named by its length: 300 -> "5-hour", 10080 -> "Weekly"."""
    if minutes >= 28 * 1440:
        return "Monthly"
    if minutes == 10080:
        return "Weekly"
    if minutes >= 1440 and minutes % 1440 == 0:
        return "Daily" if minutes == 1440 else f"{minutes // 1440}-day"
    if minutes >= 60 and minutes % 60 == 0:
        return f"{minutes // 60}-hour"
    return f"{minutes}-minute" if minutes else "Limit"


def limit_window(wid: str, label: str, used, resets_at=0, minutes: int = 0, group: str = "", counts: bool = True) -> dict:
    try:
        used = max(0, min(100, round(float(used))))
    except (TypeError, ValueError):
        used = 0
    return {"id": wid, "group": group, "label": label, "used": used, "resets_at": int(resets_at or 0),
            "minutes": int(minutes or 0), "counts": bool(counts)}


def epoch(stamp) -> int:
    """An ISO 8601 time (or epoch seconds) as epoch seconds; 0 when unreadable."""
    if isinstance(stamp, (int, float)):
        return int(stamp)
    if not isinstance(stamp, str) or not stamp:
        return 0
    from datetime import datetime
    try:
        return int(datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp())
    except ValueError:
        return 0


# ── Bridge ───────────────────────────────────────────────────────────────────


class Bridge:
    """Routes the shell's requests to the backend, and the backend's news back."""

    def __init__(self, backend_name: str, wire: Wire):
        self.wire = wire
        self.name = backend_name
        if backend_name == "claude":
            from claude_backend import ClaudeBackend as Backend
        elif backend_name == "codex":
            from codex_backend import CodexBackend as Backend
        elif backend_name == "antigravity":
            from antigravity_backend import AntigravityBackend as Backend
        else:
            raise MissingAgent(f"unknown agent '{backend_name}'")
        self.backend = Backend(self)
        self.run = Run(self.wire.event)
        self.staged_images: list[str] = []
        # Unanswered batch clarifies: our request id -> {qid: answer}
        self._batches: dict[str, dict] = {}

    # The backend's side --------------------------------------------------------

    def event(self, kind: str, payload: dict | None = None) -> None:
        self.wire.event(kind, payload)

    async def _wait(self, rid: str, future: asyncio.Future) -> dict:
        """The answer, or -- if the agent stops waiting first (an interrupt, its own
        timeout), which cancels the task asking -- the card taken back down."""
        try:
            return await future
        except asyncio.CancelledError:
            self._batches.pop(rid, None)
            self.wire.withdraw(rid)
            raise

    async def approve(self, description: str, command: str, choices=("once", "session", "deny")) -> str:
        """Ask the user to allow something; the choice they picked."""
        self.event("status.update", {"text": "Waiting for your approval"})
        rid, future = self.wire.ask("approval", {"description": description, "command": command, "choices": list(choices)})
        result = await self._wait(rid, future)
        return str(result.get("choice") or "deny")

    async def clarify(self, questions: list[dict]) -> dict:
        """Ask the user questions: [{id, question, choices, multi, custom}] -> {id: answer}.

        `custom: False` is for an agent that only takes one of its choices
        (Antigravity): the card then offers no typed answer.

        One question is answered by the reply frame; a batch is answered one
        clarify.lock at a time and settles on the last (rpc_clarify_lock)."""
        self.event("status.update", {"text": "Waiting for your answer"})

        def card(q):
            return {"question": q["question"], "choices": q.get("choices") or [], "multi_select": bool(q.get("multi")),
                    "allow_custom": q.get("custom", True) is not False or not q.get("choices")}

        if len(questions) == 1:
            q = questions[0]
            rid, future = self.wire.ask("clarify", card(q))
            result = await self._wait(rid, future)
            return {q["id"]: str(result.get("answer") or "")}
        params = {"questions": [dict(card(q), qid=q["id"]) for q in questions]}
        rid, future = self.wire.ask("clarify", params)
        self._batches[rid] = {"want": [q["id"] for q in questions], "got": {}}
        return await self._wait(rid, future)

    # The shell's side ----------------------------------------------------------

    async def handle(self, frame: dict) -> None:
        rid = frame.get("id")
        method = frame.get("method") or ""
        params = frame.get("params") or {}
        try:
            handler = getattr(self, "rpc_" + method.replace(".", "_"), None)
            if handler is None:
                self.wire.fail(rid, f"{method} is not something this agent can do", -32601)
                return
            result = await handler(params)
            self.wire.respond(rid, result)
        except BridgeError as e:
            self.wire.fail(rid, str(e), e.code)
        except Exception as e:  # one bad request must not take the bridge down
            traceback.print_exc(file=sys.stderr)
            self.wire.fail(rid, f"{type(e).__name__}: {e}")

    async def rpc_session_create(self, params):
        self.staged_images = []
        return await self.backend.create_session()

    async def rpc_session_resume(self, params):
        self.staged_images = []
        return await self.backend.resume_session(str(params.get("session_id") or ""))

    async def rpc_session_list(self, params):
        return {"sessions": await self.backend.list_sessions(int(params.get("limit") or 30))}

    async def rpc_session_delete(self, params):
        await self.backend.delete_session(str(params.get("session_id") or ""))
        return {}

    async def rpc_session_close(self, params):
        await self.backend.close_session()
        return {}

    async def rpc_session_interrupt(self, params):
        await self.backend.interrupt()
        return {}

    async def rpc_session_status(self, params):
        return {"info": self.backend.info()}

    async def rpc_usage_limits(self, params):
        """The plan's limits; `refresh` asks the agent again rather than answering
        from what it last said (each backend still spaces its own asks out)."""
        return await self.backend.limits(bool(params.get("refresh")))

    async def rpc_session_retry(self, params):
        await self.backend.rewind(1, resend=True)
        return {}

    async def rpc_session_undo(self, params):
        text = await self.backend.rewind(max(1, int(params.get("turns") or 1)), resend=False)
        return {"message": text}

    async def rpc_prompt_submit(self, params):
        images, self.staged_images = self.staged_images, []
        text = plain_refs(str(params.get("text") or ""))
        # "streaming", or for a message sent while a reply runs: "queued" (Claude
        # Code takes it as the next turn) or "steered" (Codex adds it to this one).
        return {"status": await self.backend.submit(text, images) or "streaming"}

    async def rpc_model_options(self, params):
        return await self.backend.models()

    async def rpc_model_set(self, params):
        await self.backend.set_model(str(params.get("model") or ""))
        self.event("session.info", self.backend.info())
        return {}

    async def rpc_effort_set(self, params):
        await self.backend.set_effort(str(params.get("effort") or ""))
        self.event("session.info", self.backend.info())
        return {}

    async def rpc_config_set(self, params):
        if params.get("key") != "approvals.mode" or params.get("value") not in APPROVAL_MODES:
            raise BridgeError("That setting is not one this agent has")
        await self.backend.set_approval_mode(params["value"])
        # The shell waits for this echo rather than trusting its own request.
        self.event("session.info", self.backend.info())
        return {}

    async def rpc_complete_slash(self, params):
        typed = str(params.get("text") or "").lstrip("/").lower()
        items = [c for c in self.backend.slash_commands() if c["text"].lower().startswith(typed)]
        return {"items": items[:60]}

    async def rpc_slash_exec(self, params):
        return await self.backend.slash(str(params.get("command") or "").strip())

    async def rpc_image_attach(self, params):
        path = os.path.expanduser(str(params.get("path") or ""))
        if not os.path.isfile(path):
            raise BridgeError("That file is gone")
        if not path.lower().endswith((".png", ".jpg", ".jpeg", ".gif", ".webp")):
            raise BridgeError("Not an image")  # the shell then attaches it as a file
        self.staged_images.append(path)
        return {"path": path}

    async def rpc_image_detach(self, params):
        path = str(params.get("path") or "")
        self.staged_images = [p for p in self.staged_images if p != path]
        return {}

    async def rpc_file_attach(self, params):
        path = os.path.expanduser(str(params.get("path") or ""))
        if not os.path.exists(path):
            raise BridgeError("That file is gone")
        if os.path.isdir(path):
            raise BridgeError("A folder")  # the shell probes it and attaches a folder chip
        quoted = f'"{path}"' if re.search(r"[\s`\"']", path) else path
        return {"ref_text": f"@file:{quoted}"}

    async def rpc_clarify_lock(self, params):
        rid = str(params.get("request_id") or "")
        batch = self._batches.get(rid)
        if batch is None:
            raise BridgeError("That question is no longer open")
        batch["got"][str(params.get("question_id") or "")] = str(params.get("answer") or "")
        remaining = [q for q in batch["want"] if q not in batch["got"]]
        if not remaining:
            self._batches.pop(rid, None)
            self.wire.settle(rid, batch["got"])
        return {"remaining": remaining}


async def _serve(backend_name: str) -> int:
    wire = Wire()
    bridge = Bridge(backend_name, wire)
    # Exit codes the shell reads: 127 not installed, 78 needs the user (signed
    # out) -- neither is fixed by restarting, so neither is restarted.
    try:
        capabilities = await bridge.backend.start()
    except MissingAgent as e:
        print(f"[agent-missing] {e}", file=sys.stderr, flush=True)
        return 127
    except BridgeError as e:
        print(f"[agent-error] {e}", file=sys.stderr, flush=True)
        await bridge.backend.stop()
        return 78
    wire.event("ready", {"backend": backend_name, "capabilities": capabilities})

    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader(limit=16 * 1024 * 1024)
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    tasks = set()
    try:
        while True:
            line = await reader.readline()
            if not line:
                break
            try:
                frame = json.loads(line)
            except ValueError:
                continue
            if not isinstance(frame, dict):
                continue
            # An answer to one of our questions has an id and no method.
            if "method" not in frame:
                wire.answered(frame)
                continue
            task = asyncio.create_task(bridge.handle(frame))
            tasks.add(task)
            task.add_done_callback(tasks.discard)
    finally:
        await bridge.backend.stop()
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    sys.path.insert(0, HERE)
    try:
        return asyncio.run(_serve(sys.argv[1]))
    except MissingAgent as e:
        print(f"[agent-missing] {e}", file=sys.stderr, flush=True)
        return 127
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    # The backends `from bridge import` this module; without the alias that would
    # load a second copy whose BridgeError the handlers here could never catch.
    sys.modules.setdefault("bridge", sys.modules[__name__])
    sys.exit(main())
