#!/usr/bin/env python3
"""A reading plays every part, in order, however long each takes to make.

Read-aloud asks the synth server for a reply in parts and plays each as it
comes back. When a part ended before the next one was made, the player called
the reading over, and the part that came next was thrown away as belonging to a
reading nobody wanted: the local voice, which makes a part in about the time the
one before takes to say, stopped after its first sentence or two. Nothing shows
this in a still frame, so services/AgentService.qml's reading logic -- asking
for parts, taking replies, the player's end of a clip, stopping -- is lifted out
and run under node on a virtual clock, against a stand-in server and player:

- slower than real time: every part plays, in order, the gaps are waits rather
  than ends, and the reading ends only after its last part;
- a part that fails mid-reading is a gap, not the end;
- stopped while waiting, the reading ends at once and nothing more is made;
- the server dying mid-reading ends it after the part playing;
- the server is never asked for more than two parts ahead.

    python3 tools/check-read-aloud-queue.py
"""
import json
import re
import subprocess
from pathlib import Path

SERVICE = (Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/services/AgentService.qml").read_text()


def block(header):
    """The brace-balanced block after `header`, braces included."""
    start = SERVICE.index(header)
    i = SERVICE.index("{", start + len(header) - 1)
    depth = 0
    for j in range(i, len(SERVICE)):
        depth += {"{": 1, "}": -1}.get(SERVICE[j], 0)
        if depth == 0:
            return SERVICE[i:j + 1]
    raise AssertionError(f"no end to {header}")


def function(name):
    """`function name(...)` as plain JS: QML's type annotations dropped."""
    m = re.search(rf"function {name}\(([^)]*)\)(?::\s*\w+)?\s*\{{", SERVICE)
    assert m, f"`{name}` is gone"
    params = ", ".join(p.split(":")[0].strip() for p in m.group(1).split(",") if p.strip())
    return f"function ({params}) " + block(m.group(0))


# The binding, with the lines that carry it on with && or ||.
waiting = re.search(r"readonly property bool _speakWaiting:\s*((?:.+\n\s*(?=&&|\|\|))*.+)", SERVICE)
assert waiting, "`_speakWaiting` is gone: nothing says the player is waiting on a part"
waiting = waiting.group(1).strip()
ended = block("onMediaStatusChanged: {")
ahead = re.search(r"readonly property int _speakAhead: (\d+)", SERVICE)
assert ahead, "`_speakAhead` is gone: nothing bounds how far ahead parts are asked for"
exited = block("onExited: (exitCode, exitStatus) => {")

script = """
const MediaPlayer = { PlayingState: 1, StoppedState: 0, EndOfMedia: 7 };
const Config = { options: { agent: { ttsEngine: "kokoro" } } };
const Translation = { tr: s => s };
let now = 0;
const events = [];
const at = (time, run, server) => { events.push({ time, run, server, order: events.length }); };

const log = { asked: [], played: [], ended: null, maxAhead: 0, orphans: 0, errors: [] };
const SPEED = 1.1, OVERHEAD = 0.2, PER_CHAR = 0.062;   // measured on battery: tts.py
let serverFree = 0;
let failing = new Set();

const root = {
    _minFirstChunk: 60, _minChunk: 140, _maxChunks: 8, _minLocalChunk: 40, _maxLocalChunk: 120,
    _speakAhead: __AHEAD__, _speakEpoch: 0, _speakParts: [], _speakNext: 0, _speakOutstanding: 0,
    speakingMessageId: "", _speakingChunk: "", _speakingShare: 0, _speakingSpan: 1, _speakingMarks: [],
    _ttsPending: {}, ttsReady: true, ttsAvailable: true,
    get _speakWaiting() { return __WAITING__; },
    addMessage: text => log.errors.push(text),
    _ttsRequest(chunk, callback) {
        log.asked.push(chunk);
        log.maxAhead = Math.max(log.maxAhead, root._speakOutstanding);
        serverFree = Math.max(now, serverFree) + OVERHEAD + chunk.length * PER_CHAR / SPEED;
        const index = log.asked.length - 1;
        at(serverFree, () => callback(failing.has(chunk) ? { ok: false, paths: [], error: "boom" }
            : { ok: true, paths: [`/tmp/part-${index}`], marks: [] }), true);
    },
};
root._splitForSpeech = (text, local) => text.split(/(?<=[.!?])\\s+/);   // a sentence a part

const cleanupOrphan = { command: [], set running(v) { log.orphans++; } };
const fadeOut = { running: false, start() { readerPlayer.stop(); reader.finish(); }, stop() {} };
const readerOutput = { volume: 1 };
const cleanup = { command: [], running: false };
const readerPlayer = {
    playbackState: MediaPlayer.StoppedState, mediaStatus: 0, source: "", clip: 0,
    get playing() { return this.playbackState === MediaPlayer.PlayingState; },
    play() {
        const clip = ++this.clip;
        this.playbackState = MediaPlayer.PlayingState;
        const chunk = root._speakingChunk;
        log.played.push({ chunk, start: now });
        at(now + chunk.length * PER_CHAR, () => {
            if (this.clip !== clip || this.playbackState !== MediaPlayer.PlayingState)
                return;
            this.playbackState = MediaPlayer.StoppedState;
            this.mediaStatus = MediaPlayer.EndOfMedia;
            onMediaStatusChanged();
        });
    },
    stop() { this.playbackState = MediaPlayer.StoppedState; this.clip++; },
};
const reader = { queue: [], produced: [], epoch: 0, player: readerPlayer, output: readerOutput };
reader.enqueue = (__ENQUEUE__);
reader.playEntry = (__PLAYENTRY__);
reader.finish = (__FINISH__);
reader.fadeAndStop = (__FADEANDSTOP__);
const readerLoader = { active: false, item: reader };
const onMediaStatusChanged = () => __ENDED__;
const onExited = (exitCode, exitStatus) => __EXITED__;

root.speak = (__SPEAK__);
root._askForParts = (__ASK__);
root._onSpoken = (__ONSPOKEN__);
root._endIfDone = (__ENDIFDONE__);
root.stopSpeaking = (__STOP__);

const watch = () => { if (root.speakingMessageId === "" && log.ended === null) log.ended = now; };
const reading = (text, setup) => {
    Object.assign(log, { asked: [], played: [], ended: null, maxAhead: 0, orphans: 0, errors: [] });
    now = 0;
    serverFree = 0;
    root.speakingMessageId = "turn";
    root.speak(text);
    if (setup) setup();
    while (events.length) {
        events.sort((a, b) => a.time - b.time || a.order - b.order);
        const next = events.shift();
        now = next.time;
        next.run();
        watch();
    }
    return JSON.parse(JSON.stringify({ ...log, now }));
};

const text = "Sure. This sentence is long enough to take a good while to make on battery. Short. "
    + "And this one is longer again, which is the case that used to end the reading early. Then a last one.";
const slow = reading(text);
failing = new Set(["Short."]);
const failed = reading(text);
// The last part failing while the player already waits on it.
const lastly = "And this one is longer again, which is the case that used to end the reading early.";
failing = new Set([lastly]);
const lastFailed = reading("Sure. " + lastly);
failing = new Set();
const stopped = reading(text, () => at(now + 1.5, () => root.stopSpeaking()));
// The server dying while a part plays: nothing it was asked for will come.
let crashedPlaying = false;
const crashed = reading(text, () => at(now + 0.6, () => {
    crashedPlaying = readerPlayer.playing;
    events.splice(0, events.length, ...events.filter(e => !e.server));
    onExited(1, 0);
}));
console.log(JSON.stringify({ slow, failed, lastFailed, stopped, crashed, crashedPlaying, parts: text.split(/(?<=[.!?])\\s+/) }));
"""
for name, src in {
    "AHEAD": ahead.group(1), "WAITING": waiting, "ENDED": ended, "EXITED": exited,
    "ENQUEUE": function("enqueue"), "PLAYENTRY": function("playEntry"), "FINISH": function("finish"),
    "FADEANDSTOP": function("fadeAndStop"), "SPEAK": function("speak"), "ASK": function("_askForParts"),
    "ONSPOKEN": function("_onSpoken"), "ENDIFDONE": function("_endIfDone"), "STOP": function("stopSpeaking"),
}.items():
    script = script.replace(f"__{name}__", src)

out = subprocess.run(["node", "-e", script], capture_output=True, text=True)
assert out.returncode == 0, out.stderr[-3000:]
result = json.loads(out.stdout)
parts = result["parts"]

slow = result["slow"]
assert [p["chunk"] for p in slow["played"]] == parts, \
    f"slower than real time, the reading played {[p['chunk'][:12] for p in slow['played']]} of {len(parts)} parts"
waits = [b["start"] - (a["start"] + len(a["chunk"]) * 0.062) for a, b in zip(slow["played"], slow["played"][1:])]
assert max(waits) > 0.5, "the stand-in server is no longer slow enough to leave a wait between parts"
last = slow["played"][-1]
assert slow["ended"] is not None and slow["ended"] >= last["start"] + len(last["chunk"]) * 0.062 - 1e-9, \
    "the reading was called over before its last part had played"
assert slow["maxAhead"] <= 2, f"{slow['maxAhead']} parts in the making at once: more than two ahead"
assert not slow["orphans"], "a part of the reading being played was thrown away as stale"

failed = result["failed"]
assert [p["chunk"] for p in failed["played"]] == [p for p in parts if p != "Short."], \
    f"a part failing mid-reading ended it: played {[p['chunk'][:12] for p in failed['played']]}"
assert not failed["errors"], "a part failing mid-reading reported an error, as only the first should"

last_failed = result["lastFailed"]
assert [p["chunk"] for p in last_failed["played"]] == ["Sure."], "the part before a failed last one did not play"
assert last_failed["ended"] is not None, "the last part failed while the player waited, and it waited on for ever"

stopped = result["stopped"]
assert stopped["ended"] is not None and stopped["ended"] <= 1.5 + 1e-9, "stopped, the reading did not end at once"
assert len(stopped["asked"]) <= 3, f"stopped, the server was still asked for {len(stopped['asked'])} parts"
assert len(stopped["played"]) <= 1, "a part arriving after the stop was played"

crashed = result["crashed"]
assert result["crashedPlaying"], "the stand-in server no longer dies while the first part plays"
assert crashed["ended"] is not None and [p["chunk"] for p in crashed["played"]] == ["Sure."], \
    "the server died while a part played, and the reading waited on the rest for ever"

print(f"ok: a reading slower than real time plays all {len(parts)} parts in order, waits rather than ends, and stops at once")
