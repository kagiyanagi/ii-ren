#!/usr/bin/env python3
"""The agent says so when it is blocked on you, and takes it back once it is not.

A turn parked on an approval or a question goes nowhere until it is answered, and
only replies used to notify: with the panel shut, the agent sat waiting and nothing
said so. The waiting notification is lifted out of AgentService and run under node:

- It is sent only when the card is not on screen, and closes once the request is
  answered, replaced, or its card comes on screen -- including the answer that
  lands before notify-send has printed the id it is closed by.
- The body is the command itself, escaped (the server renders markup and a command
  is full of `<`, `>`, `&`), after `--` (a command can start with a dash).

    python3 tools/check-agent-waiting-notice.py
"""
import json
import re
import subprocess
from pathlib import Path

svc = (Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/services/AgentService.qml").read_text()


def block(src, head):
    """The body of the `{ ... }` that follows `head`."""
    i = src.index("{", src.index(head)) + 1
    depth = 1
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return src[i:j]
    raise AssertionError(f"unbalanced after {head!r}")


handler = block(svc, "function _handleServerRequest(")
for method, flag in (("approval", "true"), ("clarify", "false")):
    case = handler[handler.index(f'case "{method}":'):]
    case = case[:case.index("break;")]
    assert f"root.notifyWaiting(request, {flag})" in case, f"a {method} request no longer notifies"
for prop in ("PendingApproval", "PendingClarify", "ViewingAgent"):
    assert re.search(rf"on{prop}Changed:\s*root\._closeAnsweredNotices\(\)", svc), \
        f"on{prop}Changed no longer closes the waiting notification"
read = block(block(svc, "property Component waitingNotice:"), "onRead: line =>")
assert "root._closeAnsweredNotices()" in read, "the id arriving no longer closes an already answered request"

notify = block(svc, "function notifyWaiting(")
close = block(svc, "function _closeAnsweredNotices(")
got = json.loads(subprocess.run(["node", "-e", f"""
const discarded = [];
const Notifications = {{ idOffset: 100, discardNotification: id => discarded.push(id) }};
const Config = {{ options: {{ agent: {{ notifyWhenAway: true }} }} }};
const Translation = {{ tr: s => ({{ arg: a => s.replace("%1", a), toString: () => s }}) }};
const StringUtils = {{ escapeHtml: s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }};
const console = {{ log() {{}} }};
const root = {{
    agentName: "Antigravity", notifyIconPath: "/i.svg", viewingAgent: false,
    pendingApproval: null, pendingClarify: null, _waitingNotices: [],
    waitingNotice: {{ createObject: (_, p) => ({{ srq: p.srq, serverId: -1, closed: false, command: [], running: false }}) }},
}};
root._closeAnsweredNotices = function () {{ {close} }};
root.notifyWaiting = function (request, approval) {{ {notify} }};
const out = {{}};

// Answered before the id came back: closed the moment it arrives.
root.pendingApproval = {{ srq: 1, command: "-rf <x> && y" }};
root.notifyWaiting(root.pendingApproval, true);
const first = root._waitingNotices[0];
out.command = first.command;
out.running = first.running;
root.pendingApproval = null; root._closeAnsweredNotices();
out.beforeId = discarded.slice();
first.serverId = 7; root._closeAnsweredNotices();
out.afterId = discarded.slice();
root._closeAnsweredNotices();
out.once = discarded.length;

// Still waiting: stays up. Its card on screen: closed.
root.pendingClarify = {{ srq: 2, questions: [{{ question: "Which one?" }}] }};
root.notifyWaiting(root.pendingClarify, false);
const second = root._waitingNotices[1];
second.serverId = 8; root._closeAnsweredNotices();
out.waiting = discarded.length;
out.question = second.command[second.command.length - 1];
root.viewingAgent = true; root._closeAnsweredNotices();
out.onScreen = discarded.slice();

// Asked while its card is already on screen: no notification at all.
root.notifyWaiting({{ srq: 3, command: "ls" }}, true);
out.count = root._waitingNotices.length;
process.stdout.write(JSON.stringify(out));
"""], capture_output=True, text=True, check=True).stdout)

cmd = got["command"]
assert got["running"], "the waiting notification is built but never sent"
assert cmd[0] == "notify-send" and "--print-id" in cmd and "--wait" in cmd, "notify-send no longer prints the id it is closed by"
assert "--" in cmd and cmd.index("--") == len(cmd) - 3, "the summary and body are not after `--`; a command starting with a dash is read as an option"
assert cmd[-1] == "-rf &lt;x&gt; &amp;&amp; y", f"the body is not the escaped command: {cmd[-1]!r}"
assert cmd[cmd.index("-t") + 1] == "0", "the notification times out while the agent is still waiting"
assert got["beforeId"] == [], "closed with no id to close it by"
assert got["afterId"] == [107], f"an answer that beat the id left the notification up: {got['afterId']}"
assert got["once"] == 1, "one notification closed more than once"
assert got["waiting"] == 1, "a request still waiting had its notification closed"
assert got["question"] == "Which one?", f"a question's notification does not say what it asks: {got['question']!r}"
assert got["onScreen"] == [107, 108], "the notification stays up with its card on screen"
assert got["count"] == 2, "notified about a request whose card is already on screen"

print("ok: a blocked agent notifies, says what it wants, and closes the notification once answered")
