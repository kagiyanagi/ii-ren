"""Warm text-to-speech server for the sidebar's read-aloud -- synthesizes, never plays.

The shell plays the files itself, through a MediaPlayer it can fade and stop
gracefully; killing a player mid-waveform is a loud buzz on a Bluetooth sink.
So this only writes audio, one request per sentence group, answered in order so
the first clip can play while the rest render.

The voice is Microsoft Edge's online neural TTS through the `edge-tts` package
(in the shell's venv, see sdata/uv/requirements.in). Edge is also the only
provider that reports word boundaries, which are what let the shell mark the
word being spoken instead of guessing from how far the clip has played.

Protocol, JSON lines on stdin/stdout:
  -> {"id", "text", "out"}             synthesize `text` into the file `out`
  <- {"event": "ready"}                 once, when requests can be sent
  <- {"id", "ok", "paths", "marks", "error"}

Voice and rate: ILLOGICAL_IMPULSE_TTS_VOICE (default en-US-AriaNeural),
ILLOGICAL_IMPULSE_TTS_RATE (e.g. "+10%"). A request's own "voice" (Settings >
Agent's pick) wins over the variable.
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
            reply = synthesize(str(req.get("text", "")), str(req.get("out", "")), str(req.get("voice") or ""))
        except Exception as e:  # one bad request must not take the server down
            reply = {"ok": False, "paths": [], "marks": [], "error": f"{type(e).__name__}: {e}"}
        reply["id"] = req.get("id", "")
        _emit(reply)
    return 0


if __name__ == "__main__":
    sys.exit(main())
