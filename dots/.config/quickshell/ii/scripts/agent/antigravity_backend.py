"""Antigravity behind the sidebar: Google's own ACP server, over the Agent Client Protocol.

Google forbids wrapping the `agy` CLI in another app, and ships a separate program
for exactly this instead: the Antigravity ACP server (`agy_acp_server.par`), listed
by Google in the public ACP registry that Zed and other editors install agents
from. Its sign-in is its own -- the browser flow it runs itself, stored under
`~/.gemini/antigravity-acp/` -- and nothing here reads or forwards it. The sidebar
is one more ACP client, like Zed or T3 Code.

The server is not part of `agy`, so it is installed on first use, from the URL the
registry names on dl.google.com, into $XDG_DATA_HOME/quickshell/agent/antigravity-acp/.
A newer registry version is fetched in the background and used from the next start.
`AGENT_ANTIGRAVITY_SERVER` points at a server to use instead (tools/check-agent-bridge.py
runs a fake one through it); one on PATH as `agy_acp_server` is used before downloading.

What the protocol gives, and so what the page offers: streaming text, tool rows,
approvals, Antigravity's own multiple-choice questions, a model and thinking-level
picker, three approval modes, history (listed, replayed on load), images, and the
desktop tools as an MCP server.

The models are the server's to offer, and it offers Claude and GPT-OSS only to
clients on its own allowlist (JetBrains IDEs, Android Studio, Zed, Xcode --
`model_selection.supports_third_party_models`); every other client gets the Gemini
list. The sidebar names itself in `clientInfo` as what it is, so it gets Gemini.
It has no setting for a default model either, so the pickers list exactly what the
server offers, with no "Default" row standing for the first of them. It has no rewind, no fork and no manual compaction,
so retry, undo, edit-and-resend and fold are not offered. Deleting a chat removes
the server's own files for it, as Claude Code's backend removes its transcript.

Approval modes, the server's session modes:
  manual   default    -- asks before edits, commands and web access
  smart    auto_edit  -- file edits go ahead, everything else asks
  off      yolo       -- never asks
"""
import asyncio
import base64
import fcntl
import json
import mimetypes
import os
import platform
import re
import shutil
import sys
import time
import urllib.request
import zipfile

from bridge import (HOME, LIMITS_GAP, BridgeError, MissingAgent, desktop_server, effort_label, first_string, limit_window,
                    load_state, one_line, persona, save_state)

NAME = "Antigravity"
REGISTRY_URL = "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json"
REGISTRY_ID = "antigravity-acp"
DATA_DIR = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share"), "quickshell", "agent", "antigravity-acp")
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "quickshell", "agent", "antigravity-acp")
SERVER_FILE = "agy_acp_server.par"
HARNESS_FILE = "localharness_external"
UPDATE_EVERY = 24 * 3600
# The registry's CDN turns away urllib's default agent.
USER_AGENT = "ii-sidebar/1 (ACP client)"

MODES = {"manual": "default", "smart": "auto_edit", "off": "yolo"}

# The server reads these over its own sign-in; inherited, one would quietly pick
# what answers. The same list T3 Code clears.
DROPPED_ENV = ("GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_APPLICATION_CREDENTIALS", "GOOGLE_CLOUD_PROJECT",
               "GOOGLE_CLOUD_LOCATION", "GOOGLE_CLOUD_QUOTA_PROJECT", "GOOGLE_GENAI_USE_VERTEXAI", "GCLOUD_PROJECT",
               "CLOUDSDK_CORE_PROJECT", "AGY_ACP_ENABLE_OAUTH", "ANTIGRAVITY_HARNESS_PATH", "BROWSER")

# Passed to the desktop tools explicitly: the server starts MCP servers with only
# what a session names, and without these they cannot find the screen or the shell.
DESKTOP_ENV = ("PATH", "HOME", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE",
               "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP", "DBUS_SESSION_BUS_ADDRESS", "YDOTOOL_SOCKET")

AUTH_URL = re.compile(r"Open the following link to authenticate the ACP server: (https://accounts\.google\.com/\S+)")
AUTH_REQUIRED = -32000
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
IMAGE_TYPES = ("image/png", "image/jpeg", "image/webp", "image/bmp")

# Antigravity's argument names are PascalCase (`CommandLine`, `AbsolutePath`); the
# tool row reads the snake_case its other agents use.
ARG_NAMES = {"command_line": "command", "absolute_path": "path", "target_file": "path", "file_path": "path",
             "code_content": "content", "replacement_content": "new_string", "target_content": "old_string",
             "search_path": "path", "search_directory": "path", "directory_path": "path", "working_dir": "cwd"}
KIND_TOOLS = {"read": "view_file", "edit": "write_to_file", "delete": "delete_file", "move": "move_file",
              "search": "grep_search", "fetch": "read_url_content", "execute": "run_command", "think": "think"}
RENAMED_TOOLS = {"start_subagent": "invoke_subagent", "browser_subagent": "browse"}


# ── The server itself ────────────────────────────────────────────────────────


def _version_key(name: str) -> tuple:
    return tuple(int(p) if p.isdigit() else 0 for p in re.split(r"[.-]", name))


def installed_versions() -> list[str]:
    """Complete installs, newest first. A version only counts once its marker is
    written, so a download cut off halfway is never started."""
    try:
        names = os.listdir(DATA_DIR)
    except OSError:
        return []
    done = [n for n in names if os.path.isfile(os.path.join(DATA_DIR, n, ".complete"))]
    return sorted(done, key=_version_key, reverse=True)


def find_server() -> tuple[str, str] | None:
    """(server, harness) to run, or None when nothing is installed yet."""
    override = os.environ.get("AGENT_ANTIGRAVITY_SERVER") or ""
    if override:
        return override, os.path.join(os.path.dirname(os.path.realpath(override)), HARNESS_FILE)
    versions = installed_versions()
    if versions:
        folder = os.path.join(DATA_DIR, versions[0])
        return os.path.join(folder, SERVER_FILE), os.path.join(folder, HARNESS_FILE)
    on_path = shutil.which("agy_acp_server") or shutil.which(SERVER_FILE)
    if on_path:
        return on_path, os.path.join(os.path.dirname(os.path.realpath(on_path)), HARNESS_FILE)
    return None


def _platform_key() -> str:
    machine = platform.machine().lower()
    arch = {"amd64": "x86_64", "x86_64": "x86_64", "aarch64": "aarch64", "arm64": "aarch64"}.get(machine, machine)
    return f"linux-{arch}"


def _open(url: str, timeout: float):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": USER_AGENT}), timeout=timeout)


def registry_entry() -> dict:
    """What the ACP registry says to download: {version, archive, args}."""
    with _open(REGISTRY_URL, 20) as response:
        registry = json.load(response)
    entry = next((a for a in registry.get("agents") or [] if a.get("id") == REGISTRY_ID), None)
    if not entry:
        raise BridgeError("The ACP registry no longer lists Google Antigravity")
    target = ((entry.get("distribution") or {}).get("binary") or {}).get(_platform_key())
    if not target:
        raise BridgeError(f"Google publishes no Antigravity server for {_platform_key()}")
    archive = target.get("archive") or ""
    # Only ever Google's own download host, whatever the registry is changed to.
    if not archive.startswith("https://dl.google.com/"):
        raise BridgeError("The registry points the Antigravity server somewhere other than dl.google.com")
    return {"version": str(entry.get("version") or "0"), "archive": archive, "args": target.get("args") or []}


def install(entry: dict, progress=None) -> str:
    """Download and unpack one registry version; its folder. Blocking: run it in a thread.

    Under a lock: a bridge restarted mid-download (an agent switch, a shell reload)
    waits for the first one's download instead of writing the same file."""
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(os.path.join(DATA_DIR, ".install.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return _install(entry, progress)


def _install(entry: dict, progress) -> str:
    version = re.sub(r"[^0-9A-Za-z.-]", "", entry["version"]) or "0"
    final = os.path.join(DATA_DIR, version)
    if os.path.isfile(os.path.join(final, ".complete")):
        return final
    partial = os.path.join(DATA_DIR, f".partial-{version}")
    archive = os.path.join(DATA_DIR, f".download-{version}.zip")
    shutil.rmtree(partial, ignore_errors=True)
    try:
        with _open(entry["archive"], 60) as response, open(archive, "wb") as out:
            total = int(response.headers.get("Content-Length") or 0)
            done, shown = 0, -1
            while True:
                chunk = response.read(1 << 20)
                if not chunk:
                    break
                out.write(chunk)
                done += len(chunk)
                percent = int(100 * done / total) if total else -1
                if progress and percent != shown:
                    shown = percent
                    progress(done, total)
        os.makedirs(partial)
        with zipfile.ZipFile(archive) as bundle:
            # Exactly the two files the server is made of, written by name: never a
            # path from the archive, so nothing can land outside this folder.
            for name in (SERVER_FILE, HARNESS_FILE):
                with bundle.open(name) as src, open(os.path.join(partial, name), "wb") as dst:
                    shutil.copyfileobj(src, dst, 1 << 20)
                os.chmod(os.path.join(partial, name), 0o755)
        with open(os.path.join(partial, ".complete"), "w", encoding="utf-8") as f:
            json.dump({"version": version, "archive": entry["archive"], "installed": int(time.time())}, f)
        shutil.rmtree(final, ignore_errors=True)
        os.replace(partial, final)
        return final
    finally:
        shutil.rmtree(partial, ignore_errors=True)
        try:
            os.unlink(archive)
        except OSError:
            pass


def prune(keep: str) -> None:
    """Old versions, once a newer one is in use. The running one is never touched."""
    for name in installed_versions():
        if name != keep:
            shutil.rmtree(os.path.join(DATA_DIR, name), ignore_errors=True)


def gemini_home() -> str:
    return os.path.expanduser(os.environ.get("GEMINI_HOME") or os.path.join(HOME, ".gemini"))


def configured_auth() -> str:
    """The sign-in method the server's own settings.json names -- the method, never
    a credential -- so one picked in Zed or elsewhere is kept."""
    try:
        with open(os.path.join(gemini_home(), "antigravity-acp", "settings.json"), encoding="utf-8") as f:
            value = ((json.load(f) or {}).get("auth") or {}).get("type")
        return value if isinstance(value, str) else ""
    except (OSError, ValueError, AttributeError):
        return ""


def conversations_dir() -> str:
    return os.path.join(gemini_home(), "antigravity-acp", "conversations")


# ── Translation ──────────────────────────────────────────────────────────────


def _snake(key: str) -> str:
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", key).lower()


def plain_args(raw) -> dict:
    """A call's arguments under the names the tool row reads."""
    if not isinstance(raw, dict):
        return {}
    args = {}
    for key, value in raw.items():
        if key == "arguments" and isinstance(value, dict):
            continue  # an MCP call's arguments, also given flat beside it
        name = _snake(str(key))
        args[ARG_NAMES.get(name, name)] = value
    return args


def tool_identity(update: dict) -> tuple[str, dict]:
    """(name, args) for a tool_call. ACP sends a title, not the tool's name: the
    server titles a native call "Running view_file" (or "Run view_file?" while it
    waits to be allowed), a command by its command line, an MCP call by its tool."""
    meta = update.get("_meta") if isinstance(update.get("_meta"), dict) else {}
    args = plain_args(update.get("rawInput"))
    mcp = meta.get("mcp") if isinstance(meta.get("mcp"), dict) else None
    if mcp and mcp.get("tool"):
        return str(mcp["tool"]), args
    kind = update.get("kind") or ""
    if kind == "execute":
        if "command" not in args and update.get("title"):
            args["command"] = update["title"]
        return "run_command", args
    title = (update.get("title") or "").strip()
    match = re.fullmatch(r"(?:Running |Run )?([A-Za-z_][\w.-]*)\??", title)
    if match:
        name = match.group(1)
        return RENAMED_TOOLS.get(name, name), args
    return KIND_TOOLS.get(kind, "tool"), args


APPROVAL_KINDS = {"execute": "Run a command", "edit": "Change a file", "delete": "Delete a file", "move": "Move a file",
                  "read": "Read a file", "search": "Search", "fetch": "Open a web page"}


def approval_text(call: dict, name: str) -> str:
    """What an approval card asks. Not the server's title, which for a command is
    the command again (the card shows that verbatim already) and otherwise a bare
    tool name -- "desktop_windows", "Run view_file?"."""
    meta = call.get("_meta") if isinstance(call.get("_meta"), dict) else {}
    mcp = meta.get("mcp") if isinstance(meta.get("mcp"), dict) else None
    if mcp:
        return meta.get("prompt") or f"Use the {mcp.get('server') or 'tool'} tool “{mcp.get('tool') or name}”"
    if name == "search_web":
        return "Search the web"
    return APPROVAL_KINDS.get(call.get("kind") or "") or f"Use {name}"


def tool_context(name: str, args: dict) -> str:
    """The one line a tool row and the status line show for a call."""
    for key in ("command", "path", "url", "query", "pattern", "prompt", "task", "description"):
        if isinstance(args.get(key), str) and args[key].strip():
            return one_line(args[key])
    return first_string(args)


def content_text(blocks) -> str:
    parts = []
    for block in blocks or []:
        if not isinstance(block, dict):
            continue
        inner = block.get("content") if block.get("type") == "content" else block
        if isinstance(inner, dict):
            if inner.get("type") == "text":
                parts.append(inner.get("text") or "")
            elif inner.get("type") == "image":
                parts.append(f"[image] {inner.get('uri') or ''}".strip())
        elif block.get("type") == "diff":
            parts.append(f"{block.get('path') or ''}\n{block.get('newText') or ''}".strip())
    return "\n".join(p for p in parts if p)


def tool_result(update: dict):
    """What a finished call handed back, in the shapes the tool row reads."""
    raw = update.get("rawOutput")
    if update.get("status") == "failed":
        text = raw if isinstance(raw, str) else content_text(update.get("content")) or "Failed"
        return {"error": text}
    if isinstance(raw, dict):
        if "combinedOutput" in raw or "exitCode" in raw:
            # Run in a terminal, so its lines end in \r\n.
            return {"output": (raw.get("combinedOutput") or "").replace("\r\n", "\n"), "exit_code": raw.get("exitCode")}
        if raw.get("imagePath"):
            return f"Saved {raw['imagePath']}"
    text = content_text(update.get("content"))
    if text:
        return text
    if isinstance(raw, str):
        return raw
    return json.dumps(raw, ensure_ascii=False)[:4000] if raw else "Done"


def _block_text(content) -> str:
    if isinstance(content, dict) and content.get("type") == "text":
        return content.get("text") or ""
    return ""


# ── Plan limits ──────────────────────────────────────────────────────────────
#
# The server's own `/usage`, which it answers itself -- "without triggering an LLM
# turn or incurring token cost", its source says -- with a markdown report:
#
#   - **Gemini Models**
#     *(Models within this group: Gemini Flash, Gemini Pro)*
#     - **Five Hour Limit Remaining:** 99% remaining (resets Oct 19, 2026, 22:52 UTC)
#
# T3 Code reads these from Google's API with the login's refresh token; the
# sidebar never touches the login, so it asks the server, and reads the report.

_GROUP = re.compile(r"^- \*\*(.+?)\*\*\s*$")
_GROUP_MODELS = re.compile(r"^\s+\*\(Models within this group: (.+)\)\*\s*$")
_BUCKET = re.compile(r"^\s+- \*\*(.+?):\*\*\s*(.+?)\s*$")
_REMAINING = re.compile(r"(\d+(?:\.\d+)?)% remaining")
_RESETS = re.compile(r"\(resets (.+?)\)")
_WINDOW_NAMES = {"five hour": ("5-hour", 300), "weekly": ("Weekly", 10080), "daily": ("Daily", 1440)}


def _reset_epoch(text: str) -> int:
    import calendar
    for pattern in ("%b %d, %Y, %H:%M UTC", "%b %d, %Y"):
        try:
            return calendar.timegm(time.strptime(text.strip(), pattern))
        except ValueError:
            continue
    return 0


def _words(text: str) -> set:
    return set(re.findall(r"[a-z]+", text.lower()))


def antigravity_limits(report: str, current: str = "", plan: str = "") -> dict:
    """`/usage`'s Quota Limits section as the sidebar's limits. A group counts
    toward the button when one of its models is the one in use."""
    out = {"plan": plan, "windows": [], "notes": [], "checked_at": int(time.time())}
    group, models, limits = "", [], False
    rows = []
    for line in report.splitlines():
        if line.startswith("### "):
            limits = line.strip() == "### Quota Limits"
            continue
        if not limits:
            continue
        match = _GROUP.match(line)
        if match:
            group, models = re.sub(r"\s+models$", "", match.group(1).strip(), flags=re.I), []
            continue
        match = _GROUP_MODELS.match(line)
        if match:
            models = [m.strip() for m in match.group(1).split(",") if m.strip()]
            continue
        match = _BUCKET.match(line)
        if match and group:
            name = re.sub(r"\s*limit remaining$|\s*limit$", "", match.group(1).strip(), flags=re.I)
            label, minutes = _WINDOW_NAMES.get(name.lower(), (name, 0))
            left = _REMAINING.search(match.group(2))
            if not left:
                continue  # "Disabled", or a count the report gives no fraction for
            reset = _RESETS.search(match.group(2))
            rows.append((group, models, label, minutes, 100 - float(left.group(1)), _reset_epoch(reset.group(1)) if reset else 0))
        elif line.startswith("- ") and not line.startswith("- **"):
            out["notes"].append(line[2:].strip())  # "Unable to retrieve quota status (...)"
    groups = list(dict.fromkeys(r[0] for r in rows))
    using = _words(current)
    # Shortest window first within a group, as the other agents report them.
    rows.sort(key=lambda r: (groups.index(r[0]), r[3] or 10 ** 9))
    for group, models, label, minutes, used, resets in rows:
        counts = len(groups) == 1 or any(_words(m) and _words(m) <= using for m in models)
        out["windows"].append(limit_window(f"{group}:{label}", label, used, resets, minutes,
                                           group=group if len(groups) > 1 else "", counts=counts))
    return out


class Replay:
    """A load_session replay folded into the sidebar's restore rows."""

    def __init__(self):
        self.rows = []
        self.tools = {}

    def add(self, update: dict) -> None:
        kind = update.get("sessionUpdate")
        if kind in ("user_message_chunk", "agent_message_chunk"):
            role = "user" if kind == "user_message_chunk" else "assistant"
            text = _block_text(update.get("content"))
            if not text:
                return
            if self.rows and self.rows[-1]["role"] == role:
                self.rows[-1]["text"] += text
            else:
                self.rows.append({"role": role, "text": text})
        elif kind == "tool_call":
            call_id = update.get("toolCallId") or ""
            if call_id.startswith("interaction_") or call_id in self.tools:
                return
            name, args = tool_identity(update)
            row = {"role": "tool", "name": name, "context": tool_context(name, args), "args": args}
            self.tools[call_id] = row
            self.rows.append(row)

    def result(self, keep: int = 300) -> tuple[list[dict], int]:
        rows = [r for r in self.rows if r["role"] == "tool" or r["text"].strip()]
        omitted = max(0, len(rows) - keep)
        return rows[omitted:], omitted


# ── Backend ──────────────────────────────────────────────────────────────────


class AntigravityBackend:
    def __init__(self, bridge):
        self.bridge = bridge
        self.state = load_state("antigravity")
        self.proc = None
        self.server = ("", "")
        self.session_id = ""
        self._next = 1
        self._pending = {}
        self._asking = {}       # server request id -> Task
        self._tools = {}        # toolCallId -> started monotonic
        self._replay = None     # (session id, Replay) while a load is replaying
        self._signed_in = False
        self._auth_lock = None
        self._creating = None   # a session/new in flight (it can wait on a sign-in)
        self._prompting = None  # the session/prompt task in flight
        self._cancelled = False # session/cancel sent for it
        self._queue = []        # messages typed while a reply runs
        self._stderr = []
        self.config = []        # the session's configOptions
        self.commands = []      # available_commands_update
        self.defaults = {}      # what answers with nothing pinned: {model, effort}
        self.tier = ""
        self._probe = None      # while /usage is asked: its reply, kept out of the chat
        self._probe_lock = asyncio.Lock()
        self._limits = None
        self._limits_at = 0.0
        self._limits_ask = None

    # ── Lifecycle ──

    async def start(self) -> dict:
        found = find_server()
        if found is None:
            if not shutil.which("agy"):
                raise MissingAgent("Antigravity is not installed")
            found = await self._first_install()
        self.server = found
        if not os.path.isfile(found[0]):
            raise MissingAgent(f"The Antigravity server is missing ({found[0]})")
        await self._spawn()
        await self._call("initialize", {"protocolVersion": 1,
                                        "clientCapabilities": {"fs": {"readTextFile": False, "writeTextFile": False}, "terminal": False},
                                        "clientInfo": {"name": "ii-sidebar", "title": "ii sidebar", "version": "1"}}, timeout=120)
        asyncio.create_task(self._maybe_update())
        return {"retry": False, "undo": False, "clarify": True,
                "slash": True, "images": True, "models": True, "screen": True, "effort": True, "limits": True, "name": NAME}

    async def _first_install(self) -> tuple[str, str]:
        loop = asyncio.get_running_loop()

        def progress(done, total):
            text = (f"Downloading Google's Antigravity server: {done * 100 // total}% of {total // 1_000_000} MB" if total
                    else f"Downloading Google's Antigravity server: {done // 1_000_000} MB")
            loop.call_soon_threadsafe(self.bridge.event, "status.setup", {"text": text})

        self.bridge.event("status.setup", {"text": "Looking up Google's Antigravity server…"})
        try:
            entry = await asyncio.to_thread(registry_entry)
            folder = await asyncio.to_thread(install, entry, progress)
        except BridgeError:
            raise
        except Exception as e:
            raise BridgeError(f"Could not download Google's Antigravity server: {e}")
        finally:
            self.bridge.event("status.setup", {"text": ""})
        self.state["checked"] = int(time.time())
        save_state("antigravity", self.state)
        return os.path.join(folder, SERVER_FILE), os.path.join(folder, HARNESS_FILE)

    async def _maybe_update(self) -> None:
        """A newer registry version, fetched quietly for the next start."""
        if os.environ.get("AGENT_ANTIGRAVITY_SERVER") or not self.server[0].startswith(DATA_DIR):
            return
        current = os.path.basename(os.path.dirname(self.server[0]))
        if time.time() - (self.state.get("checked") or 0) < UPDATE_EVERY:
            prune(current)
            return
        try:
            entry = await asyncio.to_thread(registry_entry)
            if _version_key(entry["version"]) > _version_key(current):
                await asyncio.to_thread(install, entry)
            else:
                prune(current)
            self.state["checked"] = int(time.time())
            save_state("antigravity", self.state)
        except Exception as e:  # offline, or the registry moved: try again next time
            print(f"[antigravity] update check failed: {e}", file=sys.stderr, flush=True)

    async def _spawn(self) -> None:
        server, harness = self.server
        env = {k: v for k, v in os.environ.items() if k not in DROPPED_ENV}
        os.makedirs(CACHE_DIR, exist_ok=True)
        self._sweep_logs()
        # The server's logs go to TMPDIR, one set per launch; ours, so they can be
        # swept. BROWSER=true keeps it from opening a browser by itself: the sign-in
        # link goes in the chat instead (see _read_stderr).
        env.update(TMPDIR=CACHE_DIR, PYTHONUNBUFFERED="1", BROWSER="true")
        if os.path.isfile(harness):
            env["ANTIGRAVITY_HARNESS_PATH"] = harness
        args = [server, "--uid="] if server.endswith(".par") else [server]
        self.proc = await asyncio.create_subprocess_exec(
            *args, cwd=HOME, env=env, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE, limit=64 * 1024 * 1024)
        asyncio.create_task(self._read(self.proc))
        asyncio.create_task(self._read_stderr(self.proc))

    def _sweep_logs(self) -> None:
        cutoff = time.time() - 3 * 86400
        try:
            for name in os.listdir(CACHE_DIR):
                path = os.path.join(CACHE_DIR, name)
                if name.startswith(SERVER_FILE) and os.path.getmtime(path) < cutoff:
                    os.unlink(path)
        except OSError:
            pass

    async def stop(self) -> None:
        proc, self.proc = self.proc, None
        if proc is None or proc.returncode is not None:
            return
        try:
            proc.stdin.close()
            await asyncio.wait_for(proc.wait(), 5)
        except (asyncio.TimeoutError, OSError, ConnectionError):
            proc.terminate()

    # ── JSON-RPC ──

    async def _send(self, frame: dict) -> None:
        if self.proc is None or self.proc.returncode is not None:
            raise BridgeError("Antigravity is not running")
        frame["jsonrpc"] = "2.0"
        self.proc.stdin.write((json.dumps(frame, ensure_ascii=False) + "\n").encode())
        await self.proc.stdin.drain()

    async def _call(self, method: str, params: dict, timeout: float = 120) -> dict:
        rid = self._next
        self._next += 1
        future = asyncio.get_running_loop().create_future()
        self._pending[rid] = future
        await self._send({"id": rid, "method": method, "params": params})
        try:
            return await asyncio.wait_for(future, timeout)
        except asyncio.TimeoutError:
            raise BridgeError(f"Antigravity did not answer {method}")
        finally:
            self._pending.pop(rid, None)

    async def _read_stderr(self, proc) -> None:
        while True:
            line = await proc.stderr.readline()
            if not line:
                return
            text = line.decode("utf-8", "replace").strip()
            if not text:
                continue
            match = AUTH_URL.search(text)
            if match:
                self._sign_in_prompt(match.group(1))
                continue
            self._stderr = (self._stderr + [text])[-20:]
            # Its C++ layer prints a stack on every exit; only lines that say
            # something reach the shell's log.
            if not text.startswith(("Binary file", "Extension modules", "E1", "W1", "I1", "*** ", "PC:", "@ ")):
                print(f"[antigravity] {text}", file=sys.stderr, flush=True)

    def _sign_in_prompt(self, url: str) -> None:
        self.bridge.event("notice", {"message": (
            "**Sign in to use Antigravity.** Google's agent server needs your Google account once, "
            f"in your browser: [open the sign-in page]({url}). This carries on by itself when you are done; "
            "the link stops working after five minutes.")})
        self.bridge.event("status.setup", {"text": "Waiting for you to sign in to Google…"})

    async def _read(self, proc) -> None:
        # AGENT_DEBUG_LOG=<file> keeps every frame the server sends, for working out
        # what a new server version changed.
        debug = open(os.environ["AGENT_DEBUG_LOG"], "ab") if os.environ.get("AGENT_DEBUG_LOG") else None
        while True:
            line = await proc.stdout.readline()
            if not line:
                break
            if debug:
                debug.write(line)
                debug.flush()
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            try:
                self._dispatch(msg)
            except Exception as e:  # a frame we misread must not stop the stream
                print(f"[antigravity] could not handle {msg.get('method')}: {e}", file=sys.stderr, flush=True)
        await proc.wait()
        for future in self._pending.values():
            if not future.done():
                future.set_exception(BridgeError("Antigravity stopped"))
        if proc is self.proc:
            self.proc = None
            self.bridge.run.finish(error=f"Antigravity stopped (exit {proc.returncode})")
            os._exit(1)  # nothing works without the server; the shell restarts us

    def _dispatch(self, msg: dict) -> None:
        if "id" in msg and "method" not in msg:
            future = self._pending.get(msg["id"])
            if future and not future.done():
                if msg.get("error"):
                    error = msg["error"] or {}
                    future.set_exception(BridgeError(error.get("message") or "Antigravity refused", error.get("code") or -32000))
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
        if method == "session/update":
            self._update(params.get("sessionId") or "", params.get("update") or {})

    def _update(self, sid: str, update: dict) -> None:
        kind = update.get("sessionUpdate") or ""
        if self._replay and sid == self._replay[0]:
            self._replay[1].add(update)
            if kind not in ("available_commands_update", "config_option_update"):
                return
        elif sid != self.session_id:
            return  # a chat we have moved on from
        if self._probe is not None and kind == "agent_message_chunk":
            self._probe.append(_block_text(update.get("content")))
            return
        run = self.bridge.run
        if kind == "agent_message_chunk":
            # After a cancel the server says so in the reply ("The request was
            # cancelled by the client."), glued to the last word; the card already
            # shows the answer was stopped.
            if not self._cancelled:
                run.text(_block_text(update.get("content")))
        elif kind == "agent_thought_chunk":
            if run.active:
                run.status("Thinking…")
        elif kind == "tool_call":
            call_id = update.get("toolCallId") or ""
            if call_id.startswith("interaction_") or call_id in self._tools:
                return  # a question (asked through permissions), or one already shown
            self._tool_started(call_id, update)
            if update.get("status") in ("completed", "failed"):
                self._tool_done(call_id, update)
        elif kind == "tool_call_update":
            call_id = update.get("toolCallId") or ""
            if call_id.startswith("interaction_"):
                return
            if call_id not in self._tools and update.get("title"):
                self._tool_started(call_id, update)
            if update.get("status") in ("completed", "failed") and call_id in self._tools:
                self._tool_done(call_id, update)
        elif kind == "available_commands_update":
            self.commands = [c for c in update.get("availableCommands") or [] if isinstance(c, dict) and c.get("name")]
        elif kind == "config_option_update":
            self.config = update.get("configOptions") or self.config
            self.bridge.event("session.info", self.info())
        elif kind == "session_info_update" and update.get("title"):
            self.bridge.event("session.title", {"title": update["title"]})

    def _tool_started(self, call_id: str, update: dict) -> None:
        self._tools[call_id] = time.monotonic()
        name, args = tool_identity(update)
        self.bridge.run.tool_start(call_id, name, tool_context(name, args), args)

    def _tool_done(self, call_id: str, update: dict) -> None:
        started = self._tools.pop(call_id, None)
        if started is not None:
            self.bridge.run.tool_complete(call_id, tool_result(update), time.monotonic() - started)

    async def _answer(self, rid, method: str, params: dict) -> None:
        """The server asking the user something. Cancelled when the turn is: ACP
        wants every open permission request answered `cancelled` then."""
        try:
            result = await self._decide(method, params)
        except asyncio.CancelledError:
            if method == "session/request_permission":
                await self._send({"id": rid, "result": {"outcome": {"outcome": "cancelled"}}})
            raise
        except BridgeError as e:
            await self._send({"id": rid, "error": {"code": -32601, "message": str(e)}})
            return
        await self._send({"id": rid, "result": result})

    async def _decide(self, method: str, params: dict) -> dict:
        if method != "session/request_permission":
            raise BridgeError(f"{method} is not handled by the sidebar")
        call = params.get("toolCall") or {}
        options = [o for o in params.get("options") or [] if isinstance(o, dict) and o.get("optionId")]
        if (call.get("toolCallId") or "").startswith("interaction_"):
            # Antigravity's own questions come this way: the choices are the options.
            question = (call.get("title") or "").strip() or "Choose one"
            answers = await self.bridge.clarify([{"id": "q", "question": question,
                                                  "choices": [o.get("name") or o["optionId"] for o in options], "custom": False}])
            answer = answers.get("q") or ""
            picked = next((o for o in options if answer in (o.get("name"), o["optionId"])), None)
            return {"outcome": {"outcome": "selected", "optionId": picked["optionId"]}} if picked else {"outcome": {"outcome": "cancelled"}}
        by_kind = {o.get("kind"): o for o in options}
        choices = [c for c, k in (("once", "allow_once"), ("session", "allow_always"), ("deny", "reject_once")) if k in by_kind]
        name, args = tool_identity(call)
        description = approval_text(call, name)
        # The server marks "allow always" risky on commands and web tools: what they
        # read could steer the next call, which would then go ahead unasked.
        if ((by_kind.get("allow_always") or {}).get("_meta") or {}).get("agy.security.warning"):
            description += "\n\nAllowing it for the session is risky here: what it reads could make it run again without asking."
        paths = [loc.get("path") for loc in call.get("locations") or [] if isinstance(loc, dict) and loc.get("path")]
        detail = args.get("command") if name == "run_command" else "\n".join(paths) or tool_context(name, args)
        choice = await self.bridge.approve(description, detail or "", choices or ("once", "deny"))
        option = by_kind.get({"once": "allow_once", "session": "allow_always", "always": "allow_always"}.get(choice, "reject_once"))
        if option is None:
            return {"outcome": {"outcome": "cancelled"}}
        return {"outcome": {"outcome": "selected", "optionId": option["optionId"]}}

    # ── Sign-in ──

    async def _sign_in(self, force: bool = False) -> None:
        """Once per server: the server refreshes a stored login silently, or starts
        Google's browser flow and waits for it (up to five minutes)."""
        if self._signed_in and not force:
            return
        self._auth_lock = self._auth_lock or asyncio.Lock()
        async with self._auth_lock:
            if self._signed_in and not force:
                return
            try:
                result = await self._call("authenticate", {"methodId": configured_auth() or "oauth-personal"}, timeout=330)
            except BridgeError as e:
                self.bridge.event("notice", {"message": "Antigravity is still signed out: the sign-in did not finish. "
                                                        "Send a message to get a new link."})
                raise BridgeError(f"Antigravity is not signed in: {e}")
            finally:
                self.bridge.event("status.setup", {"text": ""})
            self._signed_in = True
            self.tier = (((result.get("_meta") or {}).get("antigravity") or {}).get("tier") or {}).get("name") or self.tier

    async def _with_sign_in(self, method: str, params: dict, timeout: float = 120) -> dict:
        await self._sign_in()
        try:
            return await self._call(method, params, timeout)
        except BridgeError as e:
            if e.code != AUTH_REQUIRED:
                raise
        # Signed out since (an expired login, or /logout): sign in again, once.
        self._signed_in = False
        await self._sign_in(force=True)
        return await self._call(method, params, timeout)

    # ── Sessions ──

    def _session_params(self, **extra) -> dict:
        tools = desktop_server()
        env = [{"name": k, "value": os.environ[k]} for k in DESKTOP_ENV if os.environ.get(k)]
        params = {"cwd": HOME, "mcpServers": [{"name": "desktop", "command": tools["command"], "args": tools["args"], "env": env}]}
        note = persona()
        if note:
            params["_meta"] = {"antigravity": {"systemPrompt": {"append": note}}}
        params.update(extra)
        return params

    def _adopt(self, result: dict) -> None:
        self.config = result.get("configOptions") or self.config
        tier = (((result.get("_meta") or {}).get("antigravity") or {}).get("tier") or {}).get("name")
        self.tier = tier or self.tier

    async def _apply_pins(self, fresh: bool) -> None:
        """The sidebar's model, level and mode onto a session that opened without
        them. A fresh session shows what answers with nothing pinned."""
        if fresh and not self.defaults:
            self.defaults = {"model": self._option_value("model"), "effort": self._option_value("thinking_level")}
        want = self.state.get("model") or self.defaults.get("model") or ""
        if want and want != self._option_value("model") and want in self._values("model"):
            await self._set_option("model", want)
        level = self._effort() or self.defaults.get("effort") or ""
        if level and level != self._option_value("thinking_level") and level in self._values("thinking_level"):
            await self._set_option("thinking_level", level)
        mode = MODES.get(self.state.get("mode") or "smart", "auto_edit")
        if mode != self._option_value("mode"):
            await self._set_option("mode", mode)

    async def create_session(self) -> dict:
        # One at a time: a message sent while the first chat waits on a sign-in
        # joins it instead of opening a second, empty one.
        if self._creating and not self._creating.done():
            return await asyncio.shield(self._creating)
        self._creating = asyncio.ensure_future(self._create_session())
        return await asyncio.shield(self._creating)

    async def _create_session(self) -> dict:
        result = await self._with_sign_in("session/new", self._session_params(), timeout=180)
        self.session_id = result.get("sessionId") or ""
        self._adopt(result)
        await self._apply_pins(fresh=True)
        return {"session_id": self.session_id, "stored_session_id": self.session_id, "info": self.info()}

    async def resume_session(self, sid: str) -> dict:
        if not UUID.fullmatch(sid or ""):
            raise BridgeError("Not a conversation id")
        await self.close_session()
        replay = Replay()
        self._replay = (sid, replay)
        try:
            result = await self._with_sign_in("session/load", self._session_params(sessionId=sid), timeout=180)
        finally:
            self._replay = None
        self.session_id = sid
        self._adopt(result)
        await self._apply_pins(fresh=False)
        rows, omitted = replay.result()
        return {"session_id": sid, "stored_session_id": sid, "info": self.info(), "messages": rows, "messages_omitted": omitted}

    async def close_session(self) -> None:
        if self._prompting and not self._prompting.done():
            await self.interrupt()
        self._queue.clear()
        self.session_id = ""

    def _titles(self) -> dict:
        return self.state.setdefault("titles", {})

    async def list_sessions(self, limit: int) -> list[dict]:
        listed = await self._call("session/list", {"cwd": HOME})
        rows = []
        for session in listed.get("sessions") or []:
            sid = session.get("sessionId") or ""
            if not UUID.fullmatch(sid):
                continue
            try:
                updated = os.path.getmtime(os.path.join(conversations_dir(), f"{sid}.db"))
            except OSError:
                continue
            known = self._titles().get(sid) or {}
            # The server only knows "Session 1a2b3c4d"; the first thing asked is
            # remembered here for chats the sidebar started.
            title = known.get("title") or session.get("title") or "Untitled chat"
            rows.append({"id": sid, "title": title, "preview": known.get("title") or "",
                         "started_at": known.get("started") or int(updated), "updated_at": int(updated), "source": "antigravity"})
        rows.sort(key=lambda r: r["updated_at"], reverse=True)
        return rows[:limit]

    async def delete_session(self, sid: str) -> None:
        if not UUID.fullmatch(sid or ""):
            raise BridgeError("Not a conversation id")
        if sid == self.session_id:
            await self.close_session()
        base = os.path.join(conversations_dir(), sid)
        if not os.path.exists(f"{base}.db"):
            raise BridgeError("That conversation is already gone")
        # The server has no delete; these are its files for the chat and nothing else.
        for suffix in (".db", ".db-wal", ".db-shm", ".db-journal", ".meta"):
            try:
                os.unlink(base + suffix)
            except FileNotFoundError:
                pass
        shutil.rmtree(os.path.join(gemini_home(), "antigravity-acp", "brain", sid), ignore_errors=True)
        if self._titles().pop(sid, None) is not None:
            save_state("antigravity", self.state)

    # ── Turns ──

    def _prompt_blocks(self, text: str, images: list[str]) -> list[dict]:
        blocks = []
        unsupported = []
        for path in images:
            media = mimetypes.guess_type(path)[0] or ""
            if media not in IMAGE_TYPES:
                unsupported.append(path)  # a GIF: named, so the agent can open it itself
                continue
            with open(path, "rb") as f:
                blocks.append({"type": "image", "mimeType": media, "data": base64.b64encode(f.read()).decode()})
        if unsupported:
            text = (text + "\n\n" + "\n".join(f"Attached: {p}" for p in unsupported)).strip()
        if text:
            blocks.insert(0, {"type": "text", "text": text})
        return blocks

    async def submit(self, text: str, images: list[str]) -> str:
        if not self.session_id:
            await self.create_session()
        blocks = self._prompt_blocks(text, images)
        if not blocks:
            raise BridgeError("Nothing to send")
        titles = self._titles()
        if text.strip() and self.session_id not in titles:
            titles[self.session_id] = {"title": one_line(text, 80), "started": int(time.time())}
            save_state("antigravity", self.state)
            self.bridge.event("session.title", {"title": titles[self.session_id]["title"]})
        # One prompt at a time per session: a message typed mid-reply waits for it.
        if self._prompting and not self._prompting.done():
            self._queue.append(blocks)
            return "queued"
        self._prompting = asyncio.create_task(self._prompt_loop(blocks))
        return "streaming"

    async def _prompt_loop(self, blocks: list[dict]) -> None:
        while blocks:
            await self._prompt(blocks)
            blocks = self._queue.pop(0) if self._queue else None
        asyncio.create_task(self._refresh_limits())

    async def _prompt(self, blocks: list[dict]) -> None:
        async with self._probe_lock:
            pass  # a /usage still being asked finishes first, or its reply would take this one's text
        run = self.bridge.run
        sid = self.session_id
        run.begin()
        self._tools.clear()
        self._cancelled = False
        params = {"sessionId": sid, "prompt": blocks}
        try:
            try:
                result = await self._with_sign_in("session/prompt", params, timeout=24 * 3600)
            except BridgeError as e:
                # Signing out (/logout, or a login Google revoked) closes the
                # server's sessions; once signed back in, the chat is reopened.
                if "not found" not in str(e).lower():
                    raise
                self._replay = (sid, Replay())  # the history it replays is shown already
                try:
                    await self._call("session/load", self._session_params(sessionId=sid), timeout=180)
                finally:
                    self._replay = None
                await self._apply_pins(fresh=False)
                result = await self._call("session/prompt", params, timeout=24 * 3600)
        except BridgeError as e:
            run.finish(error=str(e))
            return
        if sid != self.session_id:
            return
        # Calls the server never closed (a cancelled turn) close with it.
        for call_id in list(self._tools):
            self._tool_done(call_id, {"status": "failed", "rawOutput": "Stopped"})
        reason = result.get("stopReason") or "end_turn"
        if reason == "refusal":
            run.finish(error="Antigravity declined to answer that")
        else:
            run.finish("interrupted" if reason == "cancelled" else "complete")
        self.bridge.event("sessions.changed", {})

    async def interrupt(self) -> None:
        self._queue.clear()
        if not self.session_id or not (self._prompting and not self._prompting.done()):
            return
        for task in list(self._asking.values()):
            task.cancel()
        self._cancelled = True
        await self._send({"method": "session/cancel", "params": {"sessionId": self.session_id}})
        try:
            await asyncio.wait_for(asyncio.shield(self._prompting), 15)
        except (asyncio.TimeoutError, BridgeError):
            pass

    async def rewind(self, turns: int, resend: bool) -> str:
        raise BridgeError("Antigravity cannot rewind a conversation")

    async def compact(self, focus: str) -> str:
        raise BridgeError("Antigravity folds long conversations by itself; it has no command for it")

    # ── Plan limits ──

    def _busy(self) -> bool:
        return bool(self._prompting and not self._prompting.done())

    async def limits(self, refresh: bool, force: bool = False) -> dict:
        """See bridge.py "Plan limits". `force` is the after-turn ask, never skipped.

        Asked only between replies: the server takes one prompt per chat at a time,
        and /usage's report would interleave with the answer being written. A
        second, hidden chat would free it, but each chat runs its own ~150 MB
        harness process -- too much for a number that is asked again the moment
        the reply ends (_prompt_loop)."""
        recent = time.monotonic() - self._limits_at < LIMITS_GAP
        if self._limits is not None and not force and (not refresh or recent):
            return self._limits
        if not self.session_id or self._busy():
            return self._limits or {"plan": self.tier, "windows": [], "notes": ["Antigravity reports its limits between replies."], "checked_at": 0}
        if self._limits_ask is None or self._limits_ask.done():
            self._limits_ask = asyncio.ensure_future(self._ask_limits())
        return await asyncio.shield(self._limits_ask)

    async def _ask_limits(self) -> dict:
        async with self._probe_lock:
            if self._busy():
                return self._limits or {"plan": self.tier, "windows": [], "notes": [], "checked_at": 0}
            self._probe = []
            try:
                await self._call("session/prompt", {"sessionId": self.session_id, "prompt": [{"type": "text", "text": "/usage"}]}, timeout=60)
                report = "".join(self._probe)
            except BridgeError as e:
                if self._limits is not None:
                    return self._limits
                raise BridgeError(f"Antigravity did not report its limits: {e}")
            finally:
                self._probe = None
        self._limits = antigravity_limits(report, self.info()["model"], self.tier)
        self._limits_at = time.monotonic()
        self.bridge.event("usage.limits", self._limits)
        return self._limits

    async def _refresh_limits(self) -> None:
        try:
            await self.limits(True, force=True)
        except BridgeError:
            pass

    # ── Settings ──

    def _option(self, option_id: str) -> dict:
        return next((o for o in self.config if isinstance(o, dict) and o.get("id") == option_id), {})

    def _option_value(self, option_id: str) -> str:
        return str(self._option(option_id).get("currentValue") or "")

    def _choices(self, option_id: str) -> list[dict]:
        """A select option's values, groups flattened."""
        out = []
        for entry in self._option(option_id).get("options") or []:
            if isinstance(entry, dict) and "value" in entry:
                out.append(entry)
            elif isinstance(entry, dict):
                out.extend(e for e in entry.get("options") or [] if isinstance(e, dict) and "value" in e)
        return out

    def _values(self, option_id: str) -> list[str]:
        return [str(c["value"]) for c in self._choices(option_id)]

    def _model_label(self, value: str) -> str:
        return next((c.get("name") for c in self._choices("model") if c["value"] == value), "") or value

    def _efforts(self) -> list[dict]:
        """The current model's thinking levels; only that model's are known."""
        own = self.defaults.get("effort") or ""
        return [{"id": str(c["value"]), "label": c.get("name") or effort_label(str(c["value"])),
                 "description": "Antigravity's default" if str(c["value"]) == own else ""}
                for c in self._choices("thinking_level")]

    def _effort(self) -> str:
        """The pinned level, if the current model takes it; "" means no pin."""
        level = self.state.get("effort") or ""
        return level if level in self._values("thinking_level") else ""

    async def _set_option(self, option_id: str, value: str) -> None:
        if not self.session_id:
            return
        result = await self._call("session/set_config_option", {"sessionId": self.session_id, "configId": option_id, "value": value})
        self.config = result.get("configOptions") or self.config

    def info(self) -> dict:
        # What the session is on, read off it: pinned or not, that is what answers.
        model = self._option_value("model") or self.state.get("model") or ""
        return {"model": self._model_label(model) if model else NAME, "provider": "antigravity",
                "approval_mode": self.state.get("mode") or "smart", "cwd": HOME,
                "effort": self._option_value("thinking_level") if self._efforts() else "", "plan": self.tier}

    async def models(self) -> dict:
        current = self._model_label(self._option_value("model"))
        names = [c.get("name") or c["value"] for c in self._choices("model")]
        # Levels are listed for the model in use; another model's show once it is picked.
        caps = {name: {"reasoning": name == current and bool(self._efforts()), "efforts": self._efforts() if name == current else []}
                for name in names}
        return {"providers": [{"slug": "antigravity", "name": NAME, "models": names, "capabilities": caps}],
                "model": self.info()["model"], "provider": "antigravity"}

    async def set_model(self, name: str) -> None:
        if name == "default":  # `/model default`: back to what the server starts on
            self.state["model"] = ""
            value = self.defaults.get("model") or ""
        else:
            value = next((c["value"] for c in self._choices("model") if name in (c.get("name"), c["value"])), "")
            if not value:
                raise BridgeError(f"Antigravity has no model called {name}")
            self.state["model"] = value
        save_state("antigravity", self.state)
        if value and value != self._option_value("model"):
            await self._set_option("model", value)
        # A pinned level the new model lacks falls back to the server's.
        level = self._effort() or self.defaults.get("effort") or ""
        if level and level in self._values("thinking_level") and level != self._option_value("thinking_level"):
            await self._set_option("thinking_level", level)

    async def set_effort(self, level: str) -> None:
        if level != "default" and level not in self._values("thinking_level"):
            raise BridgeError(f"This model has no {effort_label(level).lower()} thinking level")
        self.state["effort"] = "" if level == "default" else level
        save_state("antigravity", self.state)
        target = self._effort() or self.defaults.get("effort") or ""
        if target and target != self._option_value("thinking_level"):
            await self._set_option("thinking_level", target)

    async def set_approval_mode(self, mode: str) -> None:
        self.state["mode"] = mode
        save_state("antigravity", self.state)
        await self._set_option("mode", MODES[mode])

    def slash_commands(self) -> list[dict]:
        own = [{"text": c["name"], "display": f"/{c['name']}", "meta": one_line(c.get("description") or "", 120), "kind": "command"}
               for c in self.commands]
        return own + [{"text": "model", "display": "/model", "meta": "Show or switch the model", "kind": "command"},
                      {"text": "effort", "display": "/effort", "meta": "Show or switch the thinking level", "kind": "command"}]

    async def slash(self, line: str) -> dict:
        base, _, arg = line.lstrip("/").partition(" ")
        if base == "model":
            if arg.strip():
                await self.set_model(arg.strip())
                self.bridge.event("session.info", self.info())
            return {"output": f"Model: {self.info()['model']}"}
        if base == "effort":
            if arg.strip():
                await self.set_effort(arg.strip().lower())
                self.bridge.event("session.info", self.info())
            level = self._option_value("thinking_level")
            return {"output": f"Thinking level: {effort_label(level) if level else 'not adjustable'}"}
        # /plan, /usage, /logout: the server reads them out of an ordinary prompt.
        if base in [c["name"] for c in self.commands]:
            return {"send": True}
        raise BridgeError(f"Antigravity has no /{base}")
