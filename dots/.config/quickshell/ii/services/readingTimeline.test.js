// node services/readingTimeline.test.js
const assert = require("assert");
const T = require("./readingTimeline.js");

// Three parts: the first two made (1000 ms for 10 characters, 3000 for 20),
// the third not yet, so estimated at their rate: 4000 ms over 30 characters.
const parts = ["a".repeat(10), "b".repeat(20), "c".repeat(30)];
const clips = [
    { duration: 1000, marks: [[0, 0], [400, 5]] },
    { duration: 3000, marks: [[100, 0], [1500, 8], [2600, 15]] },
    undefined,
];
assert.strictEqual(T.msPerChar(parts, clips), 4000 / 30);
assert.deepStrictEqual(T.durations(parts, clips), [1000, 3000, 4000]);
assert.strictEqual(T.total(T.durations(parts, clips)), 8000);
assert.strictEqual(T.msPerChar(parts, []), 0, "no rate before anything is made");
assert.deepStrictEqual(T.durations(parts, []), [0, 0, 0]);
// A part that failed takes no room.
assert.deepStrictEqual(T.durations(parts, [clips[0], "failed", undefined]), [1000, 0, 3000]);

const durs = T.durations(parts, clips);
assert.strictEqual(T.startOf(durs, 0), 0);
assert.strictEqual(T.startOf(durs, 2), 4000);
// A boundary is the start of the later part; past either end clamps.
assert.deepStrictEqual(T.locate(durs, 0), { index: 0, offset: 0 });
assert.deepStrictEqual(T.locate(durs, 999), { index: 0, offset: 999 });
assert.deepStrictEqual(T.locate(durs, 1000), { index: 1, offset: 0 });
assert.deepStrictEqual(T.locate(durs, 5000), { index: 2, offset: 1000 });
assert.deepStrictEqual(T.locate(durs, 99999), { index: 2, offset: 4000 });
assert.deepStrictEqual(T.locate(durs, -5), { index: 0, offset: 0 });
// Zero-length parts are stepped over, never landed in mid-way.
assert.deepStrictEqual(T.locate([1000, 0, 3000], 1000), { index: 2, offset: 0 });

// The word at a time: off the marks, the first before the first mark.
assert.strictEqual(T.charAt(parts[1], clips[1], 50, 3000), 0);
assert.strictEqual(T.charAt(parts[1], clips[1], 1499, 3000), 0);
assert.strictEqual(T.charAt(parts[1], clips[1], 1500, 3000), 8);
assert.strictEqual(T.charAt(parts[1], clips[1], 2999, 3000), 15);
// Without marks, the same share of the characters.
assert.strictEqual(T.charAt(parts[2], undefined, 2000, 4000), 15);
assert.strictEqual(T.charAt(parts[2], undefined, 4000, 4000), 29, "never past the last character");

// Where to start for a word: the start of the word holding that character.
assert.strictEqual(T.startForChar(clips[1], 0), 100);
assert.strictEqual(T.startForChar(clips[1], 10), 1500);
assert.strictEqual(T.startForChar(clips[1], 19), 2600);
assert.strictEqual(T.startForChar(undefined, 5), 0);
// A seek lands on the start of the word it falls in, never mid-word.
assert.strictEqual(T.wordStart(clips[1], 2000), 1500);
assert.strictEqual(T.wordStart(clips[1], 50), 0, "before the first word: from the start");
assert.strictEqual(T.wordStart({ duration: 500, marks: [] }, 300), 0);

console.log("ok");
