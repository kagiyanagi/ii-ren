// Self-check: node modules/common/models/test_screen_translator.js
// Pulls handleTransOutput() straight out of the QML so the two can't drift.
const qml = require("fs").readFileSync(__dirname + "/TextTranslator.qml", "utf8");
const body = qml.match(/function handleTransOutput\(out: string\) \{([\s\S]*?)\n    \}/)[1];

const AsyncTask = { State: { Done: 0, Preparing: 1, Processing: 2, Error: 3 } };
const Translation = { tr: s => s };
const handle = new Function("out", "root", "AsyncTask", "Translation", body);

function run(out, pending) {
    const root = { pendingStrings: pending, translations: [], state: null, errorMessage: "", errors: 0 };
    root.error = () => root.errors++;
    root.fail = m => { root.state = AsyncTask.State.Error; root.errorMessage = m; root.error(m); };
    root.succeed = () => { root.state = AsyncTask.State.Done; };
    root.finished = () => {};
    handle(out, root, AsyncTask, Translation);
    return root;
}

// Trailing newline is stripped, not counted as a translation.
let r = run("a\nb\n", ["x", "y"]);
console.assert(JSON.stringify(r.translations) === '["a","b"]', "trailing newline: " + JSON.stringify(r.translations));
console.assert(r.state === AsyncTask.State.Done);

// A blank translation keeps its slot.
r = run("a\n\nc\n", ["x", "y", "z"]);
console.assert(JSON.stringify(r.translations) === '["a","","c"]', "blank line: " + JSON.stringify(r.translations));

// Desync must error out rather than misalign the overlay boxes.
for (const [out, pending] of [["a\n", ["x", "y"]], ["a\nb\nc\n", ["x", "y"]], ["", ["x"]], [undefined, ["x"]]]) {
    r = run(out, pending);
    console.assert(r.state === AsyncTask.State.Error && r.errors === 1, "want error for " + JSON.stringify(out));
    if (r.state !== AsyncTask.State.Error) process.exit(1);
}

// --- TextRecognizer -----------------------------------------------------------
const ocrQml = require("fs").readFileSync(__dirname + "/TextRecognizer.qml", "utf8");
const grab = (sig, args) => new Function(...args, ocrQml.match(new RegExp("function " + sig + " \\{([\\s\\S]*?)\\n    \\}"))[1]);
const handleTsv = grab("handleTsv\\(tsv: string\\)", ["tsv", "root", "AsyncTask", "Translation"]);
const joinWords = grab("joinWords\\(words: list<string>\\): string", ["words"]);

function ocr(tsv) {
    const root = { paragraphs: [], confidenceThreshold: 50, state: null, errorMessage: "", errors: 0, joinWords };
    root.error = () => root.errors++;
    root.fail = m => { root.state = AsyncTask.State.Error; root.errorMessage = m; root.error(m); };
    root.succeed = () => { root.state = AsyncTask.State.Done; };
    handleTsv(tsv, root, AsyncTask, Translation);
    return root;
}

const HEADER = "level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext";
const row = (lvl, line, l, t, w, h, conf, text) =>
    [lvl, 1, 1, 1, line, 1, l, t, w, h, conf, text].join("\t");

// Latin words take spaces; CJK does not, so a wrapped Japanese line rejoins cleanly.
console.assert(joinWords(["Good", "morning", "everyone"]) === "Good morning everyone");
console.assert(joinWords(["\u7c73\u5f53\u5c40\u306f\u3001", "\u3042\u306a\u305f\u306e"]) === "\u7c73\u5f53\u5c40\u306f\u3001\u3042\u306a\u305f\u306e", joinWords(["\u7c73\u5f53\u5c40\u306f\u3001", "\u3042\u306a\u305f\u306e"]));
console.assert(joinWords(["Png", "\u306f"]) === "Png \u306f");
console.assert(joinWords([]) === "");

// Two lines of one paragraph collapse to one line; the box is the level-3 row.
let o = ocr([HEADER,
    row(3, 0, 32, 34, 229, 84, -1, ""),
    row(5, 1, 32, 34, 82, 26, 92, "Good"),
    row(5, 1, 128, 34, 133, 34, 89, "morning"),
    row(5, 2, 32, 91, 143, 27, 89, "everyone"),
    ""].join("\n"));
console.assert(o.paragraphs.length === 1, "paragraph count: " + o.paragraphs.length);
console.assert(o.paragraphs[0].text === "Good morning everyone", JSON.stringify(o.paragraphs[0].text));
console.assert(JSON.stringify(o.paragraphs[0].boundingBox.vertices)
    === '[{"x":32,"y":34},{"x":261,"y":34},{"x":261,"y":118},{"x":32,"y":118}]',
    JSON.stringify(o.paragraphs[0].boundingBox.vertices));
console.assert(o.state === AsyncTask.State.Done);

// Low mean confidence drops the whole paragraph rather than mangling its words.
o = ocr([HEADER, row(3, 0, 0, 0, 10, 10, -1, ""), row(5, 1, 0, 0, 10, 10, 12, "rn0ise"), ""].join("\n"));
console.assert(o.state === AsyncTask.State.Error && o.paragraphs.length === 0, "low conf should error");

// Blank page and a missing/failed tesseract both surface as errors, not empty boxes.
console.assert(ocr(HEADER + "\n").state === AsyncTask.State.Error, "blank page should error");
console.assert(ocr("").state === AsyncTask.State.Error, "no tesseract should error");
console.assert(ocr(undefined).state === AsyncTask.State.Error, "undefined should error");

// --- ScreenTextOverlay.isRealTranslation --------------------------------------
const ovQml = require("fs").readFileSync(__dirname + "/../../ii/screenTranslator/ScreenTextOverlay.qml", "utf8");
const isReal = new Function("source", "translated",
    ovQml.match(/function isRealTranslation\(source: string, translated: string\): bool \{([\s\S]*?)\n    \}/)[1]);

// `trans` hands back same-language text with punctuation nudged. Not a translation.
console.assert(!isReal("View File", "View File"));
console.assert(!isReal("Hiding InTh..", "Hiding InTh."), "trailing dot");
console.assert(!isReal("don\u2019t stop", "don't stop"), "smart quote");
console.assert(!isReal("Safe search: moderate", "Safe search - moderate"));
console.assert(!isReal("anything", ""), "empty output is not a translation");
// A real one still shows.
console.assert(isReal("\u304a\u306f\u3088\u3046", "Good morning"));
console.assert(isReal("Settings", "\u8a2d\u5b9a"));

console.log("ok");
