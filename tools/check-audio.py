#!/usr/bin/env python3
"""Audio controls tolerate absent devices; volume ticks belong to one output.

Run the actual Audio.qml methods under node with absent, incomplete and working
nodes. These keys are available even on machines without a microphone or output,
and while PipeWire is reconnecting; a TypeError otherwise reaches the shell log.
Run the real volume Connections in Qt to cover target changes and signal ordering.
Switching devices, startup, mute and resume must stay silent; level changes tick.
"""
import re
import subprocess
import tempfile
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

tick = audio[audio.index("    // The volume tick."):].rsplit("\n}", 1)[0]
sink_changed = re.search(r"    onSinkChanged: \{.*?\n    \}", audio, re.S)[0]
with tempfile.TemporaryDirectory(prefix="ii-audio-check-") as directory:
    test = Path(directory) / "tst_audio.qml"
    test.write_text('''import QtQuick
import QtTest
TestCase {
    id: root
    name: "VolumeTick"
    property var sink: null
    QtObject { id: first; property real volume: 0; property bool muted: false }
    QtObject { id: second; property real volume: 0; property bool muted: false }
    QtObject { id: volumeProtection; property bool lastReady: false }
    QtObject { id: combineSinkProcess; function sync() {} }
    QtObject {
        id: soundService
        property int ticks: 0
        function playEvent(category) {
            compare(category, "volumeChange")
            ticks++
        }
    }
''' + sink_changed + tick.replace("SoundService", "soundService") + '''
    function test_outputChanges() {
        sink = {audio: first}
        first.volume = 0.4
        compare(soundService.ticks, 0, "first reading at startup")
        first.volume = 0.5
        compare(soundService.ticks, 1, "volume adjustment")
        first.muted = true
        first.volumeChanged()
        compare(soundService.ticks, 1, "mute or unchanged volume")
        sink = {audio: second}
        second.volume = 0.8
        compare(soundService.ticks, 1, "first reading of another output")
        second.volume = 0.9
        compare(soundService.ticks, 2, "adjustment on the new output")
        sink = null
        first.volume = 0.7
        compare(soundService.ticks, 2, "disconnected output")
        sink = {audio: first}
        first.volume = 0.6
        compare(soundService.ticks, 2, "reconnected output")
        first.volume = NaN
        first.volume = 0.6
        compare(soundService.ticks, 2, "first reading after resume")
        first.volume = 0.7
        compare(soundService.ticks, 3, "adjustment after resume")
    }
}
''')
    runner = "/usr/lib/qt6/bin/qmltestrunner" if Path("/usr/lib/qt6/bin/qmltestrunner").exists() else "qmltestrunner"
    result = subprocess.run([runner, "-platform", "offscreen", "-input", directory],
                            capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stdout + result.stderr
    print(result.stdout.strip())
