// node services/speechMatch.test.js
const assert = require("assert");
const { findPhrase, findWordAt, findWordAtOffset } = require("./speechMatch.js");

const rendered = "Files are read first.\nThen the patch is written and checked.";

// Plain sentence, and the positions really do bracket it.
const plain = findPhrase(rendered, "Then the patch is written and checked.");
assert.strictEqual(rendered.slice(plain.start, plain.end), "Then the patch is written and checked.");

// The source still carries markdown the view has already dropped.
const bold = findPhrase(rendered, "Files are **read** first.");
assert.strictEqual(rendered.slice(bold.start, bold.end), "Files are read first.");

// Wrapped source, one line on screen.
const wrapped = findPhrase(rendered, "Then the patch\n  is written and checked.");
assert.strictEqual(rendered.slice(wrapped.start, wrapped.end), "Then the patch is written and checked.");

// A URL the renderer ate: head and tail anchor what is left.
const linked = findPhrase("See the handbook for the rest of it, then stop.",
    "See the [handbook](https://example.com/a/very/long/path) for the rest of it, then stop.");
assert.strictEqual(linked.start, 0);
assert.strictEqual(linked.end, "See the handbook for the rest of it, then stop.".length);

// Nothing of the phrase here: no highlight rather than a wrong one.
assert.strictEqual(findPhrase(rendered, "An entirely different sentence."), null);
assert.strictEqual(findPhrase(rendered, "   "), null);

// Word by word, shared out by characters: start, middle and end of the passage.
const line = "Greetings, Master. All functions are synchronized.";
const word = (p) => { const w = findWordAt(line, line, p); return line.slice(w.start, w.end); };
assert.strictEqual(word(0), "Greetings,");
assert.strictEqual(word(0.999), "synchronized.");
assert.strictEqual(word(14 / line.length), "Master.");
// Markdown in the source still lands on the rendered word.
const marked = findWordAt("All functions are synchronized.", "All **functions** are synchronized.", 0.2);
assert.strictEqual("All functions are synchronized.".slice(marked.start, marked.end), "functions");
assert.strictEqual(findWordAt(line, "nothing like this at all", 0.5), null);

// A provider's own word offsets, counted against the source markdown.
const source = "Greetings, **Master**. All cognitive functions are fully synchronized.";
const shown = "Greetings, Master. All cognitive functions are fully synchronized.";
const spokenWord = (offset) => { const w = findWordAtOffset(shown, source, offset); return shown.slice(w.start, w.end); };
assert.strictEqual(spokenWord(0), "Greetings,");
assert.strictEqual(spokenWord(source.indexOf("Master")), "Master.");      // past the **
assert.strictEqual(spokenWord(source.indexOf("cognitive")), "cognitive");
assert.strictEqual(spokenWord(source.indexOf("synchronized")), "synchronized.");
// An offset inside a word still marks that word, not its neighbour.
assert.strictEqual(spokenWord(source.indexOf("functions") + 3), "functions");

// Qt renders a list bullet, a number, a task box and a quote bar as layout, not
// text (measured off TextEdit.getText). Counted as text, each one pushed the mark
// a marker further ahead: "run" marked "every", "After" marked "that".
const listSource = "Here is the plan:\n- read the files first\n- [ ] then write the patch\n1. run every check\n\n> After that we test it.";
const listShown = "Here is the plan: read the files first then write the patch run every check After that we test it.";
for (const w of ["plan", "read", "write", "patch", "run", "check", "After", "test"]) {
    const hit = findWordAtOffset(listShown, listSource, listSource.indexOf(w));
    assert.strictEqual(listShown.slice(hit.start, hit.end).replace(/[:.]$/, ""), w, `list: ${w}`);
}
// A table's cells arrive separated by U+FDD0/U+FDD1, and its delimiter row is gone.
const table = findWordAtOffset("see \ufdd0a\ufdd0b\ufdd0c\ufdd0d\ufdd1 done", "see\n\n| a | b |\n|---|---|\n| c | d |\n\ndone", 34);
assert.strictEqual("see \ufdd0a\ufdd0b\ufdd0c\ufdd0d\ufdd1 done".slice(table.start, table.end), "done");

// A passage split by a code block covers two views. Each marks only its own part:
// the first used to pin the mark on its last word for the rest of the passage.
const views = ["Run the build like this:", "That prints the version. Then restart."];
const across = "Run the build like this:\n\n```sh\nmake all\n```\n\nThat prints the version.";
const marksIn = (w) => views.map(v => { const hit = findWordAtOffset(v, across, across.indexOf(w)); return hit ? v.slice(hit.start, hit.end) : null; });
assert.deepStrictEqual(marksIn("Run"), ["Run", null]);
assert.deepStrictEqual(marksIn("make"), [null, null]);
assert.deepStrictEqual(marksIn("That"), [null, "That"]);
assert.deepStrictEqual(marksIn("version"), [null, "version."]);
// Pieces shorter than an anchor at the view's edges.
const short = "see below.\n\n```\nx\n```\n\nok then";
assert.strictEqual(findWordAtOffset("It ends here: see below.", short, 4).start, "It ends here: ".length + 4);
assert.strictEqual(findWordAtOffset("ok then go.", short, short.indexOf("then")).start, 3);
assert.strictEqual(findWordAtOffset("It ends here: see below.", short, short.indexOf("then")), null);
// The estimate follows the same placement.
assert.strictEqual(findWordAt(views[0], across, 0.999), null);
assert.notStrictEqual(findWordAt(views[1], across, 0.999), null);

// The read-aloud chunks are slices of the message, newlines kept, so a marker
// stays at the start of its line. Lifted from AgentService.qml.
const svc = require("fs").readFileSync(__dirname + "/AgentService.qml", "utf8");
const lift = (name, params) => {
    const src = svc.slice(svc.indexOf(`function ${name}(`));
    const body = src.slice(0, src.indexOf("\n    }\n") + 6);
    return "(function (" + params + ")" + body.slice(body.indexOf("{"), body.lastIndexOf("}") + 1) + ")";
};
const root = { _minFirstChunk: 60, _minChunk: 140, _minLocalChunk: 40, _maxLocalChunk: 120 };
const SpeechMatch = require("./speechMatch.js");
root._splitForSpeech = new Function("root", "SpeechMatch", "return " + lift("_splitForSpeech", "text, local"))(root, SpeechMatch);
root._cutClauses = new Function("root", "return " + lift("_cutClauses", "text, spans, inUnit"))(root);
const split = (text, local) => root._splitForSpeech(text, local ?? false);
const sameText = (chunks, text) => chunks.join(" ").replace(/\s+/g, " ") === text.trim().replace(/\s+/g, " ");
const reply = "Here is the plan:\n- read the files first.\n- then write the patch.\n\n" + "Then it is tested again. ".repeat(60);
const chunks = split(reply);
assert.ok(chunks.every(chunk => reply.includes(chunk)), "a chunk is not a slice of the message");
assert.ok(chunks[0].includes("\n- then"), "a list marker lost its line start");
assert.ok(sameText(chunks, reply), "text lost between chunks");
// No cap on how many: the reading asks for them as it reaches them. Capped at
// eight, the rest of a long reply was one part, and the voice fell silent after
// the seventh while all of it was made.
assert.ok(chunks.length > 8, `capped at ${chunks.length} parts`);
assert.ok(chunks.every(chunk => chunk.length < 200), `a part far past the floor: ${chunks.map(c => c.length)}`);

// A list's items seldom end in a full stop: a line where a new block starts is a
// pause too, and a long list is many parts, each from an item's marker.
const list = "These are the changes made to the reader today\n"
    + Array.from({ length: 30 }, (_, i) => `- change number ${i} to the reader, with no stop`).join("\n")
    + "\n\n## Next\n\nNothing else";
const listed = split(list);
assert.ok(sameText(listed, list), "a list: text lost between chunks");
assert.ok(listed.length > 5 && listed.every(part => part.length < 200), `a list in ${listed.length} parts: ${listed.map(p => p.length)}`);
assert.ok(listed.slice(1).every(part => /^(?:- |## )/.test(part)), `a list part not at a block's start: ${JSON.stringify(listed)}`);
// A line wrapped inside a sentence is no pause.
const softWrapped = "This first sentence is long enough on its own to pass the floor that a part has to reach before it is cut. "
    + "The second one runs on well past the floor of a part, a long run of words with no stop in it anywhere, on and on for longer than any part is let be, until the line is wrapped\nhalfway through, and ends here. A third.";
assert.ok(split(softWrapped).every(part => /(?:[.!?]|^)\s*$/.test(part)), `cut at a wrapped line: ${JSON.stringify(split(softWrapped))}`);

// Never through a code block or a formula: a fence cut in two left the next
// chunk opening on its closing ``` and reading the prose after it as code.
const fenced = "Run the build first and wait for it to finish completely. Then:\n```sh\nmake all. make install. make check.\n```\nThat is all of it. Then $a. b = c. d$ holds, and `x. y` too. Done here.";
for (const local of [false, true]) {
    const parts = split(fenced, local);
    assert.ok(sameText(parts, fenced), `text lost between chunks (local: ${local})`);
    for (const part of parts) {
        assert.strictEqual((part.match(/```/g) ?? []).length % 2, 0, `a chunk cuts a fence: ${JSON.stringify(part)}`);
        assert.strictEqual((part.match(/\$/g) ?? []).length % 2, 0, `a chunk cuts a formula: ${JSON.stringify(part)}`);
        assert.strictEqual((part.match(/`/g) ?? []).length % 2, 0, `a chunk cuts inline code: ${JSON.stringify(part)}`);
    }
}

// The local voice: a sentence a part, a long one cut at a clause, every cut at a
// pause. Its parts are asked for a few at a time, so it has no cap on them.
const long = "Sure! I found the problem in the reader of the sidebar. When the next part of a reply is not ready by the time the current one finishes playing, the player decides the reading is over, clears the speaking state, and throws away every part that arrives afterwards. " + "It is fixed now. ".repeat(40);
const local = split(long, true);
assert.ok(sameText(local, long), "local: text lost between chunks");
assert.ok(local.length > 8, `local: capped at ${local.length} parts`);
assert.ok(local[0].startsWith("Sure! I found") && local[0].endsWith("sidebar."), `local: the opening part is the first sentences: ${local[0]}`);
for (const part of local)
    assert.ok(/[.!?,;:]$/.test(part.trim()), `local: cut away from a pause: ${JSON.stringify(part)}`);
assert.ok(local.every(part => part.length <= 120), `local: a part past 120 characters: ${local.map(p => p.length)}`);
assert.ok(local.slice(1).every(part => part.length >= 30 || /^It is fixed/.test(part)), "local: a clause cut off too short");

// The formula pattern the transcript renders with, as read-aloud uses it.
const formulas = s => (s.match(SpeechMatch.formulaPattern()) ?? []).filter(SpeechMatch.isFormula);
assert.deepStrictEqual(formulas("so $x^2$ and $$y$$ and \\(z\\) and \\[w\\]"), ["$x^2$", "$$y$$", "\\(z\\)", "\\[w\\]"]);
assert.deepStrictEqual(formulas("it costs $5 and $10, or \\$3 and \\$4"), [], "prose dollars are not a formula");
assert.deepStrictEqual(formulas("set `$HOME` and `$PATH`"), [], "inline code is not a formula");
assert.deepStrictEqual(formulas("costs $10, see `$HOME`"), [], "a dollar before inline code opened a formula");

// A formula and an image are one object on screen; every word said for one
// marks it. Hand-written from TextEdit.getText of the rendered markdown.
const mathSource = "The energy is $E = mc^2$, so ![x](a.png) and **more** &amp; <b>bold</b> here.";
const mathShown = "The energy is  ￼, so ￼ and more & bold here.";
const at = (offset) => { const w = findWordAtOffset(mathShown, mathSource, offset); return w && mathShown.slice(w.start, w.end); };
assert.strictEqual(at(mathSource.indexOf("$E")), "￼,");
assert.strictEqual(at(mathSource.indexOf("more")), "more");
assert.strictEqual(at(mathSource.indexOf("&amp;")), "&");
assert.strictEqual(at(mathSource.indexOf("bold")), "bold");
assert.strictEqual(at(mathSource.indexOf("here")), "here.");
assert.deepStrictEqual(findPhrase(mathShown, mathSource), { start: 0, end: mathShown.length });

console.log("ok");
