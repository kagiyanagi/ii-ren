#!/usr/bin/env python3
"""A long Hermes reply opens and streams without re-laying all of itself.

None of it shows in a still frame, and all of it was measured on one real chat,
a 16k-character reply holding 234 LaTeX formulas:
- Opening it froze the shell for 11s, 9s of that in one frame. Every formula
  that finished rendering re-set the whole reply's text, and LatexFormulas
  rebuilt every formula's scroller on each pass: 234 x 234 rebuilds.
- Streaming it, every chunk asked for every formula again, and each request
  for one already rendered re-emitted renderFinished to every text block.
- One view held the whole reply, so every tick of the word reveal re-parsed
  all of it: at 16k characters a prose reply dropped to ~13fps and a formula
  one to ~3fps, with half-second frames.
- The reveal's word split looked ahead for a `>` from every space, which reads
  to the end of a reply that has none: 26ms a split, 28 splits a second.
- Qt reads a leading `---` as YAML front matter, so a block opening on a rule
  lost everything up to the next one, and every formula after it was drawn
  over the wrong image.

The cut text has to lay out exactly as the one view it becomes when the reveal
settles; that was compared character by character in the shell. What is
checkable here is that the markdown is literally the same, and that a settled
run never changes. The rest is structural, so each fix stays in.

  python3 tools/check-hermes-stream.py
"""
import json
import re
import subprocess
from pathlib import Path

QML = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
text = (QML / "modules/ii/sidebarPolicies/aiChat/MessageTextBlock.qml").read_text()
formulas = (QML / "modules/ii/sidebarPolicies/aiChat/LatexFormulas.qml").read_text()
renderer = (QML / "services/LatexRenderer.qml").read_text()
spinner = (QML / "modules/common/widgets/MaterialLoadingIndicator.qml").read_text()


def node(js):
    return json.loads(subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout)


def lift(name):
    """A function of MessageTextBlock as plain JS, its QML type annotations dropped."""
    m = re.search(rf"(    function {name}\(.*?\n    \}})", text, re.S)
    assert m, f"MessageTextBlock: {name}() is gone"
    assert text.count(f"function {name}(") == 1, f"MessageTextBlock: {name}() is declared twice, and the file does not load"
    head, body = m.group(1).split("\n", 1)
    head = re.sub(r"(\w+): \w+(?=[,)])", r"\1", head)
    return re.sub(r"\): \w+ \{$", ") {", head) + "\n" + body


P = "A plain paragraph long enough to wrap onto a second line of the sidebar, and then some more words."
reply = "\n\n".join([
    "---", "## Heading", P, "- one\n- two", P, "- loose\n\n- list\n\n  indented continuation", P,
    "| a | b |\n| --- | --- |\n| 1 | 2 |", "> quote", P, "1. one\n2. two", "3. three", P,
    " <img src=\"x\" alt=\"/f.svg\" width=\"9\" height=\"9\" align=\"middle\" />", "**Bold lead**", P,
    "A `code` span and [a link](https://example.org).", "[ref]: https://example.org", "    indented code", P,
] * 12)
results = node(f"""
const streamTimer = {{ running: true }};
const root = {{ renderMarkdown: true, editing: false, fadeChunkSplitting: false, done: false, shownText: "" }};
{lift("formatMarkdown")}
{lift("viewTexts")}
root.formatMarkdown = formatMarkdown;
const reply = {json.dumps(reply)};
let prev = [], joined = true, stable = true, starts = [], most = 0;
for (let n = 1; n <= reply.length; n += 41) {{
    root.shownText = reply.slice(0, n);
    const runs = viewTexts();
    joined = joined && runs.join("\\n\\n") === formatMarkdown(root.shownText);
    stable = stable && prev.slice(0, -1).every((run, i) => runs[i] === run);
    runs.slice(1).forEach(run => {{ if (/^(?:[ \\t]|[*+-]\\s|\\d+[.)]\\s)/.test(run)) starts.push(run.slice(0, 20)); }});
    most = Math.max(most, runs.length);
    prev = runs;
}}
root.done = true; streamTimer.running = false;
console.log(JSON.stringify({{ joined, stable, starts, most, settled: viewTexts().length,
    short: (root.done = false, streamTimer.running = true, root.shownText = reply.slice(0, 3000), viewTexts().length),
    frontMatter: formatMarkdown("---\\n\\nkept\\n\\n---\\n\\nafter") }}));
""")
assert results["most"] > 4, f"viewTexts: a {len(reply)}-character reply streamed as {results['most']} view(s); it is not being cut"
assert results["joined"], "viewTexts: the runs re-joined are not the one view's markdown, so the reply jumps when the reveal settles"
assert results["stable"], "viewTexts: a settled run changed as more text arrived, so it is re-parsed after all"
assert not results["starts"], f"viewTexts: a run starts on a list item or indented line, which continues the block above: {results['starts']}"
assert results["settled"] == 1, "viewTexts: a settled reply must be one view, or a selection cannot run across it"
assert results["short"] == 1, "viewTexts: a short reply is cheap to parse whole and must stay one view"
assert not results["frontMatter"].startswith("---"), "formatMarkdown: a block opening on `---` is read as front matter and loses its first section"

# The reveal's word split: linear, so no lookahead running on from every space.
for split in re.findall(r"const tokens = \w+(?:\.\w+)?\.split\((/.+/)\);", text):
    assert "(?" not in split, f"MessageTextBlock: the reveal split {split} looks ahead again, quadratic on a reply with no `>`"

# Formulas: one pass from the source, every occurrence, a repeat as well as the first.
latex = node(f"""
const segmentContent = "a $x$ b $x$ c $y$";
const root = {{ renderedSegmentContent: "", latexPattern: () => {re.search(r"function latexPattern\(\): var \{\s*return (/.+/g);", text).group(1)} }};
const LatexRenderer = {{ placeholder: "P", hashOf: e => e, renderedSizes: {{ "$x$": [5, 6] }}, renderedImagePaths: {{ "$x$": "/x.svg" }} }};
{lift("applyLatex")}
applyLatex();
console.log(JSON.stringify(root.renderedSegmentContent));
""")
assert latex.count('alt="/x.svg"') == 2 and "$y$" in latex, \
    f"applyLatex: every rendered formula is swapped, repeats included, and one not yet rendered stays source: {latex}"
assert "latexHashes[" in text and "renderedLatexHashes.includes" not in text, \
    "MessageTextBlock: a block's formulas are a set again, not a list scanned per formula per chunk"
assert "Qt.callLater(root.applyLatex)" in text and "replace(expression" not in text, \
    "MessageTextBlock: formulas are patched in one render at a time again, re-laying the text per formula"

assert re.search(r"model:\s*ScriptModel\s*\{\s*objectProp:\s*\"key\"\s*values:\s*root\.boxes", formulas), \
    "LatexFormulas: the scrollers are no longer keyed, so every layout rebuilds all of them"
assert "Qt.callLater(root.layout)" in formulas and "root.layout();" not in formulas, \
    "LatexFormulas: layout runs per textChanged again, once per bracket InlineCode strips"
assert "asynchronous: true" in formulas, "LatexFormulas: formulas decode on the GUI thread again as a turn scrolls back in"

assert "Qt.createQmlObject(" not in renderer, "LatexRenderer: a QML string is compiled per formula again"
assert re.search(r"root\.rendering < root\.maxRenders", renderer), "LatexRenderer: renders are no longer queued; 211 forked on one frame"
assert "'cd \"$0\" && exec \"$@\"'" in renderer and "-input=${proc.expression}" in renderer, \
    "LatexRenderer: the formula must be an argument, never part of the bash script: it is model output"
assert re.search(r"processedExpressions\[hash\] !== undefined\)\s*return \[hash, false\]", renderer), \
    "LatexRenderer: a formula already asked for is a lookup and returns, without re-emitting renderFinished"
assert "root.hashes[expression] ??" in renderer, "LatexRenderer: Qt.md5 runs per formula per chunk again"

# A spinner parked behind `visible: false` must not keep animating.
assert spinner.count("running: root.animating") == 2 and "root.loading && root.visible" in spinner, \
    "MaterialLoadingIndicator: a hidden indicator animates again, ticking the GUI thread every frame"

print("ok: a long reply streams in settled runs, and its formulas render once, in one pass")
