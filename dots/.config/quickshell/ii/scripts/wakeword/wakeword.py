#!/usr/bin/env python3
"""Always-on wake word detection, printed as one JSON line per event.

    {"event": "wake", "phrase": "hey_scout", "score": 0.83}
    {"event": "utterance", "path": "/tmp/.../utterance.wav", "ms": 2480}
    {"event": "level", "rms": 0.42}

This process owns the microphone for the whole cycle: it listens, detects the
phrase, and keeps recording the request that follows, then hands over a finished
WAV. Splitting those across two processes was tried and is wrong - the mic has to
be reopened between them, and every utterance loses its first word in the gap.

The detector is openWakeWord's, run directly on onnxruntime rather than through
the package. Three models chain together:

    audio -> melspectrogram.onnx -> embedding_model.onnx -> <phrase>.onnx -> score

Only the last one is per-phrase and it is ~1MB; the two expensive ones are shared,
so watching for three phrases costs barely more than watching for one.

Cost control is the RMS gate. A quiet room never reaches the ONNX models at all -
the frame is measured and dropped - so idle cost is a memcpy per 80ms rather than
a spectrogram. The gate opens ahead of speech (one chunk of lookback) and closes
well after it (hangover), so nothing that matters is computed on a truncated
buffer.

stdlib + numpy + onnxruntime, all already in the shell's venv. No new dependency.
"""

import argparse
import json
import os
import signal
import subprocess
import sys
import wave

# Before numpy and onnxruntime are imported, because both read these at import
# time and never again. Without them each spawns a pool sized to the machine -
# measured, nine threads on an 8-core laptop - which sit parked forever. The work
# here is a 32-bin spectrogram every 80ms; it is single-threaded by nature, and a
# pool of idle threads is memory and scheduler noise for nothing.
for _pool in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
              "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_pool, "1")

import numpy as np

# ---------------------------------------------------------------------------
# Audio + model constants. These are openWakeWord's and are not free parameters:
# the embedding model was trained on exactly this framing, so changing any of them
# silently destroys accuracy rather than raising.
# ---------------------------------------------------------------------------

# How this capture stream identifies itself to PipeWire. PrivacyMonitor.qml
# matches on exactly this string, so the two must stay in step.
STREAM_TAG = "quickshell-wakeword"

# Audio buffer PipeWire is asked for. See open_microphone for the measurements
# behind this number.
CAPTURE_LATENCY = "100ms"

SAMPLE_RATE = 16000
CHUNK_SAMPLES = 1280            # 80ms, the recommended frame size
CHUNK_BYTES = CHUNK_SAMPLES * 2  # s16 mono
MEL_BINS = 32
MEL_HOP = 160                   # 10ms
# The mel model loses three frames to its own window: frames = samples//160 - 3,
# verified against the model for everything from 800 to 32000 samples. So a chunk
# handed over on its own yields 5 frames where the true streaming rate is 8, and a
# detector built that way quietly runs 37% slow and never fills its feature buffer.
# Feeding MEL_CONTEXT samples of the previous chunk back in restores the missing
# three; the result is bit-exact against computing the whole file at once.
MEL_CONTEXT = 3 * MEL_HOP       # 480 samples
MEL_FRAMES_PER_CHUNK = CHUNK_SAMPLES // MEL_HOP  # 8
MEL_WINDOW = 76                 # frames per embedding window
MEL_STRIDE = 8                  # window hop
EMBEDDING_DIM = 96
MEL_BUFFER_MAX = 10 * 97        # 10s of mel frames
FEATURE_BUFFER_MAX = 120

# The melspectrogram model emits raw log-mel; openWakeWord scales it into the
# range the embedding model was trained on. Without this every score is garbage.
MEL_SCALE = 10.0
MEL_OFFSET = 2.0

# ---------------------------------------------------------------------------
# Gate + endpointing. These *are* tunable - they trade latency against CPU and
# against clipping the end of a sentence.
# ---------------------------------------------------------------------------

# Absolute floor, normalised RMS. Below this it is silence no matter what the
# room noise estimate says - stops a dead-silent room from adapting its floor to
# zero and then gating on the mic's own hiss.
ABSOLUTE_FLOOR = 0.004
# How far above the measured room noise a chunk must sit to open the gate.
NOISE_MULTIPLIER = 2.2
# Chunks of speech kept after the level drops, so a word ending quietly still
# reaches the model with its buffer intact. 12 * 80ms ~ 1s.
GATE_HANGOVER_CHUNKS = 12
# How fast the room-noise estimate follows the room. Slow: it must not adapt to
# speech itself, only to the fan turning on.
NOISE_EMA_ALPHA = 0.02

# After a detection, ignore the models for this long so one spoken phrase fires
# once rather than on every overlapping window.
REFRACTORY_CHUNKS = 25          # 2s

# The classifier scores the last 16 embeddings, which take about 2.0s of audio to
# accumulate. So the gate cannot just switch the models on when speech starts: by
# the time the buffer had filled, the wake phrase would sit at the *front* of the
# window, and these models only score it at the end - measured, it reads 0.000
# there against 0.999 in the right place.
#
# Instead a ring of raw audio is kept while the gate is shut, and replayed into
# the detector the instant it opens. That both fills the buffer and puts the
# phrase where the model expects it. The cost is one burst of ~28 frames per
# onset of speech, not per frame of silence, so the gate still does its job.
WARMUP_CHUNKS = 28              # 2.24s, past the ~2.0s the window needs

# Utterance capture.
PREROLL_CHUNKS = 4              # 320ms before the detection point
SILENCE_TO_END_CHUNKS = 8       # 640ms of quiet ends the request
MIN_UTTERANCE_CHUNKS = 7        # 560ms; below this it was a cough
MAX_UTTERANCE_CHUNKS = 150      # 12s hard stop, not a normal exit

# End of speech is a fraction of the request's own peak level. Judging it against
# an absolute level does not survive a change of microphone or room: too high and
# people are cut off mid-sentence, too low and the pause after "..." never counts
# as silence and the capture runs to MAX_UTTERANCE_CHUNKS every time.
END_RATIO = 0.15


def emit(**payload):
    """One JSON line, flushed. The shell reads these with a SplitParser."""
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def read_exact(stream, count):
    """Block until `count` bytes have arrived. Returns b"" at end of stream.

    pw-record's stdout is an unbuffered pipe, and a raw read returns whatever
    happens to be in it - which for a 2560-byte frame is usually less. Treating
    a short read as the end of the stream made the detector exit the instant it
    started, silently, having already said it was ready.
    """
    parts = []
    have = 0
    while have < count:
        block = stream.read(count - have)
        if not block:
            return b""
        parts.append(block)
        have += len(block)
    return b"".join(parts)


class Detector:
    """The openWakeWord feature chain plus one classifier per phrase."""

    def __init__(self, model_dir, phrases):
        import onnxruntime as ort

        # Single thread each. These models are tiny and always-on; letting
        # onnxruntime spin up a pool per session costs more in context switching
        # than it saves, and this has to stay invisible in `top`.
        opts = ort.SessionOptions()
        opts.inter_op_num_threads = 1
        opts.intra_op_num_threads = 1
        opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL

        def load(name):
            path = os.path.join(model_dir, name)
            if not os.path.isfile(path):
                raise FileNotFoundError(path)
            return ort.InferenceSession(path, sess_options=opts,
                                        providers=["CPUExecutionProvider"])

        self.mel = load("melspectrogram.onnx")
        self.emb = load("embedding_model.onnx")

        self.phrases = []
        for phrase in phrases:
            session = ort.InferenceSession(phrase["path"], sess_options=opts,
                                           providers=["CPUExecutionProvider"])
            # Read the window length off the model instead of assuming 16: a
            # custom-trained classifier may well want a different one, and a
            # mismatch here is an ONNX shape error at the worst possible moment.
            shape = session.get_inputs()[0].shape
            frames = shape[1] if isinstance(shape[1], int) else 16
            self.phrases.append({
                "name": phrase["name"],
                "session": session,
                "input": session.get_inputs()[0].name,
                "frames": frames,
                "threshold": phrase["threshold"],
            })

        self.mel_buffer = np.zeros((0, MEL_BINS), dtype=np.float32)
        self.mel_consumed = 0
        self.feature_buffer = np.zeros((0, EMBEDDING_DIM), dtype=np.float32)
        self.audio_tail = np.zeros(0, dtype=np.float32)

    def reset(self):
        """Drop the buffers. Called when the gate closes.

        A wake phrase cannot span a silence, so nothing useful is lost - and
        keeping stale frames would let two unrelated sounds either side of a
        pause be scored as one word.
        """
        self.mel_buffer = self.mel_buffer[:0]
        self.mel_consumed = 0
        self.feature_buffer = self.feature_buffer[:0]
        self.audio_tail = self.audio_tail[:0]

    def push(self, samples):
        """Feed one 80ms chunk (float32, in int16 range).

        The chunk is prefixed with the tail of the previous one so the mel model
        sees the overlap its window needs - see MEL_CONTEXT.
        """
        block = np.concatenate((self.audio_tail, samples)) \
            if len(self.audio_tail) else samples
        self.audio_tail = samples[-MEL_CONTEXT:].copy()

        spec = self.mel.run(None, {"input": block[None, :]})[0]
        # (1, 1, frames, 32) -> (frames, 32)
        spec = spec.reshape(-1, MEL_BINS)
        spec = spec / MEL_SCALE + MEL_OFFSET
        self.mel_buffer = np.concatenate((self.mel_buffer, spec), axis=0)

        # Every window that has become complete since last time.
        while len(self.mel_buffer) - self.mel_consumed >= MEL_WINDOW:
            window = self.mel_buffer[self.mel_consumed:self.mel_consumed + MEL_WINDOW]
            vector = self.emb.run(None, {"input_1": window[None, :, :, None].astype(np.float32)})[0]
            self.feature_buffer = np.concatenate(
                (self.feature_buffer, vector.reshape(1, EMBEDDING_DIM)), axis=0)
            self.mel_consumed += MEL_STRIDE

        # Trim from the front, moving the read cursor with it.
        if len(self.mel_buffer) > MEL_BUFFER_MAX:
            drop = len(self.mel_buffer) - MEL_BUFFER_MAX
            self.mel_buffer = self.mel_buffer[drop:]
            self.mel_consumed = max(0, self.mel_consumed - drop)
        if len(self.feature_buffer) > FEATURE_BUFFER_MAX:
            self.feature_buffer = self.feature_buffer[-FEATURE_BUFFER_MAX:]

    def best(self):
        """Highest-scoring phrase over threshold, or None.

        Returns the best rather than the first so that when "scout" and
        "hey scout" both fire on the same audio - which they will, one contains
        the other - the more specific match is the one reported.
        """
        winner = None
        for phrase in self.phrases:
            if len(self.feature_buffer) < phrase["frames"]:
                continue
            window = self.feature_buffer[-phrase["frames"]:][None, :, :].astype(np.float32)
            score = float(phrase["session"].run(None, {phrase["input"]: window})[0].squeeze())
            if score >= phrase["threshold"] and (winner is None or score > winner[1]):
                winner = (phrase["name"], score)
        return winner


def open_microphone(source):
    """pw-record streaming raw s16 mono 16k to stdout.

    The default source is deliberately avoided unless asked for: on a machine
    with a Bluetooth headset it is usually the headset, and opening that mic
    makes PipeWire renegotiate the card from A2DP to HSP/HFP - which stops music
    mid-track. The built-in mic leaves the Bluetooth card alone. Same reasoning,
    and the same awk, as SpeechToText.qml.
    """
    if source == "default":
        target = ""
    elif source:
        target = source
    else:
        try:
            listing = subprocess.run(["pactl", "list", "short", "sources"],
                                     capture_output=True, text=True, timeout=5).stdout
        except (OSError, subprocess.SubprocessError):
            listing = ""
        target = ""
        for line in listing.splitlines():
            fields = line.split()
            if len(fields) >= 2 and fields[1].startswith("alsa_input.") \
                    and not fields[1].endswith(".monitor"):
                target = fields[1]
                break

    # Tagged so the shell's privacy indicator can recognise this particular
    # stream. It is deliberately a tag and not the binary name: hiding every
    # pw-record would also hide a recording the user started themselves, which is
    # exactly what that indicator is for.
    command = ["pw-record", "-P", f'{{ application.name = "{STREAM_TAG}" }}',
               # Without an explicit latency the stream negotiates a ~110 sample
               # quantum (~7ms) and delivers audio in slivers: measured, 46 wakeups
               # a second between the two processes. Asking for 100ms halves that
               # to 23/s, and wakeups - not the 0.3% CPU - are what keep a laptop
               # out of its deep idle states. Larger buffers were measured too and
               # buy nothing: 100ms, 200ms, 320ms and 500ms all give 23/s, so this
               # takes the smallest one that gets the full saving rather than
               # paying for it in detection latency.
               "--latency", CAPTURE_LATENCY,
               "--rate", str(SAMPLE_RATE), "--channels", "1",
               "--format", "s16"]
    if target:
        command += ["--target", target]
    command.append("-")  # stdout
    return subprocess.Popen(command, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, bufsize=0)


class ReplaySource:
    """A WAV pretending to be the microphone, for testing the live loop.

    Same duck type as the pw-record Popen, so the loop under test is the real one
    rather than a copy of it that can drift from it.
    """

    class _Reader:
        # Deliberately short reads. A pipe hands over whatever it has, and a
        # harness that always returns exactly what was asked for is kinder than
        # reality - which is how a short-read bug once passed replay and still
        # died against a real microphone.
        MAX_PER_READ = 1000

        def __init__(self, pcm):
            self._pcm = pcm
            self._at = 0

        def read(self, count):
            take = min(count, ReplaySource._Reader.MAX_PER_READ)
            block = self._pcm[self._at:self._at + take]
            self._at += len(block)
            return block

    def __init__(self, path):
        with wave.open(path, "rb") as handle:
            if handle.getframerate() != SAMPLE_RATE or handle.getsampwidth() != 2:
                raise ValueError(f"expected 16kHz 16-bit, got {handle.getframerate()}Hz "
                                 f"{handle.getsampwidth() * 8}-bit")
            pcm = handle.readframes(handle.getnframes())
            if handle.getnchannels() > 1:
                pcm = np.frombuffer(pcm, dtype=np.int16)[::handle.getnchannels()].tobytes()
        self.stdout = ReplaySource._Reader(pcm)

    def terminate(self):
        pass

    def wait(self, timeout=None):
        return 0

    def kill(self):
        pass


def write_wav(path, chunks):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(b"".join(chunks))


def run(args):
    phrases = []
    for spec in args.model:
        # NAME=PATH:THRESHOLD, threshold optional.
        name, _, rest = spec.partition("=")
        path, _, threshold = rest.rpartition(":")
        if not path:  # no threshold given
            path, threshold = rest, ""
        path = os.path.expanduser(path)
        if not os.path.isfile(path):
            emit(event="error", reason=f"No wake model at {path}")
            return 2
        phrases.append({
            "name": name,
            "path": path,
            "threshold": float(threshold) if threshold else args.threshold,
        })
    if not phrases:
        emit(event="error", reason="No wake phrase models configured.")
        return 2

    try:
        detector = Detector(os.path.expanduser(args.model_dir), phrases)
    except FileNotFoundError as missing:
        emit(event="error", reason=f"Missing shared wake model: {missing}")
        return 2

    microphone = ReplaySource(args.replay) if args.replay else open_microphone(args.source)
    if microphone.stdout is None:
        emit(event="error", reason="Could not open the microphone.")
        return 2

    stopping = {"now": False}

    def stop(_signum, _frame):
        stopping["now"] = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    noise = ABSOLUTE_FLOOR
    gate_open_for = 0
    refractory = 0
    lookback = []
    capturing = False
    captured = []
    silence_run = 0
    speech_peak = 0.0
    level_tick = 0

    emit(event="ready", phrases=[p["name"] for p in phrases])

    try:
        while not stopping["now"]:
            raw = read_exact(microphone.stdout, CHUNK_BYTES)
            if not raw:
                break

            pcm = np.frombuffer(raw, dtype=np.int16)
            samples = pcm.astype(np.float32)
            rms = float(np.sqrt(np.mean(np.square(samples / 32768.0))))

            floor = max(ABSOLUTE_FLOOR, noise * NOISE_MULTIPLIER)
            loud = rms > floor
            was_open = gate_open_for > 0
            if loud:
                gate_open_for = GATE_HANGOVER_CHUNKS
            else:
                gate_open_for = max(0, gate_open_for - 1)
                # Only quiet chunks teach the noise estimate, so speech never
                # raises the floor above itself - and never during a capture.
                # Letting it adapt mid-request drags the floor down to
                # ABSOLUTE_FLOOR, at which point ordinary room tone reads as
                # speech, the silence run resets on every frame, and the request
                # only ends at the hard stop seconds later.
                if not capturing:
                    noise = (1 - NOISE_EMA_ALPHA) * noise + NOISE_EMA_ALPHA * rms

            if capturing:
                captured.append(raw)
                speech_peak = max(speech_peak, rms)
                # Silence measured against how loudly this person actually spoke,
                # rather than an absolute level. Mic gain and room tone differ by
                # orders of magnitude between machines, so a fixed threshold either
                # cuts people off mid-sentence or never fires at all.
                quiet_below = max(floor, speech_peak * END_RATIO)
                silence_run = 0 if rms > quiet_below else silence_run + 1
                done = (silence_run >= SILENCE_TO_END_CHUNKS
                        and len(captured) >= MIN_UTTERANCE_CHUNKS) \
                    or len(captured) >= MAX_UTTERANCE_CHUNKS
                emit(event="level", rms=round(min(1.0, rms * 12), 3))
                if done:
                    write_wav(args.utterance, captured)
                    emit(event="utterance", path=args.utterance,
                         ms=int(len(captured) * CHUNK_SAMPLES / SAMPLE_RATE * 1000))
                    capturing = False
                    captured = []
                    refractory = REFRACTORY_CHUNKS
                    detector.reset()
                continue

            # Raw audio kept while the gate is shut: it both warms the detector on
            # the way in (see WARMUP_CHUNKS) and gives capture its pre-roll, so the
            # first word of the request is not clipped by starting a beat late.
            lookback.append(raw)
            if len(lookback) > WARMUP_CHUNKS:
                lookback.pop(0)

            if refractory > 0:
                refractory -= 1
                continue

            if gate_open_for == 0:
                # Silence: the models are not run at all. This is the whole
                # reason this can sit in the background permanently.
                if len(detector.mel_buffer):
                    detector.reset()
                level_tick += 1
                if level_tick % 12 == 0:
                    emit(event="level", rms=round(min(1.0, rms * 12), 3))
                continue

            if not was_open:
                # Speech just started. Replay what came before it so the phrase is
                # scored against a full window ending where the phrase ends.
                for past in lookback[:-1]:
                    detector.push(np.frombuffer(past, dtype=np.int16).astype(np.float32))

            detector.push(samples)
            hit = detector.best()
            if hit is not None:
                emit(event="wake", phrase=hit[0], score=round(hit[1], 3))
                capturing = True
                captured = lookback[-PREROLL_CHUNKS:]
                lookback = []
                silence_run = 0
                speech_peak = 0.0
                detector.reset()
    finally:
        microphone.terminate()
        try:
            microphone.wait(timeout=2)
        except subprocess.TimeoutExpired:
            microphone.kill()

    return 0


def scan_wav(args):
    """Score a WAV file offline, printing every frame over the threshold.

    This is how a threshold gets chosen. Point it at a recording of the phrase to
    see whether it fires and how hard, and at half an hour of podcast to count
    what it fires on when it shouldn't. Tuning by ear instead of by this is how
    you end up with a wake word that answers the television.
    """
    phrases = []
    for spec in args.model:
        name, _, rest = spec.partition("=")
        path, _, threshold = rest.rpartition(":")
        if not path:
            path, threshold = rest, ""
        phrases.append({"name": name, "path": os.path.expanduser(path),
                        "threshold": float(threshold) if threshold else args.threshold})
    detector = Detector(os.path.expanduser(args.model_dir), phrases)

    with wave.open(args.wav, "rb") as handle:
        if handle.getframerate() != SAMPLE_RATE or handle.getsampwidth() != 2:
            print(f"expected 16kHz 16-bit, got {handle.getframerate()}Hz "
                  f"{handle.getsampwidth() * 8}-bit", file=sys.stderr)
            return 2
        channels = handle.getnchannels()
        pcm = np.frombuffer(handle.readframes(handle.getnframes()), dtype=np.int16)
    if channels > 1:
        pcm = pcm[::channels]

    peak = {}
    hits = 0
    for start in range(0, len(pcm) - CHUNK_SAMPLES + 1, CHUNK_SAMPLES):
        detector.push(pcm[start:start + CHUNK_SAMPLES].astype(np.float32))
        seconds = start / SAMPLE_RATE
        for phrase in detector.phrases:
            if len(detector.feature_buffer) < phrase["frames"]:
                continue
            window = detector.feature_buffer[-phrase["frames"]:][None, :, :].astype(np.float32)
            score = float(phrase["session"].run(None, {phrase["input"]: window})[0].squeeze())
            peak[phrase["name"]] = max(peak.get(phrase["name"], 0.0), score)
            if score >= phrase["threshold"]:
                hits += 1
                print(f"{seconds:7.2f}s  {phrase['name']:<16} {score:.3f}")
    for name, best in peak.items():
        print(f"peak {name}: {best:.3f}", file=sys.stderr)
    print(f"{hits} frame(s) over threshold", file=sys.stderr)
    return 0


def selftest():
    """Exercise the chain on synthetic audio - no mic, no trained phrase.

    Checks the shapes the whole design rests on, and that the gate really does
    skip silence, which is the difference between this being background noise in
    `top` and being a problem.
    """
    model_dir = os.path.expanduser(
        os.environ.get("WAKEWORD_MODEL_DIR", "~/.local/share/vynx-conduit/wakeword"))
    phrase = os.path.join(model_dir, "hey_jarvis_v0.1.onnx")
    detector = Detector(model_dir, [{"name": "t", "path": phrase, "threshold": 0.5}])

    rng = np.random.default_rng(0)
    chunks = 40
    for _ in range(chunks):
        detector.push((rng.standard_normal(CHUNK_SAMPLES) * 2000).astype(np.float32))

    assert detector.mel_buffer.shape[1] == MEL_BINS, detector.mel_buffer.shape
    # Regression guard on the mel rate. Only the very first chunk is short, having
    # no previous audio to overlap with; every one after it must yield the full 8.
    # If this ever reads 5 per chunk again, the left-context overlap has been lost
    # and detection will silently stop working rather than fail.
    expected = (CHUNK_SAMPLES // MEL_HOP - 3) + (chunks - 1) * MEL_FRAMES_PER_CHUNK
    assert detector.mel_buffer.shape[0] == expected, \
        f"mel rate wrong: {detector.mel_buffer.shape[0]} frames, expected {expected}"
    assert detector.feature_buffer.shape[1] == EMBEDDING_DIM, detector.feature_buffer.shape
    # 40 chunks is 3.2s, comfortably past the ~2.0s the classifier needs to fill
    # its 16-frame window - so this also proves the buffer actually fills.
    assert len(detector.feature_buffer) >= 16, \
        f"only {len(detector.feature_buffer)} embeddings after {chunks} chunks"

    # Noise must not be a wake word.
    assert detector.best() is None, "false positive on white noise"

    # Window length is read off the model, not assumed.
    assert detector.phrases[0]["frames"] == 16, detector.phrases[0]["frames"]

    detector.reset()
    assert len(detector.mel_buffer) == 0 and len(detector.feature_buffer) == 0

    # The gate arithmetic: a silent chunk must sit under the floor, a spoken-level
    # one above it.
    quiet = float(np.sqrt(np.mean(np.square(
        (rng.standard_normal(CHUNK_SAMPLES) * 3).astype(np.float32) / 32768.0))))
    speech = float(np.sqrt(np.mean(np.square(
        (rng.standard_normal(CHUNK_SAMPLES) * 3000).astype(np.float32) / 32768.0))))
    assert quiet < ABSOLUTE_FLOOR < speech, (quiet, speech)

    print("ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", default="~/.local/share/vynx-conduit/wakeword",
                        help="Where the shared melspectrogram/embedding models live")
    parser.add_argument("--model", action="append", default=[],
                        metavar="NAME=PATH[:THRESHOLD]",
                        help="A phrase classifier. Repeatable.")
    parser.add_argument("--threshold", type=float, default=0.5,
                        help="Default score threshold when a model gives none")
    parser.add_argument("--source", default="",
                        help="PipeWire node name, 'default', or empty to pick a "
                             "non-Bluetooth hardware input")
    parser.add_argument("--utterance",
                        default="/tmp/quickshell/vynx-conduit/stt/utterance.wav",
                        help="Where the captured request is written")
    parser.add_argument("--replay", default="",
                        help="Drive the live loop from a WAV instead of the mic, "
                             "for testing detection through to the captured file")
    parser.add_argument("--wav", default="",
                        help="Score a WAV file offline instead of the microphone, "
                             "for choosing a threshold")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()

    if args.selftest:
        selftest()
        return 0
    if args.wav:
        return scan_wav(args)
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
