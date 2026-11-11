#!/usr/bin/env python3
"""A missing player or a stream with no length must leave finite media controls.

Run PlayerControl.qml's actual progress and boolean bindings under node, including
the zero-length 0/0 case that Math.min/Math.max cannot repair. A seek slider only
exists for a seekable track with a known positive length; the other branch keeps
showing progress without sending invalid positions to MPRIS.
"""
import re
import subprocess
from pathlib import Path

src = (Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/ii/mediaControls/PlayerControl.qml").read_text()


def binding(name):
    match = re.search(rf"readonly property (?:real|bool) {name}: (\{{.*?\n    \}}|[^\n]+)", src, re.S)
    assert match, f"missing {name} binding"
    value = match.group(1)
    return f"(() => {value})()" if value.startswith("{") else value


live = re.search(r"live: (.+)", src).group(1)
wavy = re.search(r"wavy: (.+)", src).group(1)
subprocess.run(["node", "-e", f"""
const assert = require('assert/strict');
const root = {{ player: null }};
assert.equal(typeof ({live}), 'boolean', 'WaveVisualizer.live receives undefined');
assert.equal(typeof ({wavy}), 'boolean', 'progress wavy receives undefined');
"""], check=True)

assert src.count("value: root.progress") == 2, "both progress branches must use the finite ratio"
assert "active: root.seekable" in src and "active: !root.seekable" in src
subprocess.run(["node", "-e", f"""
const assert = require('assert/strict');
for (const [player, expected] of [
    [null, 0], [{{}}, 0], [{{position: 0, length: 0}}, 0],
    [{{position: 25, length: 0}}, 0], [{{position: 25, length: -1}}, 0],
    [{{position: NaN, length: 100}}, 0], [{{position: Infinity, length: 100}}, 0],
    [{{position: 25, length: Infinity}}, 0], [{{position: 25, length: 100}}, .25],
    [{{position: -10, length: 100}}, 0], [{{position: 110, length: 100}}, 1]
]) {{
    const root = {{player}};
    const progress = {binding('progress')};
    assert.equal(progress, expected, JSON.stringify(player));
    assert(Number.isFinite(progress));
    for (const canSeek of [true, false]) {{
        root.player = player === null ? null : {{...player, canSeek}};
        assert.equal({binding('seekable')}, !!(canSeek && player && Number.isFinite(player.length) && player.length > 0));
    }}
}}
console.log('ok: finite bounded progress, no seeking without length, boolean animation bindings');
"""], check=True)
