#!/usr/bin/env python3
"""Read-aloud marks each word when it is said, with either voice.

The sidebar highlights the word being spoken from marks scripts/agent/tts.py
returns: [[ms into the clip, offset into the message], ...]. Nothing short of
listening shows them wrong, so stand-ins with known timelines play each voice:

- Kokoro (on this computer) times every phoneme. A word is marked where its
  first phoneme starts -- at the stress mark before it, if it opens on one --
  less Kokoro's three-frame lead (75 ms). Read off the vowel instead, words
  were marked 90-125 ms after they were heard. One synthesis for the passage.
- Edge (online) times every word against the MP3 it sends, whose decoder plays
  1105 samples of priming first: every mark is 46 ms later than Edge says.
- Every mark lands on its word in the message as written, markdown and all.

The constants are measured; tts.py's comments say how. Needs the shell venv
(numpy, kokoro-onnx's espeak-ng); run with any python3, it re-runs itself there.
How the shell then moves the mark on time is tools/check-mark-clock.py.

    python3 tools/check-read-aloud-timing.py
"""
import os
import sys

try:
    import numpy as np
    from kokoro_onnx.sliding import Timing
    from kokoro_onnx.tokenizer import Tokenizer
except ImportError:
    venv = os.path.expanduser(os.environ.get("ILLOGICAL_IMPULSE_VIRTUAL_ENV", "~/.local/state/quickshell/.venv"))
    python = os.path.join(venv, "bin", "python")
    assert os.path.exists(python) and sys.executable != python, f"needs numpy and kokoro-onnx: no shell venv at {venv}"
    os.execv(python, [python, *sys.argv])

import tempfile
import types
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/scripts/agent"))
import tts  # noqa: E402

RATE = 24000
SOURCE = "Here is the **plan**. Update the `sidebar`, then restart it!"
WORDS = ["Here", "is", "the", "plan", "Update", "the", "sidebar", "then", "restart", "it"]
# Seconds each kind of phoneme lasts in the stand-in's timeline.
LENGTH = {"ˈ": 0.09, "ˌ": 0.09, " ": 0.03, ".": 0.25, ",": 0.12, "!": 0.25}


def landed(marks):
    for (_, offset), word in zip(marks, WORDS):
        assert SOURCE[offset:].lstrip("*`").startswith(word), f"{word!r} marked at {SOURCE[offset:offset + 12]!r}"


# ── Kokoro ────────────────────────────────────────────────────────────────


class FakeKokoro:
    """Times the phonemes espeak gives the passage, at known lengths."""

    def __init__(self):
        self.tokenizer = Tokenizer()  # also points phonemizer at kokoro-onnx's espeak-ng
        self.calls = []

    def create_timed(self, text, voice, speed, lang):
        self.calls.append(text)
        phonemes = self.tokenizer.phonemize(text, lang)
        timings, at = [], 0.0
        for p in phonemes:
            length = LENGTH.get(p, 0.06)
            timings.append(Timing(p, at, at + length))
            at += length
        self.timeline = timings
        return np.zeros(int(at * RATE), np.float32), RATE, timings


fake = FakeKokoro()
tts._kokoro = fake
with tempfile.TemporaryDirectory() as tmp:
    reply = tts.synthesize_kokoro(SOURCE, f"{tmp}/clip.mp3", "af_heart", tmp)
assert reply["ok"], reply
assert reply["paths"][0].endswith(".wav"), reply["paths"]
# The bar under the transcript lays the parts end to end by these.
assert reply["duration"] == int(fake.timeline[-1].end * RATE) * 1000 // RATE, f"Kokoro's clip length: {reply['duration']}"
assert fake.calls == [tts.spoken(SOURCE)], f"one synthesis for the passage: {fake.calls}"

# Where each word's first phoneme -- or the stress mark opening it -- starts,
# from the stand-in's own timeline. This passage keeps one phoneme word per
# word, so the k-th word is what follows the k-th space.
starts, opening = [], True
for t in fake.timeline:
    if t.phoneme == " ":
        opening = True
    elif opening and t.phoneme not in ".,!":
        starts.append(t.start)
        opening = False
assert len(starts) == len(WORDS), f"the passage kept its words apart: {''.join(t.phoneme for t in fake.timeline)}"
assert fake.timeline[[t.start for t in fake.timeline].index(starts[4])].phoneme == "ˈ", "Update opens on a stress mark"

marks = reply["marks"]
assert len(marks) == len(WORDS), marks
expected = [max(0, int((s - tts._KOKORO_LEAD_S) * 1000)) for s in starts]
assert [ms for ms, _ in marks] == expected, f"Kokoro marks {[ms for ms, _ in marks]}, expected {expected}"
landed(marks)

# ── Edge ──────────────────────────────────────────────────────────────────

said = tts.spoken(SOURCE)
boundaries = [(i * 3_000_000, word) for i, word in enumerate(said.split())]  # 300 ms apart, in 100 ns ticks


class FakeCommunicate:
    def __init__(self, text, **_):
        assert text == said

    async def stream(self):
        yield {"type": "audio", "data": b"\xff\xf3" * 64}
        for offset, word in boundaries:
            yield {"type": "WordBoundary", "offset": offset, "duration": 2_000_000, "text": word.strip(".,!")}


sys.modules["edge_tts"] = types.SimpleNamespace(Communicate=FakeCommunicate)
with tempfile.TemporaryDirectory() as tmp:
    reply = tts.synthesize(SOURCE, f"{tmp}/clip.mp3", "en-US-AriaNeural")
assert reply["ok"], reply
assert tts._MP3_PRIMING_MS == 46, tts._MP3_PRIMING_MS
assert [ms for ms, _ in reply["marks"]] == [offset // 10_000 + 46 for offset, _ in boundaries], reply["marks"]
landed(reply["marks"])

print("ok: read-aloud marks each word when it is said, on both voices")
