"""Word timings from a TTS provider, against the text the shell actually holds.

The voice speaks the *normalized* text -- markdown stripped, emoji gone, units
spelled out -- while the transcript shows what the model wrote. A word boundary
is reported against the former, and the shell can only mark the latter, so the
two are aligned once here rather than guessed at on the other side.

Pure stdlib and free of the agent's import graph, so it can be tested on its own
(``python scripts/hermes/test_tts_marks.py``).
"""
import difflib


def align(spoken: str, source: str) -> list:
    """``spoken`` index -> ``source`` index, from one diff of the two.

    Inside a matching run the mapping is exact; a run that only one side has --
    an expanded unit, a dropped emoji -- collapses to where it begins, which is
    the last position known to be right.
    """
    mapping = [0] * (len(spoken) + 1)
    for tag, i1, i2, j1, _j2 in difflib.SequenceMatcher(a=spoken, b=source, autojunk=False).get_opcodes():
        for i in range(i1, i2):
            mapping[i] = j1 + (i - i1) if tag == "equal" else j1
    mapping[len(spoken)] = len(source)
    return mapping


def marks(spoken: str, source: str, boundaries: list) -> list:
    """``[[start_ms, offset_into_source], ...]`` for each spoken word.

    ``boundaries`` is ``[(start_ms, word), ...]`` in the order they are said,
    which is what lets each word be found by walking a cursor through the spoken
    text: the same word said twice gets its two different offsets.
    """
    to_source = align(spoken, source)
    out = []
    cursor = 0
    for start_ms, word in boundaries:
        at = spoken.find(word, cursor)
        if at < 0:  # a word the provider spelled differently than it was given
            continue
        cursor = at + len(word)
        out.append([start_ms, to_source[at]])
    return out
