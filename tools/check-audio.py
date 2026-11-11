#!/usr/bin/env python3
"""Mute keys must tolerate missing PipeWire devices, including a node without audio.

Run the actual Audio.qml methods under node with absent, incomplete and working
nodes. These keys are available even on machines without a microphone or output,
and while PipeWire is reconnecting; a TypeError otherwise reaches the shell log.
"""
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
audio = (II / "services/Audio.qml").read_text()
methods = "\n".join(re.search(rf"    function {name}\(\) \{{.*?\n    \}}", audio, re.S)[0]
                    for name in ("toggleMute", "toggleMicMute"))
subprocess.run(["node", "-e", """
const assert = require('node:assert/strict');
let sink, source;
const Audio = {get sink() { return sink; }, get source() { return source; }};
""" + methods + """
for (const node of [null, undefined, {}, {audio: null}, {audio: undefined}]) {
    sink = source = node;
    assert.doesNotThrow(toggleMute, 'mute with no output/audio');
    assert.doesNotThrow(toggleMicMute, 'mute with no microphone/audio');
}
sink = {audio: {muted: false}};
source = {audio: {muted: true}};
toggleMute();
assert.equal(sink.audio.muted, true);
assert.equal(source.audio.muted, true, 'output mute touched the microphone');
toggleMute();
assert.equal(sink.audio.muted, false);
toggleMicMute();
assert.equal(source.audio.muted, false);
assert.equal(sink.audio.muted, false, 'microphone mute touched the output');
toggleMicMute();
assert.equal(source.audio.muted, true);
"""], check=True)
print("ok: mute and mic-mute tolerate missing nodes/audio and toggle only their own device")
