#!/usr/bin/env python3
"""The sidebar's agent connector speaks all three agents correctly, without spending a token.

scripts/agent/bridge.py translates between the sidebar and Claude Code, Codex or
Google's Antigravity ACP server.
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
  * Antigravity's ACP the same way, against a fake server: its sign-in link lands
    in the chat instead of a browser opening by itself, its titles become tool
    names the rows know, its questions take only its own choices, the thinking
    level and mode reach the session, history replays into rows, a chat is
    deleted with exactly its own files, and a message typed mid-reply waits.
  * Plan limits, the usage button's numbers: each agent's own report (Claude
    Code's get_usage and its streamed rate_limit_event, Codex's rateLimits read
    and partial updates, Antigravity's /usage, whose reply must never reach the
    chat) becomes the same windows, and only the ones limiting the model in use
    count toward the button.
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
import antigravity_backend as ab  # noqa: E402
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

# ── 4a. plan limits, read from each agent's own report ───────────────────────

assert [bridge.window_label(m) for m in (300, 10080, 43200, 1440, 120)] == ["5-hour", "Weekly", "Monthly", "Daily", "2-hour"]
# Claude Code's get_usage, as it answered live: the `limits` list first.
claude_usage = {"subscription_type": "team", "rate_limits_available": True, "rate_limits": {
    "five_hour": {"utilization": 67, "resets_at": "2026-10-19T18:50:00+00:00"},
    "limits": [{"kind": "session", "group": "session", "percent": 67, "resets_at": "2026-10-19T18:50:00+00:00", "scope": None},
               {"kind": "weekly_all", "group": "weekly", "percent": 8, "resets_at": "2026-10-26T07:00:00+00:00", "scope": None},
               {"kind": "weekly_scoped", "group": "weekly", "percent": 1, "resets_at": "2026-10-26T07:00:00+00:00",
                "scope": {"model": {"display_name": "Fable"}}}],
    "extra_usage": {"is_enabled": False}}}
limits = cb.claude_limits(claude_usage, "Opus 9")
assert limits["plan"] == "Claude Team" and [(w["label"], w["used"], w["minutes"]) for w in limits["windows"]] == \
    [("5-hour", 67, 300), ("Weekly", 8, 10080), ("Weekly · Fable", 1, 10080)], f"Claude limits: {limits}"
assert limits["windows"][0]["resets_at"] == 1792435800, "Claude limits: the reset time is not epoch seconds"
assert [w["counts"] for w in limits["windows"]] == [True, True, False], "Claude limits: a window scoped to another model counts"
assert cb.claude_limits(claude_usage, "Fable 9")["windows"][2]["counts"], "Claude limits: the model's own weekly window must count"
assert cb.claude_limits({"rate_limits_available": False})["notes"], "Claude limits: an API-key login must say why there is nothing"
# Codex's account/rateLimits/read, as it answered live.
codex_rate = {"limitId": "codex", "planType": "plus", "primary": {"usedPercent": 0, "windowDurationMins": 300, "resetsAt": 1792452216},
              "secondary": {"usedPercent": 3, "windowDurationMins": 10080, "resetsAt": 1792896029}}
limits = xb.codex_limits(codex_rate, {"availableCount": 2})
assert limits["plan"] == "ChatGPT Plus" and [(w["label"], w["used"]) for w in limits["windows"]] == [("5-hour", 0), ("Weekly", 3)], limits
assert any("2 free limit resets" in n for n in limits["notes"]), "Codex limits: its free resets went unmentioned"
assert xb.codex_limits({"planType": "free", "primary": {"usedPercent": 40}})["windows"][0]["label"] == "Monthly", \
    "Codex limits: a Free plan's one window is its monthly allowance"
merged = xb.merge_limits(codex_rate, {"limitId": "codex", "primary": {"usedPercent": 9, "windowDurationMins": 300}, "secondary": None})
assert merged["primary"]["usedPercent"] == 9 and merged["secondary"]["usedPercent"] == 3, "Codex limits: a partial update dropped a window"
assert xb.merge_limits(codex_rate, {"limitId": "codex_spark", "primary": {"usedPercent": 99}}) is codex_rate, \
    "Codex limits: a model-specific allowance replaced the plan's"
# Antigravity's /usage, as its server answered live.
report = """### Session Usage
- **Session total:** data not available yet

### Quota Limits
- **Gemini Models**
  *(Models within this group: Gemini Flash, Gemini Pro)*
  - **Weekly Limit Remaining:** 100% remaining (resets Oct 26, 2026, 17:52 UTC)
  - **Five Hour Limit Remaining:** 99% remaining (resets Oct 19, 2026, 22:52 UTC)
- **Claude and GPT models**
  *(Models within this group: Claude Opus, Claude Sonnet, GPT-OSS)*
  - **Weekly Limit Remaining:** 98% remaining (resets Oct 20, 2026, 23:37 UTC)
  - **Five Hour Limit Remaining:** 100% remaining (resets Oct 19, 2026, 23:21 UTC)"""
limits = ab.antigravity_limits(report, "Gemini 3.8 Flash", "Google AI Pro")
assert [(w["group"], w["label"], w["used"], w["counts"]) for w in limits["windows"]] == [
    ("Gemini", "5-hour", 1, True), ("Gemini", "Weekly", 0, True),
    ("Claude and GPT", "5-hour", 0, False), ("Claude and GPT", "Weekly", 2, False)], f"Antigravity limits: {limits['windows']}"
assert limits["windows"][0]["resets_at"] == 1792450320, "Antigravity limits: the reset time is misread"
assert ab.antigravity_limits("### Quota Limits\n- Unable to retrieve quota status (offline)")["notes"] == ["Unable to retrieve quota status (offline)"]

# ── 4b. Antigravity's ACP updates ────────────────────────────────────────────

# ACP sends a title, not a tool name; the rows are keyed on the name.
assert ab.tool_identity({"title": "Running view_file", "kind": "read", "rawInput": {"AbsolutePath": "/a"}}) == ("view_file", {"path": "/a"})
assert ab.tool_identity({"title": "Run write_to_file?", "kind": "edit", "rawInput": {"TargetFile": "/b", "CodeContent": "x"}}) == \
    ("write_to_file", {"path": "/b", "content": "x"}), "Antigravity: a call waiting on approval lost its name or arguments"
name, args = ab.tool_identity({"title": "ls -la", "kind": "execute", "rawInput": {"CommandLine": "ls -la", "Cwd": "/h"}})
assert name == "run_command" and args["command"] == "ls -la" and args["cwd"] == "/h", (name, args)
assert ab.tool_identity({"title": "desktop_see", "kind": "other", "rawInput": {"arguments": {"Class": "kitty"}, "Class": "kitty"},
                         "_meta": {"mcp": {"tool": "see", "server": "desktop"}}}) == ("see", {"class": "kitty"}), \
    "Antigravity: an MCP call must be named by its own tool, with its arguments once"
assert ab.tool_identity({"title": "Running start_subagent", "kind": "other"})[0] == "invoke_subagent"
assert ab.tool_result({"status": "completed", "rawOutput": {"combinedOutput": "a\r\nb\r\n", "exitCode": 1}}) == {"output": "a\nb\n", "exit_code": 1}, \
    "Antigravity: a command's output must arrive as the row's output, with plain newlines"
assert ab.tool_result({"status": "failed", "rawOutput": "no such file"}) == {"error": "no such file"}
assert ab.tool_result({"status": "completed", "content": [{"type": "content", "content": {"type": "text", "text": "hi"}}]}) == "hi"
assert ab.approval_text({"kind": "execute", "title": "rm -rf /tmp/x"}, "run_command") == "Run a command", \
    "Antigravity: a command's approval must not just repeat the command (the card shows it already)"
assert ab.approval_text({"_meta": {"mcp": {"tool": "click", "server": "desktop"}}}, "click") == "Use the desktop tool “click”"
replay = ab.Replay()
for update in ({"sessionUpdate": "user_message_chunk", "content": {"type": "text", "text": "hel"}},
               {"sessionUpdate": "user_message_chunk", "content": {"type": "text", "text": "lo"}},
               {"sessionUpdate": "tool_call", "toolCallId": "interaction_1", "title": "Pick one"},
               {"sessionUpdate": "tool_call", "toolCallId": "c1", "title": "Running view_file", "kind": "read", "rawInput": {"AbsolutePath": "/a"}},
               {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "done"}}):
    replay.add(update)
rows, _ = replay.result()
assert [(r["role"], r.get("text") or r.get("name")) for r in rows] == [("user", "hello"), ("tool", "view_file"), ("assistant", "done")], \
    f"Antigravity: a replayed chat must fold into rows, chunks joined, its questions left out: {rows}"

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
               {"percentage": 12.4, "totalTokens": 1200, "maxTokens": 10000, "categories": [{"name": "Messages", "tokens": 900}]} if sub == "get_context_usage" else \
               {"subscription_type": "max", "rate_limits_available": True, "rate_limits": {"limits": [
                   {"kind": "session", "group": "session", "percent": 40, "resets_at": "2030-01-01T00:00:00+00:00"},
                   {"kind": "weekly_all", "group": "weekly", "percent": 10, "resets_at": "2030-01-05T00:00:00+00:00"}]}} if sub == "get_usage" else {}
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
        send({"type": "rate_limit_event", "session_id": sid, "uuid": "u", "rate_limit_info": {"status": "allowed", "unifiedWindows": {
            "five_hour": {"utilization": 0.42, "resetsAt": 1893456000}}}})
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
    elif meth == "account/rateLimits/read":
        send({"id": rid, "result": {"rateLimits": {"limitId": "codex", "planType": "pro", "primary": {"usedPercent": 20, "windowDurationMins": 300, "resetsAt": 1893456000},
                                                   "secondary": {"usedPercent": 5, "windowDurationMins": 10080, "resetsAt": 1893800000}}}})
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
        send({"method": "account/rateLimits/updated", "params": {"rateLimits": {"limitId": "codex", "primary": {"usedPercent": 21, "windowDurationMins": 300}}}})
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

FAKE_ANTIGRAVITY = r'''
import json, os, sys, threading, time
assert os.environ.get("BROWSER") == "true", "the server could open a browser by itself"
assert "GEMINI_API_KEY" not in os.environ, "an ambient API key reached the server"
log = open(os.path.join(os.environ["HOME"], "acp.jsonl"), "a")
def send(o): sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
def update(sid, u): send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": sid, "update": u}})
SID = "11111111-2222-4333-8444-555555555555"
config = {"model": "flash", "thinking_level": "high", "mode": "default"}
def options():
    return [{"id": "model", "type": "select", "currentValue": config["model"], "options": [{"value": "flash", "name": "Flash"}, {"value": "pro", "name": "Pro"}]},
            {"id": "thinking_level", "type": "select", "currentValue": config["thinking_level"], "options": [{"value": "low", "name": "Low"}, {"value": "high", "name": "High"}]},
            {"id": "mode", "type": "select", "currentValue": config["mode"], "options": [{"value": m, "name": m} for m in ("default", "auto_edit", "yolo")]}]
prompting = {}
asked = {}
def finish(rid, reason="end_turn"):
    send({"jsonrpc": "2.0", "id": rid, "result": {"stopReason": reason}})
for line in sys.stdin:
    m = json.loads(line)
    log.write(line); log.flush()
    meth, rid, p = m.get("method"), m.get("id"), m.get("params") or {}
    if meth is None:  # the client's answer to our request
        kind, prompt_id = asked.pop(m["id"])
        outcome = m["result"]["outcome"]
        if kind == "permission":
            ok = outcome.get("optionId") == "allow"
            update(SID, {"sessionUpdate": "tool_call_update", "toolCallId": "c1", "status": "completed" if ok else "failed",
                         "rawOutput": {"combinedOutput": "probe-ok\r\n", "exitCode": 0} if ok else "denied"})
            update(SID, {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "Done."}})
            update(SID, {"sessionUpdate": "usage_update", "used": 250, "size": 1000})
        else:
            update(SID, {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "picked " + str(outcome.get("optionId"))}})
        finish(prompt_id)
    elif meth == "initialize":
        assert p["clientCapabilities"]["terminal"] is False
        send({"jsonrpc": "2.0", "id": rid, "result": {"protocolVersion": 1, "agentCapabilities": {"loadSession": True}}})
    elif meth == "authenticate":
        print("Open the following link to authenticate the ACP server: https://accounts.google.com/o/oauth2/v2/auth?state=x", file=sys.stderr, flush=True)
        time.sleep(0.3)  # the user signing in
        send({"jsonrpc": "2.0", "id": rid, "result": {"_meta": {"antigravity": {"tier": {"name": "Google AI Pro"}}}}})
    elif meth in ("session/new", "session/load"):
        desktop = next(s for s in p["mcpServers"] if s["name"] == "desktop")
        assert desktop["args"][0].endswith("desktop_mcp.py") and isinstance(desktop["env"], list), desktop
        assert p["_meta"]["antigravity"]["systemPrompt"]["append"], "the sidebar's note did not reach the session"
        if meth == "session/load":
            update(p["sessionId"], {"sessionUpdate": "user_message_chunk", "content": {"type": "text", "text": "old question"}})
            update(p["sessionId"], {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "old answer"}})
            send({"jsonrpc": "2.0", "id": rid, "result": {"configOptions": options()}})
        else:
            send({"jsonrpc": "2.0", "id": rid, "result": {"sessionId": SID, "configOptions": options()}})
    elif meth == "session/set_config_option":
        config[p["configId"]] = p["value"]
        send({"jsonrpc": "2.0", "id": rid, "result": {"configOptions": options()}})
    elif meth == "session/list":
        send({"jsonrpc": "2.0", "id": rid, "result": {"sessions": [{"sessionId": SID, "cwd": p.get("cwd"), "title": "Session 11111111"}]}})
    elif meth == "session/cancel":
        for prompt_id in list(prompting):
            update(SID, {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "The request was cancelled by the client."}})
            finish(prompting.pop(prompt_id), "cancelled")
    elif meth == "session/prompt":
        text = p["prompt"][0]["text"]
        if text.startswith("run"):
            update(SID, {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "Running it."}})
            call = {"toolCallId": "c1", "title": "echo probe-ok", "kind": "execute", "status": "pending", "rawInput": {"CommandLine": "echo probe-ok"}}
            update(SID, dict(call, sessionUpdate="tool_call"))
            asked[900] = ("permission", rid)
            send({"jsonrpc": "2.0", "id": 900, "method": "session/request_permission", "params": {"sessionId": SID, "toolCall": call, "options": [
                {"optionId": "allow_always", "name": "Allow Always (risky)", "kind": "allow_always", "_meta": {"agy.security.warning": {"message": "risky"}}},
                {"optionId": "allow", "name": "Allow", "kind": "allow_once"}, {"optionId": "deny", "name": "Deny", "kind": "reject_once"}]}})
        elif text.startswith("ask"):
            call = {"toolCallId": "interaction_ab", "title": "Which colour?", "status": "pending", "rawInput": {}}
            update(SID, dict(call, sessionUpdate="tool_call"))
            asked[901] = ("question", rid)
            send({"jsonrpc": "2.0", "id": 901, "method": "session/request_permission", "params": {"sessionId": SID, "toolCall": call, "options": [
                {"optionId": "1", "name": "Red", "kind": "allow_once"}, {"optionId": "2", "name": "Blue", "kind": "allow_once"}]}})
        elif text == "/usage":
            update(SID, {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "### Quota Limits\n- **Gemini Models**\n"}})
            update(SID, {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "  - **Five Hour Limit Remaining:** 70% remaining (resets Jan 01, 2030, 00:00 UTC)\n"}})
            finish(rid)
        elif text.startswith("slow"):
            prompting[rid] = rid
            update(SID, {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "1 2 3"}})
        else:
            update(SID, {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "echo: " + text}})
            finish(rid)
    elif rid is not None:
        send({"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": "unknown"}})
'''


class Shell:
    """The sidebar's side of the wire, as AgentService plays it."""

    def __init__(self, backend, path_dir, home, extra_env=None):
        env = dict(os.environ, PATH=f"{path_dir}:{os.environ['PATH']}", HOME=home, ANTHROPIC_API_KEY="must-not-arrive",
                   XDG_STATE_HOME=os.path.join(home, "state"), **(extra_env or {}))
        for key in ("XDG_DATA_HOME", "XDG_CACHE_HOME", "GEMINI_HOME"):
            env.pop(key, None)
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
            elif frame.get("method") == "clarify":
                self.send({"jsonrpc": "2.0", "id": frame["id"], "result": {"answer": (frame["params"].get("choices") or ["yes"])[-1]}})
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
        # Plan limits: the agent's own report, and its mid-turn news pushed as an event.
        pushed = [f["params"]["payload"] for f in shell.seen if f.get("method") == "event" and f["params"]["type"] == "usage.limits"]
        limits = shell.call("usage.limits", {"refresh": True})["result"]
        if backend == "claude":
            assert limits["plan"] == "Claude Max" and [(w["label"], w["used"]) for w in limits["windows"]] == [("5-hour", 40), ("Weekly", 10)], limits
            # The next turn's rate_limit_event moves the 5-hour window without asking again.
            mark = len(shell.seen)
            shell.call("prompt.submit", {"session_id": created["session_id"], "text": "run again"})
            shell.until(turn_end)
            moved = [f["params"]["payload"] for f in shell.seen[mark:] if f.get("method") == "event" and f["params"]["type"] == "usage.limits"]
            assert moved and moved[0]["windows"][0]["used"] == 42 and moved[0]["windows"][0]["resets_at"] == 1893456000, \
                f"Claude: a streamed rate_limit_event did not move the 5-hour window: {moved}"
        else:
            assert pushed and pushed[-1]["windows"][0]["used"] == 21, f"Codex: a rateLimits update was not passed on: {pushed}"
            assert limits["plan"] == "ChatGPT Pro" and [(w["label"], w["used"]) for w in limits["windows"]] == [("5-hour", 20), ("Weekly", 5)], limits
        assert caps.get("limits") is not False and ready["params"]["payload"]["capabilities"].get("limits"), f"{backend}: limits not offered"
        unknown = shell.call("no.such.method")
        assert unknown.get("error"), f"{backend}: an unknown request must be answered with an error"
        shell.close()
        assert shell.proc.returncode == 0, f"{backend}: the bridge did not exit cleanly"

    # Antigravity: Google's ACP server, played by a fake.
    server = fakes / "fake_agy_acp.py"
    server.write_text(f"#!{sys.executable}\n" + textwrap.dedent(FAKE_ANTIGRAVITY))
    server.chmod(0o755)
    shell = Shell("antigravity", fakes, str(home), {"AGENT_ANTIGRAVITY_SERVER": str(server), "GEMINI_API_KEY": "must-not-arrive"})
    ready = shell.until(lambda f: f.get("method") == "event" and f["params"]["type"] == "ready")
    caps = ready["params"]["payload"]["capabilities"]
    assert caps.get("clarify") and caps.get("effort") and caps.get("screen") and caps.get("images"), f"Antigravity: capabilities lost: {caps}"
    assert not (caps.get("retry") or caps.get("undo")), f"Antigravity: offered what ACP cannot do (no rewind): {caps}"
    created = shell.call("session.create")["result"]
    notices = [f["params"]["payload"]["message"] for f in shell.seen if f.get("method") == "event" and f["params"]["type"] == "notice"]
    assert any("https://accounts.google.com/" in n and "](" in n for n in notices), \
        f"Antigravity: the sign-in link must reach the chat as a link: {notices}"
    assert created["info"]["plan"] == "Google AI Pro" and created["info"]["model"] == "Flash" and created["info"]["effort"] == "high", \
        f"Antigravity: the chips must name what the session is on: {created['info']}"
    acp_log = home / "acp.jsonl"
    sent = lambda method: [json.loads(l)["params"] for l in acp_log.read_text().splitlines() if json.loads(l).get("method") == method]
    assert {"sessionId": created["session_id"], "configId": "mode", "value": "auto_edit"} in sent("session/set_config_option"), \
        "Antigravity: the sidebar's Smart mode did not reach the session as auto_edit"
    sid = created["session_id"]
    shell.call("prompt.submit", {"session_id": sid, "text": "run @file:/tmp/x"})
    shell.until(turn_end)
    approval = next(f for f in shell.seen if f.get("method") == "approval")["params"]
    assert approval["choices"] == ["once", "session", "deny"] and approval["command"] == "echo probe-ok", approval
    assert "risky" in approval["description"], "Antigravity: the server's warning on allowing a command for the session was dropped"
    assert sent("session/prompt")[0]["prompt"][0]["text"] == "run /tmp/x", "Antigravity: the @file: chip did not arrive as a path"
    steps = [e for e in shell.events() if e in ("message.start", "message.complete", "tool.start", "tool.complete")]
    assert steps == ["message.start", "tool.start", "tool.complete", "message.complete", "message.start", "message.complete"], \
        f"Antigravity: the turn's steps are wrong: {steps}"
    done = next(f for f in shell.seen if f.get("method") == "event" and f["params"]["type"] == "tool.complete")["params"]["payload"]
    assert done["result"] == {"output": "probe-ok\n", "exit_code": 0}, done
    start = next(f for f in shell.seen if f.get("method") == "event" and f["params"]["type"] == "tool.start")["params"]["payload"]
    assert start["name"] == "run_command" and start["args"]["command"] == "echo probe-ok", start
    # Its own question: the card takes only its choices, and the pick goes back as that option.
    mark = len(shell.seen)
    shell.call("prompt.submit", {"session_id": sid, "text": "ask me"})
    shell.until(turn_end)
    question = next(f for f in shell.seen[mark:] if f.get("method") == "clarify")["params"]
    assert question["choices"] == ["Red", "Blue"] and question["allow_custom"] is False, question
    assert not any(f.get("method") == "event" and f["params"]["type"] == "tool.start" for f in shell.seen[mark:]), \
        "Antigravity: its question showed up as a tool row as well as the card"
    replies = "".join(f["params"]["payload"].get("text", "") for f in shell.seen[mark:] if f.get("method") == "event" and f["params"]["type"] == "message.delta")
    assert replies == "picked 2", f"Antigravity: the chosen option did not go back as its id: {replies}"
    # Effort and model reach the session's config options.
    options = shell.call("model.options")["result"]
    # No "Default" row: the server has no default-model setting, so one would only
    # repeat the first model under a second name.
    assert options["providers"][0]["models"] == ["Flash", "Pro"], options
    levels = [e["id"] for e in options["providers"][0]["capabilities"]["Flash"]["efforts"]]
    assert levels == ["low", "high"], f"Antigravity: thinking levels {levels}"
    shell.call("effort.set", {"effort": "low"})
    assert {"sessionId": sid, "configId": "thinking_level", "value": "low"} in sent("session/set_config_option")
    assert shell.call("effort.set", {"effort": "max"}).get("error"), "Antigravity: a level the model lacks was accepted"
    shell.call("model.set", {"model": "Pro"})
    assert {"sessionId": sid, "configId": "model", "value": "pro"} in sent("session/set_config_option")
    assert shell.call("session.status")["result"]["info"]["model"] == "Pro"
    # A message typed mid-reply waits for it; a stop ends the reply without the
    # server's "cancelled by the client" glued to it.
    mark = len(shell.seen)
    shell.call("prompt.submit", {"session_id": sid, "text": "slow count"})
    queued = shell.call("prompt.submit", {"session_id": sid, "text": "next"})["result"]
    assert queued["status"] == "queued", f"Antigravity: a message typed mid-reply must wait for it: {queued}"
    # Sent, not called: the interrupted end can arrive before the interrupt's own answer.
    shell.send({"jsonrpc": "2.0", "id": "ii-stop", "method": "session.interrupt", "params": {}})
    shell.until(lambda f: turn_end(f) and f["params"]["payload"].get("status") == "interrupted")
    text = "".join(f["params"]["payload"].get("text", "") for f in shell.seen[mark:] if f.get("method") == "event" and f["params"]["type"] == "message.delta")
    assert text == "1 2 3", f"Antigravity: the stopped reply is wrong: {text!r}"
    # Plan limits: asked with the server's own /usage between replies, and its
    # reply kept out of the chat entirely.
    mark = len(shell.seen)
    limits = shell.call("usage.limits", {"refresh": True})["result"]
    assert [(w["label"], w["used"]) for w in limits["windows"]] == [("5-hour", 30)] and limits["plan"] == "Google AI Pro", limits
    assert not any(f.get("method") == "event" and f["params"]["type"] in ("message.start", "message.delta", "session.title")
                   for f in shell.seen[mark:]), "Antigravity: asking for the limits showed up in the chat"
    # History: listed with the first thing asked, replayed into rows, deleted with its own files.
    convo = home / ".gemini/antigravity-acp/conversations"
    convo.mkdir(parents=True)
    for suffix in (".db", ".meta"):
        (convo / f"{sid}{suffix}").write_text("x")
    (convo / "keep.db").write_text("x")
    listed = shell.call("session.list", {"limit": 10})["result"]["sessions"]
    assert [r["id"] for r in listed] == [sid] and listed[0]["title"] == "run /tmp/x", f"Antigravity: history rows {listed}"
    resumed = shell.call("session.resume", {"session_id": sid})["result"]
    assert [(r["role"], r["text"]) for r in resumed["messages"]] == [("user", "old question"), ("assistant", "old answer")], resumed
    assert not any(f.get("method") == "event" and f["params"]["type"] == "message.delta" and "old answer" in f["params"]["payload"].get("text", "")
                   for f in shell.seen), "Antigravity: a replayed chat streamed into the live reply"
    shell.call("session.delete", {"session_id": sid})
    assert sorted(p.name for p in convo.iterdir()) == ["keep.db"], "Antigravity: delete removed the wrong files"
    assert shell.call("session.delete", {"session_id": "../../etc"}).get("error"), "Antigravity: a delete took a path"
    shell.close()
    assert shell.proc.returncode == 0, "Antigravity: the bridge did not exit cleanly"

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
clarify = (QS / "modules/ii/sidebarPolicies/agent/AgentClarifyCard.qml").read_text()
assert "root.current?.allow_custom ?? true" in clarify and "visible: !root.multiSelect && root.typedAnswer" in clarify, \
    "AgentClarifyCard: a typed answer is offered to an agent that only takes its own choices"
assert '"antigravity-server"' in svc and "b.firstUse && !serverHere" in svc, \
    "AgentService: Antigravity is not offered, or not told apart from an install still to download"
assert "AgentService.setupText.length > 0" in page, "Agent.qml: a first-use download or sign-in wait shows nothing"
usage = (QS / "modules/ii/sidebarPolicies/agent/AgentUsageMeter.qml").read_text()
assert "AgentUsageMeter {}" in page and "AgentContextMeter" not in page, "Agent.qml: the composer lost its usage button"
assert "AgentService.refreshUsageLimits(true)" in usage and "window.counts" in usage, \
    "AgentUsageMeter: opening it must ask again, and the ring must follow only windows that limit the model in use"
# The usage button replaced the context pill outright (the owner's call): nothing of
# the context window is drawn, and no backend spends a request reporting it.
assert "Context window" not in usage and "contextPercent" not in usage and "contextPercent" not in svc, \
    "AgentUsageMeter: the context window is back in the usage button"
for name in ("claude_backend.py", "codex_backend.py", "antigravity_backend.py"):
    assert "session.usage" not in (AGENT / name).read_text(), f"{name}: still reports the context window nobody draws"
assert 'case "usage.limits"' in svc and "root.refreshUsageLimits(false)" in svc, "AgentService: limits are never fetched or never updated"
for gone in ("gateway.sh", "hermes", "Hermes", "subagent.list", "spawn_tree", "prompt.background", "yolo"):
    assert gone not in svc, f"AgentService: the Hermes-era `{gone}` is back"

print("ok: the connector steps answers right, speaks all three agents, and the page offers only what the agent can do")
