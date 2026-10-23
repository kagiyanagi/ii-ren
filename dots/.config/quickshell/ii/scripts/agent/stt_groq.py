#!/usr/bin/env python3
"""Online dictation: send one recording to Groq's hosted Whisper and print the text.

The opt-in alternative to the local whisper.cpp (services/agent/SpeechToText.qml,
Settings > Agent > Voice). Groq runs whisper-large-v3-turbo -- the local Best
model, unquantized -- on its own hardware, so a clip comes back in about a second
on any machine. The price is that the audio leaves it, and an account.

The key is the user's own, from console.groq.com, saved by Settings > Agent > Voice
as a keyring entry of its own (KEY_ATTRS). Not in services/KeyringStorage.qml's
shared JSON: the shell and the settings app each hold a copy of that and write it
back whole, so a key saved from one process was lost the next time the other saved.
It is read here at every use rather than handed over by the shell, so it never
sits in a command line (`ps` shows those to every user) and a key saved in the
settings app works on the next dictation without the shell having to hear about
it. $GROQ_API_KEY is the fallback for a machine without a keyring.

Usage: stt_groq.py AUDIO.wav LANGUAGE [PROMPT]
  LANGUAGE  an ISO-639-1 code, or "auto" to let the model detect it

Standard library only. Exit codes, which SpeechToText.qml turns into messages:
  0 the transcript on stdout       5 the keyring is locked
  3 the recording is empty         6 the key was refused
  4 no key saved                   7 rate limited
                                   8 anything else, the reason on stderr
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
import uuid

ENDPOINT = "https://api.groq.com/openai/v1/audio/transcriptions"
MODEL = "whisper-large-v3-turbo"
HERE = os.path.dirname(os.path.abspath(__file__))
IS_UNLOCKED = os.path.join(HERE, "..", "keyring", "is_unlocked.sh")
# Shared with modules/settings/AgentConfig.qml, which stores and clears it.
KEY_ATTRS = ["application", "ii-ren", "secret", "groq-api-key"]


def api_key() -> str:
    """The saved key, or exits with the reason there is none."""
    try:
        found = subprocess.run(["secret-tool", "lookup", *KEY_ATTRS], capture_output=True, text=True, timeout=30)
        if found.returncode == 0 and found.stdout.strip():
            return found.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    env = os.environ.get("GROQ_API_KEY", "").strip()
    if env:
        return env
    try:
        locked = subprocess.run([IS_UNLOCKED], capture_output=True, timeout=10).returncode != 0
    except (OSError, subprocess.TimeoutExpired):
        locked = False
    sys.exit(5 if locked else 4)


def multipart(fields: dict, audio_path: str) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    with open(audio_path, "rb") as audio:
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="dictation.wav"\r\n'
                     "Content-Type: audio/wav\r\n\r\n".encode() + audio.read() + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit("usage: stt_groq.py AUDIO.wav LANGUAGE [PROMPT]")
    audio, language = sys.argv[1], sys.argv[2]
    prompt = sys.argv[3].strip() if len(sys.argv) > 3 else ""
    # A WAV header alone is 44 bytes; anything that small holds no speech.
    if not os.path.isfile(audio) or os.path.getsize(audio) <= 44:
        sys.exit(3)
    key = api_key()

    fields = {"model": MODEL, "response_format": "text", "temperature": "0"}
    if language and language != "auto":
        fields["language"] = language
    if prompt:
        fields["prompt"] = prompt
    body, content_type = multipart(fields, audio)
    request = urllib.request.Request(ENDPOINT, data=body, method="POST", headers={
        "Authorization": f"Bearer {key}",
        "Content-Type": content_type,
        # Cloudflare in front of Groq answers urllib's default agent with a 403
        # (error 1010) before the key is even looked at.
        "User-Agent": "ii-ren-dictation",
    })
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            sys.stdout.write(response.read().decode("utf-8", "replace").strip() + "\n")
    except urllib.error.HTTPError as error:
        if error.code in (401, 403):
            sys.exit(6)
        if error.code == 429:
            sys.exit(7)
        detail = error.read().decode("utf-8", "replace")
        try:
            detail = json.loads(detail)["error"]["message"]
        except (ValueError, KeyError, TypeError):
            pass
        print(f"Groq answered {error.code}: {detail}".strip(), file=sys.stderr)
        sys.exit(8)
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        print(f"Could not reach Groq: {getattr(error, 'reason', error)}", file=sys.stderr)
        sys.exit(8)


if __name__ == "__main__":
    main()
