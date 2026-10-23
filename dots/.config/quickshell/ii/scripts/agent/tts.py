"""Warm text-to-speech server for the sidebar's read-aloud -- synthesizes, never plays.

The shell plays the files itself, through a MediaPlayer it can fade and stop
gracefully; killing a player mid-waveform is a loud buzz on a Bluetooth sink.
So this only writes audio, one request per sentence group, answered in order so
the first clip can play while the rest render.

Two engines, picked per request (Settings > Agent > Voice):

  edge    Microsoft Edge's online neural TTS through the `edge-tts` package. The
          default: nothing to download, and the only provider that reports word
          boundaries, which let the shell mark the word being spoken exactly.
  kokoro  Kokoro-82M on this computer through `kokoro-onnx`, so nothing read
          aloud leaves it. The fp16 model: on an 11th-gen i7 it ran 3.7x faster
          than real time, against 3.2x for the 325 MB fp32 one and 0.8x -- too
          slow to keep up with playback -- for the "smaller" int8 one. Fetched
          into the request's `modelDir` on first use (~205 MB with the voices).
          It reports no timings, so each sentence is synthesized on its own and
          its words are spread over where the speech in it starts and ends:
          the estimate restarts at every sentence instead of drifting across
          a paragraph.

Both packages are in the shell's venv (sdata/uv/requirements.in).

Protocol, JSON lines on stdin/stdout:
  -> {"id", "text", "out", "engine", "voice", "modelDir"}
                                        synthesize `text` into `out` (kokoro
                                        writes a .wav beside it instead)
  <- {"event": "ready"}                 once, when requests can be sent
  <- {"event": "status", "text"}        something worth telling the user, such
                                        as the one-time model download
  <- {"id", "ok", "paths", "marks", "error"}

Voice and rate: ILLOGICAL_IMPULSE_TTS_VOICE (default en-US-AriaNeural, or
af_heart for kokoro), ILLOGICAL_IMPULSE_TTS_RATE (e.g. "+10%"). A request's own
"voice" (Settings > Agent's pick) wins over the variable.
"""
import asyncio
import contextlib
import json
import os
import re
import sys

import tts_marks

VOICE = os.environ.get("ILLOGICAL_IMPULSE_TTS_VOICE") or "en-US-AriaNeural"
RATE = os.environ.get("ILLOGICAL_IMPULSE_TTS_RATE") or "+0%"

KOKORO_RELEASE = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
KOKORO_FILES = ("kokoro-v1.0.fp16.onnx", "voices-v1.0.bin")
KOKORO_VOICE = "af_heart"


def _emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


_FENCE = re.compile(r"```.*?(```|$)", re.S)
_LINK = re.compile(r"\[([^\]]+)\]\([^)]+\)")
_URL = re.compile(r"https?://\S+")
_MARKUP = re.compile(r"(^|\s)[#>*+-]+\s+|[*_~`|]+")


def spoken(text: str) -> str:
    """What a person reading the reply aloud would say: no code blocks, no
    markdown punctuation, links as their text, bare URLs as "a link"."""
    text = _FENCE.sub(" (code) ", text or "")
    text = _LINK.sub(r"\1", text)
    text = _URL.sub("a link", text)
    text = _MARKUP.sub(lambda m: m.group(1) or "", text)
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    # A line without its own stop is still a pause when read aloud.
    return " ".join(line if line[-1] in ".!?:;," else line + "." for line in lines)


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
    from kokoro_onnx import Kokoro

    os.makedirs(model_dir, exist_ok=True)
    paths = [os.path.join(model_dir, name) for name in KOKORO_FILES]
    missing = [(name, path) for name, path in zip(KOKORO_FILES, paths) if not os.path.isfile(path)]
    if missing:
        _emit({"event": "status", "text": "Downloading the local voice once (about 205 MB). Reading starts when it's ready."})
        for name, path in missing:
            _download(f"{KOKORO_RELEASE}/{name}", path)
    _kokoro = Kokoro(*paths)
    return _kokoro


_SENTENCE = re.compile(r"(?<=[.!?;:])\s+")


def synthesize_kokoro(text: str, out_path: str, voice: str, model_dir: str) -> dict:
    import wave

    import numpy as np

    said = spoken(text)
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

    pieces, boundaries, at = [], [], 0
    try:
        for sentence in (s for s in _SENTENCE.split(said) if s.strip()):
            samples, rate = engine.create(sentence, voice=voice, speed=speed, lang=lang)
            # Where the speech is, between the clip's own lead-in and tail.
            loud = np.flatnonzero(np.abs(samples) > 0.02 * max(float(np.abs(samples).max()), 1e-6))
            start, end = (int(loud[0]), int(loud[-1])) if loud.size else (0, len(samples))
            words = sentence.split()
            weights = [len(word) + 1 for word in words]
            total, done = sum(weights), 0
            for word, weight in zip(words, weights):
                boundaries.append(((at + start + (end - start) * done / total) * 1000 // rate, word))
                done += weight
            pieces.append(samples)
            at += len(samples)
    except Exception as e:
        return {"ok": False, "paths": [], "marks": [], "error": f"Read-aloud failed: {e}"}

    wav_path = os.path.splitext(out_path)[0] + ".wav"
    os.makedirs(os.path.dirname(wav_path) or ".", exist_ok=True)
    pcm = (np.clip(np.concatenate(pieces), -1, 1) * 32767).astype("<i2")
    with wave.open(wav_path, "wb") as clip:
        clip.setnchannels(1)
        clip.setsampwidth(2)
        clip.setframerate(rate)
        clip.writeframes(pcm.tobytes())
    return {"ok": True, "paths": [wav_path], "error": "", "marks": tts_marks.marks(said, text, [(int(ms), w) for ms, w in boundaries])}


def synthesize(text: str, out_path: str, voice: str = "") -> dict:
    import edge_tts

    said = spoken(text)
    if not said.strip():
        return {"ok": False, "paths": [], "marks": [], "error": "nothing to say"}
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    boundaries = []

    async def stream() -> None:
        with open(out_path, "wb") as audio:
            async for chunk in edge_tts.Communicate(said, voice=voice or VOICE, rate=RATE, boundary="WordBoundary").stream():
                if chunk["type"] == "audio":
                    audio.write(chunk["data"])
                elif chunk["type"] == "WordBoundary":
                    boundaries.append((chunk["offset"] // 10_000, chunk["text"]))  # 100ns ticks

    try:
        asyncio.run(stream())
    except Exception as e:
        with contextlib.suppress(OSError):
            os.unlink(out_path)
        return {"ok": False, "paths": [], "marks": [], "error": f"Read-aloud failed: {e}"}
    if not (os.path.isfile(out_path) and os.path.getsize(out_path) > 0):
        return {"ok": False, "paths": [], "marks": [], "error": "Read-aloud produced no audio"}
    return {"ok": True, "paths": [out_path], "error": "", "marks": tts_marks.marks(said, text, boundaries)}


def main() -> int:
    try:
        import edge_tts  # noqa: F401
    except ImportError:
        print("[tts-missing] edge-tts is not installed in the shell's venv", file=sys.stderr, flush=True)
        return 127
    _emit({"event": "ready"})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except ValueError:
            continue
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
        _emit(reply)
    return 0


if __name__ == "__main__":
    sys.exit(main())
