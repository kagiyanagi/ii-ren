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

console.log("ok");
