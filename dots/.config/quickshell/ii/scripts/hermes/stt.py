"""Speech-to-text server for the Hermes sidebar -- transcribes a WAV the shell recorded.

Why this exists: dictation must use whatever STT provider Hermes is configured
with (`stt.provider` in ~/.hermes/config.yaml -- groq, openai, local, a command
provider), not a second engine the shell picked for itself. Setting the provider
in one place has to be enough.

Why the shell still records: the gateway's `voice.record` opens a PipeWire capture
it never releases, which also drags a Bluetooth headset from A2DP down to HSP. The
shell owns the microphone (pw-record, see SpeechToText.qml) and hands the finished
file here, so only the transcription is delegated.

Why a long-lived process: the agent's import graph and config resolution cost over
a second, and a one-shot script would pay it on every utterance. Started when
recording starts, so the cost is absorbed while the user is still speaking.

Protocol, JSON lines on stdin/stdout:
  -> {"id": "…", "wav": "/path/dictation.wav"}
  <- {"id": "…", "ok": true, "text": "…", "provider": "groq", "error": ""}
  <- {"event": "ready", "provider": "groq"}   once, after config resolves
Uses the agent's own `transcribe_recording`, so hallucination filtering and the
no-speech handling match what the agent would have done with the same audio.
"""
import json
import os
import sys

# Same preamble as tui_gateway/entry.py: a stray ``utils/`` in the launch
# directory must not shadow the agent's own modules (cwd is the checkout; stt.sh).
import hermes_bootstrap  # noqa: E402

hermes_bootstrap.harden_import_path()

from hermes_constants import get_hermes_home  # noqa: E402
from hermes_cli.env_loader import load_hermes_dotenv  # noqa: E402


def _emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def _provider_name() -> str:
    """Which backend `stt.provider` resolves to, for the status line. Best effort:
    the name is cosmetic and must never stop a transcription from running."""
    try:
        from tools.transcription_tools import _get_provider, _load_stt_config
        return str(_get_provider(_load_stt_config()) or "")
    except Exception:
        return ""


def _transcribe(wav_path: str) -> dict:
    from tools.voice_mode import transcribe_recording

    if not wav_path or not os.path.isfile(wav_path) or os.path.getsize(wav_path) == 0:
        return {"ok": False, "text": "", "error": "Nothing was recorded. Is an input device active?"}
    result = transcribe_recording(wav_path) or {}
    text = str(result.get("transcript") or "").strip()
    if not result.get("success"):
        return {"ok": False, "text": "", "error": str(result.get("error") or "Transcription failed")}
    # An empty transcript here is silence or a filtered hallucination, not a fault:
    # say so in the same words the local engine uses rather than as an error.
    if not text:
        return {"ok": False, "text": "", "error": "Didn't catch anything — try again a bit closer to the mic."}
    return {"ok": True, "text": text, "error": ""}


def main() -> int:
    load_hermes_dotenv(hermes_home=get_hermes_home(), project_env=os.path.join(os.getcwd(), ".env"))
    provider = _provider_name()
    _emit({"event": "ready", "provider": provider})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            continue
        try:
            reply = _transcribe(str(req.get("wav", "")))
        except Exception as e:  # one bad request must not take the server down
            reply = {"ok": False, "text": "", "error": f"{type(e).__name__}: {e}"}
        reply["id"] = req.get("id", "")
        reply["provider"] = provider
        _emit(reply)
    return 0


if __name__ == "__main__":
    sys.exit(main())
