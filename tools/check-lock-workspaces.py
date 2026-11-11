#!/usr/bin/env python3
"""Run the lock's workspace commands without locking the user's desktop.

The parking animation used to be a bare `keyword` shell command, so bash rejected
it while the following hyprctl dispatches still moved the workspaces. Lua configs
also reject `hyprctl keyword`. Execute the QML JavaScript with fake screens and
capture the command actually submitted; it must be one hyprctl eval, with the
animation before any workspace move. Run that Lua with a fake compositor too.

A missing monitor reply must not abort parking the remaining screens or leave
the previous lock's saved map behind. Cover hotplug gaps, native-monitor fallback,
and a shell restarting on already-parked workspaces.
Restoring every screen must finish on the screen focused before locking, even
when it is not the last screen in the list; a disconnected screen is skipped.
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
restore = body("onTriggered:", 8)
focus = body(r"function focusSavedMonitor\(\)") if "function focusSavedMonitor()" in src else "return '';"
subprocess.run(["node", "-e", f"""
const assert = require('assert/strict');
const {{ execFileSync }} = require('child_process');
const calls = [];
const GlobalStates = {{ screenLocked: true, screenLockExiting: false }};
const animProc = {{ running: false }};
const root = {{ savedWorkspaces: {{}}, lockWorkspaceBase: 2147483647, workspacesAnim: {{ bezier: 'original' }} }};
const Quickshell = {{ screens: [{{ name: 'DP-1' }}, {{ name: 'HDMI-A-1' }}],
    execDetached: command => calls.push(command) }};
const HyprlandData = {{ monitors: [
    {{ name: 'DP-1', activeWorkspace: {{ id: 2 }} }},
    {{ name: 'HDMI-A-1', activeWorkspace: {{ id: 7 }} }}
] }};
const Hyprland = {{ monitorFor: () => null }};
const park = () => {{ {parking} }};
park();
assert.equal(calls.length, 1, 'parking should submit one command');
assert.deepEqual(calls[0].slice(0, 2), ['hyprctl', 'eval'],
    'the animation must be submitted to hyprctl, not executed as a shell command');
execFileSync('lua', ['-'], {{ input: `
local moves = 0
hl = {{ dsp = {{ focus = function(target) return target end }},
    get_config = function() return false end, config = function() end }}
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

for (const present of ['DP-1', 'HDMI-A-1', null]) {{
    root.savedWorkspaces = {{ 'DP-1': 90, 'HDMI-A-1': 91, 'disconnected': 92 }};
    calls.length = 0;
    HyprlandData.monitors = present ? [{{ name: present, activeWorkspace: {{ id: 4 }} }}] : [];
    park();
    assert.deepEqual(root.savedWorkspaces, present ? {{ [present]: 4 }} : {{}},
        'missing monitor data aborted the loop or reused the last lock map');
    if (present)
        assert.match(calls[0][2], /workspace=2147483643/);
}}

HyprlandData.monitors = [];
Hyprland.monitorFor = screen => screen.name === 'DP-1' ? {{ activeWorkspace: {{ id: 3 }} }} : null;
park();
assert.deepEqual(root.savedWorkspaces, {{ 'DP-1': 3 }}, 'the native monitor did not cover a missing JSON reply');
Hyprland.monitorFor = () => null;
HyprlandData.monitors = [{{ name: 'DP-1', activeWorkspace: {{ id: 2147483645 }} }}];
park();
assert.deepEqual(root.savedWorkspaces, {{ 'DP-1': 2 }}, 'a recovered lock saved the parked id');
assert.ok(!calls.at(-1)[2].includes('workspace='), 'an already parked workspace was parked again');
root.workspacesAnim = null;
park();
assert.ok(!calls.at(-1)[2].includes('hl.animation'), 'a failed animation read applied an override it cannot restore');
for (const [locked, exiting] of [[false, false], [true, true]]) {{
    calls.length = 0;
    GlobalStates.screenLocked = locked;
    GlobalStates.screenLockExiting = exiting;
    park();
    assert.equal(calls.length, 0, 'a delayed animation reply parked after unlock began');
}}
console.log('ok: parking sends valid Lua for the animation and workspace moves in one hyprctl eval');

root.focusSavedMonitor = () => {{ {focus} }};
root.workspacesAnim = null;
root.savedWorkspaces = {{ 'DP-1': 2, 'HDMI-A-1': 7 }};
const restore = () => {{ {restore} }};
for (const name of ['DP-1', 'HDMI-A-1']) {{
    root.savedFocusedMonitor = name;
    restore();
    execFileSync('lua', ['-'], {{ input: `
local monitor, workspaces = nil, {{}}
hl = {{ dsp = {{ focus = function(target) return target end }},
    get_config = function() return false end, config = function() end }}
hl.dispatch = function(target)
    if target.monitor then monitor = target.monitor end
    if target.workspace then workspaces[monitor] = target.workspace end
end
${{calls.at(-1)[2]}}
assert(workspaces['DP-1'] == 2 and workspaces['HDMI-A-1'] == 7)
assert(monitor == '${{name}}', 'unlock focused the last screen instead of the saved screen')
` }});
}}
Quickshell.screens = [{{ name: 'HDMI-A-1' }}];
root.savedFocusedMonitor = 'DP-1';
restore();
assert.ok(!calls.at(-1)[2].includes('monitor = "DP-1"'), 'unlock tried to focus a disconnected screen');
console.log('ok: unlock restores all workspaces and finishes on the saved connected monitor');
"""], check=True)
