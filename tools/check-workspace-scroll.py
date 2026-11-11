#!/usr/bin/env python3
"""A high-resolution wheel stream switches by notches, not by event count.

Touchpads send many tiny angle deltas for one swipe. Run Workspaces.qml's actual
wheel handler with partial deltas, mouse notches, reversals and horizontal input;
one standard 120-unit notch must mean one workspace, regardless of event count.
"""
import re
import subprocess
from pathlib import Path

src = (Path(__file__).resolve().parent.parent
       / "dots/.config/quickshell/ii/modules/ii/bar/Workspaces.qml").read_text()
wheel = re.search(r"onWheel: \(event\) => \{\n(.*?)\n        \}", src, re.S)
assert wheel, "Workspaces.qml: missing wheel handler"

subprocess.run(["node", "-e", f"""
const assert = require('assert/strict');
const calls = [];
const Hyprland = {{ dispatch: command => calls.push(command) }};
const interactionMouseArea = {{ scrollDelta: 0, scrollThreshold: 120 }};
const wheel = event => {{ {wheel.group(1)} }};
const send = (y, x = 0) => wheel({{ angleDelta: {{ x, y }}, accepted: false }});
for (let i = 0; i < 12; i++) send(-10);
assert.deepEqual(calls, ['hl.dsp.focus({{workspace = "r+1"}})'],
    'one touchpad notch switched once per event instead of once per accumulated notch');
calls.length = 0;
send(120); send(-120); send(360);
assert.deepEqual(calls, [
    'hl.dsp.focus({{workspace = "r-1"}})', 'hl.dsp.focus({{workspace = "r+1"}})',
    'hl.dsp.focus({{workspace = "r-3"}})'
], 'mouse notches lost steps');
calls.length = 0;
send(90); send(-60);
assert.equal(calls.length, 0, 'partial movement switched a workspace');
send(-60);
assert.deepEqual(calls, ['hl.dsp.focus({{workspace = "r+1"}})'], 'reversing kept stale movement');
calls.length = 0;
send(0); send(0, -120);
assert.deepEqual(calls, ['hl.dsp.focus({{workspace = "r+1"}})'], 'horizontal input did not work');
console.log('ok: touchpad deltas accumulate, mouse notches retain their steps, and reversal resets the remainder');
"""], check=True)
