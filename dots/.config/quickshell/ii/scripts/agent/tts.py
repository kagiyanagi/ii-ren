"""Warm text-to-speech server for the sidebar's read-aloud -- synthesizes, never plays.

The shell plays the files itself, through a MediaPlayer it can fade and stop
gracefully; killing a player mid-waveform is a loud buzz on a Bluetooth sink.
So this only writes audio, one request per sentence group, answered in order so
the first clip can play while the rest render. What it says is what the
transcript shows, read as a person would (tts_text.py): no markdown or LaTeX
syntax, a formula in words.

Two engines, picked per request (Settings > Agent > Voice):

  edge    Microsoft Edge's online neural TTS through the `edge-tts` package. The
          default: nothing to download. Reports a boundary per word, which lets
          the shell mark the word being spoken; see _MP3_PRIMING_MS for the one
          correction those need.
  kokoro  Kokoro-82M on this computer through `kokoro-onnx`, so nothing read
          aloud leaves it. Fetched into the request's `modelDir` on first use
          (~205 MB with the voices). The onnx-community export that also outputs
          each phoneme's duration, so words are marked when they are actually
          said rather than estimated. Measured against the alternatives, side by
          side on an 11th-gen i7 on battery: as fast as the untimed fp16 export
          (1.1x real time); the release's timed fp32 ran 0.9x, its timed fp16 0.6x
          and its int8 0.2x -- too slow to keep up with playback.

Both packages are in the shell's venv (sdata/uv/requirements.in).

Protocol, JSON lines on stdin/stdout:
  -> {"id", "text", "out", "engine", "voice", "modelDir"}
                                        synthesize `text` into `out` (kokoro
                                        writes a .wav beside it instead)
  -> {"drop": [id, ...]}                forget requests not yet started: the
                                        reading moved somewhere they are not
  <- {"event": "ready"}                 once, when requests can be sent
  <- {"event": "status", "text"}        something worth telling the user, such
                                        as the one-time model download
  <- {"id", "ok", "paths", "marks", "duration", "error"}
                                        `duration` in ms, as the player will
                                        play it; a dropped request is answered
                                        {"id", "ok": false, "dropped": true}

Requests are made one at a time, in order. They are read on a thread of their
own, so a drop reaches the queue while a request is still being made.

Voice and rate: ILLOGICAL_IMPULSE_TTS_VOICE (default en-US-AriaNeural, or
af_heart for kokoro), ILLOGICAL_IMPULSE_TTS_RATE (e.g. "+10%"). A request's own
"voice" (Settings > Agent's pick) wins over the variable.
"""
import asyncio
import collections
import contextlib
import json
import os
import sys
import threading

import tts_marks
import tts_text

VOICE = os.environ.get("ILLOGICAL_IMPULSE_TTS_VOICE") or "en-US-AriaNeural"
RATE = os.environ.get("ILLOGICAL_IMPULSE_TTS_RATE") or "+0%"

# (local name, where from, MB). The model is pinned to a revision: a re-export
# could rename the duration output this relies on.
KOKORO_FILES = (
    ("kokoro-v1.0-timestamped.uint8.onnx",
     "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX-timestamped/resolve/"
     "dd4401a9add81ac692d20e240d22ec9dda82cc29/onnx/model_uint8.onnx", 177),
    ("voices-v1.0.bin",
     "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin", 28),
)
# The untimed model the first local read-aloud fetched, removed once replaced.
KOKORO_SUPERSEDED = "kokoro-v1.0.fp16.onnx"
KOKORO_VOICE = "af_heart"
# Kokoro's audio leads the frames its durations put it in: its own timestamps
# start three 25 ms frames early (hexgrad/kokoro, KPipeline.join_timestamps).
# Checked against 117 word onsets found in the audio alone, over five voices:
# with this and tts_marks' stress rule the mark lands a median 12 ms ahead of a
# word after a full stop and 37 ms ahead after a comma (it was 125 and 88 ms
# behind, read off the phoneme). Ahead is the side to miss on: a picture is
# noticed running ahead of its sound only past ~125 ms, behind it past ~45 ms
# (ITU-R BT.1359).
_KOKORO_LEAD_S = 3 * 600 / 24000

# Edge sends MP3 without a gapless (Xing/Info) header, so the decoder -- ffmpeg,
# here and in Qt -- plays LAME's priming before the first real sample: 576
# encoder + 529 decoder samples, 1105 at Edge's 24 kHz. Word offsets count from
# the real first sample, so uncorrected, the mark ran ahead of the voice.
# Measured on Ryan and Aria: vowel-initial words after a pause sounded 28-48 ms
# after their offset, at the 10 ms resolution of the onset detector.
_MP3_PRIMING_MS = 1105 * 1000 // 24000

# edge-tts waits 10 s to connect and 60 s for each message by default. A
# sentence's messages come close together, so a 60 s wait is a stalled
# connection: the reading fell silent on it for up to a minute, then lost the
# sentence. Given up on sooner, and tried once more on a fresh connection.
_EDGE_CONNECT_S = 5
_EDGE_RECEIVE_S = 10
_EDGE_ATTEMPTS = 2


_emitting = threading.Lock()


def _emit(obj: dict) -> None:
    with _emitting:  # a drop is answered from the reading thread
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


# MPEG audio frame header fields: bitrate (kbps) by version and index, sample
# rate by version, for Layer III (ISO 11172-3, 13818-3).
_MP3_KBPS = {1: (0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320),
             2: (0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160)}
_MP3_RATES = {1: (44100, 48000, 32000), 2: (22050, 24000, 16000), 2.5: (11025, 12000, 8000)}


def _mp3_duration_ms(path: str) -> int:
    """How long the player plays an MP3: every frame it decodes, the priming
    included, as a count of samples -- not an estimate off the bitrate."""
    with open(path, "rb") as f:
        data = f.read()
    samples, rate, at = 0, 0, 0
    while at + 4 <= len(data):
        b1, b2 = data[at + 1], data[at + 2]
        if data[at] != 0xFF or b1 & 0xE0 != 0xE0 or (b1 >> 1) & 3 != 1:  # sync, Layer III
            at += 1
            continue
        version = {3: 1, 2: 2, 0: 2.5}.get((b1 >> 3) & 3)
        index = b2 >> 4  # 0 is free format, 15 forbidden: neither is a frame here
        kbps = _MP3_KBPS[1 if version == 1 else 2][index] if version and index < 15 else 0
        if not kbps or (b2 >> 2) & 3 == 3:
            at += 1
            continue
        rate = _MP3_RATES[version][(b2 >> 2) & 3]
        per_frame = 1152 if version == 1 else 576
        at += per_frame // 8 * kbps * 1000 // rate + ((b2 >> 1) & 1)
        samples += per_frame
    return samples * 1000 // rate if rate else 0


def spoken(text: str) -> str:
    """What is said for `text`: what the transcript shows, as it would be read."""
    return tts_text.spoken(text)


def _download(url: str, dest: str) -> None:
    """To a .part beside `dest`, then moved: an interrupted transfer never
    leaves a truncated model that would fail to load next time."""
    import urllib.request

    part = dest + ".part"
    request = urllib.request.Request(url, headers={"User-Agent": "ii-ren-read-aloud"})
    with urllib.request.urlopen(request, timeout=60) as response, open(part, "wb") as out:
        while block := response.read(1 << 20):
            out.write(block)
    os.replace(part, dest)


_kokoro = None


def _kokoro_engine(model_dir: str):
    """The loaded model, fetching it the first time. Kept for the server's life:
    loading costs about half a second, synthesis much less per sentence."""
    global _kokoro
    if _kokoro is not None:
        return _kokoro
    import onnxruntime
    from kokoro_onnx import Kokoro

    # Its graph optimizer notes every fp16 node it cannot fold, dozens of lines
    # the shell would log as read-aloud output.
    onnxruntime.set_default_logger_severity(3)
    os.makedirs(model_dir, exist_ok=True)
    paths = [os.path.join(model_dir, name) for name, _, _ in KOKORO_FILES]
    missing = [(url, path, mb) for (_, url, mb), path in zip(KOKORO_FILES, paths) if not os.path.isfile(path)]
    if missing:
        size = sum(mb for _, _, mb in missing)
        _emit({"event": "status", "text": f"Downloading the local voice once (about {size} MB). Reading starts when it's ready."})
        for url, path, _ in missing:
            _download(url, path)
    with contextlib.suppress(OSError):
        os.unlink(os.path.join(model_dir, KOKORO_SUPERSEDED))
    engine = Kokoro(*paths)
    # kokoro-onnx reads timings from an output named "duration"; this export
    # calls it "durations" (frames, as floats) and puts it in the same place.
    if "durations" in {o.name for o in engine.sess.get_outputs()}:
        engine.has_timings = True
    _kokoro = engine
    return _kokoro


def _phonemize_words(words: list, lang: str) -> list:
    """Each word's phonemes said on its own, through the espeak-ng kokoro-onnx
    loaded. One call for the lot: espeak starts up once per call."""
    import phonemizer

    return phonemizer.phonemize(words, lang, preserve_punctuation=True, with_stress=True)


def synthesize_kokoro(text: str, out_path: str, voice: str, model_dir: str) -> dict:
    import wave

    import numpy as np

    said, at = tts_text.speech(text)
    if not said.strip():
        return {"ok": False, "paths": [], "marks": [], "error": "nothing to say"}
    try:
        engine = _kokoro_engine(model_dir)
    except ImportError:
        return {"ok": False, "paths": [], "marks": [], "error": "Local read-aloud needs kokoro-onnx in the shell's venv. Run `iiren update`."}
    except OSError as e:
        return {"ok": False, "paths": [], "marks": [], "error": f"Could not download the local voice: {e}"}

    voice = voice or (VOICE if not VOICE.startswith("en-") else KOKORO_VOICE)
    # Kokoro's voice ids lead with their accent: a = American, b = British.
    lang = "en-gb" if voice.startswith("b") else "en-us"
    try:
        speed = 1 + float(RATE.strip().rstrip("%")) / 100
    except ValueError:
        speed = 1.0

    words = said.split()
    try:
        samples, rate, timings = engine.create_timed(said, voice=voice, speed=speed, lang=lang)
        starts = tts_marks.phoneme_word_starts(
            _phonemize_words(words, lang), [(t.phoneme, t.start) for t in timings])
    except Exception as e:
        return {"ok": False, "paths": [], "marks": [], "error": f"Read-aloud failed: {e}"}
    # A word with no phonemes of its own (a dash) gets no mark, and the one before
    # stays marked through it. Never earlier than the last: the mark only moves on.
    boundaries, latest = [], 0.0
    for word, start in zip(words, starts):
        if start is not None:
            latest = max(latest, start - _KOKORO_LEAD_S)
            boundaries.append((int(latest * 1000), word))

    wav_path = os.path.splitext(out_path)[0] + ".wav"
    os.makedirs(os.path.dirname(wav_path) or ".", exist_ok=True)
    pcm = (np.clip(samples, -1, 1) * 32767).astype("<i2")
    with wave.open(wav_path, "wb") as clip:
        clip.setnchannels(1)
        clip.setsampwidth(2)
        clip.setframerate(rate)
        clip.writeframes(pcm.tobytes())
    return {"ok": True, "paths": [wav_path], "error": "", "marks": tts_marks.marks(said, at, boundaries),
            "duration": len(pcm) * 1000 // rate}


def synthesize(text: str, out_path: str, voice: str = "") -> dict:
    import edge_tts

    said, at = tts_text.speech(text)
    if not said.strip():
        return {"ok": False, "paths": [], "marks": [], "error": "nothing to say"}
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    boundaries = []

    async def stream() -> None:
        boundaries.clear()  # an attempt that stalled leaves none behind
        with open(out_path, "wb") as audio:
            communicate = edge_tts.Communicate(said, voice=voice or VOICE, rate=RATE, boundary="WordBoundary",
                                               connect_timeout=_EDGE_CONNECT_S, receive_timeout=_EDGE_RECEIVE_S)
            async for chunk in communicate.stream():
                if chunk["type"] == "audio":
                    audio.write(chunk["data"])
                elif chunk["type"] == "WordBoundary":
                    boundaries.append((chunk["offset"] // 10_000 + _MP3_PRIMING_MS, chunk["text"]))  # 100ns ticks

    for _attempt in range(_EDGE_ATTEMPTS):
        try:
            asyncio.run(stream())
            break
        except Exception as e:
            failure = e
    else:
        with contextlib.suppress(OSError):
            os.unlink(out_path)
        return {"ok": False, "paths": [], "marks": [], "error": f"Read-aloud failed: {failure}"}
    if not (os.path.isfile(out_path) and os.path.getsize(out_path) > 0):
        return {"ok": False, "paths": [], "marks": [], "error": "Read-aloud produced no audio"}
    return {"ok": True, "paths": [out_path], "error": "", "marks": tts_marks.marks(said, at, boundaries),
            "duration": _mp3_duration_ms(out_path)}


def _serve(req: dict) -> dict:
    try:
        text, out, voice = str(req.get("text", "")), str(req.get("out", "")), str(req.get("voice") or "")
        if req.get("engine") == "kokoro":
            model_dir = str(req.get("modelDir") or os.path.expanduser("~/.local/share/vynx-conduit/models"))
            reply = synthesize_kokoro(text, out, voice, model_dir)
        else:
            reply = synthesize(text, out, voice)
    except Exception as e:  # one bad request must not take the server down
        reply = {"ok": False, "paths": [], "marks": [], "error": f"{type(e).__name__}: {e}"}
    reply["id"] = req.get("id", "")
    return reply


def main() -> int:
    try:
        import edge_tts  # noqa: F401
    except ImportError:
        print("[tts-missing] edge-tts is not installed in the shell's venv", file=sys.stderr, flush=True)
        return 127
    queue, ready, done = collections.deque(), threading.Condition(), threading.Event()

    def read() -> None:
        for line in sys.stdin:
            try:
                req = json.loads(line)
            except ValueError:
                continue
            with ready:
                if "drop" in req:
                    dropped = set(req["drop"])
                    for gone in [r for r in queue if r.get("id") in dropped]:
                        queue.remove(gone)
                        _emit({"id": gone.get("id", ""), "ok": False, "dropped": True, "paths": [], "marks": [], "error": ""})
                else:
                    queue.append(req)
                ready.notify()
        done.set()
        with ready:
            ready.notify()

    threading.Thread(target=read, daemon=True).start()
    _emit({"event": "ready"})
    while True:
        with ready:
            while not queue and not done.is_set():
                ready.wait()
            if not queue:
                return 0
            req = queue.popleft()
        _emit(_serve(req))


if __name__ == "__main__":
    sys.exit(main())
