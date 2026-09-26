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
// stays at the start of its line. Lifted from HermesService.qml.
const svc = require("fs").readFileSync(__dirname + "/HermesService.qml", "utf8");
const splitSrc = svc.slice(svc.indexOf("function _splitForSpeech(text: string): var {"));
const split = new Function("root", "return " + splitSrc.slice(0, splitSrc.indexOf("\n    }\n") + 6)
    .replace("function _splitForSpeech(text: string): var", "function (text)"))({ _minFirstChunk: 60, _minChunk: 140, _maxChunks: 8 });
const reply = "Here is the plan:\n- read the files first.\n- then write the patch.\n\n" + "Then it is tested again. ".repeat(60);
const chunks = split(reply);
assert.ok(chunks.length > 1 && chunks.length <= 8, "chunks");
assert.ok(chunks.every(chunk => reply.includes(chunk)), "a chunk is not a slice of the message");
assert.ok(chunks[0].includes("\n- then"), "a list marker lost its line start");
assert.strictEqual(chunks.join(" ").replace(/\s+/g, " "), reply.trim().replace(/\s+/g, " "), "text lost between chunks");

console.log("ok");
