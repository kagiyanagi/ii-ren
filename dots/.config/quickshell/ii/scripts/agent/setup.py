#!/usr/bin/env python3
"""What Settings > Agent runs: each agent's own program, for its status, sign-in and install.

The settings app is a process of its own, and each of these is a one-shot job it
watches: JSON objects on stdout, one per line, then exit. Like the bridge, nothing
here reads, copies or forwards a login. Signing in and out are the programs' own
commands -- `claude auth login`, `codex login`, the Antigravity server's ACP
`authenticate` and `logout` -- and this only catches the link each would open in a
browser, so the page can open it once and offer it to copy. That is how T3 Code
drives them too: `$BROWSER` set to a helper that hands the link back, the program
finishing on its own localhost callback.

  status  <agent> [--bin PATH]   {"installed", "path", "version", "signed_in", "account", "plan", ...}
  login   <agent> [--bin PATH]   {"url"} once the link is known, then {"done"} or {"error"}
  logout  <agent> [--bin PATH]   {"done"} or {"error"}
  install antigravity            {"progress": [bytes, total]} as it goes, then {"done": version}
  remove  antigravity            {"done"}
  latest  antigravity            {"version"}: what the ACP registry offers now

`--bin` is the program the user pointed Settings at; without it, the one the sidebar
would find. For Antigravity it is Google's ACP server, not the `agy` CLI.

Killed (the page closed, Cancel), it stops the program it started: a sign-in left
waiting would hold Codex's callback port, and a download would keep writing.

Standard library only, like the bridge.
"""
import json
import os
import queue
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bridge  # noqa: E402

# The backends `from bridge import`; one module, or two copies of BridgeError.
sys.modules.setdefault("bridge", bridge)
import antigravity_backend as ab  # noqa: E402
from claude_backend import PLANS as CLAUDE_PLANS  # noqa: E402

LOGIN_TIMEOUT = 600  # the providers' own links expire well before this
VERSION = re.compile(r"\d+(?:\.\d+)+")
LINK = re.compile(r"https://\S+")
ANTIGRAVITY_METHODS = {"oauth-personal": "Google account", "oauth-business": "Gemini Enterprise",
                       "gemini-api-key": "Gemini API key", "agent-platform": "Agent Platform"}

_children: list[subprocess.Popen] = []


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def _stop_children() -> None:
    for proc in _children:
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(3)
            except (OSError, subprocess.TimeoutExpired):
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except OSError:
                    pass


def spawn(args: list[str], env: dict | None = None, stdin=subprocess.DEVNULL, stderr=subprocess.STDOUT) -> subprocess.Popen:
    """A program in its own process group, so stopping it takes whatever it started."""
    proc = subprocess.Popen(args, cwd=bridge.HOME, env=env, stdin=stdin, stdout=subprocess.PIPE, stderr=stderr,
                            text=True, start_new_session=True)
    _children.append(proc)
    return proc


def run(args: list[str], env: dict | None = None, timeout: float = 30) -> tuple[int, str]:
    try:
        done = subprocess.run(args, cwd=bridge.HOME, env=env, stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, timeout=timeout)
        return done.returncode, (done.stdout or "") + (done.stderr or "")
    except (OSError, subprocess.TimeoutExpired) as e:
        return -1, str(e)


def last_line(text: str) -> str:
    lines = [l.strip() for l in (text or "").splitlines() if l.strip() and not LINK.fullmatch(l.strip())]
    return bridge.one_line(lines[-1], 240) if lines else ""


def version_of(binary: str, env: dict | None = None) -> str:
    _, out = run([binary, "--version"], env=env, timeout=15)
    match = VERSION.search(out)
    return match.group(0) if match else ""


def executable(path: str) -> str:
    """`path` as given, or found on PATH; "" when it runs nothing."""
    path = os.path.expanduser(path or "")
    if os.sep in path:
        return path if os.path.isfile(path) and os.access(path, os.X_OK) else ""
    return shutil.which(path) or ""


def catalog_path(agent: str) -> str:
    return os.path.join(bridge.STATE_DIR, f"catalog-{agent}.json")


def catalog(agent: str) -> dict:
    try:
        with open(catalog_path(agent), encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


# ── The browser link ─────────────────────────────────────────────────────────


class BrowserCatcher:
    """A `$BROWSER` that opens nothing: it writes the link it was given to a file
    beside itself, where `link()` picks it up. Both CLIs call `$BROWSER` with the
    link that completes on their own localhost callback."""

    def __init__(self):
        base = os.environ.get("XDG_RUNTIME_DIR") or None
        self.dir = tempfile.mkdtemp(prefix="agent-signin-", dir=base if base and os.path.isdir(base) else None)
        self.path = os.path.join(self.dir, "browser")
        with open(self.path, "w", encoding="utf-8") as f:
            f.write('#!/bin/sh\nfor a in "$@"; do case "$a" in http*) printf \'%s\\n\' "$a" >> "$(dirname "$0")/links";; esac; done\n')
        os.chmod(self.path, 0o700)

    def link(self) -> str:
        try:
            with open(os.path.join(self.dir, "links"), encoding="utf-8") as f:
                links = [l.strip() for l in f if l.strip()]
            return links[0] if links else ""
        except OSError:
            return ""

    def close(self) -> None:
        shutil.rmtree(self.dir, ignore_errors=True)


def _pump(stream, into: queue.Queue) -> None:
    for line in stream:
        into.put(line)
    into.put(None)


def cli_login(args: list[str], env: dict, name: str) -> int:
    """Run a CLI's own sign-in to its end, passing its browser link on as {"url"}.

    A link only on its output (no `$BROWSER` call) is the manual flow, where the
    browser shows a code to paste back: then {"url", "code": true}, and whatever
    the page writes to stdin goes on to the program."""
    catcher = BrowserCatcher()
    env = dict(env, BROWSER=catcher.path)
    out: queue.Queue = queue.Queue()
    proc = spawn(args, env=env, stdin=subprocess.PIPE)
    threading.Thread(target=_pump, args=(proc.stdout, out), daemon=True).start()
    threading.Thread(target=_forward_stdin, args=(proc,), daemon=True).start()
    printed, sent, said = "", "", []
    started = time.monotonic()
    try:
        while True:
            try:
                line = out.get(timeout=0.2)
            except queue.Empty:
                line = ""
            if line is None:
                break
            if line:
                said.append(line)
                match = LINK.search(line)
                if match and not printed:
                    printed = match.group(0)
            link = catcher.link()
            if link and not sent:
                sent = link
                emit({"url": link})
            elif printed and not sent and time.monotonic() - started > 5:
                sent = printed
                emit({"url": printed, "code": True})
            if time.monotonic() - started > LOGIN_TIMEOUT:
                emit({"error": "The sign-in took too long. Start it again."})
                return 1
        code = proc.wait()
        if code == 0:
            emit({"done": True})
            return 0
        emit({"error": last_line("".join(said)) or f"{name} could not sign in (exit {code})"})
        return 1
    finally:
        catcher.close()


def _forward_stdin(proc: subprocess.Popen) -> None:
    """A pasted code, from the page, to the program waiting on it."""
    for line in sys.stdin:
        try:
            proc.stdin.write(line)
            proc.stdin.flush()
        except (OSError, ValueError):
            return


# ── Claude Code ──────────────────────────────────────────────────────────────


def claude_env() -> dict:
    # As the bridge runs it: with a key in the environment the CLI answers for the
    # key, not for the login being shown.
    env = dict(os.environ)
    for key in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"):
        env.pop(key, None)
    return env


def claude_status(binary: str) -> dict:
    if not binary:
        return {"installed": False}
    out = {"installed": True, "path": binary, "version": version_of(binary, claude_env()), "signed_in": None, "account": "", "plan": ""}
    code, said = run([binary, "auth", "status", "--json"], env=claude_env())
    try:
        data = json.loads(said[said.index("{"):]) if "{" in said else None
    except ValueError:
        data = None
    if not isinstance(data, dict):
        # Unreadable is not signed out: the page says it could not tell.
        out["error"] = last_line(said) or f"Claude Code did not say who is signed in (exit {code})"
        return out
    kind = str(data.get("subscriptionType") or "")
    plan = CLAUDE_PLANS.get(kind) or (f"Claude {kind.capitalize()}" if kind else "")
    if not plan and data.get("loggedIn") and str(data.get("authMethod") or "") not in ("claude.ai", ""):
        plan = "API usage billing"
    out.update(signed_in=bool(data.get("loggedIn")), account=str(data.get("email") or ""), plan=plan,
               org=str(data.get("orgName") or ""))
    return out


# ── Codex ────────────────────────────────────────────────────────────────────


class Rpc:
    """Newline JSON-RPC to a child: Codex's app-server, or an ACP server."""

    def __init__(self, proc: subprocess.Popen, jsonrpc: bool):
        self.proc = proc
        self.jsonrpc = jsonrpc
        self.next = 1
        self.frames: queue.Queue = queue.Queue()
        threading.Thread(target=_pump, args=(proc.stdout, self.frames), daemon=True).start()

    def send(self, frame: dict) -> None:
        if self.jsonrpc:
            frame = dict(frame, jsonrpc="2.0")
        self.proc.stdin.write(json.dumps(frame) + "\n")
        self.proc.stdin.flush()

    def call(self, method: str, params, timeout: float = 30) -> dict:
        rid = self.next
        self.next += 1
        self.send({"id": rid, "method": method, "params": params})
        deadline = time.monotonic() + timeout
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                raise TimeoutError(method)
            try:
                line = self.frames.get(timeout=left)
            except queue.Empty:
                raise TimeoutError(method)
            if line is None:
                raise EOFError(method)
            try:
                frame = json.loads(line)
            except ValueError:
                continue
            if frame.get("id") == rid and "method" not in frame:
                if frame.get("error"):
                    raise RuntimeError((frame["error"] or {}).get("message") or f"{method} failed")
                return frame.get("result") or {}

    def close(self) -> None:
        try:
            self.proc.stdin.close()
            self.proc.wait(5)
        except (OSError, subprocess.TimeoutExpired):
            pass


def codex_status(binary: str) -> dict:
    if not binary:
        return {"installed": False}
    out = {"installed": True, "path": binary, "version": version_of(binary), "signed_in": None, "account": "", "plan": ""}
    # account/read is the app-server's own answer for apps; `codex login status`
    # names only the method.
    rpc = Rpc(spawn([binary, "app-server"], stdin=subprocess.PIPE, stderr=subprocess.DEVNULL), jsonrpc=False)
    try:
        rpc.call("initialize", {"clientInfo": {"name": "ii_settings", "title": "ii settings", "version": "1"}})
        rpc.send({"method": "initialized"})
        read = rpc.call("account/read", {})
        account = read.get("account") or {}
        out["signed_in"] = bool(account) or not read.get("requiresOpenaiAuth", True)
        if account.get("type") == "chatgpt":
            out["account"] = str(account.get("email") or "")
            plan = str(account.get("planType") or "")
            out["plan"] = f"ChatGPT {plan.capitalize()}" if plan and plan != "unknown" else "ChatGPT"
        elif account.get("type") == "apiKey":
            out["plan"] = "API usage billing"
    except (OSError, TimeoutError, EOFError, RuntimeError) as e:
        out["error"] = f"Codex did not say who is signed in: {e}"
    finally:
        rpc.close()
    return out


# ── Antigravity ──────────────────────────────────────────────────────────────


def antigravity_server(custom: str) -> tuple[str, str] | None:
    if custom:
        os.environ["AGENT_ANTIGRAVITY_SERVER"] = os.path.expanduser(custom)
    return ab.find_server()


def _folder_size(folder: str) -> int:
    total = 0
    for name in os.listdir(folder):
        try:
            total += os.path.getsize(os.path.join(folder, name))
        except OSError:
            pass
    return total


def antigravity_status(custom: str) -> dict:
    found = antigravity_server(custom)
    installed = bool(found and os.path.isfile(found[0]))
    out = {"installed": installed, "path": found[0] if installed else "", "version": "", "managed": False, "size": 0}
    if installed and found[0].startswith(ab.DATA_DIR + os.sep):
        folder = os.path.dirname(found[0])
        out.update(version=os.path.basename(folder), managed=True, size=_folder_size(folder))
    # Where the server keeps its own sign-in. Only whether it is there is looked
    # at; what is in it is the server's.
    out["signed_in"] = os.path.isfile(os.path.join(ab.gemini_home(), "antigravity-acp", "acp_token.json"))
    out["method"] = ANTIGRAVITY_METHODS.get(ab.configured_auth() or "oauth-personal", "")
    out["plan"] = str(catalog("antigravity").get("plan") or "")
    out["account"] = ""
    return out


def antigravity_rpc(found: tuple[str, str]) -> Rpc:
    server, harness = found
    env = {k: v for k, v in os.environ.items() if k not in ab.DROPPED_ENV}
    os.makedirs(ab.CACHE_DIR, exist_ok=True)
    # As the bridge starts it (antigravity_backend._spawn): logs into our cache,
    # and BROWSER=true so the server opens nothing; its link comes back on stderr.
    env.update(TMPDIR=ab.CACHE_DIR, PYTHONUNBUFFERED="1", BROWSER="true")
    if os.path.isfile(harness):
        env["ANTIGRAVITY_HARNESS_PATH"] = harness
    args = [server, "--uid="] if server.endswith(".par") else [server]
    proc = spawn(args, env=env, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    rpc = Rpc(proc, jsonrpc=True)
    rpc.call("initialize", {"protocolVersion": 1,
                            "clientCapabilities": {"fs": {"readTextFile": False, "writeTextFile": False}, "terminal": False},
                            "clientInfo": {"name": "ii-sidebar", "title": "ii sidebar", "version": "1"}}, timeout=120)
    return rpc


def save_plan(plan: str) -> None:
    """The tier Google reports on sign-in, beside the models the bridge saw."""
    data = catalog("antigravity")
    data["plan"] = plan
    os.makedirs(bridge.STATE_DIR, exist_ok=True)
    path = catalog_path("antigravity")
    with open(path + ".tmp", "w", encoding="utf-8") as f:
        json.dump(data, f)
    os.replace(path + ".tmp", path)


def antigravity_login(custom: str) -> int:
    found = antigravity_server(custom)
    if not found or not os.path.isfile(found[0]):
        emit({"error": "Install Google's agent server first"})
        return 1
    rpc = antigravity_rpc(found)
    sent = []

    def watch_stderr():
        for line in rpc.proc.stderr:
            match = ab.AUTH_URL.search(line)
            if match and not sent:
                sent.append(match.group(1))
                emit({"url": match.group(1)})

    threading.Thread(target=watch_stderr, daemon=True).start()
    try:
        # Signed in already, the server refreshes quietly and answers at once.
        result = rpc.call("authenticate", {"methodId": ab.configured_auth() or "oauth-personal"}, timeout=330)
    except TimeoutError:
        emit({"error": "The sign-in took too long. Start it again."})
        return 1
    except (EOFError, RuntimeError) as e:
        emit({"error": f"Antigravity did not sign in: {e}"})
        return 1
    finally:
        rpc.close()
    tier = (((result.get("_meta") or {}).get("antigravity") or {}).get("tier") or {}).get("name") or ""
    if tier:
        save_plan(tier)
    emit({"done": True, "plan": tier})
    return 0


def antigravity_logout(custom: str) -> int:
    found = antigravity_server(custom)
    if not found or not os.path.isfile(found[0]):
        emit({"error": "Google's agent server is not installed"})
        return 1
    try:
        rpc = antigravity_rpc(found)
        try:
            rpc.call("logout", {}, timeout=60)
        finally:
            rpc.close()
    except (OSError, TimeoutError, EOFError, RuntimeError) as e:
        emit({"error": f"Antigravity did not sign out: {e}"})
        return 1
    save_plan("")
    emit({"done": True})
    return 0


def antigravity_install() -> int:
    def progress(done, total):
        emit({"progress": [done, total]})

    try:
        entry = ab.registry_entry()
        folder = ab.install(entry, progress)
    except bridge.BridgeError as e:
        emit({"error": str(e)})
        return 1
    except Exception as e:  # offline, a full disk: the page says so and offers it again
        emit({"error": f"Could not download Google's agent server: {e}"})
        return 1
    # The versions it replaces stay: a sidebar running one still starts its
    # helpers from there. The bridge prunes them on its next start.
    emit({"done": os.path.basename(folder)})
    return 0


def antigravity_remove() -> int:
    for name in os.listdir(ab.DATA_DIR) if os.path.isdir(ab.DATA_DIR) else []:
        path = os.path.join(ab.DATA_DIR, name)
        if os.path.isdir(path):
            shutil.rmtree(path, ignore_errors=True)
    emit({"done": True})
    return 0


def antigravity_latest() -> int:
    try:
        emit({"version": ab.registry_entry()["version"]})
        return 0
    except Exception as e:
        emit({"error": str(e)})
        return 1


# ── Entry ────────────────────────────────────────────────────────────────────


def main(argv: list[str]) -> int:
    args = list(argv)
    custom = ""
    if "--bin" in args:
        i = args.index("--bin")
        custom = args[i + 1] if i + 1 < len(args) else ""
        del args[i:i + 2]
    if len(args) != 2 or args[1] not in ("claude", "codex", "antigravity"):
        print(__doc__, file=sys.stderr)
        return 2
    command, agent = args
    if agent == "antigravity":
        jobs = {"status": lambda: emit(antigravity_status(custom)) or 0, "login": lambda: antigravity_login(custom),
                "logout": lambda: antigravity_logout(custom), "install": antigravity_install,
                "remove": antigravity_remove, "latest": antigravity_latest}
    else:
        binary = executable(custom or os.environ.get(f"AGENT_{agent.upper()}_BIN") or agent)
        if agent == "claude":
            jobs = {"status": lambda: emit(claude_status(binary)) or 0,
                    "login": lambda: cli_login([binary, "auth", "login"], claude_env(), "Claude Code"),
                    "logout": lambda: _logout([binary, "auth", "logout"], claude_env(), "Claude Code")}
        else:
            jobs = {"status": lambda: emit(codex_status(binary)) or 0,
                    "login": lambda: cli_login([binary, "login"], dict(os.environ), "Codex"),
                    "logout": lambda: _logout([binary, "logout"], dict(os.environ), "Codex")}
        if command != "status" and command in jobs and not binary:
            emit({"error": f"{'Claude Code' if agent == 'claude' else 'Codex'} is not installed"})
            return 1
    job = jobs.get(command)
    if job is None:
        emit({"error": f"{agent} has no {command}"})
        return 2
    return job()


def _logout(args: list[str], env: dict, name: str) -> int:
    code, out = run(args, env=env, timeout=60)
    if code == 0:
        emit({"done": True})
        return 0
    emit({"error": last_line(out) or f"{name} could not sign out (exit {code})"})
    return 1


if __name__ == "__main__":
    # Killed by the page (Cancel, or the window closing): unwind, so the program
    # started here is stopped and a half download is cleaned up.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(129))
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
    finally:
        _stop_children()
