"""Warm text-to-speech server for the Hermes sidebar -- synthesizes, never plays.

Why this exists: the gateway's `voice.tts` synthesizes and then plays the result
itself through an `ffplay` child, and exposes no way to stop that playback. The
shell needs the audio *file*, so it can play it through its own MediaPlayer where
stop() drains the stream gracefully and can be faded first.

Why it is a long-lived process: the piper model takes ~8s to load and ~1s to
synthesize once loaded. A one-shot script pays the load on every request.

Protocol, JSON lines on stdin/stdout:
  -> {"id": "…", "text": "…", "out": "/path/file.mp3"}
  <- {"id": "…", "ok": true, "paths": ["/path/file.mp3", …], "error": ""}
  <- {"event": "ready"}                      once, after the warm-up synth
Uses the agent's own text normalizer and `text_to_speech_tool`, so the voice is
identical to what the agent would have spoken.
"""
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


def _synthesize(text: str, out_path: str) -> dict:
    from tools.tts_tool import text_to_speech_tool
    spoken = _spoken(text)
    if not spoken.strip():
        return {"ok": False, "paths": [], "error": "nothing to say"}
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    raw = text_to_speech_tool(text=spoken, output_path=out_path)
    try:
        result = json.loads(raw) if isinstance(raw, str) else (raw or {})
    except Exception:
        result = {}
    # The tool result is authoritative: long-form output may be several files.
    paths = result.get("file_paths") or ([result.get("file_path")] if result.get("file_path") else [out_path])
    paths = [p for p in paths if p and os.path.isfile(p) and os.path.getsize(p) > 0]
    ok = bool(result.get("success")) and bool(paths)
    return {"ok": ok, "paths": paths, "error": "" if ok else str(result.get("error") or "TTS produced no audio")}


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
            reply = {"ok": False, "paths": [], "error": f"{type(e).__name__}: {e}"}
        reply["id"] = rid
        _emit(reply)
    return 0


if __name__ == "__main__":
    sys.exit(main())
