#!/usr/bin/env python3
"""Settings > Agent sets the agents up for real, and the sidebar follows what it set.

The page signs agents in and out, installs Google's server, and picks paths, models
and defaults. None of that can be watched without real logins, so this runs it
against fake `claude`, `codex` and Antigravity programs:

  * scripts/agent/setup.py, the page's helper. Each sign-in is the program's own:
    the link the page opens is the one the program hands `$BROWSER` (its localhost
    callback), never the manual one it prints -- unless it prints only that, when
    the page asks for the code and passes it on. Cancelling kills the program, or
    a waiting Codex holds its callback port. A status the program could not give
    is "could not tell", not "signed out". Antigravity's sign-in is the ACP
    server's `authenticate`, with BROWSER=true so the server opens nothing.
  * The bridge, started with the page's settings: a program path that is not on
    PATH, the desktop tools turned off (no MCP server handed over, and the page
    stops offering the screen), the user's instructions in the system prompt, and
    each new chat moved to the default model through the picker's own path. It
    leaves the models it offered where the page can read them.
  * AgentService's side, under node: an agent turned off is never looked for, a
    path set in Settings is the only one tried, the default agent applies at the
    shell's start and not after, and new settings restart the bridge only once a
    reply is over -- on the same chat, unless the agent itself changed. None of it
    starts anything before the sidebar's first open (check-sidebar-boot.py).

Run with the system python3; the fakes are written to a temporary directory.
"""
import json
import os
import pathlib
import queue
import signal
import subprocess
import sys
import tempfile
import textwrap
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
QS = ROOT / "dots/.config/quickshell/ii"
AGENT = QS / "scripts/agent"
SETUP = AGENT / "setup.py"

FAKE_CLAUDE = r'''
import json, os, subprocess, sys, time
home = os.environ["HOME"]
state = os.path.join(home, "claude-signed-in")
assert "ANTHROPIC_API_KEY" not in os.environ, "an API key reached the CLI"
args = sys.argv[1:]
if args == ["--version"]:
    print("9.9.9 (Claude Code)"); sys.exit(0)
if args[:2] == ["auth", "status"]:
    if os.environ.get("FAKE_BROKEN"):
        print("segfault in auth"); sys.exit(1)
    print(json.dumps({"loggedIn": True, "email": "me@example.com", "subscriptionType": "max", "orgName": "Org"}
                     if os.path.exists(state) else {"loggedIn": False})); sys.exit(0)
if args[:2] == ["auth", "login"]:
    open(os.path.join(home, "login.pid"), "w").write(str(os.getpid()))
    if os.environ.get("FAKE_MANUAL"):
        print("visit: https://claude.example/manual", flush=True)
        code = sys.stdin.readline().strip()
        if code != "CODE123":
            print("Wrong code"); sys.exit(1)
    else:
        print("Opening browser to sign in…", flush=True)
        subprocess.run([os.environ["BROWSER"], "https://claude.example/auto?redirect_uri=http://localhost:4242/callback"])
        print("If the browser didn't open, visit: https://claude.example/manual", flush=True)
        for _ in range(400):
            if os.path.exists(os.path.join(home, "callback")):
                break
            time.sleep(0.05)
        else:
            sys.exit(3)
    open(state, "w").close()
    print("Login successful."); sys.exit(0)
if args[:2] == ["auth", "logout"]:
    os.path.exists(state) and os.unlink(state); sys.exit(0)
# The bridge's stream-json session.
open(os.path.join(home, "claude-argv.json"), "w").write(json.dumps(sys.argv))
def send(o): sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
for line in sys.stdin:
    m = json.loads(line)
    if m["type"] != "control_request":
        continue
    req = m["request"]
    with open(os.path.join(home, "claude-controls.jsonl"), "a") as log:
        log.write(json.dumps(req) + "\n")
    body = {"models": [{"value": "default", "displayName": "Default", "description": "Fable 9"},
                       {"value": "opus", "displayName": "Opus"}], "commands": []} if req["subtype"] == "initialize" else {}
    send({"type": "control_response", "response": {"subtype": "success", "request_id": m["request_id"], "response": body}})
'''

FAKE_CODEX = r'''
import json, os, subprocess, sys
home = os.environ["HOME"]
state = os.path.join(home, "codex-signed-in")
args = sys.argv[1:]
if args == ["--version"]:
    print("codex-cli 1.2.3"); sys.exit(0)
if args == ["login"]:
    subprocess.run([os.environ["BROWSER"], "https://auth.example/oauth?redirect_uri=http://127.0.0.1:1455/auth/callback"])
    print("Starting local login server on http://localhost:1455.", flush=True)
    open(state, "w").close(); sys.exit(0)
if args == ["logout"]:
    os.path.exists(state) and os.unlink(state); sys.exit(0)
assert args == ["app-server"], args
def send(o): sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
for line in sys.stdin:
    m = json.loads(line)
    if m.get("method") == "initialize":
        send({"id": m["id"], "result": {"userAgent": "fake"}})
    elif m.get("method") == "account/read":
        signed = os.path.exists(state)
        send({"id": m["id"], "result": {"account": {"type": "chatgpt", "email": "you@example.com", "planType": "pro"} if signed else None,
                                        "requiresOpenaiAuth": True}})
'''

FAKE_ACP = r'''
import json, os, sys, time
assert os.environ.get("BROWSER") == "true", "the server could open a browser by itself"
token = os.path.join(os.environ["HOME"], ".gemini/antigravity-acp/acp_token.json")
def send(o): sys.stdout.write(json.dumps(dict(o, jsonrpc="2.0")) + "\n"); sys.stdout.flush()
for line in sys.stdin:
    m = json.loads(line)
    rid, meth = m.get("id"), m.get("method")
    if meth == "initialize":
        send({"id": rid, "result": {"protocolVersion": 1, "agentCapabilities": {"auth": {"logout": {}}}}})
    elif meth == "authenticate":
        sys.stderr.write("Open the following link to authenticate the ACP server: https://accounts.google.com/o/oauth2/v2/auth?x=1\n")
        sys.stderr.flush()
        time.sleep(0.5)  # the user signing in
        os.makedirs(os.path.dirname(token), exist_ok=True)
        open(token, "w").write("{}")  # the server's own storage
        send({"id": rid, "result": {"_meta": {"antigravity": {"tier": {"name": "Google AI Pro"}}}}})
    elif meth == "logout":
        os.path.exists(token) and os.unlink(token)
        send({"id": rid, "result": {}})
'''


def write(path: pathlib.Path, body: str) -> pathlib.Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"#!{sys.executable}\n" + textwrap.dedent(body))
    path.chmod(0o755)
    return path


with tempfile.TemporaryDirectory() as tmp:
    tmp = pathlib.Path(tmp)
    fakes = tmp / "bin"
    home = tmp / "home"
    home.mkdir()
    write(fakes / "claude", FAKE_CLAUDE)
    write(fakes / "codex", FAKE_CODEX)
    env = dict(os.environ, PATH=f"{fakes}:{os.environ['PATH']}", HOME=str(home), ANTHROPIC_API_KEY="must-not-arrive",
               XDG_STATE_HOME=str(tmp / "state"), XDG_DATA_HOME=str(tmp / "data"), XDG_CACHE_HOME=str(tmp / "cache"),
               XDG_RUNTIME_DIR=str(tmp))
    for key in ("GEMINI_HOME", "AGENT_ANTIGRAVITY_SERVER", "AGENT_CLAUDE_BIN", "AGENT_CODEX_BIN"):
        env.pop(key, None)

    def setup(*args, extra=None, timeout=30):
        done = subprocess.run([sys.executable, str(SETUP), *args], capture_output=True, text=True, timeout=timeout,
                              env=dict(env, **(extra or {})))
        return [json.loads(l) for l in done.stdout.splitlines() if l.strip()], done

    class Job:
        """A long setup.py job, read as the page reads it."""

        def __init__(self, *args, extra=None):
            self.proc = subprocess.Popen([sys.executable, str(SETUP), *args], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                         stderr=subprocess.PIPE, text=True, env=dict(env, **(extra or {})))
            self.lines = queue.Queue()
            threading.Thread(target=lambda: [self.lines.put(json.loads(l)) for l in self.proc.stdout if l.strip()], daemon=True).start()

        def next(self, timeout=20):
            try:
                return self.lines.get(timeout=timeout)
            except queue.Empty:
                raise AssertionError(f"setup.py said nothing in {timeout}s: {self.proc.stderr.read()[-500:] if self.proc.poll() is not None else ''}")

    # ── Claude Code ──
    (status,), _ = setup("status", "claude")
    assert status["installed"] and status["version"] == "9.9.9" and status["signed_in"] is False, f"Claude, signed out: {status}"

    login = Job("login", "claude")
    first = login.next()
    assert first == {"url": "https://claude.example/auto?redirect_uri=http://localhost:4242/callback"}, \
        f"Claude: the link opened must be the one handed to $BROWSER (it finishes on its own), not the printed one: {first}"
    (home / "callback").write_text("")
    assert login.next() == {"done": True}, "Claude: a finished sign-in is not reported as done"
    assert login.proc.wait(10) == 0
    (status,), _ = setup("status", "claude")
    assert (status["signed_in"], status["account"], status["plan"], status["org"]) == (True, "me@example.com", "Claude Max", "Org"), status

    # Cancel: the CLI waiting on its callback is stopped with the job.
    (home / "callback").unlink()
    login = Job("login", "claude")
    assert "url" in login.next()
    pid = int((home / "login.pid").read_text())
    login.proc.send_signal(signal.SIGTERM)
    assert login.proc.wait(10) == 143, "setup.py: a cancelled sign-in does not exit as cancelled"
    time.sleep(0.3)
    try:
        os.kill(pid, 0)
        alive = True
    except ProcessLookupError:
        alive = False
    assert not alive, "setup.py: cancelling left the CLI's sign-in running"

    # Only a printed link: the manual flow, where the browser shows a code to paste.
    login = Job("login", "claude", extra={"FAKE_MANUAL": "1"})
    asked = login.next(timeout=20)
    assert asked == {"url": "https://claude.example/manual", "code": True}, f"Claude: the manual flow is not offered for its code: {asked}"
    login.proc.stdin.write("CODE123\n")
    login.proc.stdin.flush()
    assert login.next() == {"done": True}, "Claude: the pasted code did not reach the CLI"

    (done,), _ = setup("logout", "claude")
    assert done == {"done": True}
    (status,), _ = setup("status", "claude")
    assert status["signed_in"] is False, "Claude: still signed in after signing out"

    (status,), _ = setup("status", "claude", extra={"FAKE_BROKEN": "1"})
    assert status["signed_in"] is None and status.get("error"), f"Claude: an unreadable status must not read as signed out: {status}"

    # A path set in Settings is the one used; one that runs nothing is not installed.
    own = write(tmp / "elsewhere" / "my-claude", FAKE_CLAUDE)
    (status,), _ = setup("status", "claude", "--bin", str(own))
    assert status["installed"] and status["path"] == str(own), status
    (status,), _ = setup("status", "claude", "--bin", str(tmp / "nowhere"))
    assert status == {"installed": False}, status
    (failed,), _ = setup("login", "claude", "--bin", str(tmp / "nowhere"))
    assert "error" in failed, "setup.py: a sign-in for a program that is not there must say so"

    # ── Codex ──
    (status,), _ = setup("status", "codex")
    assert status["version"] == "1.2.3" and status["signed_in"] is False, f"Codex, signed out: {status}"
    lines, done = setup("login", "codex")
    assert lines == [{"url": "https://auth.example/oauth?redirect_uri=http://127.0.0.1:1455/auth/callback"}, {"done": True}], lines
    (status,), _ = setup("status", "codex")
    assert (status["signed_in"], status["account"], status["plan"]) == (True, "you@example.com", "ChatGPT Pro"), status
    assert setup("logout", "codex")[0] == [{"done": True}]
    assert setup("status", "codex")[0][0]["signed_in"] is False

    # ── Antigravity ──
    (status,), _ = setup("status", "antigravity")
    assert status["installed"] is False and status["signed_in"] is False, f"Antigravity, nothing installed: {status}"
    folder = tmp / "data/quickshell/agent/antigravity-acp/1.2.3"
    write(folder / "agy_acp_server.par", FAKE_ACP)
    (folder / ".complete").write_text("{}")
    (status,), _ = setup("status", "antigravity")
    assert (status["installed"], status["managed"], status["version"]) == (True, True, "1.2.3") and status["size"] > 0, status
    assert status["method"] == "Google account", status
    lines, done = setup("login", "antigravity")
    assert lines == [{"url": "https://accounts.google.com/o/oauth2/v2/auth?x=1"}, {"done": True, "plan": "Google AI Pro"}], \
        f"Antigravity: the server's link, then its tier: {lines} {done.stderr[-400:]}"
    (status,), _ = setup("status", "antigravity")
    assert status["signed_in"] is True and status["plan"] == "Google AI Pro", f"Antigravity: the sign-in is not seen: {status}"
    assert setup("logout", "antigravity")[0] == [{"done": True}]
    (status,), _ = setup("status", "antigravity")
    assert status["signed_in"] is False and status["plan"] == "", f"Antigravity: still signed in after signing out: {status}"
    assert setup("remove", "antigravity")[0] == [{"done": True}] and not folder.exists(), "Antigravity: Remove left the server"

    # ── The bridge, on the page's settings ──
    def bridge(backend, extra):
        proc = subprocess.Popen([sys.executable, str(AGENT / "bridge.py"), backend], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, env=dict(env, **extra))
        frames = queue.Queue()
        threading.Thread(target=lambda: [frames.put(json.loads(l)) for l in proc.stdout], daemon=True).start()
        seen = []

        def until(done, timeout=20):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                try:
                    frame = frames.get(timeout=0.2)
                except queue.Empty:
                    if proc.poll() is not None:
                        raise AssertionError(f"bridge exited {proc.returncode}: {proc.stderr.read()[-800:]}")
                    continue
                seen.append(frame)
                if done(frame):
                    return frame
            raise AssertionError(f"bridge: timed out; saw {seen[-5:]}")

        def call(method, params=None):
            rid = f"ii-{len(seen)}-{method}"
            proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}}) + "\n")
            proc.stdin.flush()
            return until(lambda f: f.get("id") == rid and "method" not in f)

        return proc, until, call, seen

    (home / "claude-signed-in").write_text("")
    proc, until, call, seen = bridge("claude", {"AGENT_CLAUDE_BIN": str(own), "AGENT_DESKTOP_TOOLS": "0",
                                                "PATH": "/usr/bin:/bin"})
    ready = until(lambda f: f.get("method") == "event" and f["params"]["type"] == "ready")
    assert ready["params"]["payload"]["capabilities"]["screen"] is False, "bridge: the page still offers the screen with the desktop tools off"
    created = call("session.create", {"model": "opus", "instructions": "Always answer in haiku"})["result"]
    argv = json.loads((home / "claude-argv.json").read_text())
    assert argv[0] == str(own), f"bridge: the program set in Settings was not the one run: {argv[0]}"
    assert "--mcp-config" not in argv, "bridge: the desktop tools were handed over while turned off"
    prompt = argv[argv.index("--append-system-prompt") + 1]
    assert prompt.endswith("The user's own instructions for you:\nAlways answer in haiku") and len(prompt) > 60, \
        f"bridge: the user's instructions must follow the sidebar's own note: {prompt[-120:]!r}"
    controls = [json.loads(l) for l in (home / "claude-controls.jsonl").read_text().splitlines()]
    assert {"subtype": "set_model", "model": "opus"} in controls and created["info"]["model"] == "Opus", \
        f"bridge: a new chat did not move to the default model: {created['info']} {controls}"
    call("model.options")
    catalog = json.loads((tmp / "state/quickshell/agent/catalog-claude.json").read_text())
    assert catalog["models"] == [{"id": "default", "label": "Fable 9 (default)"}, {"id": "opus", "label": "Opus"}], \
        f"bridge: the page cannot list the models it offered: {catalog}"
    stale = call("session.create", {"model": "gone-model"})
    assert "result" in stale, "bridge: a default the agent dropped must not fail the new chat"
    assert any(f.get("method") == "event" and f["params"]["type"] == "notice" and "gone-model" in f["params"]["payload"]["message"]
               for f in seen), "bridge: a default model no longer offered goes unexplained"
    proc.stdin.close()
    proc.wait(10)
    gone = subprocess.run([sys.executable, str(AGENT / "bridge.py"), "claude"], input="", capture_output=True, text=True,
                          env=dict(env, AGENT_CLAUDE_BIN=str(tmp / "nowhere")))
    assert gone.returncode == 127 and str(tmp / "nowhere") in gone.stderr, \
        f"bridge: a path set in Settings that runs nothing must say where it looked: {gone.stderr[-200:]}"

# ── AgentService, under node ─────────────────────────────────────────────────

service = (QS / "services/AgentService.qml").read_text()


def body(src, header):
    start = src.index(header)
    i = src.index("{", start + len(header) - 1)
    depth = 0
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return src[i + 1:j]
    raise AssertionError(f"unbalanced block after {header!r}")


def block(src, header, opener="[", closer="]"):
    start = src.index(header)
    i = src.index(opener, start)
    depth = 0
    for j in range(i, len(src)):
        depth += {opener: 1, closer: -1}.get(src[j], 0)
        if depth == 0:
            return src[i:j + 1]


def node(js):
    out = subprocess.run(["node", "-e", js], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr[-1500:]
    return json.loads(out.stdout)


PRELUDE = f"""
const Translation = {{ tr: s => s }};
const FileUtils = {{ trimFileProtocol: s => s.replace(/^file:\\/\\//, "") }};
const Directories = {{ home: "file:///home/u" }};
const Persistent = {{ states: {{ agent: {{ backend: "claude" }} }} }};
const knownBackends = {block(service, "readonly property var knownBackends:")};
"""

probe = node(PRELUDE + f"""
const Config = {{ options: {{ agent: {{ defaultBackend: "codex",
    claude: {{ enable: true, binary: " ~/bin/claude " }}, codex: {{ enable: true, binary: "" }}, antigravity: {{ enable: true, binary: "" }} }} }} }};
const calls = [];
const root = {{ knownBackends, backendsProbed: false, _startWhenProbed: true, backends: [], missing: false,
    ensureStarted: () => calls.push("ensureStarted"), _applySettings: () => calls.push("applySettings") }};
root._expandHome = function (path) {{ {body(service, "function _expandHome(path: string): string")} }};
const targets = (function () {{ {body(service, "readonly property var _probeTargets:")} }})();
Config.options.agent.codex.enable = false;
const withoutCodex = (function () {{ {body(service, "readonly property var _probeTargets:")} }})();
Config.options.agent.codex.enable = true;
const finished = function () {{ {body(service, "onStreamFinished: {")} }};
finished.call({{ text: "claude /home/u/bin/claude\\ncodex codex\\nantigravity agy\\n" }});
const first = {{ backends: root.backends.map(b => [b.id, b.plan]), picked: Persistent.states.agent.backend, calls: calls.slice() }};
Persistent.states.agent.backend = "claude";
finished.call({{ text: "claude /home/u/bin/claude\\nantigravity antigravity-server\\n" }});
console.log(JSON.stringify({{ targets, withoutCodex, first,
    second: {{ backends: root.backends.map(b => [b.id, b.plan]), picked: Persistent.states.agent.backend, calls }} }}));
""")
assert probe["targets"] == ["claude=/home/u/bin/claude", "codex=codex", "antigravity=agy", "antigravity=agy_acp_server", "antigravity=@installed"], \
    f"AgentService: a path set in Settings must be the only one tried for its agent: {probe['targets']}"
assert not any(t.startswith("codex=") for t in probe["withoutCodex"]), "AgentService: an agent turned off is still looked for"
first = probe["first"]
assert [b[0] for b in first["backends"]] == ["claude", "codex", "antigravity"] and "First use downloads" in first["backends"][2][1], \
    f"AgentService: Antigravity with only `agy` must say its server is still to download: {first['backends']}"
assert first["picked"] == "codex" and first["calls"] == ["ensureStarted"], \
    f"AgentService: the shell's start must begin on the default agent: {first}"
second = probe["second"]
assert second["picked"] == "claude", "AgentService: the default agent overrode a pick made in the sidebar after the start"
assert "First use" not in second["backends"][1][1] and second["calls"][-1] == "applySettings", \
    f"AgentService: a later probe must bring the bridge in line, not start it again: {second}"

restart = node(PRELUDE + f"""
const out = {{}};
function make(state) {{
    const log = [];
    const root = Object.assign({{ _restartFor: "", _launchedId: "claude", _launchedEnv: "A", _bridgeEnvKey: "A",
        backend: {{ id: "claude" }}, enabled: true, missing: false, starting: false, busy: false, pendingApproval: null,
        pendingClarify: null, storedSessionId: "chat-1", _resumeAfterStart: "", _restartWhenIdle: false, consecutiveFailures: 2,
        ensureStarted: () => log.push("ensureStarted"), _restart: () => log.push("restart"), _forgetAgent: () => log.push("forget") }}, state);
    const bridgeProc = {{ running: state.running ?? true }};
    const restartTimer = {{ stop: () => log.push("stopTimer") }};
    root._restartForSettings = function () {{ {body(service, "function _restartForSettings(): void")} }};
    root._applySettings = function () {{ {body(service, "function _applySettings(): void")} }};
    root._applySettings();
    return {{ log, resume: root._resumeAfterStart, waiting: root._restartWhenIdle }};
}}
out.same = make({{}});
out.env = make({{ _bridgeEnvKey: "B" }});
out.busy = make({{ _bridgeEnvKey: "B", busy: true }});
out.agent = make({{ backend: {{ id: "codex" }} }});
out.account = make({{ _restartFor: "claude" }});
out.other = make({{ _restartFor: "codex" }});
out.stopped = make({{ running: false }});
out.off = make({{ running: false, enabled: false }});
const boot = [];
const root = {{ backendsProbed: false }};
const backendProbe = {{ refresh: () => boot.push("probe") }};
(function () {{ {body(service, "on_LaunchSettingsChanged: {")} }})();
root.backendsProbed = true;
(function () {{ {body(service, "on_LaunchSettingsChanged: {")} }})();
out.boot = boot;
console.log(JSON.stringify(out));
""")
assert restart["same"]["log"] == [], f"AgentService: a re-read that changed nothing restarted the bridge: {restart['same']}"
assert restart["env"]["log"] == ["restart"] and restart["env"]["resume"] == "chat-1", \
    f"AgentService: new settings must restart on the same chat: {restart['env']}"
assert restart["busy"]["log"] == [] and restart["busy"]["waiting"], "AgentService: new settings cut a reply short"
assert restart["agent"]["log"] == ["forget", "restart"] and restart["agent"]["resume"] == "", \
    f"AgentService: a switch to another agent must not reopen the old agent's chat: {restart['agent']}"
assert restart["account"]["log"] == ["restart"], "AgentService: a new sign-in for the agent in use did not restart it"
assert restart["other"]["log"] == [], "AgentService: a sign-in for another agent restarted this one"
assert restart["stopped"]["log"] == ["stopTimer", "ensureStarted"], \
    f"AgentService: an agent stopped as signed out or missing must try again on new settings: {restart['stopped']}"
assert restart["off"]["log"] == [], "AgentService: new settings started an agent that is turned off"
assert restart["boot"] == ["probe"], f"AgentService: a settings change looked for agents before the first open: {restart['boot']}"
assert "environment: root._bridgeEnv" in service and '"AGENT_DESKTOP_TOOLS": agent.desktopTools ? "1" : "0"' in service, \
    "AgentService: the bridge is not started with the page's settings"
assert 'Config.options.agent[root._launchedId]?.model' in service and "instructions: Config.options.agent.instructions" in service, \
    "AgentService: new chats do not carry the default model and the user's instructions"

ipc = (QS / "services/agent/AgentSetupAgent.qml").read_text()
assert '["qs", "-c", "ii", "ipc", "call", "agent", "refresh", root.agentId]' in ipc and "function refresh(id: string): void" in service, \
    "Settings: a finished sign-in or install is never told to the shell"

print("ok: Settings signs agents in through their own programs, and the sidebar starts on what it set, between replies")
