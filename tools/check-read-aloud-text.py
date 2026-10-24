#!/usr/bin/env python3
"""Read-aloud says what the transcript shows, and marks the word it is saying.

The voice was handed the message's markdown and LaTeX with little taken out, so
it read syntax the transcript never shows -- espeak says "$x^2$" as "dollar ex
two dollar" and "## Plan" as "hash hash plan" -- and the word mark waited on
words nobody could see. scripts/agent/tts_text.py now makes the message what a
person reading the transcript would say. This asserts, per kind of markup:

- what is said has none of its syntax left, and keeps its pauses;
- each word said marks the word shown for it: the rendered text here is what
  TextEdit.getText gave for that markdown (Qt 6, measured), a formula's image
  included, and the mark is found the way SpeechHighlight finds it
  (services/speechMatch.js under node);
- the transcript, speechMatch.js and tts_text.py agree on what a formula is.

    python3 tools/check-read-aloud-text.py
"""
import json
import re
import subprocess
import sys
from pathlib import Path

SHELL = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
sys.path.insert(0, str(SHELL / "scripts/agent"))
import tts_marks  # noqa: E402
import tts_text  # noqa: E402

# One formula pattern, three copies.
block = (SHELL / "modules/ii/sidebarPolicies/aiChat/MessageTextBlock.qml").read_text()
match = (SHELL / "services/speechMatch.js").read_text()
rendered_with = re.search(r"function latexPattern\(\): var \{\s*return /(.+)/g;", block).group(1)
matched_with = re.search(r"function formulaPattern\(\) \{\s*return /(.+)/g;", match).group(1)
assert rendered_with == matched_with == tts_text.FORMULAS, \
    f"the formula patterns differ:\n  MessageTextBlock {rendered_with}\n  speechMatch.js   {matched_with}\n  tts_text.py      {tts_text.FORMULAS}"

# (message, what Qt shows for it, what is said, [(word said, word marked), ...])
CASES = [
    ("## Plan\n\nHere is the **plan**. Update the `sidebar`, then restart it!",
     "Plan Here is the plan. Update the sidebar, then restart it!",
     "Plan. Here is the plan. Update the sidebar, then restart it!",
     [("Plan.", "Plan"), ("plan.", "plan."), ("sidebar,", "sidebar,"), ("restart", "restart")]),
    ("The energy is $E = mc^2$, so ![x](a.png) and **more** &amp; <b>bold</b> here.",
     "The energy is  ￼, so ￼ and more & bold here.",
     "The energy is E equals m c squared, so and more & bold here.",
     [("is", "is"), ("E", "￼,"), ("equals", "￼,"), ("squared,", "￼,"), ("so", "so"),
      ("and", "and"), ("&", "&"), ("bold", "bold")]),
    ("- item one\n- [ ] task two\n1. first step\n2) second\n\n> quoted text\n\n---\n\nAfter the rule",
     "item one task two first step second quoted text  After the rule",
     "item one. task two. 1, first step. 2, second. quoted text. After the rule.",
     [("item", "item"), ("task", "task"), ("1,", "first"), ("first", "first"), ("2,", "second"),
      ("quoted", "quoted"), ("After", "After")]),
    ("| Name | Size |\n|---|---|\n| kokoro | 177 MB |\n| voices | 28 MB |",
     "﷐Name﷐Size﷐kokoro﷐177 MB﷐voices﷐28 MB﷑",
     "Name, Size. kokoro, 177 MB. voices, 28 MB.",
     [("Name,", "Name"), ("Size.", "Size"), ("kokoro,", "kokoro"), ("177", "177"), ("voices,", "voices")]),
    ("See [the docs](https://example.com/a/b) or https://github.com/kagiyanagi/ii-ren/pull/12.",
     "See the docs or https://github.com/kagiyanagi/ii-ren/pull/12.",
     "See the docs or github.com.",
     [("docs", "docs"), ("or", "or"), ("github.com.", "https://github.com/kagiyanagi/ii-ren/pull/12.")]),
    ("~200 MB, 2 * 3, A -> B, snake_case and __init__ ✅ done 🚀",
     "~200 MB, 2 * 3, A -> B, snake_case and init ✅ done \U0001f680",
     "about 200 MB, 2 times 3, A to B, snake_case and init done.",
     [("about", "200"), ("200", "200"), ("times", "3,"), ("to", "->"), ("snake_case", "snake_case"),
      ("init", "init"), ("done.", "done")]),
    ("It costs $5 and $10, or \\$20.",
     "It costs $5 and $10, or $20.",
     "It costs $5 and $10, or $20.",
     [("$5", "$5"), ("$10,", "$10,"), ("$20.", "$20.")]),
    ("### Heading with closing ###\nText",
     "Heading with closing Text",
     "Heading with closing. Text.",
     [("closing.", "closing"), ("Text.", "Text")]),
]

# Formulas in words, for the shapes a reply most often has.
MATH = {
    "E = mc^2": "E equals m c squared",
    "\\frac{a+b}{2} \\geq \\sqrt{ab}": "a plus b over 2, is greater than or equal to the square root of a b",
    "e^{i\\pi} + 1 = 0": "e to the power of i pi, plus 1 equals 0",
    "\\sum_{i=1}^{n} i": "the sum from i equals 1 to n of i",
    "x_{max} = \\hat{y}^{-1}": "x max equals y hat inverse",
    "\\alpha \\leq 90^\\circ": "alpha is less than or equal to 90 degrees",
    "\\text{speed} = \\frac{d}{t}": "speed equals d over t",
}
for tex, words in MATH.items():
    assert tts_text.math_words(tex) == words, f"{tex!r} is said {tts_text.math_words(tex)!r}, not {words!r}"


def formulas(text):
    """What of `text` is a formula: code and prose dollars are not, wherever they fall."""
    return [m.group(0) for m in re.finditer(tts_text.FORMULAS, text) if re.match(r"\$|\\[\[(]", m.group(0))]


assert formulas("so $x^2$ and $$y$$ and \\(z\\) and \\[w\\]") == ["$x^2$", "$$y$$", "\\(z\\)", "\\[w\\]"]
assert formulas("it costs $5 and $10, or \\$3 and \\$4, or $5-$10") == [], "prose dollars are a formula"
assert formulas("costs $10, see `$HOME` and `$PATH`") == [], "a dollar before inline code opened a formula"

# Syntax that must never be said. A dollar is prose here only before a digit.
SYNTAX = re.compile(r"[#`\\{}^|\[\]<>]|\*\*|__|\$(?!\d)|&\w+;")

queries = []
for source, shown, expected, pairs in CASES:
    said, at = tts_text.speech(source)
    assert len(at) == len(said), f"{source!r}: an offset per spoken character"
    assert said == expected, f"{source!r} is said\n  {said!r}, not\n  {expected!r}"
    assert not SYNTAX.search(said), f"{source!r}: syntax said aloud: {said!r}"
    words = said.split()
    marks = tts_marks.marks(said, at, [(i * 300, w) for i, w in enumerate(words)])
    assert len(marks) == len(words), f"{source!r}: a word went unmarked: {marks}"
    for word, marked in pairs:
        index = words.index(word)
        queries.append({"source": source, "shown": shown, "offset": marks[index][1], "word": word, "marked": marked})

found = json.loads(subprocess.run(["node", "-e", f"""
const {{ normalize, place, placedWordAtOffset }} = require({json.dumps(str(SHELL / "services/speechMatch.js"))});
const queries = {json.dumps(queries)};
console.log(JSON.stringify(queries.map(q => {{
    // As SpeechHighlight does: the view's text normalized, the passage placed in
    // it, then the word looked up.
    const placed = place(normalize(q.shown), q.source);
    const hit = placed && placedWordAtOffset(placed, q.offset);
    return hit ? q.shown.slice(hit.start, hit.end) : null;
}})));
"""], capture_output=True, text=True, check=True).stdout)
for query, hit in zip(queries, found):
    assert hit == query["marked"], \
        f"{query['source']!r}: saying {query['word']!r} marks {hit!r}, not {query['marked']!r}"

print(f"ok: read-aloud says what {len(CASES)} kinds of markup show, and marks {len(queries)} words where they are shown")
