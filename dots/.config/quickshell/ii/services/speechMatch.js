// Finding a spoken passage inside rendered markdown.
//
// Read-aloud speaks the message *source*, while the transcript shows Qt's
// rendered markdown: `**bold**` is four characters shorter on screen and a link
// is only its label. So a source offset means nothing to the text view, and the
// passage is located by matching both sides with the syntax the renderer drops
// taken out, then reading the surviving positions back off a map.

const DROPPED = "*_`~#[]()\\|";

// Block syntax the view renders as layout rather than text: a list bullet or
// number, a task box, a quote bar. Only ever at the start of a line.
const BLOCK_MARKER = /^[ \t]*(?:>[ \t]?)*(?:(?:[-*+]|\d{1,9}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?)?/;
// A rule or a table's delimiter row, which leave no text at all.
const RULE_LINE = /^[ \t|:]*(?:[-*_][ \t|:]*){3,}(?=\n|$)/;
// Qt's markdown import separates table cells with these two noncharacters.
const SPACES = " \t\n\r\u00a0\u2028\u2029\ufdd0\ufdd1";

/**
 * Strip markdown syntax and collapse whitespace, keeping `map[i]` -- where the
 * i-th surviving character came from in `s`.
 */
function normalize(s) {
    const chars = [];
    const map = [];
    let prevSpace = true;
    for (let i = 0; i < s.length; i++) {
        if (i === 0 || s[i - 1] === "\n") {
            const rest = s.slice(i);
            const skip = (RULE_LINE.exec(rest) ?? BLOCK_MARKER.exec(rest))[0].length;
            if (skip > 0) {
                i += skip - 1;
                if (!prevSpace) {
                    chars.push(" ");
                    map.push(i);
                    prevSpace = true;
                }
                continue;
            }
        }
        const c = s[i];
        if (SPACES.indexOf(c) !== -1) {
            if (!prevSpace) {
                chars.push(" ");
                map.push(i);
                prevSpace = true;
            }
            continue;
        }
        if (c === "]" && s[i + 1] === "(") { // a link's target: the view shows the label only
            const close = s.indexOf(")", i + 2);
            i = close === -1 ? s.length : close;
            continue;
        }
        if (DROPPED.indexOf(c) !== -1)
            continue;
        chars.push(c.toLowerCase());
        map.push(i);
        prevSpace = false;
    }
    if (prevSpace && chars.length > 0) { // a trailing space belongs to no word
        chars.pop();
        map.pop();
    }
    return { text: chars.join(""), map: map };
}

// Enough to identify one sentence's opening or close, short enough to survive a
// link's URL or an image sitting in the middle of it.
const ANCHOR = 24;

/**
 * How `phrase` lies over the normalized haystack, or null: haystack index =
 * phrase index + `shift`, trusted over haystack positions [from, to).
 *
 * A reply is several views -- a code block splits the text around it -- while
 * the passage being spoken is cut at sentence ends, so it often starts in one
 * view and ends in the next. Each view places the part it holds: the whole
 * phrase; its head, with the rest eaten by the renderer (a LaTeX image) or
 * carried on into the next view; its tail, carried over from the previous one;
 * or the view lies wholly inside the phrase. A view that holds none of it gets
 * null, so the word being spoken is marked in the one view that has it and
 * never pinned to the end of the one it has left.
 */
function locate(hay, phrase) {
    const needle = normalize(phrase || "").text;
    const text = hay.text;
    const len = needle.length;
    if (len === 0 || text.length === 0)
        return null;
    const place = (shift, from, to) => ({ shift: shift, from: Math.max(0, from), to: Math.min(text.length, to) });
    // Starts and ends only on word edges: a short piece of the phrase inside some
    // other word is not where the phrase is.
    const edge = (str, at) => at <= 0 || at >= str.length || str[at - 1] === " " || str[at] === " ";

    let at = text.indexOf(needle);
    if (at >= 0)
        return place(at, at, at + len);

    const head = needle.slice(0, ANCHOR);
    const tail = needle.slice(-ANCHOR);
    at = text.indexOf(head);
    if (at >= 0) {
        const tailAt = text.indexOf(tail, at + head.length);
        return place(at, at, tailAt >= 0 ? tailAt + tail.length : at + len);
    }
    at = text.lastIndexOf(tail);
    if (at >= 0)
        return place(at + tail.length - len, at + tail.length - len, at + tail.length);

    at = needle.indexOf(text);
    if (at >= 0 && edge(needle, at) && edge(needle, at + text.length))
        return place(-at, 0, text.length);
    // Pieces shorter than an anchor at either edge of the view.
    for (let k = Math.min(head.length, text.length) - 1; k > 0; k--)
        if (text.endsWith(needle.slice(0, k)) && edge(text, text.length - k) && edge(needle, k))
            return place(text.length - k, text.length - k, text.length);
    for (let k = Math.min(tail.length, text.length) - 1; k > 0; k--)
        if (text.startsWith(needle.slice(len - k)) && edge(needle, len - k) && edge(text, k))
            return place(k - len, 0, k);
    return null;
}

/** Where `phrase` sits in `rendered`, as positions into `rendered`, or null. */
function findPhrase(rendered, phrase) {
    const hay = normalize(rendered || "");
    const hit = locate(hay, phrase);
    return hit ? { start: hay.map[hit.from], end: hay.map[hit.to - 1] + 1 } : null;
}

/** The word of `hay` at phrase position `at`, if this haystack holds that part. */
function wordAt(hay, hit, at) {
    const pos = at + hit.shift;
    return pos >= hit.from && pos < hit.to ? wordAround(hay, pos) : null;
}

/** The word of the haystack around normalized position `at`. */
function wordAround(hay, at) {
    let from = at;
    while (from > 0 && hay.text[from - 1] !== " ")
        from--;
    let to = at;
    while (to < hay.text.length && hay.text[to] !== " ")
        to++;
    return to > from ? { start: hay.map[from], end: hay.map[to - 1] + 1 } : null;
}

/**
 * The word at `offset` characters into `phrase`, as positions into `rendered`,
 * or null. The offset is what a provider's word timings point at, so this is the
 * exact mark; `findWordAt` below is the estimate for a provider that gives none.
 */
function findWordAtOffset(rendered, phrase, offset) {
    const hay = normalize(rendered || "");
    const hit = locate(hay, phrase);
    if (!hit)
        return null;
    // The offset counts characters of the phrase as written; the haystack has
    // dropped the markdown out of it, so it is counted again on the phrase's own
    // normalized form.
    const spoken = normalize(phrase || "");
    let ahead = 0;
    while (ahead < spoken.map.length && spoken.map[ahead] < offset)
        ahead++;
    return wordAt(hay, hit, Math.min(ahead, spoken.text.length - 1));
}

/**
 * The one word of `phrase` being spoken when `progress` (0..1) of it has been
 * said, as positions into `rendered`, or null.
 *
 * Shared out by characters rather than by words: "synchronized" takes four times
 * as long to say as "and", and a word-count split would run ahead of the voice
 * through a long one and wait for it through short ones.
 */
function findWordAt(rendered, phrase, progress) {
    const hay = normalize(rendered || "");
    const hit = locate(hay, phrase);
    if (!hit)
        return null;
    const len = normalize(phrase || "").text.length;
    return wordAt(hay, hit, Math.floor(Math.max(0, Math.min(0.999, progress)) * len));
}

if (typeof module !== "undefined")
    module.exports = {
        normalize: normalize,
        findPhrase: findPhrase,
        findWordAt: findWordAt,
        findWordAtOffset: findWordAtOffset
    };
