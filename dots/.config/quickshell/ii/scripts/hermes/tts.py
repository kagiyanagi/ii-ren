"""Warm text-to-speech server for the Hermes sidebar -- synthesizes, never plays.

Why this exists: the gateway's `voice.tts` synthesizes and then plays the result
itself through an `ffplay` child, and exposes no way to stop that playback. The
shell needs the audio *file*, so it can play it through its own MediaPlayer where
stop() drains the stream gracefully and can be faded first.

Why it is a long-lived process: the provider is set up once per start -- the
agent's import graph and the voice config -- and a one-shot script would pay that
on every request. Measured on Edge: ~1.4s to a ready server, then ~0.6-1.2s per
request, which is round-trip latency rather than compute. Local providers (piper,
kokoro) trade that for a multi-second model load, which this also absorbs.

The shell sends one request per sentence group rather than one per reply, so the
first clip can start playing while the rest are still being made; replies are
answered in the order they arrive, which is what keeps the clips in order.

With edge -- the default provider -- the synthesis is streamed here rather than
handed to the tool, because the word boundaries edge reports come only off that
stream and are thrown away by anything that just saves the file. They are the
only exact timing available, and they are what lets the shell mark the word being
spoken instead of guessing from how far the clip has played.

Protocol, JSON lines on stdin/stdout:
  -> {"id": "…", "text": "…", "out": "/path/file.mp3"}
  <- {"id": "…", "ok": true, "paths": ["/path/file.mp3", …], "marks": [[ms, offset], …], "error": ""}
  <- {"event": "ready"}                      once, after the warm-up synth
Uses the agent's own text normalizer and `text_to_speech_tool`, so the voice is
identical to what the agent would have spoken.
"""
import asyncio
import contextlib
import json
import os
import sys
import tempfile

# Same preamble as tui_gateway/entry.py: a stray ``utils/`` in the launch
# directory must not shadow the agent's own modules (cwd is the checkout; tts.sh).
import hermes_bootstrap  # noqa: E402

hermes_bootstrap.harden_import_path()

from hermes_constants import get_hermes_home  # noqa: E402
from hermes_cli.env_loader import load_hermes_dotenv  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tts_marks  # noqa: E402


def _emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def _spoken(text: str) -> str:
    """The agent's cleaner: markdown, emoji, code fences, units. Without it the
    voice reads asterisks and backticks aloud."""
    try:
        from tools.tts_text_normalize import prepare_spoken_text
        return prepare_spoken_text(text, max_chars=None) or ""
    except Exception:
        return (text or "").strip()


def _synthesize_edge(spoken: str, source: str, out_path: str) -> dict:
    """edge-tts, streamed here for its word boundaries. None when it is not the
    configured provider, or when anything at all goes wrong -- the tool below
    synthesizes the same text the same way, only without the timings."""
    try:
        import edge_tts
        from tools.tts_tool import _get_provider, _load_tts_config
        from tools.tts_tool_providers import DEFAULT_EDGE_VOICE
    except Exception:
        return None

    config = _load_tts_config()
    if _get_provider(config) != "edge":
        return None
    # Same resolution as the agent's own `_generate_edge_tts`, so the voice does
    # not change depending on which path synthesized the clip.
    edge_config = config.get("edge") or {}
    speed = float(edge_config.get("speed", config.get("speed", 1.0)))
    # Sentence boundaries are the library's default; a word is what gets marked.
    kwargs = {"voice": edge_config.get("voice", DEFAULT_EDGE_VOICE), "boundary": "WordBoundary"}
    if speed != 1.0:
        kwargs["rate"] = f"{round((speed - 1.0) * 100):+d}%"

    boundaries = []

    async def stream() -> None:
        with open(out_path, "wb") as audio:
            async for chunk in edge_tts.Communicate(spoken, **kwargs).stream():
                if chunk["type"] == "audio":
                    audio.write(chunk["data"])
                elif chunk["type"] == "WordBoundary":
                    boundaries.append((chunk["offset"] // 10_000, chunk["text"]))  # 100ns ticks

    try:
        asyncio.run(stream())
    except Exception:
        with contextlib.suppress(OSError):
            os.unlink(out_path)
        return None
    if not (os.path.isfile(out_path) and os.path.getsize(out_path) > 0):
        return None
    return {"ok": True, "paths": [out_path], "error": "",
            "marks": tts_marks.marks(spoken, source, boundaries)}


def _synthesize(text: str, out_path: str) -> dict:
    from tools.tts_tool import text_to_speech_tool
    spoken = _spoken(text)
    if not spoken.strip():
        return {"ok": False, "paths": [], "error": "nothing to say"}
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    timed = _synthesize_edge(spoken, text, out_path)
    if timed is not None:
        return timed
    raw = text_to_speech_tool(text=spoken, output_path=out_path)
    try:
        result = json.loads(raw) if isinstance(raw, str) else (raw or {})
    except Exception:
        result = {}
    # The tool result is authoritative: long-form output may be several files.
    paths = result.get("file_paths") or ([result.get("file_path")] if result.get("file_path") else [out_path])
    paths = [p for p in paths if p and os.path.isfile(p) and os.path.getsize(p) > 0]
    ok = bool(result.get("success")) and bool(paths)
    return {"ok": ok, "paths": paths, "marks": [],
            "error": "" if ok else str(result.get("error") or "TTS produced no audio")}


def _warm_up() -> None:
    """Load the model now so the first real request answers in ~1s, not ~8s."""
    fd, path = tempfile.mkstemp(prefix="hermes-tts-warm-", suffix=".mp3")
    os.close(fd)
    try:
        _synthesize("Ready.", path)
    except Exception:
        pass
    finally:
        with contextlib.suppress(OSError):
            os.unlink(path)


def main() -> int:
    load_hermes_dotenv(hermes_home=get_hermes_home(), project_env=os.path.join(os.getcwd(), ".env"))
    _warm_up()
    _emit({"event": "ready"})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            continue
        rid = req.get("id", "")
        try:
            reply = _synthesize(str(req.get("text", "")), str(req.get("out", "")))
        except Exception as e:  # one bad request must not take the server down
            reply = {"ok": False, "paths": [], "marks": [], "error": f"{type(e).__name__}: {e}"}
        reply["id"] = rid
        _emit(reply)
    return 0


if __name__ == "__main__":
    sys.exit(main())
