// node services/markdownTodo.test.js
// A note that is more than a checklist: heading, prose after the list, mixed
// bullets, an indented subtask, and an extended box that isn't a plain to-do.
const assert = require("assert");
const Md = require("./markdownTodo.js");

const NOTE = [
    "# Chores",
    "",
    "- [ ] fix the password mess",
    "* [x] migrate immich and hermes to vps",
    "  - [ ] and the photos",
    "- [/] in progress, not ours",
    "",
    "Notes below the list.",
    "",
].join("\n");

const tasks = Md.parse(NOTE);
assert.deepStrictEqual(tasks.map(t => t.content),
    ["fix the password mess", "migrate immich and hermes to vps", "and the photos"]);
assert.deepStrictEqual(tasks.map(t => t.done), [false, true, false]);
assert.deepStrictEqual(tasks.map(t => t.line), [2, 3, 4]); // heading and blank skipped

// Toggling twice must give back the file byte for byte: bullet, indent and
// spacing all survive, and "- [/]" is left where it was.
assert.strictEqual(Md.setDone(Md.setDone(NOTE, 3, false), 3, true), NOTE);
assert.strictEqual(Md.setDone(NOTE, 3, false).split("\n")[3],
    "* [ ] migrate immich and hermes to vps");
assert.strictEqual(Md.setDone(NOTE, 4, true).split("\n")[4], "  - [x] and the photos");

const removed = Md.remove(NOTE, 2);
assert.deepStrictEqual(Md.parse(removed).map(t => t.content),
    ["migrate immich and hermes to vps", "and the photos"]);
assert.ok(removed.startsWith("# Chores\n\n*"));
assert.ok(removed.includes("Notes below the list."));

// New tasks land after the last checkbox, not after the trailing prose.
const added = Md.append(NOTE, "buy milk");
assert.strictEqual(added.split("\n")[5], "- [ ] buy milk");
assert.ok(added.includes("Notes below the list."));
assert.strictEqual(Md.parse(added).length, 4);

assert.strictEqual(Md.append("", "first"), "- [ ] first"); // file didn't exist yet
// No checklist yet, so it goes at the end rather than into the prose.
assert.strictEqual(Md.append("# Empty note\n", "first"), "# Empty note\n\n- [ ] first");

console.log("markdownTodo.test.js: all assertions passed");
