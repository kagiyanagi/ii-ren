#!/usr/bin/env python3
"""The sidebar's agent connector speaks both CLIs correctly, without spending a token.

scripts/agent/bridge.py translates between the sidebar and Claude Code or Codex.
Every mistake in it is invisible until a live chat goes wrong in a way that looks
like the agent's fault, so this pins down:

  * The run emitter. The sidebar folds an answer into one card but expects it in
    model steps; a step that ends having called tools is mid-run and must not
    notify. Text after a tool call is the next step. A tool.complete outside a
    step is dropped by the shell, so one has to reopen it.
  * What reaches the model: chips (`@file:`, `@folder:`) become plain paths.
  * Claude's transcripts: the conversation is the newest leaf walked back, not
    file order -- a rewind branches the file -- and an undo nothing has been said
    after yet pins the leaf, or reopening the chat brings the undone turn back.
  * Both protocols end to end, against fake `claude` and `codex` binaries that
    speak them: approvals are asked and answered, tool rows open and close inside
    a step, a turn ends exactly once, and the CLI's own login is never touched.
  * The desktop tool server's handshake, and that the tools the bridge lets
    Claude run unasked are exactly the read-only ones.
  * The page only offers what the agent said it can do.

Run with the system python3; the fakes are written to a temporary directory.
"""
import json
import os
import pathlib
import queue
import subprocess
import sys
import tempfile
import textwrap
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
QS = ROOT / "dots/.config/quickshell/ii"
AGENT = QS / "scripts/agent"
sys.path.insert(0, str(AGENT))

import bridge  # noqa: E402

sys.modules["bridge"] = bridge
import claude_backend as cb  # noqa: E402
import codex_backend as xb  # noqa: E402

# ── 1. the run emitter ───────────────────────────────────────────────────────

out = []
run = bridge.Run(lambda kind, payload: out.append((kind, payload)))
run.begin()
run.text("Looking. ")
run.tool_start("t1", "bash", "ls", {"command": "ls"})
run.tool_complete("t1", "a b", 0.1)
run.text("Found two.")
run.finish("complete")
kinds = [k for k, _ in out]
assert kinds == ["message.start", "message.delta", "tool.start", "tool.complete", "message.complete",
                 "message.start", "message.delta", "message.complete"], f"Run: steps are wrong: {kinds}"
assert out[4][1] == {"text": ""}, "Run: a mid-run step must complete with empty text, keeping what streamed"
assert out[-1][1]["status"] == "complete", "Run: the final step must carry the status"

out.clear()
run.begin()
run.tool_start("t2", "bash", "", {})
run.text("after")
run.tool_complete("t2", "late", 0)  # parallel calls can finish after the next text
run.finish()
assert [k for k, _ in out].count("message.start") == 2 and out[-1][0] == "message.complete", \
    "Run: a late tool.complete must land inside an open step"

out.clear()
run.begin()
run.finish()
assert [k for k, _ in out] == ["message.start", "message.complete"], "Run: an empty answer must still end the turn"
out.clear()
run.finish()
assert out == [], "Run: a turn must end once, not once per result frame"
run.begin()
run.text("x")
run.finish(error="boom")
assert out[-1] == ("error", {"message": "boom"}), "Run: a failed turn must end through the error event"

# ── 2. what reaches the model ────────────────────────────────────────────────

assert bridge.plain_refs('see @file:/a/b.txt and @folder:"/tmp/my dir" now') == "see /a/b.txt and /tmp/my dir/ now", \
    "plain_refs: chips must reach the model as plain paths"
assert bridge.plain_refs("mail me @ noon") == "mail me @ noon", "plain_refs: an ordinary @ was rewritten"

# ── 3. Claude transcripts ────────────────────────────────────────────────────


def entry(uid, parent, kind, content):
    return {"uuid": uid, "parentUuid": parent, "type": kind, "message": {"content": content}}


entries = [
    entry("u1", None, "user", "first question"),
    entry("a1", "u1", "assistant", [{"type": "text", "text": "first answer"}]),
    entry("u2", "a1", "user", "second question"),
    entry("a2", "u2", "assistant", [{"type": "tool_use", "id": "x", "name": "Bash", "input": {"command": "ls", "description": "List"}}]),
    entry("r2", "a2", "user", [{"type": "tool_result", "tool_use_id": "x", "content": "a b"}]),
    entry("a3", "r2", "assistant", [{"type": "text", "text": "second answer"}]),
    # a retry of the second question, branched off the first answer
    entry("u2b", "a1", "user", "second question, again"),
    entry("a2b", "u2b", "assistant", [{"type": "text", "text": "better answer"}]),
]
rows, omitted = cb.transcript(entries)
assert [r.get("text") for r in rows] == ["first question", "first answer", "second question, again", "better answer"], \
    f"Claude transcript: a rewound branch is being replayed: {rows}"
rows, _ = cb.transcript(entries[:6])
assert [r["role"] for r in rows] == ["user", "assistant", "user", "tool", "assistant"], f"Claude transcript: {rows}"
assert rows[3]["name"] == "bash" and rows[3]["context"] == "List", "Claude transcript: tool rows lost their name or context"
rows, _ = cb.transcript(entries[:6], leaf="a1")
assert [r.get("text") for r in rows] == ["first question", "first answer"], "Claude transcript: a pinned undo point is ignored"
assert cb.prompt_text(entry("m", None, "user", "<local-command-stdout>ok</local-command-stdout>")) is None, \
    "Claude transcript: the CLI's own notes show as user turns"
assert cb.prompt_text(entry("c", None, "user", "<command-name>/compact</command-name><command-args>keep x</command-args>")) == "/compact keep x"
assert cb.tool_name("mcp__desktop__screenshot") == "screenshot" and cb.tool_name("Read") == "read_file"
assert cb.project_dir("/home/a.b").endswith("/projects/-home-a-b"), "Claude: the project folder name no longer matches the CLI's"

with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "11111111-2222-3333-4444-555555555555.jsonl")
    with open(path, "w") as f:
        f.write(json.dumps({"type": "user", "uuid": "u", "timestamp": "2026-01-01T00:00:00Z", "message": {"content": "hello there"}}) + "\n")
        f.write(json.dumps({"type": "ai-title", "aiTitle": "Greeting"}) + "\n")
    row = cb.session_summary(path)
    assert row["id"] == "11111111-2222-3333-4444-555555555555" and row["title"] == "Greeting" and row["preview"] == "hello there", row
    assert abs(row["started_at"] - 1767225600) < 1, "Claude history: started_at is not the first message's time, in seconds"

# ── 4. Codex items ───────────────────────────────────────────────────────────

name, context, args = xb.item_tool({"type": "commandExecution", "command": "ls -la", "cwd": "/h"})
assert name == "command_execution" and args["command"] == "ls -la"
assert xb.item_result({"type": "commandExecution", "aggregatedOutput": "x", "exitCode": 2}) == {"output": "x", "exit_code": 2}
assert xb.item_result({"type": "commandExecution", "status": "declined"}) == {"error": "Declined"}
assert xb.item_tool({"type": "agentMessage"}) is None and xb.item_tool({"type": "reasoning"}) is None
rows, _ = xb.turn_rows([{"items": [{"type": "userMessage", "content": [{"type": "text", "text": "hi"}]},
                                   {"type": "agentMessage", "text": "hello"}]}])
assert rows == [{"role": "user", "text": "hi"}, {"role": "assistant", "text": "hello"}], rows
assert xb._toml({"A": 'x"y'}) == '{A="x\\"y"}', "Codex: an env table override is not valid TOML"

# ── 5. both protocols, end to end, against fakes ─────────────────────────────

FAKE_CLAUDE = r'''
import json, sys
if sys.argv[1:3] == ["auth", "status"]:
    print(json.dumps({"loggedIn": True})); sys.exit(0)
assert "--permission-prompt-tool" in sys.argv and "stdio" in sys.argv
assert not any(a.startswith("--bare") for a in sys.argv), "--bare would refuse the claude.ai login"
import os
assert "ANTHROPIC_API_KEY" not in os.environ, "the API key reached the CLI"
sid = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--session-id=")), "s")
def send(o): sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
for line in sys.stdin:
    m = json.loads(line)
    if m["type"] == "control_request":
        sub = m["request"]["subtype"]
        with open(os.path.join(os.environ["HOME"], "claude-controls.jsonl"), "a") as log:
            log.write(json.dumps(m["request"]) + "\n")
        body = {"models": [{"value": "default", "displayName": "Default", "description": "Fable 9", "supportsAutoMode": True,
                            "supportsEffort": True, "supportedEffortLevels": ["low", "high"]}],
                "commands": [{"name": "review", "description": "Review"}]} if sub == "initialize" else \
               {"percentage": 12.4, "totalTokens": 1200, "maxTokens": 10000, "categories": [{"name": "Messages", "tokens": 900}]} if sub == "get_context_usage" else {}
        send({"type": "control_response", "response": {"subtype": "success", "request_id": m["request_id"], "response": body}})
    elif m["type"] == "control_response":
        allowed = m["response"]["response"]["behavior"] == "allow"
        send({"type": "user", "parent_tool_use_id": None, "message": {"content": [{"type": "tool_result", "tool_use_id": "t1", "content": "probe-ok" if allowed else "denied", "is_error": not allowed}]}})
        send({"type": "stream_event", "parent_tool_use_id": None, "event": {"type": "message_start", "message": {"id": "m2"}}})
        send({"type": "stream_event", "parent_tool_use_id": None, "event": {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "Done."}}})
        send({"type": "assistant", "parent_tool_use_id": None, "message": {"id": "m2", "content": [{"type": "text", "text": "Done."}]}})
        send({"type": "result", "subtype": "success", "is_error": False, "session_id": sid})
    elif m["type"] == "user":
        send({"type": "system", "subtype": "init", "session_id": sid})
        send({"type": "stream_event", "parent_tool_use_id": None, "event": {"type": "message_start", "message": {"id": "m1"}}})
        send({"type": "stream_event", "parent_tool_use_id": None, "event": {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "Running it."}}})
        send({"type": "assistant", "parent_tool_use_id": None, "message": {"id": "m1", "content": [{"type": "text", "text": "Running it."}, {"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "echo probe-ok"}}]}})
        send({"type": "control_request", "request_id": "c1", "request": {"subtype": "can_use_tool", "tool_name": "Bash", "input": {"command": "echo probe-ok"}, "permission_suggestions": []}})
'''

FAKE_CODEX = r'''
import json, sys
assert sys.argv[1] == "app-server"
assert any(a.startswith("mcp_servers.desktop.command=") for a in sys.argv), "the desktop tools were not handed over"
def send(o): sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
for line in sys.stdin:
    m = json.loads(line)
    meth, rid, p = m.get("method"), m.get("id"), m.get("params") or {}
    if meth is None:  # the answer to our approval request
        ok = m["result"]["decision"] == "accept"
        send({"method": "item/completed", "params": {"threadId": "th", "turnId": "tu", "item": {"type": "commandExecution", "id": "c1", "command": "echo probe-ok", "aggregatedOutput": "probe-ok\n" if ok else "", "exitCode": 0 if ok else None, "status": "completed" if ok else "declined", "durationMs": 5}}})
        send({"method": "item/agentMessage/delta", "params": {"threadId": "th", "turnId": "tu", "itemId": "a2", "delta": "Done."}})
        send({"method": "thread/tokenUsage/updated", "params": {"threadId": "th", "turnId": "tu", "tokenUsage": {"last": {"totalTokens": 500}, "total": {"totalTokens": 500}, "modelContextWindow": 1000}}})
        send({"method": "turn/completed", "params": {"threadId": "th", "turn": {"id": "tu", "status": "completed", "items": []}}})
    elif meth == "initialize":
        send({"id": rid, "result": {"userAgent": "fake"}})
    elif meth == "account/read":
        send({"id": rid, "result": {"account": {"type": "chatgpt"}, "requiresOpenaiAuth": True}})
    elif meth == "model/list":
        send({"id": rid, "result": {"data": [{"id": "g", "model": "g-1", "displayName": "G One", "isDefault": True, "hidden": False,
                                             "defaultReasoningEffort": "medium",
                                             "supportedReasoningEfforts": [{"reasoningEffort": "medium", "description": "Balanced"},
                                                                           {"reasoningEffort": "high", "description": "Deeper"}]}]}})
    elif meth == "thread/start":
        assert p["approvalPolicy"] == "on-request" and p["sandbox"] == "workspace-write", p
        send({"id": rid, "result": {"thread": {"id": "th"}}})
    elif meth == "turn/start":
        assert p["input"][0]["text"] == "run /tmp/x", p  # the @file: chip arrives as a path
        send({"id": rid, "result": {"turn": {"id": "tu", "status": "inProgress"}}})
        send({"method": "turn/started", "params": {"threadId": "th", "turn": {"id": "tu"}}})
        send({"method": "item/agentMessage/delta", "params": {"threadId": "th", "turnId": "tu", "itemId": "a1", "delta": "Running it."}})
        send({"method": "item/started", "params": {"threadId": "th", "turnId": "tu", "item": {"type": "commandExecution", "id": "c1", "command": "echo probe-ok", "cwd": "/"}}})
        send({"id": 900, "method": "item/commandExecution/requestApproval", "params": {"threadId": "th", "turnId": "tu", "itemId": "c1", "command": "echo probe-ok"}})
    elif rid is not None:
        if meth == "thread/settings/update":
            import os
            with open(os.path.join(os.environ["HOME"], "codex-settings.jsonl"), "a") as log:
                log.write(json.dumps(p) + "\n")
        send({"id": rid, "result": {}})
'''


class Shell:
    """The sidebar's side of the wire, as AgentService plays it."""

    def __init__(self, backend, path_dir, home):
        env = dict(os.environ, PATH=f"{path_dir}:{os.environ['PATH']}", HOME=home, ANTHROPIC_API_KEY="must-not-arrive",
                   XDG_STATE_HOME=os.path.join(home, "state"))
        self.proc = subprocess.Popen([sys.executable, str(AGENT / "bridge.py"), backend], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        self.frames = queue.Queue()
        self.seen = []
        self.n = 0
        threading.Thread(target=lambda: [self.frames.put(json.loads(l)) for l in self.proc.stdout], daemon=True).start()

    def send(self, frame):
        self.proc.stdin.write(json.dumps(frame) + "\n")
        self.proc.stdin.flush()

    def call(self, method, params=None):
        self.n += 1
        rid = f"ii-{self.n}"
        self.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}})
        return self.until(lambda f: f.get("id") == rid and "method" not in f)

    def until(self, done, timeout=20):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                frame = self.frames.get(timeout=0.2)
            except queue.Empty:
                if self.proc.poll() is not None:
                    raise AssertionError(f"bridge exited {self.proc.returncode}: {self.proc.stderr.read()[-800:]}")
                continue
            self.seen.append(frame)
            if frame.get("method") == "approval":
                self.send({"jsonrpc": "2.0", "id": frame["id"], "result": {"choice": "once", "all": False}})
            if done(frame):
                return frame
        raise AssertionError(f"timed out; saw {[f.get('method') or f.get('id') for f in self.seen][-12:]}")

    def events(self):
        return [f["params"]["type"] for f in self.seen if f.get("method") == "event"]

    def close(self):
        self.proc.stdin.close()
        self.proc.wait(timeout=10)


def turn_end(frame):
    return frame.get("method") == "event" and frame["params"]["type"] in ("error", "message.complete") \
        and (frame["params"]["payload"].get("status") or frame["params"]["type"] == "error")


with tempfile.TemporaryDirectory() as tmp:
    fakes = pathlib.Path(tmp, "bin")
    fakes.mkdir()
    for name, body in (("claude", FAKE_CLAUDE), ("codex", FAKE_CODEX)):
        script = fakes / name
        script.write_text(f"#!{sys.executable}\n" + textwrap.dedent(body))
        script.chmod(0o755)
    home = pathlib.Path(tmp, "home")
    home.mkdir()

    for backend in ("claude", "codex"):
        shell = Shell(backend, fakes, str(home))
        ready = shell.until(lambda f: f.get("method") == "event" and f["params"]["type"] == "ready")
        caps = ready["params"]["payload"]["capabilities"]
        assert caps.get("retry") and caps.get("undo") and caps.get("screen"), f"{backend}: capabilities lost: {caps}"
        created = shell.call("session.create")["result"]
        assert created["session_id"] and created["session_id"] == created["stored_session_id"], f"{backend}: {created}"
        if backend == "claude":
            assert created["info"]["model"] == "Fable 9 (default)", "Claude: the default model is not named by what it resolves to"
        shell.call("prompt.submit", {"session_id": created["session_id"], "text": "run @file:/tmp/x"})
        shell.until(turn_end)
        events = shell.events()
        assert "approval" in [f.get("method") for f in shell.seen], f"{backend}: the approval was never asked"
        steps = [e for e in events if e in ("message.start", "message.complete", "tool.start", "tool.complete")]
        assert steps == ["message.start", "tool.start", "tool.complete", "message.complete", "message.start", "message.complete"], \
            f"{backend}: the turn's steps are wrong: {steps}"
        done = next(f for f in shell.seen if f.get("method") == "event" and f["params"]["type"] == "tool.complete")
        result = done["params"]["payload"]["result"]
        assert "probe-ok" in (result if isinstance(result, str) else result.get("output", "")), f"{backend}: tool result lost: {result}"
        assert events.count("error") == 0, f"{backend}: the turn failed: {shell.seen[-3:]}"
        bad = [f for f in shell.seen if f.get("method") == "event" and "id" in f]
        assert not bad, f"{backend}: an event carries an id, which the shell reads as an answer"
        assert shell.call("session.status")["result"]["info"]["approval_mode"] == "smart"
        mark = len(shell.seen)
        shell.call("config.set", {"key": "approvals.mode", "value": "manual"})
        # The echo can land before the answer; the shell takes either order.
        echoed = [f for f in shell.seen[mark:] if f.get("method") == "event" and f["params"]["type"] == "session.info"]
        assert echoed and echoed[-1]["params"]["payload"]["approval_mode"] == "manual", \
            f"{backend}: a mode change is not echoed back as session.info"
        # Effort: the levels are the model's own, a change reaches the CLI live and
        # comes back as session.info, and a level the model lacks is refused.
        options = shell.call("model.options")["result"]
        caps = next(iter(options["providers"][0]["capabilities"].values()))
        levels = [e["id"] for e in caps["efforts"]]
        assert levels == (["default", "low", "high"] if backend == "claude" else ["default", "medium", "high"]), f"{backend}: effort levels {levels}"
        # Nothing pinned yet: Default, which is the CLI's own setting, not a level of ours.
        assert created["info"].get("effort") == "default", f"{backend}: starting effort {created['info']}"
        assert options["model"].endswith("(default)") and options["model"] in options["providers"][0]["models"], \
            f"{backend}: the unpinned model is not the picker's Default row: {options['model']}"
        mark = len(shell.seen)
        assert "result" in shell.call("effort.set", {"effort": "high"}), f"{backend}: effort.set failed"
        echoed = [f for f in shell.seen[mark:] if f.get("method") == "event" and f["params"]["type"] == "session.info"]
        assert echoed and echoed[-1]["params"]["payload"]["effort"] == "high", f"{backend}: an effort change is not echoed back"
        assert shell.call("effort.set", {"effort": "ultra"}).get("error"), f"{backend}: a level the model lacks was accepted"
        log = home / ("claude-controls.jsonl" if backend == "claude" else "codex-settings.jsonl")
        sent = [json.loads(l) for l in log.read_text().splitlines()]
        if backend == "claude":
            assert {"subtype": "apply_flag_settings", "settings": {"effortLevel": "high"}} in sent, \
                f"Claude: the effort did not reach the running CLI through apply_flag_settings: {sent}"
        else:
            assert any(u.get("effort") == "high" for u in sent), f"Codex: the effort did not reach the thread: {sent}"
        unknown = shell.call("no.such.method")
        assert unknown.get("error"), f"{backend}: an unknown request must be answered with an error"
        shell.close()
        assert shell.proc.returncode == 0, f"{backend}: the bridge did not exit cleanly"

    # Not installed: exit 127 and say so, so the shell stops instead of retrying.
    empty = pathlib.Path(tmp, "empty")
    empty.mkdir()
    gone = subprocess.run([sys.executable, str(AGENT / "bridge.py"), "claude"], input="", capture_output=True, text=True,
                          env=dict(os.environ, PATH=f"{empty}:/usr/bin/nonexistent", HOME=str(home)))
    assert gone.returncode == 127 and "[agent-missing]" in gone.stderr, f"a missing CLI must exit 127: {gone.returncode} {gone.stderr[-200:]}"

# ── 6. the desktop tools ─────────────────────────────────────────────────────

hello = [{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
         {"jsonrpc": "2.0", "method": "notifications/initialized"},
         {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
         {"jsonrpc": "2.0", "id": 3, "method": "nope"}]
mcp = subprocess.run([sys.executable, str(AGENT / "desktop_mcp.py")], input="".join(json.dumps(m) + "\n" for m in hello),
                     capture_output=True, text=True, timeout=30)
replies = [json.loads(l) for l in mcp.stdout.splitlines()]
assert [r["id"] for r in replies] == [1, 2, 3], f"desktop_mcp: a notification was answered, or a request was not: {replies}"
assert replies[0]["result"]["protocolVersion"] == "2025-06-18", "desktop_mcp: the client's protocol version is not echoed"
tools = {t["name"]: t for t in replies[1]["result"]["tools"]}
read_only = {n for n, t in tools.items() if (t.get("annotations") or {}).get("readOnlyHint")}
assert set(cb.DESKTOP_READ_ONLY) == read_only, \
    f"the tools Claude runs unasked ({cb.DESKTOP_READ_ONLY}) must be exactly the read-only ones ({read_only})"
assert "click" not in read_only and "ipc_call" not in read_only, "acting on the desktop must go through approval"
assert replies[2].get("error", {}).get("code") == -32601

# ── 7. the page offers only what the agent can do ────────────────────────────

svc = (QS / "services/AgentService.qml").read_text()
page = (QS / "modules/ii/sidebarPolicies/Agent.qml").read_text()
message = (QS / "modules/ii/sidebarPolicies/agent/AgentMessage.qml").read_text()
assert 'root.can("retry")' in svc and 'root.can("undo")' in svc, "AgentService: retry/undo run for an agent that cannot"
assert 'AgentService.can("retry")' in message and 'AgentService.can("undo")' in message, "AgentMessage: retry/edit offered regardless"
assert message.count("visible: AgentService.ttsAvailable") == 1, "AgentMessage: read-aloud offered without a voice"
assert "visible: AgentService.dictationInstalled" in page, "Agent.qml: the mic is offered without whisper.cpp"
assert "visible: AgentService.effortOptions.length > 0" in page, "Agent.qml: the effort chip shows for a model with no effort levels"
assert '"python3", root.bridgeScript, root.backend?.id' in svc, "AgentService: the bridge is not what runs"
assert "exitCode === 127 || exitCode === 78" in svc, "AgentService: a missing or signed-out agent would be restarted in a loop"
for gone in ("gateway.sh", "hermes", "Hermes", "subagent.list", "spawn_tree", "prompt.background", "yolo"):
    assert gone not in svc, f"AgentService: the Hermes-era `{gone}` is back"

print("ok: the connector steps answers right, speaks both CLIs, and the page offers only what the agent can do")
