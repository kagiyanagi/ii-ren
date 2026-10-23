#!/usr/bin/env python3
"""The read-aloud player goes where it is told, in Qt itself.

AgentService's reader holds one part's clip at a time and is moved about the
reading: a clip loaded to start mid-way, a seek back within it, a hold and a
release, a switch to another clip while one plays. Qt's MediaPlayer drops a
seek issued while a clip is loading and, switching sources mid-play, reports
the old clip loaded first (measured, Qt 6.12), so none of that can be taken on
trust from tools/check-read-aloud-queue.py's stand-in player. This lifts the
reader component out of services/AgentService.qml as it is, mutes its output,
drives it through a real MediaPlayer over two generated tones, and asserts:

- a clip loaded to start at 1200 ms plays from there, and its MarkClock marks
  the word there;
- a seek back within the clip playing is taken, mark and all;
- held, it falls silent and stays put; released, it plays on from there;
- a clip switched to mid-play, held at 2000 ms, is at 2000 ms;
- a clip played out says so, once, with its part.

Needs a Wayland session and quickshell (`qs -p`), nothing audible. The probe
file is written into the shell dir (the `qs.` imports only resolve there) and
removed on exit.

    python3 tools/check-reading-player.py
"""
import json
import math
import os
import re
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

SHELL = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
SERVICE = (SHELL / "services/AgentService.qml").read_text()
probe = SHELL / f".probe-reading-player-{os.getpid()}.qml"

start = SERVICE.index("        sourceComponent: Item {\n            id: reader")
end = SERVICE.index("\n    }\n", SERVICE.index("id: resumeFade", start))
reader = SERVICE[start + len("        sourceComponent: "):end].rstrip()
assert reader.endswith("}"), "the reader component no longer ends where expected"
# Muted: the check must not be heard.
reader, n = re.subn(r"(id: readerOutput\n)", r"\1muted: true\n", reader)
assert n == 1, "the reader's AudioOutput is gone"

with tempfile.TemporaryDirectory() as tmp:
    tones = []
    for name, seconds in (("a", 3), ("b", 3)):
        path = Path(tmp) / f"{name}.wav"
        with wave.open(str(path), "wb") as clip:
            clip.setnchannels(1)
            clip.setsampwidth(2)
            clip.setframerate(24000)
            clip.writeframes(b"".join(struct.pack("<h", int(6000 * math.sin(2 * math.pi * 330 * i / 24000)))
                                       for i in range(seconds * 24000)))
        tones.append(str(path))

    probe.write_text("""//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import QtMultimedia
import Quickshell
import qs.modules.common
import qs.services.agent

ShellRoot {
    id: shell
    property var log: []
    property var ended: []
    // What the reader asks of the service.
    QtObject {
        id: root
        // A word every 500 ms in each clip.
        property var _speakClips: [
            { path: "TONE_A", marks: [[0, 0], [500, 10], [1000, 20], [1500, 30], [2000, 40], [2500, 50]] },
            { path: "TONE_B", marks: [[0, 0], [1000, 7], [2000, 14]] }
        ]
        function _partEnded(index) { shell.ended.push([Date.now(), index]); }
    }
    Loader {
        id: host
        sourceComponent: READER
    }
    function note(label) {
        const r = host.item;
        shell.log.push({ label: label, index: r.loadedIndex, state: r.player.playbackState, position: r.player.position,
            clock: r.markClock.position, offset: r.markClock.offset, loading: r.loading });
    }
    property var steps: [
        [0, () => host.item.load(0, "file://TONE_A".slice(7), 1200, true)],
        [450, () => shell.note("loaded at 1200")],
        [500, () => host.item.seekWithin(400, true)],
        [700, () => shell.note("seeked back to 400")],
        [750, () => host.item.hold()],
        [1050, () => shell.note("held")],
        [1400, () => shell.note("still held")],
        [1450, () => host.item.release()],
        [1800, () => shell.note("released")],
        [1850, () => host.item.load(1, "TONE_B", 2000, false)],
        [2150, () => shell.note("switched, held at 2000")],
        [2200, () => host.item.release()],
        [2500, () => shell.note("released at 2000")],
        [3500, () => shell.note("played out")],
        [3550, () => { console.log("PROBE " + JSON.stringify({ log: shell.log, ended: shell.ended.length, endedIndex: shell.ended.map(e => e[1]) })); Qt.quit(); }]
    ]
    property real t0: 0
    Timer {
        id: clock
        interval: 10
        repeat: true
        running: true
        property int next: 0
        onTriggered: {
            if (shell.t0 === 0)
                shell.t0 = Date.now();
            while (clock.next < shell.steps.length && Date.now() - shell.t0 >= shell.steps[clock.next][0])
                shell.steps[clock.next++][1]();
        }
    }
}
""".replace("READER", reader).replace("TONE_A", tones[0]).replace("TONE_B", tones[1]))
    try:
        out = subprocess.run(["timeout", "30", "qs", "-p", str(probe), "--no-color"], capture_output=True, text=True).stdout
    finally:
        probe.unlink(missing_ok=True)

found = re.search(r"PROBE (\{.*\})", out)
assert found, f"the probe reported nothing:\n{out[-3000:]}"
data = json.loads(found.group(1))
log = {entry["label"]: entry for entry in data["log"]}
PLAYING, PAUSED = 1, 2
MARKS = ([[0, 0], [500, 10], [1000, 20], [1500, 30], [2000, 40], [2500, 50]], [[0, 0], [1000, 7], [2000, 14]])


def word_at(entry):
    """The word the clip's marks put at the clock's position."""
    return [offset for ms, offset in MARKS[entry["index"]] if ms <= entry["clock"]][-1]

loaded = log["loaded at 1200"]
assert loaded["state"] == PLAYING and 1200 <= loaded["position"] <= 1200 + 450, \
    f"a clip loaded to start at 1200 ms is at {loaded['position']} ({loaded})"
assert loaded["offset"] == word_at(loaded), f"loaded at 1200 ms, the clip's mark is on the wrong word: {loaded}"

back = log["seeked back to 400"]
assert back["state"] == PLAYING and 400 <= back["position"] <= 400 + 200 and back["clock"] < 1000, \
    f"a seek back to 400 ms was not taken: {back}"
assert back["offset"] == word_at(back) <= 10, f"moved back to 400 ms, the mark stayed on {back['offset']}"

held, still = log["held"], log["still held"]
assert held["state"] == PAUSED and still["state"] == PAUSED and held["position"] == still["position"], \
    f"held, the clip did not stop where it was: {held} then {still}"
released = log["released"]
assert released["state"] == PLAYING and released["position"] > held["position"], f"released, it did not play on: {released}"

switched = log["switched, held at 2000"]
assert (switched["index"], switched["state"], switched["position"]) == (1, PAUSED, 2000), \
    f"a clip switched to mid-play and held at 2000 ms is at {switched}"
assert switched["offset"] == word_at(switched) == 14, f"held at 2000 ms of the second clip, the mark is on {switched['offset']}"
went_on = log["released at 2000"]
assert went_on["state"] == PLAYING and went_on["position"] > 2000, f"released at 2000 ms, it is at {went_on}"

assert data["endedIndex"] == [1], f"a clip played out was reported {data['endedIndex']}, not once for its part"

print(f"ok: the reader loads mid-clip, seeks back, holds, switches and ends in a real MediaPlayer "
      f"(loaded at 1200 ms, it was at {loaded['position']} ms 450 ms later)")
