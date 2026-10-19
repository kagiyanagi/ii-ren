#!/usr/bin/env python3
"""The agent's history sheet survives a refresh and grows out of the button that
opens it.

None of this shows in a still frame:
- The list was a plain JS array rebuilt from AgentService on every refresh, so
  every delegate was destroyed on every pass and every row re-ran its entrance.
  It is a keyed ScriptModel now; this runs the `rows` builder under node against
  two refreshes of fresh objects and asserts the keys match and are unique.
- A keyed ScriptModel still hands delegates over by position when rows shift, so
  a DelegateChooser's per-kind pick goes stale; the delegate picks by kind itself.
- The sheet scaled from `Item.Top` while its button sits at the right end of the
  composer row, below it.
"""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
P = ROOT / "dots/.config/quickshell/ii/modules/ii/sidebarPolicies"
H = P / "agent"
history = (H / "AgentHistoryPanel.qml").read_text()
row = (H / "AgentHistoryRow.qml").read_text()
button = (H / "AgentIconButton.qml").read_text()
page = (P / "Agent.qml").read_text()


def block(src: str, head: str) -> str:
    """The body of the `{ ... }` that follows `head`."""
    start = src.index(head) + len(head)
    depth, i = 1, start
    while depth:
        depth += {"{": 1, "}": -1}.get(src[i], 0)
        i += 1
    return src[start:i - 1]


def run_rows(src: str, polls: list) -> list:
    """Evaluate a panel's `rows` binding once per poll, `root.` bound to the poll."""
    body = block(src, "readonly property var rows: {").replace("root.", "ctx.")
    js = f"""
const Translation = {{ tr: s => s }};
const rows = ctx => {{ {body} }};
const polls = {json.dumps(polls)};
console.log(JSON.stringify(polls.map(p => {{
    p.groupFor = stamp => stamp > 1e12 ? "Today" : "Older";
    p.query = p.query ?? "";
    return rows(p);
}})));
"""
    return json.loads(subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout)


def keys(rows: list) -> list:
    return [r["key"] for r in rows]


# ── History: keyed on the session id, headers on their label ───────────────
sessions = [{"id": "s1", "title": "one", "started_at": 2e9}, {"id": "s2", "title": "two", "started_at": 1}]
first, second = run_rows(history, [{"sessions": sessions}, {"sessions": json.loads(json.dumps(sessions))}])
assert keys(first) == keys(second) == ["header:Today", "session:s1", "header:Older", "session:s2"], \
    f"History: keys drifted: {keys(first)}"
(shuffled,) = run_rows(history, [{"sessions": [sessions[1], {"id": "s3", "started_at": 2}, sessions[0]]}])
assert keys(shuffled) == ["header:Today", "session:s1", "header:Older", "session:s3", "session:s2"], \
    f"History: rows in last-active order repeat a day header: {keys(shuffled)}"
(filtered,) = run_rows(history, [{"sessions": sessions, "query": "two"}])
assert keys(filtered) == ["header:Older", "session:s2"], "History: a filtered row changed its key"

m = re.search(r"model:\s*ScriptModel\s*\{([^}]*)\}", history)
assert m and 'objectProp: "key"' in m.group(1), "History: the list is not a keyed ScriptModel"
# ScriptModel hands a row's delegate to whatever lands in its place (measured with
# qs: after one insert, a header delegate held a chat and a chat delegate a
# header), and a DelegateChooser never re-chooses -- a chat row handed a header
# threw on `session.id`. One delegate that picks by kind is what holds.
assert "DelegateChooser" not in re.sub(r"/\*[\s\S]*?\*/", "", history), \
    "History: a DelegateChooser is back; its pick goes stale when rows shift"
assert re.search(r'sourceComponent:\s*listRow\.modelData\.kind === "session"', history), \
    "History: the row delegate no longer picks header vs chat from its own modelData"
assert re.search(r"visible:\s*root\.loading", history) and \
    re.search(r"shown:\s*!root\.loading && root\.rows\.length === 0", history), \
    "History: before session.list answers the sheet must say it is loading, not 'No conversations yet'"
assert "onSessionsChanged: root.answered = true" in history, "History: nothing marks the first answer"

# ── One icon button, and sheets that grow out of their buttons ─────────────
for name, src in (("AgentHistoryPanel", history),):
    assert not re.search(r"component \w*IconButton: RippleButton", src), \
        f"{name}: an in-file icon button is back; use AgentIconButton"
assert "AgentIconButton {" in row, "AgentHistoryRow: the delete button is a bare RippleButton again"
assert "buttonRadius: Appearance.rounding.full" in button and 'colBackground: "transparent"' in button, \
    "AgentIconButton: must be round and transparent at rest"
assert "colLayer2Hover" not in row, \
    "AgentHistoryRow: the row sits bare on the layer 1 sheet; a layer 2 film is solved for another base"

origins = re.findall(r"id: (historyPanel)\b.*?transformOrigin:\s*Item\.(\w+)", page, re.S)
assert origins == [("historyPanel", "BottomRight")], \
    f"Agent.qml: the history sheet must grow out of the composer-row button below it, got {origins}"
assert "workPanel" not in page and "runInBackground" not in page, "Agent.qml: the Hermes-only work sheet is back"

print("ok: the history sheet is keyed and grows from its button")
