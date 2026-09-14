# python scripts/hermes/test_tts_marks.py
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tts_marks import align, marks  # noqa: E402

SOURCE = "All **systems** are running at 5 km/h."
SPOKEN = "All systems are running at 5 kilometers per hour."

# Each word lands on itself in the source, markdown and all.
got = marks(SPOKEN, SOURCE, [(0, "All"), (300, "systems"), (900, "are"), (1200, "running")])
assert [ms for ms, _ in got] == [0, 300, 900, 1200], got
assert SOURCE[got[0][1]:].startswith("All"), got
assert SOURCE[got[1][1]:].startswith("systems"), got     # past the ** the voice never saw
assert SOURCE[got[3][1]:].startswith("running"), got

# An expansion the source has no words for still points into the unit it came from.
unit = marks(SPOKEN, SOURCE, [(1800, "kilometers"), (2100, "per")])
assert SOURCE[unit[0][1]:].startswith("km") or SOURCE[unit[0][1]:].startswith("5"), unit

# The same word twice gets two offsets, in the order it is said.
twice = marks("go on, go", "go on, go", [(0, "go"), (500, "go")])
assert [offset for _, offset in twice] == [0, 7], twice

# A word the provider renamed is skipped, not mis-placed.
assert marks("hello there", "hello there", [(0, "howdy")]) == []

# The map covers every index, ends included.
mapping = align(SPOKEN, SOURCE)
assert len(mapping) == len(SPOKEN) + 1 and mapping[-1] == len(SOURCE)

print("ok")
