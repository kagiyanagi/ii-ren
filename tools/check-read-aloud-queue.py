#!/usr/bin/env python3
"""A reading plays every part in order, and goes where it is moved, word-exact.

Read-aloud asks the synth server for a reply in parts (sentences) and plays each
as it comes back; the bar under the transcript is the whole reply, to drag or
click anywhere in. None of it shows in a still frame, so
services/AgentService.qml's reading logic -- asking for parts, taking replies,
the player's loading and ends, pausing, seeking, dragging -- is lifted out and
run under node on a virtual clock, against a stand-in server and a stand-in
player that behaves as Qt's was measured to (Qt 6.12, FFmpeg backend): a seek
issued while a clip loads is dropped, a source changed mid-play first reports
the old clip loaded, a clip loads in about 20 ms.

- Slower than real time (Kokoro on battery): every part plays in order, the gaps
  are waits rather than ends -- ending there was the local voice stopping after
  its first sentence -- and the reading ends only after its last part.
- A part that fails mid-reading is a gap; the first failing is an error.
- The server is asked for at most two parts at a time, and for none further
  than two past the part the reading is at -- a paused reading costs nothing --
  and what the reading moves away from is dropped from its queue.
- Paused -- in a part, between parts, before the first -- it is silent until
  resumed, and goes on from where it was.
- Moved -- back within the part playing, to a part made but not played, to one
  not made yet, back to one already played -- it goes on from the start of the
  word it was moved to, from the clips it kept.
- Dragged, the voice holds and the passage and word marked follow the bar; let
  go, it goes on from that word, or stays paused if it was.
- Stopped, or the server dying, ends it; a new reading replaces one in progress.

    python3 tools/check-read-aloud-queue.py
"""
import json
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
SERVICE = (II / "services/AgentService.qml").read_text()


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


def function(name, within=0):
    """`function name(...)` as plain JS, QML's type annotations dropped: the
    first one past `within`."""
    m = re.compile(rf"function {name}\(([^)]*)\)(?::\s*\w+)?\s*\{{").search(SERVICE, within)
    assert m, f"`{name}` is gone"
    params = ", ".join(p.split(":")[0].strip() for p in m.group(1).split(",") if p.strip())
    return f"function ({params}) " + block(m.group(0))


def binding(name):
    """A one-line `readonly property` binding's expression."""
    m = re.search(rf"readonly property \w+ {name}: (.+)", SERVICE)
    assert m, f"`{name}` is gone"
    return m.group(1).strip()


lifted = {
    "AHEAD": re.search(r"readonly property int _speakAhead: (\d+)", SERVICE).group(1),
    "DURATIONS": binding("_speakDurations"),
    "READINGDURATION": binding("readingDuration"),
    "PLAYING": binding("readingPlaying"),
    "PASSAGE": block("readonly property string speakingPassage: {"),
    "OFFSET": block("readonly property int speakingOffset: {"),
    "STATUS": block("onMediaStatusChanged: {"),
}
service_functions = ["speak", "_askForParts", "_onSpoken", "_playing", "_goTo", "_partEnded", "_seek", "beginScrub",
                     "scrubTo", "endScrub", "seekReading", "pauseSpeaking", "resumeSpeaking", "stopSpeaking",
                     "_endReading", "_clearReading", "_serverGone", "readingPositionNow"]
reader_functions = ["load", "seekWithin", "hold", "release", "fadeAndStop", "unload"]

script = r"""
const Timeline = require(__TIMELINE__);
const MediaPlayer = { StoppedState: 0, PlayingState: 1, PausedState: 2,
    NoMedia: 0, LoadingMedia: 1, LoadedMedia: 2, EndOfMedia: 6 };
const Config = { options: { agent: { ttsEngine: "kokoro" } } };
const Translation = { tr: s => s };

// ── Clock ──
let now = 0;
let events = [];
let order = 0;
const at = (time, run, tag) => { events.push({ time, run, tag, order: order++ }); };

// ── Server: one request at a time, in order; drops what it has not started ──
const SPEED = 1.1, OVERHEAD = 200, PER_CHAR = 62;    // measured for Kokoro on battery: tts.py
let failing = new Set();
let server;
let log;
const clipLength = text => text.length * PER_CHAR;
const wordMarks = text => [...text.matchAll(/\S+/g)].map(m => [m.index * PER_CHAR, m.index]);
const lengths = {};
let nextId = 0;
const answer = (request, reply) => {
    server.outstanding--;
    request.callback(reply);
};
const serve = () => {
    if (server.busy || server.dead || server.queue.length === 0)
        return;
    const request = server.queue.shift();
    server.busy = true;
    log.made.push(request.text);
    at(now + OVERHEAD + clipLength(request.text) / SPEED, () => {
        server.busy = false;
        answer(request, failing.has(request.text) ? { id: request.id, ok: false, paths: [], error: "boom" }
            : { id: request.id, ok: true, paths: [`/clip/${request.id}`], marks: wordMarks(request.text),
                duration: clipLength(request.text) });
        serve();
    }, "server");
};

// ── Player: as Qt's was measured ──
const readerOutput = { volume: 1 };
const readerPlayer = {
    playbackState: MediaPlayer.StoppedState, mediaStatus: MediaPlayer.NoMedia,
    _source: "", _position: 0, _since: 0, _token: 0, duration: 0, _heard: null,
    get source() { return this._source; },
    set source(value) {
        if (this._source !== "" && value !== "" && this.playbackState === MediaPlayer.PlayingState)
            this.status(MediaPlayer.LoadedMedia);   // the old clip, reported loaded first
        this.heardEnd();
        this._token++;
        this._source = value;
        this._position = 0;
        this.playbackState = MediaPlayer.StoppedState;
        this.mediaStatus = MediaPlayer.NoMedia;
        if (value === "")
            return;
        const token = this._token;
        at(now + 2, () => { if (this._token === token) this.status(MediaPlayer.LoadingMedia); });
        at(now + 20, () => {
            if (this._token !== token)
                return;
            this.duration = lengths[value];
            this.status(MediaPlayer.LoadedMedia);
        });
    },
    get position() {
        return this.playbackState === MediaPlayer.PlayingState
            ? Math.min(this.duration, this._position + now - this._since) : this._position;
    },
    set position(ms) {
        if (this.mediaStatus !== MediaPlayer.LoadedMedia)
            return;   // dropped, as Qt drops a seek before the clip has loaded
        this.heardEnd();
        this._position = Math.max(0, Math.min(ms, this.duration));
        this._since = now;
        this.run();
    },
    get playing() { return this.playbackState === MediaPlayer.PlayingState; },
    status(value) { this.mediaStatus = value; onStatus(); },
    play() {
        if (this.playbackState === MediaPlayer.PlayingState || this.mediaStatus !== MediaPlayer.LoadedMedia)
            return;
        this.playbackState = MediaPlayer.PlayingState;
        this._since = now;
        this.run();
    },
    pause() {
        this.heardEnd();
        this._position = this.position;
        this.playbackState = MediaPlayer.PausedState;
        this._token++;
    },
    stop() {
        this.heardEnd();
        const wasLoaded = this.mediaStatus !== MediaPlayer.NoMedia && this.playbackState !== MediaPlayer.StoppedState;
        this._position = 0;
        this.playbackState = MediaPlayer.StoppedState;
        this._token++;
        if (wasLoaded)
            this.status(MediaPlayer.LoadedMedia);   // stopped, Qt reports the clip loaded again
    },
    // Playing from here: heard from now, and over at the clip's end.
    run() {
        const token = ++this._token;
        if (this.playbackState !== MediaPlayer.PlayingState)
            return;
        this._heard = { clip: this._source, from: this._position, at: now };
        at(now + this.duration - this._position, () => {
            if (this._token !== token || this.playbackState !== MediaPlayer.PlayingState)
                return;
            this.heardEnd();
            this._position = this.duration;
            this.playbackState = MediaPlayer.StoppedState;
            this.status(MediaPlayer.EndOfMedia);
        });
    },
    heardEnd() {
        if (!this._heard)
            return;
        const to = Math.min(this.duration, this._heard.from + now - this._heard.at);
        if (to > this._heard.from)
            log.heard.push({ clip: this._heard.clip, from: Math.round(this._heard.from), to: Math.round(to), at: this._heard.at });
        this._heard = null;
    },
};
const readerMarks = {
    jump(ms) { },
    now() { return readerPlayer.position; },
    get position() { return readerPlayer.position; },
    get offset() {
        const clip = root._speakClips[reader.loadedIndex];
        const marks = clip && clip.marks ? clip.marks : [];
        if (marks.length === 0)
            return -1;
        let offset = marks[0][1];
        for (let i = 0; i < marks.length && marks[i][0] <= readerPlayer.position; i++)
            offset = marks[i][1];
        return offset;
    },
};
// The fades take their specs' durations: a part can end inside one.
const fade = (ms, done) => ({
    running: false, _token: 0,
    start() {
        this.running = true;
        const token = ++this._token;
        at(now + ms, () => { if (this._token === token && this.running) { this.running = false; done(); } });
    },
    stop() { this.running = false; this._token++; },
});
const fadeOut = fade(200, () => reader.unload());
const pauseFade = fade(130, () => readerPlayer.pause());
const resumeFade = fade(200, () => { readerOutput.volume = 1; });

const reader = { loadedIndex: -1, startAt: 0, playOnLoad: false, fadeIn: false, loading: false,
    player: readerPlayer, markClock: readerMarks };
const readerLoader = { active: false, item: reader };
const onStatus = () => __STATUS__;

// ── The service ──
const root = {
    speakingMessageId: "", speakingPaused: false, readingScrub: -1, _scrubResume: false,
    _speakEpoch: 0, _speakParts: [], _speakClips: [], _speakAsked: {}, _speakDropped: {},
    _speakIndex: 0, _speakStartMs: 0, _speakStartChar: -1, _speakAhead: __AHEAD__,
    get _speakDurations() { return __DURATIONS__; },
    get readingDuration() { return __READINGDURATION__; },
    get readingPlaying() { return __PLAYING__; },
    get speakingPassage() __PASSAGE__,
    get speakingOffset() __OFFSET__,
    interfaceRole: "interface",
    addMessage: text => log.errors.push(text),
    _splitForSpeech: text => text.split(/(?<=[.!?])\s+/),
    _removeFiles: paths => log.removed.push(...paths),
    _ttsRequest(text, callback) {
        const id = `r${nextId++}`;
        log.asked.push(text);
        log.askedAt.push(now);
        lengths[`file:///clip/${id}`] = clipLength(text);
        server.queue.push({ id, text, callback });
        log.maxAhead = Math.max(log.maxAhead, ++server.outstanding);
        at(now, serve, "server");
        return id;
    },
    _ttsDrop(ids) {
        for (const id of ids) {
            log.dropped.push(id);
            const queued = server.queue.find(r => r.id === id);
            if (!queued)
                continue;
            server.queue = server.queue.filter(r => r !== queued);
            at(now, () => answer(queued, { id, ok: false, dropped: true, paths: [] }), "server");
        }
    },
};
__SERVICE_FUNCTIONS__
__READER_FUNCTIONS__

// ── Running a reading ──
const sample = () => ({ at: now, passage: root.speakingPassage, offset: root.speakingOffset,
    position: Math.round(root.readingPositionNow()), playing: root.readingPlaying });
const reading = (text, setup) => {
    log = { asked: [], askedAt: [], made: [], dropped: [], heard: [], removed: [], errors: [], samples: [], ended: null, maxAhead: 0 };
    events = [];
    now = 0;
    server = { queue: [], busy: false, dead: false, outstanding: 0 };
    root.speakingMessageId = "turn";
    root.speak(text);
    if (setup)
        setup();
    while (events.length) {
        events.sort((a, b) => a.time - b.time || a.order - b.order);
        const next = events.shift();
        now = next.time;
        next.run();
        if (root.speakingMessageId === "" && log.ended === null)
            log.ended = now;
    }
    return JSON.parse(JSON.stringify({ ...log, paused: root.speakingPaused }));
};
const later = (time, run) => at(time, run, "user");
const look = time => later(time, () => log.samples.push(sample()));

const text = "Sure. This sentence is long enough to take a good while to make on battery. Short. "
    + "And this one is longer again, which is the case that used to end the reading early. Then a last one.";
const parts = text.split(/(?<=[.!?])\s+/);
// Where the bar is for a part's word: inside it, past its start.
const wordAt = (part, word) => {
    const durs = root._speakDurations;
    const index = parts.indexOf(part);
    const clip = root._speakClips[index];
    const char = part.indexOf(word);
    const ms = clip && clip.marks ? clip.marks.find(m => m[1] === char)[0] : char / part.length * durs[index];
    return Timeline.startOf(durs, index) + ms + 40;
};
const click = (time, part, word) => later(time, () => {
    const ms = wordAt(part, word);
    root.beginScrub(ms);
    root.endScrub(ms);
});

const results = {};
results.slow = reading(text);
failing = new Set(["Short."]);
results.failed = reading(text);
failing = new Set(["Sure."]);
results.failedFirst = reading(text);
failing = new Set();
results.stopped = reading(text, () => later(1500, () => root.stopSpeaking()));
results.crashed = reading(text, () => later(600, () => {
    server.dead = true;
    events = events.filter(e => e.tag !== "server");
    root._serverGone();
}));
results.replaced = reading(text, () => {
    later(6000, () => root.pauseSpeaking());
    later(7000, () => { root.speakingMessageId = "next"; root.speak("Something else entirely."); });
});
results.pausedIn = reading(text, () => { later(6000, () => root.pauseSpeaking()); later(16000, () => root.resumeSpeaking()); });
results.pausedBetween = reading(text, () => { later(1000, () => root.pauseSpeaking()); later(8000, () => root.resumeSpeaking()); });
results.pausedFirst = reading(text, () => { later(100, () => root.pauseSpeaking()); later(3000, () => root.resumeSpeaking()); });
results.pausedLong = reading(text, () => { later(100, () => root.pauseSpeaking()); later(60000, () => root.resumeSpeaking()); });
results.stoppedPaused = reading(text, () => { later(6000, () => root.pauseSpeaking()); later(7000, () => root.stopSpeaking()); });
results.seekBack = reading(text, () => { click(7000, parts[1], "long"); look(7001); });
results.seekAhead = reading(text, () => click(6000, parts[2], "Short."));
results.seekUnmade = reading(text, () => { click(1000, parts[4], "last"); look(1001); });
results.seekPlayed = reading(text, () => click(11000, parts[1], "while"));
results.drag = reading(text, () => {
    later(6000, () => root.beginScrub(wordAt(parts[1], "enough")));
    look(6001);
    later(6200, () => root.scrubTo(wordAt(parts[1], "make")));
    look(6201);
    later(6400, () => root.scrubTo(wordAt(parts[3], "case")));
    look(6401);
    look(6900);
    later(7000, () => root.endScrub(wordAt(parts[2], "Short.")));
    look(7100);
});
// Dragged while the part the reading waits on is made: it arrives held.
results.dragWaiting = reading(text, () => {
    later(1000, () => root.beginScrub(wordAt(parts[1], "This")));
    later(5500, () => root.endScrub(wordAt(parts[1], "long")));
});
results.dragPaused = reading(text, () => {
    later(6000, () => root.pauseSpeaking());
    click(6500, parts[1], "good");
    look(6600);
    later(9000, () => root.resumeSpeaking());
});
console.log(JSON.stringify({ results, parts, lengths: parts.map(clipLength), marks: parts.map(wordMarks) }));
"""
script = script.replace("__TIMELINE__", json.dumps(str(II / "services/readingTimeline.js")))
for name, src in lifted.items():
    script = script.replace(f"__{name}__", src)
script = script.replace("__SERVICE_FUNCTIONS__", "\n".join(f"root.{n} = ({function(n)});" for n in service_functions))
player = SERVICE.index("id: readerLoader")
script = script.replace("__READER_FUNCTIONS__", "\n".join(f"reader.{n} = ({function(n, player)});" for n in reader_functions))

out = subprocess.run(["node", "-e", script], capture_output=True, text=True)
assert out.returncode == 0, out.stderr[-3000:]
data = json.loads(out.stdout)
R, parts, lengths, marks = data["results"], data["parts"], data["lengths"], data["marks"]


def whole_parts(run):
    """The parts heard start to end, in order (None for a stretch that was not a whole part)."""
    return [lengths.index(round(h["to"])) if round(h["from"]) == 0 and round(h["to"]) in lengths else None for h in run["heard"]]


def start_of(word, index):
    """Where part `index`'s `word` starts in its clip."""
    char = parts[index].index(word)
    return next(ms for ms, c in marks[index] if c == char)


def silent(run, start, end):
    """Nothing was heard between `start` and `end`."""
    return not [h for h in run["heard"] if h["at"] < end and h["at"] + h["to"] - h["from"] > start + 1]


def heard_from(run, time):
    """The stretches heard that began at or after `time`."""
    return [h for h in run["heard"] if h["at"] >= time]


slow = R["slow"]
assert whole_parts(slow) == list(range(len(parts))), f"slower than real time, heard {whole_parts(slow)} of {len(parts)} parts"
gaps = [b["at"] - (a["at"] + a["to"]) for a, b in zip(slow["heard"], slow["heard"][1:])]
assert max(gaps) > 500, "the stand-in server is no longer slow enough to leave a wait between parts"
end = slow["heard"][-1]["at"] + slow["heard"][-1]["to"]
assert slow["ended"] is not None and slow["ended"] >= end - 1, "the reading was called over before its last part had played"
assert slow["maxAhead"] <= 2, f"{slow['maxAhead']} parts in the making at once: more than two ahead"
assert len(slow["asked"]) == len(parts) and not slow["dropped"], "a reading heard straight through asked twice, or dropped one"
assert len(slow["removed"]) == len(parts), "the reading's clips were not all deleted once it was over"

failed = R["failed"]
assert whole_parts(failed) == [0, 1, 3, 4] and not failed["errors"], \
    f"a part failing mid-reading ended it or reported: heard {whole_parts(failed)}, {failed['errors']}"
failed_first = R["failedFirst"]
assert failed_first["errors"] and failed_first["ended"] is not None and not failed_first["heard"], \
    "the opening part failing did not end the reading with an error"
stopped = R["stopped"]
assert stopped["ended"] == 1500 and whole_parts(stopped) == [0], "stopped while waiting, the reading did not end at once"
crashed = R["crashed"]
assert crashed["ended"] is not None and whole_parts(crashed) == [0], \
    "the server died while a part played, and the reading waited on the rest for ever"
replaced = R["replaced"]
assert silent(replaced, 6130, 7000) and replaced["heard"][-1]["to"] == len("Something else entirely.") * 62, \
    "a new reading while one was paused did not replace it"

paused_in = R["pausedIn"]
assert silent(paused_in, 6130, 16000), "paused, the reading went on being heard"
resumed = heard_from(paused_in, 16000)
assert resumed and resumed[0]["at"] == 16000 and resumed[0]["from"] > 0, \
    "resumed, the part it was paused in started over rather than carrying on"
assert round(sum(h["to"] - h["from"] for h in paused_in["heard"])) == sum(lengths), \
    "paused and resumed, a stretch was skipped or heard twice"
paused_between = R["pausedBetween"]
assert silent(paused_between, 1000, 8000) and heard_from(paused_between, 8000)[0]["at"] == 8000, \
    "paused between parts, the part that came meanwhile played before the reading was resumed"
paused_first = R["pausedFirst"]
assert paused_first["heard"][0]["at"] == 3000, "paused before the first part came, it played on arrival rather than on resume"
paused_long = R["pausedLong"]
asked_paused = [text for text, t in zip(paused_long["asked"], paused_long["askedAt"]) if t < 60000]
assert asked_paused == parts[:3], \
    f"paused at the first part for a minute, the server was asked for {len(asked_paused)} parts, not that one and two more"
assert whole_parts(paused_long) == list(range(len(parts))) and paused_long["heard"][0]["at"] == 60000, \
    "paused at the start for a minute, the reading did not play through once resumed"
stopped_paused = R["stoppedPaused"]
assert stopped_paused["ended"] == 7000 and silent(stopped_paused, 6130, 10 ** 9) and not stopped_paused["paused"], \
    "stopped while paused, the reading did not end at once"

seek_back = R["seekBack"]
after = heard_from(seek_back, 7000)
assert after and after[0]["at"] == 7000 and after[0]["from"] == start_of("long", 1), \
    f"moved back within the part playing, it went on from {after and after[0]['from']}, not the start of the word"
assert (seek_back["samples"][0]["passage"], seek_back["samples"][0]["offset"]) == (parts[1], parts[1].index("long")), \
    "moved, the transcript did not mark the word it was moved to at once"

seek_ahead = R["seekAhead"]
after = heard_from(seek_ahead, 6000)
assert after and after[0]["from"] == 0 and after[0]["to"] == lengths[2] and after[0]["at"] < 6100, \
    "moved to a part made but not played, it did not play it straight away"

seek_unmade = R["seekUnmade"]
first = seek_unmade["samples"][0]
assert first["passage"] == parts[4] and abs(first["offset"] - parts[4].index("last")) <= 2, \
    f"moved to a part not made yet, the transcript marked {first} rather than the word it was moved to"
assert seek_unmade["dropped"], "moved away from the parts being made, they were not dropped from the server's queue"
assert seek_unmade["made"] == parts[:2] + [parts[4]], \
    f"moved to a part not made, the server made {seek_unmade['made']}, not the part being made then that one"
after = heard_from(seek_unmade, 1000)
assert after and after[0]["from"] == start_of("last", 4), "a part made after the reading moved to it did not start at the word"

seek_played = R["seekPlayed"]
after = heard_from(seek_played, 11000)
assert after and after[0]["from"] == start_of("while", 1) and seek_played["asked"].count(parts[1]) == 1, \
    "moved back to a part already played, it was not replayed from its kept clip at the word"

drag = R["drag"]
s0, s1, s2, s3, s4 = drag["samples"]
assert (s0["passage"], s0["offset"]) == (parts[1], parts[1].index("enough")), f"pressed, the mark is at {s0}"
assert (s1["passage"], s1["offset"]) == (parts[1], parts[1].index("make")), f"dragged within a part, the mark is at {s1}"
assert s2["passage"] == parts[3] and abs(s2["offset"] - parts[3].index("case")) <= 2, \
    f"dragged to a part not made yet, the mark is at {s2}"
assert (s3["passage"], s3["offset"]) == (s2["passage"], s2["offset"]), "held still mid-drag, the mark moved"
assert not s1["playing"] and silent(drag, 6130, 7000), "dragged, the voice went on rather than holding"
assert (s4["passage"], s4["offset"]) == (parts[2], 0) and s4["playing"], f"let go, the reading is at {s4}"

drag_waiting = R["dragWaiting"]
after = heard_from(drag_waiting, 1000)
assert after and after[0]["at"] == 5500 and after[0]["from"] == start_of("long", 1), \
    "a part made while the bar was dragged played before it was let go"

drag_paused = R["dragPaused"]
s0 = drag_paused["samples"][0]
assert (s0["passage"], s0["offset"]) == (parts[1], parts[1].index("good")) and not s0["playing"], \
    "clicked while paused, the reading did not move there and stay paused"
after = heard_from(drag_paused, 6500)
assert after and after[0]["at"] == 9000 and after[0]["from"] == start_of("good", 1), \
    "resumed after a click while paused, it did not go on from the word clicked"

print(f"ok: a reading of {len(parts)} parts plays in order slower than real time, pauses, and goes where it is moved or dragged, word-exact")
