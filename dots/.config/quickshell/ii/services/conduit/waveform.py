#!/usr/bin/env python3
"""Peak envelope of a WAV file, printed as one JSON line.

    {"bytes": 548844, "bars": [0.08, 0.41, ...]}

Peaks rather than RMS: peaks keep pauses between words visibly flat, which is
what makes a 56-bar strip readable as speech instead of a grey block.

stdlib only (wave + array) — the synthesised WAV is already 16-bit PCM, so
pulling in ffmpeg to decode it would buy nothing.
"""

import array
import json
import os
import sys
import wave

BARS = 56
FLOOR = 0.08  # Silence still gets a visible tick, like Telegram's own strip


def envelope(path, bars=BARS):
    with wave.open(path, "rb") as handle:
        if handle.getsampwidth() != 2:
            raise ValueError(f"expected 16-bit PCM, got {handle.getsampwidth() * 8}-bit")
        frames = handle.getnframes()
        channels = handle.getnchannels()
        samples = array.array("h")
        samples.frombytes(handle.readframes(frames))

    if channels > 1:
        samples = samples[::channels]  # One channel is enough for a shape

    # Sliced by proportion, not by a truncated step, so the last bar still
    # covers the tail of the audio.
    total = len(samples)
    peaks = [
        max((abs(v) for v in samples[total * i // bars:total * (i + 1) // bars]), default=0)
        for i in range(bars)
    ]
    loudest = max(peaks) or 1

    return {
        "bytes": os.path.getsize(path),
        "bars": [round(max(FLOOR, peak / loudest), 3) for peak in peaks],
    }


def selftest():
    import math
    import tempfile

    path = os.path.join(tempfile.gettempdir(), "conduit-waveform-selftest.wav")
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(8000)
        # One loud second then one silent second: the envelope has to show the drop.
        loud = [int(20000 * math.sin(i / 4)) for i in range(8000)]
        handle.writeframes(array.array("h", loud + [0] * 8000).tobytes())

    got = envelope(path, bars=8)
    assert len(got["bars"]) == 8, got["bars"]
    assert min(got["bars"][:4]) > 0.9, got["bars"]        # loud half
    assert max(got["bars"][4:]) == FLOOR, got["bars"]     # silent half, floored
    assert got["bytes"] > 32000, got["bytes"]
    os.remove(path)
    print("ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    else:
        print(json.dumps(envelope(sys.argv[1])))
