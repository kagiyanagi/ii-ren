#!/usr/bin/env python3
"""Local read-aloud marks the word being said, restarting the estimate per sentence.

Edge reports a boundary per word; Kokoro, the on-this-computer voice in
scripts/agent/tts.py, reports none. Left to the shell's fallback, the highlight is
the clip's playback fraction spread over the whole chunk, and every pause and
lead-in drifts it further for the rest of a paragraph. So tts.py synthesizes each
sentence on its own, finds where the speech in it starts and ends, and spreads
that sentence's words across it. Nothing short of listening shows it, so a stand-in
engine with known silences plays Kokoro here:

- each sentence's first word is marked where its speech starts, past the clip's
  lead-in and the previous sentence's tail -- the estimate restarts there;
- marks rise in time and in offset, and every offset lands on its word in the
  text as written, markdown and all (tts_marks.py aligns spoken to source);
- the clip is a .wav beside the requested path, as long as the pieces together.

Needs numpy, which the shell's venv has; run with any python3, it re-runs itself
under that venv when the system one lacks it.

    python3 tools/check-local-voice.py
"""
import os
import sys

try:
    import numpy as np
except ImportError:
    venv = os.path.expanduser(os.environ.get("ILLOGICAL_IMPULSE_VIRTUAL_ENV", "~/.local/state/quickshell/.venv"))
    python = os.path.join(venv, "bin", "python")
    assert os.path.exists(python) and sys.executable != python, f"needs numpy: no shell venv at {venv}"
    os.execv(python, [python, *sys.argv])

import tempfile
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/scripts/agent"))
import tts  # noqa: E402

RATE = 24000
LEAD, TAIL = 0.10, 0.25  # seconds of silence around each sentence's speech
PER_CHAR = 0.06


class FakeKokoro:
    """Silence, then speech in proportion to the sentence, then silence."""

    def __init__(self):
        self.calls = []

    def create(self, sentence, voice, speed, lang):
        self.calls.append((sentence, voice, lang))
        speech = np.full(int(len(sentence) * PER_CHAR * RATE), 0.5, dtype=np.float32)
        return np.concatenate([np.zeros(int(LEAD * RATE), np.float32), speech,
                               np.zeros(int(TAIL * RATE), np.float32)]), RATE


fake = FakeKokoro()
tts._kokoro = fake
source = "Here is the **plan**. Update the `sidebar`, then restart it! Done."

with tempfile.TemporaryDirectory() as tmp:
    reply = tts.synthesize_kokoro(source, f"{tmp}/clip.mp3", "bf_emma", tmp)
    assert reply["ok"], reply
    assert reply["paths"] == [f"{tmp}/clip.wav"], reply["paths"]
    with wave.open(reply["paths"][0]) as clip:
        frames, rate = clip.getnframes(), clip.getframerate()

said = tts.spoken(source)
sentences = [s for s in tts._SENTENCE.split(said) if s.strip()]
assert [c[0] for c in fake.calls] == sentences, f"one synthesis per sentence: {fake.calls}"
assert all(lang == "en-gb" for _, _, lang in fake.calls), "a b-voice is British English"
assert rate == RATE
expected = sum(int(LEAD * RATE) + int(len(s) * PER_CHAR * RATE) + int(TAIL * RATE) for s in sentences)
assert frames == expected, f"the clip is the pieces together: {frames} != {expected}"

marks = reply["marks"]
assert len(marks) == len(said.split()), f"a mark per word: {marks}"
times, offsets = [m[0] for m in marks], [m[1] for m in marks]
assert times == sorted(times) and len(set(times)) == len(times), f"marks rise in time: {times}"
assert offsets == sorted(offsets), f"marks rise through the text: {offsets}"
for (_, offset), word in zip(marks, ["Here", "is", "the", "plan", "Update", "the", "sidebar", "then", "restart", "it", "Done"]):
    assert source[offset:].lstrip("*`").startswith(word), f"{word!r} marked at {source[offset:offset + 12]!r}"

# Where each sentence's speech starts, from the stand-in's known silences.
starts, at = [], 0
for s in sentences:
    starts.append((at + int(LEAD * RATE)) * 1000 // RATE)
    at += int(LEAD * RATE) + int(len(s) * PER_CHAR * RATE) + int(TAIL * RATE)
firsts = [0, 4, 10]  # the marks of "Here", "Update", "Done"
for index, start in zip(firsts, starts):
    assert abs(times[index] - start) <= 1, f"sentence {firsts.index(index) + 1} starts at {start}ms, marked {times[index]}ms"

print("ok: local read-aloud marks each word from where its sentence's speech starts")
