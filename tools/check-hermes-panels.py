#!/usr/bin/env python3
"""The Hermes history and work sheets survive a poll, swap pages visibly, and grow
out of the buttons that open them.

None of this shows in a still frame:
- Both lists were plain JS arrays rebuilt from HermesService on every refresh (the
  Live list every 2s while a turn runs), so every delegate was destroyed on every
  pass: a half-typed steer lost its caret and every row re-ran its entrance. They
  are keyed ScriptModels now; this runs the two `rows` builders under node against
  two polls of fresh objects and asserts the keys match, are unique, and fall back
  to the index only where the gateway gave no id.
- The run list <-> run detail swap flipped `showingDetail` before the animation
  started, so both pages' `visible` changed on frame 1: the old page vanished and
  the new one faded out and back in. Pages now follow `shownPage`, which only the
  animation's midpoint moves, and the Live / History tabs go through the same swap.
- The sheets scaled from `Item.Top` while their buttons sit at the right end of the
  composer row, below them.
- The subagent card animated its own height on top of the Revealer inside it, which
  is one Behavior chasing another.
"""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
P = ROOT / "dots/.config/quickshell/ii/modules/ii/sidebarPolicies"
H = P / "hermes"
live = (H / "HermesSideTasksPanel.qml").read_text()
work = (H / "HermesWorkPanel.qml").read_text()
history = (H / "HermesHistoryPanel.qml").read_text()
row = (H / "HermesHistoryRow.qml").read_text()
button = (H / "HermesIconButton.qml").read_text()
page = (P / "Hermes.qml").read_text()


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


# ── Live: keyed on kind plus the row's own id ──────────────────────────────
poll = lambda: {
    "sideTasks": [{"taskId": "bg_1", "done": False}, {"taskId": "", "done": True}],
    "subagents": [{"subagent_id": "a", "depth": 0}, {"subagent_id": "b", "depth": 1}],
    "processes": [{"session_id": "p1"}],
}
first, second = run_rows(live, [poll(), poll()])
assert keys(first) == keys(second), "Live: two polls of the same work produced different keys, so the rows rebuild"
assert len(set(keys(first))) == len(first), f"Live: duplicate keys {keys(first)}"
assert keys(first) == ["tasksHeader", "task:bg_1", "task:1", "subagentsHeader", "subagent:a", "subagent:b",
                       "processesHeader", "process:p1"], f"Live: keys drifted: {keys(first)}"
# Running side work sits above finished, whatever order the service appended it in.
(ordered,) = run_rows(live, [{"sideTasks": [{"taskId": "old", "done": True}, {"taskId": "new", "done": False}],
                              "subagents": [], "processes": []}])
assert keys(ordered) == ["tasksHeader", "task:new", "task:old"], f"Live: finished work sits above running: {keys(ordered)}"
# A child finishing above another must not re-key the one below it.
fewer = poll()
fewer["subagents"].pop(0)
(after,) = run_rows(live, [fewer])
assert "subagent:b" in keys(after), "Live: a row's key depends on its position, so a removal above it rebuilds it"

m = re.search(r"model:\s*ScriptModel\s*\{([^}]*)\}", live)
assert m and 'objectProp: "key"' in m.group(1) and "root.rows" in m.group(1), \
    "Live: the list is not a ScriptModel keyed on `key` over root.rows"
assert 'role: "kind"' in live and "DelegateChooser" in live, "Live: rows are no longer chosen by `kind`"
assert "sourceComponent: {" not in live, "Live: the Loader + switch is back; it rebuilds the row on every kind change"
assert not re.search(r"Behavior on implicitHeight", live), \
    "Live: the subagent card animates its height again, on top of the Revealer that already does"
assert "embedded" not in live and "requestClose" not in live, \
    "Live: the non-embedded mode is back; its only caller always embedded it"
steer = block(live, "id: steerField")
assert "enabled: subRow.canSteer" in steer and "opacity: enabled ? 1 : 0.4" in steer, \
    "Live: a child that stops taking steer must show its field disabled at 0.4"
stop = live[live.index('symbol: "stop_circle"') - 200:live.index('symbol: "stop_circle"') + 200]
assert "enabled:" not in stop, "Live: interrupt must stay live when steer is refused"

# ── History: keyed on the session id, headers on their label ───────────────
sessions = [{"id": "s1", "title": "one", "started_at": 2e9}, {"id": "s2", "title": "two", "started_at": 1}]
first, second = run_rows(history, [{"sessions": sessions}, {"sessions": json.loads(json.dumps(sessions))}])
assert keys(first) == keys(second) == ["header:Today", "session:s1", "header:Older", "session:s2"], \
    f"History: keys drifted: {keys(first)}"
(filtered,) = run_rows(history, [{"sessions": sessions, "query": "two"}])
assert keys(filtered) == ["header:Older", "session:s2"], "History: a filtered row changed its key"

m = re.search(r"model:\s*ScriptModel\s*\{([^}]*)\}", history)
assert m and 'objectProp: "key"' in m.group(1), "History: the list is not a keyed ScriptModel"
assert "DelegateChooser" in history and "sourceComponent:" not in history, \
    "History: the Loader + Component switch is back"
assert re.search(r"visible:\s*root\.loading", history) and \
    re.search(r"shown:\s*!root\.loading && root\.rows\.length === 0", history), \
    "History: before session.list answers the sheet must say it is loading, not 'No conversations yet'"
assert "onSessionsChanged: root.answered = true" in history, "History: nothing marks the first answer"

# ── Work: pages follow the midpoint, never the request ─────────────────────
swap = block(work, "component PageSwap: Item {")
assert "swap.shownPage = swap.page" in block(swap, "ScriptAction {"), \
    "PageSwap: the drawn page must flip at the midpoint"
parts = re.findall(r"ParallelAnimation\s*\{", swap)
assert len(parts) == 2, "PageSwap: expected an exit half and an enter half"
exit_half = block(swap, "ParallelAnimation {")
enter_half = block(swap[swap.index("ScriptAction"):], "ParallelAnimation {")
assert "elementMoveExit" in exit_half and "elementMoveEnter" not in exit_half, \
    "PageSwap: the old page must leave on elementMoveExit"
assert "elementMoveEnter" in enter_half and "elementMoveFast" in enter_half, \
    "PageSwap: the new page arrives with its shift on elementMoveEnter and its opacity on elementMoveFast"
bad = re.findall(r"visible:[^\n]*(?:currentIndex|showingDetail)", work)
assert not bad, f"Work: a page's visibility reads the request ({bad}), so it changes on frame 1"
assert len(re.findall(r"visible:\s*\w+\.shownPage === \d", work)) == 4, \
    "Work: all four pages (two tabs, list and detail) must follow a PageSwap's shownPage"
m = re.search(r"model:\s*ScriptModel\s*\{([^}]*)\}", work)
assert m and 'objectProp: "path"' in m.group(1), "Work: the saved-run list is not keyed on `path`"

# ── One icon button, and sheets that grow out of their buttons ─────────────
for name, src in (("HermesWorkPanel", work), ("HermesSideTasksPanel", live), ("HermesHistoryPanel", history)):
    assert not re.search(r"component \w*IconButton: RippleButton", src), \
        f"{name}: an in-file icon button is back; use HermesIconButton"
assert "HermesIconButton {" in row, "HermesHistoryRow: the delete button is a bare RippleButton again"
assert "buttonRadius: Appearance.rounding.full" in button and 'colBackground: "transparent"' in button, \
    "HermesIconButton: must be round and transparent at rest"
assert "colLayer2Hover" not in row, \
    "HermesHistoryRow: the row sits bare on the layer 1 sheet; a layer 2 film is solved for another base"

origins = re.findall(r"id: (historyPanel|workPanel)\b.*?transformOrigin:\s*Item\.(\w+)", page, re.S)
assert sorted(origins) == [("historyPanel", "BottomRight"), ("workPanel", "BottomRight")], \
    f"Hermes.qml: the sheets must grow out of the composer-row buttons below them, got {origins}"

print("ok: the Hermes sheets are keyed, swap on the midpoint, and grow from their buttons")
