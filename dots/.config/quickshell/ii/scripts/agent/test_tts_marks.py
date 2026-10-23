# python scripts/agent/test_tts_marks.py
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tts_marks import marks, phoneme_word_starts  # noqa: E402

SOURCE = "All **systems** are running at $5 km/h$."
SPOKEN = "All systems are running at 5 km over h."
# Where each spoken character came from: the formula's words all from its `$`.
AT = [*range(0, 4), *range(6, 13), *range(15, 31), *[31] * (len(SPOKEN) - 27 - 1), 40]
assert len(AT) == len(SPOKEN)

# Each word lands on itself in the source, markdown and all.
got = marks(SPOKEN, AT, [(0, "All"), (300, "systems"), (900, "are"), (1200, "running"), (1500, "over")])
assert [ms for ms, _ in got] == [0, 300, 900, 1200, 1500], got
assert SOURCE[got[0][1]:].startswith("All"), got
assert SOURCE[got[1][1]:].startswith("systems"), got     # past the ** the voice never saw
assert SOURCE[got[3][1]:].startswith("running"), got
assert SOURCE[got[4][1]:].startswith("$5"), got           # a formula's word: the formula

# The same word twice gets two offsets, in the order it is said.
twice = marks("go on, go", list(range(9)), [(0, "go"), (500, "go")])
assert [offset for _, offset in twice] == [0, 7], twice

# A word the provider renamed is skipped, not mis-placed.
assert marks("hello there", list(range(11)), [(0, "howdy")]) == []

# Kokoro's phonemes, in context and word by word, as espeak gives them: "of"
# alone is ʌv, in the sentence əv; "a" alone eɪ, in it ɐ; the dash says nothing.
WORDS = ["mˈoʊst ", "ʌv ", "ðə ", "tˈaɪm, ", "ˈeɪ ", "ˈɪn ", "— "]
TIMED = [(p, i / 10) for i, p in enumerate("mˈoʊst əv ðə tˈaɪm, ɐ ˈɪn —")]
when = dict(zip(range(len(TIMED)), (t for _, t in TIMED)))
starts = phoneme_word_starts(WORDS, TIMED)
assert starts[0] == when[0], starts          # m
assert starts[1] == when[7], starts          # said differently, still found: ə
assert starts[2] == when[10], starts         # ð
assert starts[3] == when[13], starts         # t, not the stress mark after it
assert starts[4] == when[20], starts         # ɐ for eɪ
assert starts[5] == when[22], starts         # at its stress mark, not its vowel
assert starts[6] is None, starts             # nothing to say, so no mark
assert phoneme_word_starts(["ɐ "], []) == [None]

print("ok")
