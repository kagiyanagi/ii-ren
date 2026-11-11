#!/usr/bin/env python3
"""Run the lock's workspace commands without locking the user's desktop.

The parking animation used to be a bare `keyword` shell command, so bash rejected
it while the following hyprctl dispatches still moved the workspaces. Lua configs
also reject `hyprctl keyword`. Execute the QML JavaScript with fake screens and
capture the command actually submitted; it must be one hyprctl eval, with the
animation before any workspace move. Run that Lua with a fake compositor too.
"""
import json
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
src = (II / "modules/ii/lock/Lock.qml").read_text()


def body(head, indent=4):
    match = re.search(rf"^ {{{indent}}}{head} \{{\n(.*?)^ {{{indent}}}\}}", src, re.M | re.S)
    assert match, f"Lock.qml: missing {head}"
    return match.group(1)


# Before the repair, the parking code lived in the signal handler itself.
parking = (body(r"function parkWorkspaces\(\)") if "function parkWorkspaces()" in src
           else body(r"function onScreenLockedChanged\(\)", 8))
subprocess.run(["node", "-e", f"""
const assert = require('assert/strict');
const {{ execFileSync }} = require('child_process');
const calls = [];
const GlobalStates = {{ screenLocked: true, screenLockExiting: false }};
const animProc = {{ running: false }};
const root = {{ savedWorkspaces: {{}}, lockWorkspaceBase: 2147483647 }};
const Quickshell = {{ screens: [{{ name: 'DP-1' }}, {{ name: 'HDMI-A-1' }}],
    execDetached: command => calls.push(command) }};
const HyprlandData = {{ monitors: [
    {{ name: 'DP-1', activeWorkspace: {{ id: 2 }} }},
    {{ name: 'HDMI-A-1', activeWorkspace: {{ id: 7 }} }}
] }};
(function () {{ {parking} }})();
assert.equal(calls.length, 1, 'parking should submit one command');
assert.deepEqual(calls[0].slice(0, 2), ['hyprctl', 'eval'],
    'the animation must be submitted to hyprctl, not executed as a shell command');
execFileSync('lua', ['-'], {{ input: `
local moves = 0
hl = {{ dsp = {{ focus = function(target) return target end }} }}
hl.animation = function(spec)
    assert(moves == 0, 'animation was applied after parking')
    assert(spec.leaf == 'workspaces' and spec.enabled and spec.speed == 7)
    assert(spec.bezier == 'menu_decel' and spec.style == 'slidevert')
end
hl.dispatch = function(target) moves = moves + 1 end
${{calls[0][2]}}
assert(moves == 4, 'not all monitors were parked')
` }});
assert.deepEqual(root.savedWorkspaces, {{ 'DP-1': 2, 'HDMI-A-1': 7 }});
console.log('ok: parking sends valid Lua for the animation and workspace moves in one hyprctl eval');
"""], check=True)
