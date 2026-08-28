// An Obsidian-style Markdown checklist read as a to-do list. Only "- [ ]"
// lines are ours: headings, prose, and boxes Obsidian treats as extended
// states ("- [/]", "- [-]") are carried through a write untouched.

// Kept in four pieces so a rewrite puts back the original indent, bullet and
// spacing, and only the box or the text changes.
const TASK_LINE = /^(\s*[-*+]\s+\[)([ xX])(\]\s*)(.*)$/;

function parse(text) {
    const tasks = [];
    text.split("\n").forEach((line, i) => {
        const match = line.match(TASK_LINE);
        if (match)
            tasks.push({ "content": match[4], "done": match[2] !== " ", "line": i });
    });
    return tasks;
}

function setDone(text, line, done) {
    const lines = text.split("\n");
    lines[line] = lines[line].replace(TASK_LINE, `$1${done ? "x" : " "}$3$4`);
    return lines.join("\n");
}

function remove(text, line) {
    const lines = text.split("\n");
    lines.splice(line, 1);
    return lines.join("\n");
}

function append(text, content) {
    const lines = text === "" ? [] : text.split("\n");
    const tasks = parse(text);
    // Land inside the checklist, not after whatever prose trails it.
    const at = tasks.length > 0 ? tasks[tasks.length - 1].line + 1 : lines.length;
    lines.splice(at, 0, `- [ ] ${content}`);
    return lines.join("\n");
}

if (typeof module !== "undefined")
    module.exports = { parse: parse, setDone: setDone, remove: remove, append: append };
