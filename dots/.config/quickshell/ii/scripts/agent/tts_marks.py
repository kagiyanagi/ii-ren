"""Word timings from a TTS provider, against the text the shell actually holds.

The voice speaks what tts_text.speech makes of a message -- markdown gone, a
formula in words -- while the transcript shows what the model wrote. A word
boundary is reported against the former and the shell can only mark the
latter, so each spoken character carries its offset into the message, and a
word is marked where its first character came from.

Pure stdlib and free of the agent's import graph, so it can be tested on its own
(``python scripts/agent/test_tts_marks.py``).
"""
import difflib


def marks(spoken: str, at: list, boundaries: list) -> list:
    """``[[start_ms, offset_into_message], ...]`` for each spoken word.

    ``at[i]`` is where ``spoken[i]`` came from in the message. ``boundaries`` is
    ``[(start_ms, word), ...]`` in the order they are said, which is what lets
    each word be found by walking a cursor through the spoken text: the same
    word said twice gets its two different offsets.
    """
    out = []
    cursor = 0
    for start_ms, word in boundaries:
        found = spoken.find(word, cursor)
        if found < 0:  # a word the provider spelled differently than it was given
            continue
        cursor = found + len(word)
        out.append([start_ms, at[found]])
    return out


# What a word's phonemes are not made of: the pauses and stress marks around them.
_STRESS = frozenset("ˈˌ")
_UNWORDED = frozenset(" \t;:,.!?¡¿—…\"«»“”()") | _STRESS


def phoneme_word_starts(word_phonemes: list, timed: list) -> list:
    """When each word starts, in seconds, or None for a word not found.

    ``timed`` is ``[(phoneme, start_s), ...]`` for a whole passage, as a voice
    that times its phonemes (Kokoro) reports them, and ``word_phonemes`` the
    phonemes of each word of the passage said on its own. The two do not
    match one to one: in context espeak merges short words ("of the" is said as
    one) and reads some differently ("a" alone is "eɪ", in a sentence "ɐ"). So
    both are aligned once, and a word starts where the first of its phonemes
    that found a partner was said.

    A stress mark is a token of its own with real time (~90 ms before the
    vowel of "In"), and the vowel is already sounding through it, so a word
    opening on one starts at the mark. Kokoro's own timestamps do the same
    (hexgrad/kokoro, KPipeline.join_timestamps, whose words carry their stress).
    They also start a word halfway through the space before it; that is left
    out, because after punctuation the model gives the pause to the space, and
    half of it put the mark up to 105 ms ahead of the word.
    """
    own, owner = [], []
    for index, phonemes in enumerate(word_phonemes):
        for p in phonemes:
            if p not in _UNWORDED:
                own.append(p)
                owner.append(index)
    # (phoneme, when a word opening on it starts)
    said, stressed_at = [], None
    for p, start in timed:
        if p in _STRESS:
            stressed_at = start if stressed_at is None else stressed_at
        elif p in _UNWORDED:
            stressed_at = None
        else:
            said.append((p, start if stressed_at is None else stressed_at))
            stressed_at = None

    partner = [None] * len(own)
    matcher = difflib.SequenceMatcher(a="".join(own), b="".join(p for p, _ in said), autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            for i in range(i1, i2):
                partner[i] = j1 + (i - i1)
        elif tag == "replace":  # said differently: spread one run over the other
            for i in range(i1, i2):
                partner[i] = j1 + (i - i1) * (j2 - j1) // (i2 - i1)

    starts = [None] * len(word_phonemes)
    for i, index in enumerate(owner):
        if starts[index] is None and partner[i] is not None:
            starts[index] = said[partner[i]][1]
    return starts
