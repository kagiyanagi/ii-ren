// Where a read-aloud is, across all of its parts.
//
// A reply is read as parts -- sentences -- each made into a clip of its own
// when it is asked for (AgentService). The bar under the transcript is the
// whole reply, though, so the parts are laid end to end: a part already made
// is as long as its clip, one not made yet is estimated from its length in
// characters at the rate the made ones were said. The estimates give way to the
// real lengths as the clips come.
//
// A clip is {duration, marks}: `marks` as tts.py returns them, [[ms, character
// offset into the part], ...], one per word said, in order.

/** Milliseconds per character of the parts made so far, or 0 before any is. */
function msPerChar(parts, clips) {
    let ms = 0;
    let chars = 0;
    for (let i = 0; i < parts.length; i++) {
        const clip = clips[i];
        if (clip && clip.duration > 0) {
            ms += clip.duration;
            chars += parts[i].length;
        }
    }
    return chars > 0 ? ms / chars : 0;
}

/** Each part's length in ms: its clip's, an estimate, or 0 for one that failed. */
function durations(parts, clips) {
    const rate = msPerChar(parts, clips);
    return parts.map((part, i) => {
        const clip = clips[i];
        if (clip === "failed")
            return 0;
        return clip && clip.duration > 0 ? clip.duration : Math.round(part.length * rate);
    });
}

function total(durs) {
    return durs.reduce((sum, d) => sum + d, 0);
}

/** Where part `index` starts, in ms from the start of the reading. */
function startOf(durs, index) {
    let at = 0;
    for (let i = 0; i < index && i < durs.length; i++)
        at += durs[i];
    return at;
}

/**
 * The part a time falls in and how far into it: {index, offset}. A time on a
 * boundary is the start of the later part; past the end is the end of the last.
 */
function locate(durs, ms) {
    let at = Math.max(0, ms);
    for (let i = 0; i < durs.length; i++) {
        if (at < durs[i] || i === durs.length - 1)
            return { index: i, offset: Math.min(at, durs[i]) };
        at -= durs[i];
    }
    return { index: 0, offset: 0 };
}

/** The word said at `offset` ms into a clip: its mark, or the first. */
function markAt(marks, offset) {
    let found = marks[0];
    for (let i = 0; i < marks.length && marks[i][0] <= offset; i++)
        found = marks[i];
    return found;
}

/**
 * The character the word at `offset` ms into a part starts on: off the clip's
 * marks when it has them, otherwise the same share of the part's characters.
 */
function charAt(part, clip, offset, duration) {
    const marks = clip && clip.marks ? clip.marks : [];
    if (marks.length > 0)
        return markAt(marks, offset)[1];
    const share = duration > 0 ? Math.max(0, Math.min(1, offset / duration)) : 0;
    return Math.min(part.length - 1, Math.floor(share * part.length));
}

/**
 * Where to start playing a clip so the word holding character `char` is the
 * first one heard: the mark of the last word starting at or before it, at the
 * start of the clip without marks or before the first.
 */
function startForChar(clip, char) {
    const marks = clip && clip.marks ? clip.marks : [];
    let start = 0;
    for (let i = 0; i < marks.length && marks[i][1] <= char; i++)
        start = marks[i][0];
    return start;
}

/** Where to start playing a clip to land on the start of the word at `offset`. */
function wordStart(clip, offset) {
    const marks = clip && clip.marks ? clip.marks : [];
    if (marks.length === 0 || offset < marks[0][0])
        return 0;
    return markAt(marks, offset)[0];
}

if (typeof module !== "undefined")
    module.exports = { msPerChar, durations, total, startOf, locate, markAt, charAt, startForChar, wordStart };
