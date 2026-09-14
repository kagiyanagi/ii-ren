// Finding a spoken passage inside rendered markdown.
//
// Read-aloud speaks the message *source*, while the transcript shows Qt's
// rendered markdown: `**bold**` is four characters shorter on screen and a link
// is only its label. So a source offset means nothing to the text view, and the
// passage is located by matching both sides with the syntax the renderer drops
// taken out, then reading the surviving positions back off a map.

const DROPPED = "*_`~#[]()\\";

/**
 * Strip markdown syntax and collapse whitespace, keeping `map[i]` -- where the
 * i-th surviving character came from in `s`.
 */
function normalize(s) {
    const chars = [];
    const map = [];
    let prevSpace = true;
    for (let i = 0; i < s.length; i++) {
        const c = s[i];
        if (c === " " || c === "\t" || c === "\n" || c === "\r") {
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
 * Where `phrase` sits in the normalized haystack, or null. Normalized positions,
 * for the callers below to map back or to walk word by word.
 *
 * An exact match is the normal case -- link targets are dropped on both sides,
 * so a link inside the sentence is no obstacle. When the phrase still carries
 * something the renderer ate whole (a LaTeX image, say) the ends match even
 * though the middle does not, so the head anchors the start and the tail the
 * end; failing that the phrase's own length stands in, which is only ever off
 * by what was eaten.
 */
function locate(hay, phrase) {
    const needle = normalize(phrase || "").text;
    if (needle.length === 0 || hay.text.length === 0)
        return null;

    let at = hay.text.indexOf(needle);
    let end;
    if (at >= 0) {
        end = at + needle.length;
    } else {
        const head = needle.slice(0, ANCHOR);
        at = hay.text.indexOf(head);
        if (at < 0)
            return null;
        const tail = needle.slice(-ANCHOR);
        const tailAt = hay.text.indexOf(tail, at + head.length);
        end = tailAt >= 0 ? tailAt + tail.length : Math.min(hay.text.length, at + needle.length);
    }
    return { at: at, end: end };
}

/** Where `phrase` sits in `rendered`, as positions into `rendered`, or null. */
function findPhrase(rendered, phrase) {
    const hay = normalize(rendered || "");
    const hit = locate(hay, phrase);
    return hit ? { start: hay.map[hit.at], end: hay.map[hit.end - 1] + 1 } : null;
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
    // normalized form and carried across from where the phrase was found.
    const spoken = normalize(phrase || "");
    let ahead = 0;
    while (ahead < spoken.map.length && spoken.map[ahead] < offset)
        ahead++;
    const at = Math.max(hit.at, Math.min(hit.at + ahead, hay.text.length - 1));
    return wordAround(hay, at);
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
    const said = Math.max(0, Math.min(0.999, progress)) * (hit.end - hit.at);
    const words = /\S+/g;
    const slice = hay.text.slice(hit.at, hit.end);
    let match;
    let last = null;
    while ((match = words.exec(slice)) !== null) {
        const from = hit.at + match.index;
        const to = from + match[0].length;
        last = { start: hay.map[from], end: hay.map[to - 1] + 1 };
        if (said < match.index + match[0].length)
            return last;
    }
    return last;
}

if (typeof module !== "undefined")
    module.exports = {
        normalize: normalize,
        findPhrase: findPhrase,
        findWordAt: findWordAt,
        findWordAtOffset: findWordAtOffset
    };
