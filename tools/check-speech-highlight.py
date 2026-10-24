#!/usr/bin/env python3
"""Marking the word being read costs the word, not the reply.

SpeechHighlight marks the word a read-aloud is saying in one view of a reply.
Finding it means taking the markdown out of the view's whole text and placing
the sentence being read in what is left -- time in proportion to the reply,
measured in the shell at 23 ms for an 11,000-character one and 55 ms for
28,000. It did that on every word, in every view of the reply, three or four
times a second: a long reply stuttered under a scroll while it was read out,
and a reply idle on screen did not. So the view's text is normalized once (until
it changes) and the sentence placed once (until the next one), and a word is a
lookup in both.

This lifts SpeechHighlight's update() out of the QML as it is, runs it under
node against speechMatch.js with its entry points counted, and asserts:

- every word of a sentence is marked where the one-shot findWordAtOffset()
  marks it, and the whole sentence where findPhrase() does;
- across all of those words the text is read and normalized once, and the
  sentence placed once;
- the next sentence is placed again, the text not normalized again; a resize
  does neither; changed text is normalized again;
- a view without the sentence leaves its (empty) marks alone on each word;
- once nothing is being read, the normalized copy is let go.

    python3 tools/check-speech-highlight.py
"""
import json
import re
import subprocess
from pathlib import Path

SHELL = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
QML = (SHELL / "modules/ii/sidebarPolicies/aiChat/SpeechHighlight.qml").read_text()


def block(text, header):
    """The brace-balanced block after `header`, braces included."""
    start = text.index(header)
    i = text.index("{", start + len(header) - 1)
    depth = 0
    for j in range(i, len(text)):
        depth += {"{": 1, "}": -1}.get(text[j], 0)
        if depth == 0:
            return text[i:j + 1]
    raise AssertionError(f"no end to {header}")


def function(name):
    """`function name(...)` as plain JS, QML's type annotations dropped."""
    m = re.compile(rf"function {name}\(([^)]*)\)(?::\s*\w+)?\s*\{{").search(QML)
    assert m, f"`{name}` is gone from SpeechHighlight.qml"
    params = ", ".join(p.split(":")[0].strip() for p in m.group(1).split(",") if p.strip())
    return f"function ({params}) " + block(QML, m.group(0))


# Rendered text as Qt shows it (no markdown left), and the passages read, as
# the source has them -- with the markdown the view dropped.
SHOWN = " ".join([
    "Here is the plan. Update the sidebar, then restart it!",
    "The reader holds one part at a time and moves between them on request.",
    "Every word said is marked where it is shown, on time, while it plays.",
] * 40)
PASSAGES = [
    "The reader holds one part at a time and moves between them on **request**.",
    "Every word said is marked where it is `shown`, on time, while it plays.",
]

ON_TEXT_CHANGED = "function () " + block(QML, "function onTextChanged(): void {")

script = f"""
const real = require({json.dumps(str(SHELL / "services/speechMatch.js"))});
const counts = {{ normalize: 0, place: 0, getText: 0, rects: 0 }};
const SpeechMatch = Object.assign({{}}, real, {{
    normalize: s => {{ counts.normalize++; return real.normalize(s); }},
    place: (hay, phrase) => {{ counts.place++; return real.place(hay, phrase); }},
}});
let text = {json.dumps(SHOWN)};
const view = {{
    get length() {{ return text.length; }},
    getText: (from, to) => {{ counts.getText++; return text.slice(from, to); }},
}};
let marks = [];
const root = {{
    target: view, phrase: "", query: "", progress: -1, wordOffset: -1,
    _hay: null, _placed: null, _placedFor: null,
    get rects() {{ return marks; }},
    set rects(value) {{ counts.rects++; marks = value; }},
    // The span marked, standing in for its line rectangles.
    lineRects: (start, end) => [{{ start: start, end: end }}],
}};
root.update = {function("update")};
root.clear = {function("clear")};
const onTextChanged = {ON_TEXT_CHANGED};

const out = {{}};
const passages = {json.dumps(PASSAGES)};
const marked = () => marks.length ? text.slice(marks[0].start, marks[0].end) : null;
const words = phrase => [...phrase.matchAll(/\\S+/g)].map(m => m.index);

// The whole passage, before any word timing.
root.phrase = passages[0];
root.update();
const whole = real.findPhrase(text, passages[0]);
out.whole = [marked(), whole ? text.slice(whole.start, whole.end) : null];

// Every word of it.
out.words = [];
for (const at of words(passages[0])) {{
    root.wordOffset = at;
    root.update();
    const hit = real.findWordAtOffset(text, passages[0], at);
    out.words.push([marked(), hit ? text.slice(hit.start, hit.end) : null]);
}}
out.afterWords = Object.assign({{}}, counts);

// The next sentence, then a resize.
root.phrase = passages[1];
root.wordOffset = 0;
root.update();
for (const at of words(passages[1])) {{
    root.wordOffset = at;
    root.update();
    const hit = real.findWordAtOffset(text, passages[1], at);
    out.words.push([marked(), hit ? text.slice(hit.start, hit.end) : null]);
}}
out.afterNext = Object.assign({{}}, counts);
root.update();
out.afterResize = Object.assign({{}}, counts);

// The text changes under it.
text = text + " One more sentence arrives.";
onTextChanged();
out.afterText = Object.assign({{}}, counts);

// A view that does not hold the sentence: nothing to mark, on every word.
const before = counts.rects;
text = "Something else entirely, said in another view of the reply.";
onTextChanged();
const settled = counts.rects;
for (const at of words(passages[1])) {{
    root.wordOffset = at;
    root.update();
}}
out.elsewhere = {{ marks: marks.length, rebuilt: counts.rects - settled, cleared: settled - before }};

// The reading ends.
root.phrase = "";
root.update();
out.released = root._hay === null && root._placed === null;
console.log(JSON.stringify(out));
"""
out = json.loads(subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True).stdout)

mine, theirs = out["whole"]
assert mine is not None and mine == theirs, f"the whole passage is marked {mine!r}, findPhrase() marks {theirs!r}"
for mine, theirs in out["words"]:
    assert mine is not None and mine == theirs, f"a word is marked {mine!r} where findWordAtOffset() marks {theirs!r}"

n = len(out["words"])
first = out["afterWords"]
assert (first["getText"], first["normalize"], first["place"]) == (1, 1, 1), \
    f"marking a sentence word by word read the text {first['getText']}x, normalized it {first['normalize']}x " \
    f"and placed the sentence {first['place']}x; once each, not per word"
nxt = out["afterNext"]
assert (nxt["normalize"], nxt["place"]) == (1, 2), \
    f"the next sentence normalized the text again ({nxt['normalize']}x) or was not placed afresh ({nxt['place']}x)"
resized = out["afterResize"]
assert (resized["getText"], resized["normalize"], resized["place"]) == (nxt["getText"], nxt["normalize"], nxt["place"]), \
    f"a resize, which only rewraps the lines, redid the matching: {nxt} -> {resized}"
changed = out["afterText"]
assert (changed["normalize"], changed["place"]) == (2, 3), f"changed text was not matched again: {changed}"
elsewhere = out["elsewhere"]
assert elsewhere["marks"] == 0 and elsewhere["rebuilt"] == 0, \
    f"a view without the sentence reset its marks {elsewhere['rebuilt']}x over its words"
assert out["released"], "the normalized text is kept after the reading ended"

print(f"ok: {n} words marked where the one-shot match marks them, the {len(SHOWN):,}-character text "
      f"normalized once and each sentence placed once")
