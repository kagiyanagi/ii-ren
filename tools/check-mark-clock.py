#!/usr/bin/env python3
"""A read-aloud mark moves when its word is due, not at the next position report.

MediaPlayer reports its position ten times a second, so a mark read straight off
`position` moved up to 100 ms after its word -- the read-aloud highlight trailed
the voice by a median 65-88 ms on any voice. services/agent/MarkClock.qml times
the next mark itself. This plays a 4 s tone, muted, through a real MediaPlayer
with a mark every 237 ms (off the report grid, as words are) and asserts:

- position reports are still ~100 ms apart (the reason this exists);
- MarkClock moves each mark within a few ms of when the player's own clock
  says it is due, and well ahead of a mark read off `position`;
- the marks it moves through are every mark, in order -- none skipped, none
  stepped back.

Needs a Wayland session and quickshell (`qs -p`), nothing audible. The probe
file is written into the shell dir (the `qs.` imports only resolve there) and
removed on exit.

    python3 tools/check-mark-clock.py
"""
import math
import os
import re
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

SHELL = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
probe = SHELL / f".probe-mark-clock-{os.getpid()}.qml"

with tempfile.TemporaryDirectory() as tmp:
    tone = Path(tmp) / "tone.wav"
    with wave.open(str(tone), "wb") as clip:
        clip.setnchannels(1)
        clip.setsampwidth(2)
        clip.setframerate(24000)
        clip.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * i / 24000))) for i in range(4 * 24000)))

    probe.write_text("""//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import QtMultimedia
import Quickshell
import qs.services.agent

ShellRoot {
    id: shell
    readonly property var marks: Array.from({ length: 15 }, (_, i) => [200 + i * 237, i])
    property var reports: []
    property var bound: []
    property var clocked: []
    readonly property int boundOffset: {
        let offset = marks[0][1];
        for (let i = 0; i < marks.length && marks[i][0] <= player.position; i++) offset = marks[i][1];
        return offset;
    }
    onBoundOffsetChanged: bound.push([Date.now(), boundOffset])
    MarkClock {
        player: player
        marks: shell.marks
        onOffsetChanged: shell.clocked.push([Date.now(), offset])
    }
    MediaPlayer {
        id: player
        source: "file://TONE"
        audioOutput: AudioOutput { muted: true }
        onPositionChanged: shell.reports.push([Date.now(), position])
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) shell.report()
        Component.onCompleted: play()
    }
    function report(): void {
        const playing = reports.filter(r => r[1] > 0);
        const gaps = playing.slice(1).map((r, i) => r[0] - playing[i][0]).sort((a, b) => a - b);
        // A report can only arrive late, so the earliest start any implies is the start.
        const start = Math.min(...playing.map(r => r[0] - r[1]));
        const lags = changes => changes.filter(c => c[1] > 0).map(c => c[0] - (start + marks[c[1]][0])).sort((a, b) => a - b);
        const median = xs => xs[Math.floor(xs.length / 2)];
        const b = lags(bound), c = lags(clocked);
        console.log(`PROBE gap=${median(gaps)} bound=${median(b)} clocked=${median(c)} clockedMax=${c[c.length - 1]} order=${clocked.map(x => x[1]).join(",")}`);
        Qt.quit();
    }
}
""".replace("TONE", str(tone)))
    try:
        out = subprocess.run(["timeout", "30", "qs", "-p", str(probe), "--no-color"], capture_output=True, text=True).stdout
    finally:
        probe.unlink(missing_ok=True)

found = re.search(r"PROBE gap=(\d+) bound=(-?\d+) clocked=(-?\d+) clockedMax=(-?\d+) order=([\d,]*)", out)
assert found, f"the probe reported nothing:\n{out[-2000:]}"
gap, bound, clocked, clocked_max = map(int, found.groups()[:4])
order = [int(x) for x in found.group(5).split(",") if x]

assert 80 <= gap <= 120, f"position reports are {gap} ms apart, not ~100: re-measure what MarkClock assumes"
assert clocked <= 10, f"MarkClock moved marks a median {clocked} ms late"
assert clocked_max <= 40, f"MarkClock moved a mark {clocked_max} ms late"
assert clocked < bound, f"MarkClock ({clocked} ms) is no better than position ({bound} ms)"
# The first mark is where the offset starts, so it is never a change.
assert order == list(range(1, 15)), f"marks skipped or stepped back: {order}"

print(f"ok: marks move {clocked} ms after their word (read off position: {bound} ms; reports {gap} ms apart)")
