#!/usr/bin/env python3
"""HyprlandData asks hyprctl once per change, and only what the change can touch.

Every Hyprland event used to start five hyprctl processes (clients, monitors, layers,
workspaces, activeworkspace), twice, since Hyprland sends most events as a v1/v2 pair:
210 spawns for 20 window-title changes, and a retitling terminal streams those. Each
reply also replaced the arrays every dock, overview and workspace binding reads, even
when hyprctl said exactly what it said last time. And a refresh asked for while a query
was running was dropped, so an event landing mid-query left a stale list standing.

This runs RefreshProcess (modules/common/utils), which every such read now goes
through, plus the Query reply handling and event filter, under node with a fake Process:
two refreshes in one tick start one run; a refresh mid-run gets exactly one more run
after it; an identical or broken reply changes nothing; a title event refreshes the
window list alone.
"""
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
QML = (II / "services/HyprlandData.qml").read_text()
REFRESH = (II / "modules/common/utils/RefreshProcess.qml").read_text()

def block(src, head, indent):
    m = re.search(rf"\n {{{indent}}}{head} \{{\n(.*?)\n {{{indent}}}\}}\n", src, re.S)
    assert m, f"no `{head}` block"
    return m.group(1).replace("root.", "query.")

refresh = block(REFRESH, r"function refresh\(\)", 4)
start = block(REFRESH, r"function _start\(\)", 4)
running_changed = block(REFRESH, "onRunningChanged:", 4)
assert "component Query: RefreshProcess" in QML, "HyprlandData's queries no longer go through RefreshProcess"
stream_finished = block(QML, "onStreamFinished:", 12)
ev = re.search(r"function onRawEvent\(event\) \{\n(.*?)\n {8}\}\n", QML, re.S)
assert ev, "HyprlandData.qml: no onRawEvent"

JS = f"""
const assert = require("assert");
let later = [];
const Qt = {{ callLater: f => {{ if (!later.includes(f)) later.push(f); }} }};
const tick = () => {{ const fs = later; later = []; fs.forEach(f => f()); }};
function makeQuery() {{
    const query = {{ _again: false, last: "", runs: 0, replies: [], _running: false }};
    const out = {{ text: "" }};
    Object.defineProperty(query, "running", {{
        get() {{ return this._running; }},
        set(v) {{ if (v === this._running) return; this._running = v; if (v) this.runs++; this.onRunningChanged(); }}
    }});
    query.reply = d => query.replies.push(d);
    query.refresh = function () {{ {refresh} }};
    query._start = function () {{ {start} }};
    query.onRunningChanged = function () {{ {running_changed} }};
    query.finish = function (text) {{ out.text = text; (function () {{ {stream_finished} }})(); this.running = false; }};
    return query;
}}

let q = makeQuery();
q.refresh(); q.refresh(); tick(); q.finish('[0]'); tick();
assert.strictEqual(q.runs, 1, "two refreshes in one tick ran " + q.runs + " times");
q = makeQuery();
q.refresh(); tick();
q.refresh(); tick();
assert.strictEqual(q.runs, 1, "a refresh mid-run started a second process at once");
q.finish('[1]'); tick();
assert.strictEqual(q.runs, 2, "the refresh asked for mid-run never ran");
q.finish('[1]'); tick();
assert.strictEqual(q.runs, 2, "ran again with nothing asked");
assert.deepStrictEqual(q.replies, [[1]], "an identical reply was passed on");
q.refresh(); tick(); q.finish('[1, '); tick();
assert.deepStrictEqual(q.replies, [[1]], "a broken reply was passed on");

const calls = [];
const root = {{}};
for (const f of ["updateWindowList", "updateWorkspaces", "updateMonitors", "updateLayers", "updateAll"]) root[f] = () => calls.push(f);
const onRawEvent = event => {{ {ev.group(1)} }};
onRawEvent({{ name: "windowtitlev2" }});
assert.deepStrictEqual(calls, ["updateWindowList"], "a title change asked for " + calls);
calls.length = 0; onRawEvent({{ name: "custom" }});
assert.deepStrictEqual(calls, [], "FloatingMode's custom event triggered a refresh");
calls.length = 0; onRawEvent({{ name: "openwindow" }});
assert.deepStrictEqual(calls, ["updateAll"], "a new window did not refresh everything");
console.log("ok: one hyprctl run per change, none for an unchanged reply, title changes fetch clients only");
"""
subprocess.run(["node", "-e", JS], check=True)
