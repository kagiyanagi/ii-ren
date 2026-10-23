// Settings search: every setting the settings pages draw, read out of their QML,
// and a ranking that forgives the way people actually type.
//
// The index used to be regexes over each page's text: it took section titles,
// switches and spin boxes, never a sub-page, never a slider or a chip row, and it
// scored sections by summing loose letter-subsequence matches, so a long section
// outranked the one row that said exactly what was typed. "Shake to find the
// pointer" lives on the Cursor sub-page and could not be found at all.
//
// This parses each file into its object tree, so a row knows its section, its
// sub-page and its page, and every row is its own result. Matching works per
// word: exact, prefix, infix, then typos (Damerau distance, scaled to the word's
// length), plus a few synonyms ("cursor" finds "pointer"). settingsSearch.test.js
// checks it with `node`; tools/check-settings-search.py runs it over the real pages.

// Rows that are one setting each, and the property that labels them.
var ROW_TYPES = {
    ConfigSwitch: "text",
    ConfigSpinBox: "text",
    ConfigSlider: "text",
    ConfigLabeledRow: "text",
    ConfigSelectionRow: "text",
    ConfigFormatPicker: "text",
    ConfigNavRow: "text",
    ConfigTextField: "text"
};

// ---------------------------------------------------------------------------
// A QML reader: just enough of the grammar to get the object tree and each
// object's bindings as raw text. Strings, comments, regex literals and JS
// blocks are stepped over whole, so a brace or an apostrophe inside one never
// unbalances the tree.

function isIdentStart(c) {
    return c !== undefined && /[A-Za-z_$]/.test(c);
}

function isIdentChar(c) {
    return c !== undefined && /[A-Za-z0-9_$]/.test(c);
}

function readIdent(s, i) {
    while (i < s.length && isIdentChar(s[i]))
        i++;
    return i;
}

function readDotted(s, i) {
    let j = readIdent(s, i);
    while (s[j] === "." && isIdentStart(s[j + 1]))
        j = readIdent(s, j + 1);
    return j;
}

function skipLineComment(s, i) {
    const e = s.indexOf("\n", i);
    return e === -1 ? s.length : e;
}

function skipBlockComment(s, i) {
    const e = s.indexOf("*/", i + 2);
    return e === -1 ? s.length : e + 2;
}

function skipWs(s, i) {
    while (i < s.length) {
        const c = s[i];
        if (c === " " || c === "\t" || c === "\n" || c === "\r") {
            i++;
        } else if (c === "/" && s[i + 1] === "/") {
            i = skipLineComment(s, i);
        } else if (c === "/" && s[i + 1] === "*") {
            i = skipBlockComment(s, i);
        } else {
            break;
        }
    }
    return i;
}

function skipString(s, i) {
    const q = s[i];
    i++;
    while (i < s.length) {
        const c = s[i];
        if (c === "\\") {
            i += 2;
        } else if (c === q) {
            return i + 1;
        } else if (q === "`" && c === "$" && s[i + 1] === "{") {
            i = skipBalanced(s, i + 1);
        } else if (c === "\n" && q !== "`") {
            return i; // an unterminated quote ends with its line, not the file
        } else {
            i++;
        }
    }
    return i;
}

function skipRegex(s, i) {
    i++;
    let inClass = false;
    while (i < s.length) {
        const c = s[i];
        if (c === "\\") {
            i += 2;
            continue;
        }
        if (c === "\n")
            return i;
        if (c === "[")
            inClass = true;
        else if (c === "]")
            inClass = false;
        else if (c === "/" && !inClass) {
            i++;
            while (isIdentChar(s[i]))
                i++; // flags
            return i;
        }
        i++;
    }
    return i;
}

// A `/` starts a regex literal where a value is expected, not after one.
function regexCanStart(prev) {
    return prev === "" || "(,=:[!&|?{};+-*%<>~^".indexOf(prev) !== -1;
}

// s[i] opens a bracket; returns the index just past its partner.
function skipBalanced(s, i) {
    let depth = 0;
    let prev = "";
    while (i < s.length) {
        const c = s[i];
        if (c === '"' || c === "'" || c === "`") {
            i = skipString(s, i);
            prev = "a";
            continue;
        }
        if (c === "/" && s[i + 1] === "/") {
            i = skipLineComment(s, i);
            continue;
        }
        if (c === "/" && s[i + 1] === "*") {
            i = skipBlockComment(s, i);
            continue;
        }
        if (c === "/" && regexCanStart(prev)) {
            i = skipRegex(s, i);
            prev = "a";
            continue;
        }
        if (c === "(" || c === "[" || c === "{") {
            depth++;
        } else if (c === ")" || c === "]" || c === "}") {
            depth--;
            if (depth === 0)
                return i + 1;
        }
        if (c !== " " && c !== "\t" && c !== "\n" && c !== "\r")
            prev = c;
        i++;
    }
    return i;
}

// A line that ends on one of these, or a next line that starts with one,
// continues the same expression.
var CONTINUES_AFTER = "?:+-*/%&|=,<>!.([{";
var CONTINUES_BEFORE = "?:.+-*/%&|,=<>";

// The end of a binding's value: a `;`, the object's closing brace, or a newline
// that the expression does not run on past.
function readExpression(s, i) {
    let prev = "";
    while (i < s.length) {
        const c = s[i];
        if (c === "\n" || c === "\r") {
            const next = skipWs(s, i);
            if (prev !== "" && CONTINUES_AFTER.indexOf(prev) === -1 && CONTINUES_BEFORE.indexOf(s[next]) === -1)
                return i;
            i = next;
            continue;
        }
        if (c === ";")
            return i + 1;
        if (c === "}" || c === ")" || c === "]")
            return i;
        if (c === '"' || c === "'" || c === "`") {
            i = skipString(s, i);
            prev = "a";
            continue;
        }
        if (c === "/" && s[i + 1] === "/") {
            i = skipLineComment(s, i);
            continue;
        }
        if (c === "/" && s[i + 1] === "*") {
            i = skipBlockComment(s, i);
            continue;
        }
        if (c === "/" && regexCanStart(prev)) {
            i = skipRegex(s, i);
            prev = "a";
            continue;
        }
        if (c === "(" || c === "[" || c === "{") {
            i = skipBalanced(s, i);
            prev = c === "(" ? ")" : c === "[" ? "]" : "}";
            continue;
        }
        if (c !== " " && c !== "\t")
            prev = c;
        i++;
    }
    return i;
}

function newNode(type) {
    return {
        type: type,
        props: {},
        children: []
    };
}

// A binding's value: an object (`contentItem: RowLayout { }`) joins the tree,
// anything else is kept as its raw text.
function parseValue(s, i, node, name) {
    const k = skipWs(s, i);
    if (/[A-Z]/.test(s[k] || "")) {
        const e = readDotted(s, k);
        const k2 = skipWs(s, e);
        if (s[k2] === "{") {
            const child = newNode(s.slice(k, e));
            child.prop = name;
            node.children.push(child);
            return parseBody(s, k2 + 1, child);
        }
    }
    const end = readExpression(s, k);
    node.props[name] = s.slice(k, end).replace(/;\s*$/, "").trim();
    return end;
}

// The members of an object, from just past its `{` to just past its `}`.
function parseBody(s, i, node) {
    while (i < s.length) {
        i = skipWs(s, i);
        const c = s[i];
        if (c === undefined)
            return i;
        if (c === "}")
            return i + 1;
        if (!isIdentStart(c)) {
            i = c === "(" || c === "[" || c === "{" ? skipBalanced(s, i) : i + 1;
            continue;
        }

        const start = i;
        let j = readIdent(s, i);
        const word = s.slice(start, j);

        if (word === "import" || word === "pragma") {
            i = skipLineComment(s, j);
            continue;
        }
        if (word === "function") {
            j = s.indexOf("(", j);
            if (j === -1)
                return s.length;
            j = skipWs(s, skipBalanced(s, j));
            if (s[j] === ":") // a type annotation
                j = skipWs(s, readDotted(s, skipWs(s, j + 1)));
            i = s[j] === "{" ? skipBalanced(s, j) : j;
            continue;
        }
        if (word === "signal") {
            j = skipWs(s, readIdent(s, skipWs(s, j)));
            i = s[j] === "(" ? skipBalanced(s, j) : j;
            continue;
        }
        if (word === "enum") {
            j = s.indexOf("{", j);
            i = j === -1 ? s.length : skipBalanced(s, j);
            continue;
        }
        if (word === "component") {
            j = skipWs(s, readIdent(s, skipWs(s, j)));
            if (s[j] === ":")
                j = skipWs(s, j + 1);
            const typeEnd = readDotted(s, j);
            const type = s.slice(j, typeEnd);
            const k = skipWs(s, typeEnd);
            if (s[k] !== "{") {
                i = k;
                continue;
            }
            const child = newNode(type);
            child.inlineComponent = true;
            node.children.push(child);
            i = parseBody(s, k + 1, child);
            continue;
        }
        if (word === "readonly" || word === "required" || word === "default" || word === "property") {
            let w = word;
            while (w === "readonly" || w === "required" || w === "default") {
                j = skipWs(s, j);
                const e = readIdent(s, j);
                w = s.slice(j, e);
                j = e;
            }
            if (w !== "property") { // `required name`, re-declaring an inherited one
                i = readExpression(s, j);
                continue;
            }
            j = skipWs(s, j);
            j = readDotted(s, j); // the type
            j = skipWs(s, j);
            if (s[j] === "<") { // list<string>
                const e = s.indexOf(">", j);
                j = skipWs(s, e === -1 ? s.length : e + 1);
            }
            const nameEnd = readIdent(s, j);
            const name = s.slice(j, nameEnd);
            j = skipWs(s, nameEnd);
            if (s[j] === ":") {
                i = parseValue(s, j + 1, node, name);
            } else {
                i = j;
            }
            continue;
        }

        j = readDotted(s, start);
        const name = s.slice(start, j);
        let k = skipWs(s, j);

        if (s[k] === "{") { // an object, or a grouped property (`font { }`)
            const child = newNode(name);
            node.children.push(child);
            i = parseBody(s, k + 1, child);
            continue;
        }
        if (s.slice(k, k + 2) === "on" && !isIdentChar(s[k + 2])) { // Behavior on x { }
            k = skipWs(s, readDotted(s, skipWs(s, k + 2)));
            if (s[k] === "{") {
                const child = newNode(name);
                node.children.push(child);
                i = parseBody(s, k + 1, child);
                continue;
            }
        }
        if (s[k] === ":") {
            i = parseValue(s, k + 1, node, name);
            continue;
        }
        i = readExpression(s, j);
        if (i === j)
            i++;
    }
    return i;
}

// The file as a tree; the root node is the file itself, its one child the
// document's root object.
function parseQml(text) {
    const root = newNode("");
    parseBody(text || "", 0, root);
    return root;
}

// ---------------------------------------------------------------------------
// From the tree to entries.

function unquote(lit) {
    const q = lit[0];
    const body = lit.slice(1, -1);
    if (q === '"') {
        try {
            return JSON.parse(lit);
        } catch (e) {
            return body;
        }
    }
    return body.replace(/\\(.)/g, (m, ch) => ch === "n" ? "\n" : ch);
}

var TR_RE = /Translation\.tr\(\s*("(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')\s*\)/g;

// Every Translation.tr literal in a binding, in order.
function trStrings(raw) {
    if (!raw)
        return [];
    const out = [];
    TR_RE.lastIndex = 0;
    let m;
    while ((m = TR_RE.exec(raw)) !== null)
        out.push(unquote(m[1]));
    return out;
}

// What a label binding says, when it is static: one Translation.tr call or one
// string literal. A label built at runtime (`.arg()`, a model field) is null,
// since the index cannot know what it will read.
function staticString(raw) {
    if (!raw)
        return null;
    const v = raw.trim();
    let m = v.match(/^Translation\.tr\(\s*("(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')\s*\)$/);
    if (!m)
        m = v.match(/^("(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')$/);
    if (!m)
        return null;
    const s = unquote(m[1]).trim();
    return s.length > 0 && !/%\d/.test(s) ? s : null;
}

function isRow(node) {
    return node.type === "ContentSection" || node.type === "ContentSubsection" || ROW_TYPES[node.type] !== undefined;
}

// The words around a row that say what it does without being its label: its
// summary, tooltip, placeholder and choices. Nested rows keep their own.
function detailStrings(node, labelProp, out) {
    for (const key in node.props) {
        if (key === labelProp || key === "keywords" || key === "stringMap")
            continue;
        const strs = trStrings(node.props[key]);
        for (const s of strs)
            out.push(s);
    }
    for (const child of node.children) {
        if (isRow(child))
            continue;
        detailStrings(child, null, out);
    }
    return out;
}

function uniq(arr) {
    const seen = {};
    const out = [];
    for (const s of arr) {
        const k = s.toLowerCase();
        if (seen[k])
            continue;
        seen[k] = true;
        out.push(s);
    }
    return out;
}

function splitKeywords(strs) {
    const out = [];
    for (const s of strs)
        for (const part of s.split(","))
            if (part.trim().length > 0)
                out.push(part.trim());
    return out;
}

function walk(node, ctx, out) {
    let next = ctx;
    if (node.type === "ContentPage" && ctx.subPage && !ctx.subPageTitle) {
        const title = staticString(node.props.title);
        if (title)
            next = Object.assign({}, ctx, { subPageTitle: title });
    }
    if (node.type === "ContentSection" || node.type === "ContentSubsection") {
        const title = staticString(node.props.title);
        if (title) {
            out.push({
                kind: node.type === "ContentSection" ? "section" : "subsection",
                label: title,
                subPage: ctx.subPage,
                subPageTitle: next.subPageTitle,
                section: node.type === "ContentSubsection" ? ctx.section : "",
                subsection: "",
                keywords: splitKeywords(trStrings(node.props.stringMap)),
                // Its tooltip, and what it draws that is not a row of its own:
                // Power mode's chips say "Performance".
                details: uniq(detailStrings(node, "title", []).filter(s => s !== title))
            });
            next = Object.assign({}, next, node.type === "ContentSection" ? { section: title, subsection: "" } : { subsection: title });
        }
    } else if (ROW_TYPES[node.type] !== undefined) {
        const labelProp = ROW_TYPES[node.type];
        const label = staticString(node.props[labelProp]);
        if (label) {
            out.push({
                kind: "row",
                label: label,
                subPage: ctx.subPage,
                subPageTitle: next.subPageTitle,
                section: ctx.section,
                subsection: ctx.subsection,
                keywords: splitKeywords(trStrings(node.props.keywords)),
                details: uniq(detailStrings(node, labelProp, []).filter(s => s !== label))
            });
        }
    }
    for (const child of node.children)
        walk(child, next, out);
}

// Every searchable thing one file draws. `subPage` is the file's path relative
// to modules/settings/ when it is a sub-page ("widgets/CustomCursorConfig.qml"),
// empty for a page.
function indexFile(text, subPage) {
    const out = [];
    walk(parseQml(text), {
        subPage: subPage || "",
        subPageTitle: "",
        section: "",
        subsection: ""
    }, out);
    // A row repeated in one place (a Loader's two arms) is one result.
    const seen = {};
    return out.filter(e => {
        const k = [e.kind, e.label, e.subPage, e.section, e.subsection].join("\u0001");
        if (seen[k])
            return false;
        seen[k] = true;
        return true;
    });
}

// The sub-pages a page opens, named the way it opens them.
function subPagesOf(text) {
    const out = [];
    const re = /["'](widgets\/[A-Za-z0-9_]+\.qml)["']/g;
    let m;
    while ((m = re.exec(text || "")) !== null)
        if (out.indexOf(m[1]) === -1)
            out.push(m[1]);
    return out;
}

// ---------------------------------------------------------------------------
// Matching.

function normalize(text) {
    let s = String(text || "").toLowerCase();
    if (typeof s.normalize === "function")
        s = s.normalize("NFD").replace(/[̀-ͯ]/g, "");
    let out = "";
    for (let i = 0; i < s.length; i++) {
        const c = s[i];
        const letter = c.toLowerCase() !== c.toUpperCase() || (c >= "0" && c <= "9");
        out += letter ? c : " ";
    }
    return out.replace(/\s+/g, " ").trim();
}

function words(text) {
    const n = normalize(text);
    return n.length > 0 ? n.split(" ") : [];
}

// Words a query can leave out without losing anything.
var STOP_WORDS = {};
("a an the to of for on off in at by and or is it its my me i how do does can could with from this that "
    + "turn enable disable enabled disabled set change setting settings option options where want make").split(" ").forEach(w => STOP_WORDS[w] = true);

// The few places people and this shell name one thing two ways.
var SYNONYMS = {
    cursor: ["pointer", "mouse"],
    pointer: ["cursor", "mouse"],
    mouse: ["cursor", "pointer", "touchpad"],
    touchpad: ["mouse", "trackpad"],
    trackpad: ["touchpad"],
    wallpaper: ["background"],
    background: ["wallpaper"],
    volume: ["audio", "sound"],
    sound: ["audio", "volume", "sounds"],
    audio: ["sound", "volume"],
    color: ["colour", "colors", "colours"],
    colour: ["color", "colors", "colours"],
    colors: ["colours", "color"],
    colours: ["colors", "colour"],
    wifi: ["network", "wireless"],
    network: ["wifi", "internet"],
    internet: ["network", "wifi"],
    screen: ["display", "monitor"],
    display: ["screen", "monitor"],
    monitor: ["display", "screen"],
    shortcut: ["keybind", "hotkey", "shortcuts"],
    hotkey: ["shortcut", "keybind"],
    keybind: ["shortcut", "hotkey"],
    font: ["fonts", "typography", "typeface"],
    typeface: ["font"],
    taskbar: ["bar", "dock"],
    panel: ["bar", "sidebar"],
    ai: ["agent", "claude", "codex"],
    assistant: ["agent"],
    chatbot: ["agent"],
    lockscreen: ["lock"],
    sleep: ["suspend", "idle"],
    suspend: ["sleep", "idle"],
    theme: ["colours", "colors"],
    transparent: ["transparency", "opacity", "blur"],
    transparency: ["transparent", "opacity"],
    opacity: ["transparency"],
    clock: ["time"],
    time: ["clock"],
    weather: ["forecast"],
    language: ["translation", "locale"],
    animation: ["animations", "motion"],
    animations: ["animation", "motion"],
    corner: ["corners", "rounding"],
    rounding: ["corner", "corners", "radius"],
    notification: ["notifications"],
    notifications: ["notification"],
    icon: ["icons"],
    icons: ["icon"]
};

// Optimal string alignment distance, giving up past `max`.
function editDistance(a, b, max) {
    const la = a.length;
    const lb = b.length;
    if (Math.abs(la - lb) > max)
        return max + 1;
    let prev2 = null;
    let prev = new Array(lb + 1);
    for (let j = 0; j <= lb; j++)
        prev[j] = j;
    for (let i = 1; i <= la; i++) {
        const cur = new Array(lb + 1);
        cur[0] = i;
        let rowMin = cur[0];
        for (let j = 1; j <= lb; j++) {
            const cost = a[i - 1] === b[j - 1] ? 0 : 1;
            let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
            if (prev2 && i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1])
                v = Math.min(v, prev2[j - 2] + 1);
            cur[j] = v;
            if (v < rowMin)
                rowMin = v;
        }
        if (rowMin > max)
            return max + 1;
        prev2 = prev;
        prev = cur;
    }
    return prev[lb];
}

function maxTypos(len) {
    return len <= 3 ? 0 : len <= 5 ? 1 : 2;
}

// Below this a match is a guess at a typo, not something that was typed.
var TYPED = 0.8;

// How well one typed word matches one indexed word, 0..1.
function wordQuality(q, w) {
    if (q === w)
        return 1;
    if (w.length > q.length && w.indexOf(q) === 0)
        return 0.82 + 0.13 * q.length / w.length;
    if (q.length < 3)
        return 0;
    // A plural typed for a singular, or the other way round.
    const stem = q.replace(/(es|s)$/, "");
    if (stem.length >= 3 && stem !== q && w.indexOf(stem) === 0)
        return 0.85;
    if (w.indexOf(q) > 0)
        return 0.6;
    const max = maxTypos(q.length);
    if (max === 0)
        return 0;
    // A slip is almost never in the first letter; checking that first keeps
    // a few thousand distance tables off every keystroke.
    if (q[0] !== w[0] && q[0] !== w[1] && q[1] !== w[0])
        return 0;
    // A whole word with a slip in it.
    const d = editDistance(q, w, max);
    if (d <= max)
        return d === 1 ? 0.72 : 0.58;
    // The start of a word, typed with a slip, before the rest of it is typed.
    if (w.length > q.length) {
        let best = max + 1;
        for (let len = q.length - 1; len <= q.length + 1; len++)
            if (len >= 3 && len < w.length)
                best = Math.min(best, editDistance(q, w.slice(0, len), max));
        if (best <= max)
            return best === 1 ? 0.62 : 0.5;
    }
    return 0;
}

// Field weights: what a word counts for depends on where it sits.
var W_LABEL = 1;
var W_KEYWORD = 0.8;
var W_CONTEXT = 0.6; // the section or subsection the row is in
var W_PLACE = 0.55; // the page or sub-page
var W_DETAIL = 0.35; // summary, tooltip, choices

// Builds the search index. `entries` come from indexFile, each with `page`
// (index into `pages`) set; `pages` is settings.qml's list ({ name, summary });
// `tr` translates a source string (Translation.tr), or is omitted.
function buildIndex(entries, pages, tr) {
    const translate = typeof tr === "function" ? tr : (s => s);
    const vocab = [];
    const vocabId = {};

    function idsOf(strings) {
        const ids = [];
        for (const s of strings) {
            const ws = words(s);
            for (let i = 0; i < ws.length; i++) {
                const forms = [ws[i]];
                if (i + 1 < ws.length)
                    forms.push(ws[i] + ws[i + 1]); // "wi fi" is "wifi"
                for (const w of forms) {
                    let id = vocabId[w];
                    if (id === undefined) {
                        id = vocab.length;
                        vocab.push(w);
                        vocabId[w] = id;
                    }
                    if (ids.indexOf(id) === -1)
                        ids.push(id);
                }
            }
        }
        return ids;
    }

    function both(s) {
        if (!s)
            return [];
        const t = translate(s);
        return t && t !== s ? [s, t] : [s];
    }

    function bothAll(arr) {
        let out = [];
        for (const s of arr || [])
            out = out.concat(both(s));
        return out;
    }

    const items = entries.map(e => {
        const page = pages[e.page] || {};
        const label = translate(e.label);
        const subPageTitle = e.subPageTitle ? translate(e.subPageTitle) : "";
        const place = [page.name || "", subPageTitle];
        const fields = [
            { w: W_LABEL, ids: idsOf(both(e.label)) },
            { w: W_KEYWORD, ids: idsOf(bothAll(e.keywords)) },
            { w: W_CONTEXT, ids: idsOf(bothAll([e.section, e.subsection].filter(s => s && e.kind !== "section"))) },
            { w: W_PLACE, ids: idsOf(place.filter(s => s).concat(e.subPageTitle ? [e.subPageTitle] : [])) },
            { w: W_DETAIL, ids: idsOf(bothAll(e.details)) }
        ].filter(f => f.ids.length > 0);
        // Where it lives, as the result's second line: the page, then the
        // sub-page or, on the page itself, the section.
        const where = [page.name || "", subPageTitle || (e.kind === "section" ? "" : translate(e.section))];
        return {
            entry: e,
            key: [e.page, e.subPage, e.section, e.subsection, e.kind, e.label].join("|"),
            label: label,
            where: where.filter(s => s).join(" \u203a "),
            labelNorms: both(e.label).map(normalize),
            fields: fields
        };
    });

    return {
        items: items,
        vocab: vocab,
        cache: {} // query word -> its match qualities, reused while the query grows
    };
}

// Query words, each with the words it may stand for and whether it can be left
// out ("turn off the ..." still has to find the row without a "turn" in it).
function queryTerms(query) {
    const ws = words(query);
    const allStop = ws.every(w => STOP_WORDS[w]);
    return ws.map(w => ({
        word: w,
        optional: !allStop && STOP_WORDS[w] === true,
        alts: SYNONYMS[w] || []
    }));
}

// Ranked results for a query: [{ entry, key, label, where, score }], best first.
// A result scores the mean of how well each query word matched it, so one that
// matches every word, even weakly ("lock screen blur": Blur, on the Lock screen
// page), beats one that matches two words well and the third not at all. What
// scores under RELEVANT of the best is dropped: a long tail of one-word matches
// is noise, not choice.
var RELEVANT = 0.45;

function search(index, query, limit) {
    const terms = queryTerms(query);
    if (terms.length === 0 || !index)
        return [];
    const vocab = index.vocab;

    // How well each indexed word matches each query word, computed once. A
    // word that some setting really contains is taken as typed: guessing at
    // typos for it too put "Shape" under "shake".
    const quality = terms.map(t => {
        if (index.cache[t.word])
            return index.cache[t.word];
        const q = new Float32Array(vocab.length);
        let typed = false;
        for (let i = 0; i < vocab.length; i++) {
            q[i] = wordQuality(t.word, vocab[i]);
            if (q[i] >= TYPED)
                typed = true;
        }
        for (let i = 0; i < vocab.length; i++) {
            if (typed && q[i] < TYPED && vocab[i].indexOf(t.word) <= 0)
                q[i] = 0;
            if (q[i] < 1)
                for (const alt of t.alts)
                    if (vocab[i] === alt || (alt.length >= 4 && vocab[i].indexOf(alt) === 0))
                        q[i] = Math.max(q[i], 0.75);
        }
        index.cache[t.word] = q;
        return q;
    });

    const phrase = normalize(query);
    const results = [];
    let top = 0;

    for (const item of index.items) {
        let score = 0;
        let matched = 0;
        for (let t = 0; t < terms.length; t++) {
            const q = quality[t];
            let best = 0;
            for (const f of item.fields) {
                for (const id of f.ids) {
                    const v = q[id] * f.w;
                    if (v > best)
                        best = v;
                }
            }
            score += best;
            if (best > 0 && !terms[t].optional)
                matched++;
        }
        if (matched === 0)
            continue;
        score /= terms.length;
        for (const n of item.labelNorms) {
            if (n === phrase) {
                score += 0.5;
                break;
            }
            if (n.indexOf(phrase) === 0) {
                score += 0.3;
                break;
            }
            if (phrase.length >= 3 && n.indexOf(phrase) > 0) {
                score += 0.2;
                break;
            }
        }
        if (score > top)
            top = score;
        results.push({
            entry: item.entry,
            key: item.key,
            label: item.label,
            where: item.where,
            score: score
        });
    }

    const kept = results.filter(r => r.score >= top * RELEVANT);
    kept.sort((a, b) => b.score - a.score || a.label.length - b.label.length || a.label.localeCompare(b.label));
    return typeof limit === "number" ? kept.slice(0, limit) : kept;
}

if (typeof module !== "undefined")
    module.exports = {
        parseQml: parseQml,
        indexFile: indexFile,
        subPagesOf: subPagesOf,
        staticString: staticString,
        trStrings: trStrings,
        normalize: normalize,
        editDistance: editDistance,
        wordQuality: wordQuality,
        buildIndex: buildIndex,
        search: search
    };
