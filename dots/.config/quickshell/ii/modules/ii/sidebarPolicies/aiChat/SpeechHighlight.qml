pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import "../../../../services/speechMatch.js" as SpeechMatch

/**
 * Marks the word a read-aloud is speaking, inside one text view.
 *
 * Drawn as rectangles behind the glyphs rather than by moving the view's
 * selection: the selection belongs to the user, and taking it would both wipe
 * what they highlighted and hand the selection toolbar text nobody picked.
 *
 * A reply is rendered as many views -- one per paragraph, plus one per code
 * block -- and each carries one of these. The one whose text holds the passage
 * marks the word inside it; the rest find nothing and draw nothing.
 */
Item {
    id: root

    /** The view whose text is searched and covered; a TextArea is one of these. */
    required property TextEdit target
    /** The passage being spoken, as it appears in the message source. */
    property string phrase: ""
    /**
     * How far into that passage the voice is, 0..1: the word there is the one
     * marked. At -1 -- a caller with no position to give -- the whole passage is
     * marked instead.
     */
    property real progress: -1
    /**
     * Where the word being spoken starts in the passage, when the voice reported
     * its own word timings. Exact, and preferred over `progress`.
     */
    property int wordOffset: -1

    /**
     * Mark every case-insensitive occurrence of this instead of looking `phrase`
     * up, for transcript search. A reply is rendered as many views and the query
     * can appear several times in one of them, so this finds all of them where
     * the speech path wants exactly one.
     */
    property string query: ""

    /** Marking colour, so a search hit does not look like a read-aloud mark. */
    property color markColor: ColorUtils.applyAlpha(Appearance.colors.colTertiaryContainer, 0.45)

    /**
     * The mark is painted OVER the glyphs, so its alpha is not a style choice --
     * an opaque one hides the very word it is pointing at. Capped here rather
     * than trusted to every caller: reaching for a container colour hands you a
     * full-strength one, and full strength on this side of the text means the
     * text is gone.
     */
    readonly property color effectiveMark: ColorUtils.applyAlpha(root.markColor, Math.min(root.markColor.a, 0.55))

    property var rects: []

    anchors.fill: parent
    // Over the text, not behind it: a selection being read out has the view's own
    // selection colour painted across the same words, and anything behind that is
    // not seen. Translucent, so it reads as a highlighter over the glyphs.
    z: 1

    function update(): void {
        const view = root.target;
        if (!view || view.length === 0) {
            root.rects = [];
            return;
        }
        if (root.query.length > 0) {
            root.rects = root.queryRects(view.getText(0, view.length));
            return;
        }
        if (root.phrase.trim().length === 0) {
            root.rects = [];
            return;
        }
        const text = view.getText(0, view.length);
        const found = root.wordOffset >= 0 ? SpeechMatch.findWordAtOffset(text, root.phrase, root.wordOffset)
            : root.progress >= 0 ? SpeechMatch.findWordAt(text, root.phrase, root.progress)
            : SpeechMatch.findPhrase(text, root.phrase);
        root.rects = found ? root.lineRects(found.start, found.end) : [];
    }

    /** Every occurrence of `query` in `text`, as line rectangles. */
    function queryRects(text: string): var {
        const hay = text.toLowerCase();
        const needle = root.query.toLowerCase();
        const out = [];
        // Bounded: a one-character query against a long reply would otherwise ask
        // for a rectangle per character, inside a delegate.
        for (let at = hay.indexOf(needle); at !== -1 && out.length < 40; at = hay.indexOf(needle, at + needle.length))
            out.push(...root.lineRects(at, at + needle.length));
        return out;
    }

    /**
     * One rectangle per visual line.
     *
     * `positionToRectangle` is per character, and where the text wraps is not
     * knowable from the string, so each line's end is found by bisecting on the
     * y it reports -- a handful of calls per line instead of one per character.
     */
    function lineRects(start: int, end: int): var {
        const view = root.target;
        const out = [];
        let pos = start;
        while (pos < end && out.length < 64) {
            const first = view.positionToRectangle(pos);
            let lo = pos;
            let hi = end;
            while (lo < hi) {
                const mid = Math.ceil((lo + hi) / 2);
                if (Math.abs(view.positionToRectangle(mid).y - first.y) < 1)
                    lo = mid;
                else
                    hi = mid - 1;
            }
            const last = view.positionToRectangle(lo);
            out.push(Qt.rect(first.x, first.y, Math.max(1, last.x - first.x), first.height));
            pos = lo + 1;
        }
        return out;
    }

    onPhraseChanged: root.update()
    onQueryChanged: root.update()
    // Word timings supersede the estimate: with them the mark moves per word, not
    // per position report, which is twenty times a second in every message shown.
    onProgressChanged: if (root.wordOffset < 0) root.update()
    onWordOffsetChanged: root.update()
    Component.onCompleted: root.update()

    Connections {
        target: root.target
        // Text arrives token by token while a reply streams, and a resize rewraps
        // every line under the mark.
        function onTextChanged(): void {
            root.update();
        }
        function onWidthChanged(): void {
            root.update();
        }
    }

    Repeater {
        model: root.rects

        delegate: Rectangle {
            required property rect modelData

            x: modelData.x
            y: modelData.y
            width: modelData.width
            height: modelData.height
            radius: Appearance.rounding.verysmall
            color: root.effectiveMark
        }
    }
}
