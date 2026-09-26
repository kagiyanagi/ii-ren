pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick

/**
 * The pill behind each inline `code` span of one text view: a rounded, bordered
 * container with room on both sides of the text, which Qt's rich text cannot put on
 * a span (it has a background colour and nothing else).
 *
 * MessageTextBlock.styleCodeSpans brackets every span with U+2063 and spaces its
 * edges with letter-spacing. This reads the brackets to learn where each span is,
 * removes them from the document, so copying, selection, search marks and
 * read-aloud never see them, and draws behind those ranges, one pill per line a
 * span wraps across.
 *
 * A `z: -1` child of the view, so it paints under the glyphs and the selection.
 * Not the view's `background`: that is built while the view itself is, and the
 * Connections below, pointed at a half-built view, segfaulted the shell on reload.
 */
Item {
    id: root

    required property TextEdit target
    property color fill: Appearance.colors.colLayer4Base
    property color border: Appearance.colors.colOutlineVariant
    /** Room between the text and the pill's edge, each side. */
    property real pad: 4
    /** The letter-spacing styleCodeSpans put after each span's last character. */
    readonly property real gap: root.pad * 2

    property var ranges: []
    property var rects: []
    property bool stripping: false
    /** The text as it was left after the last strip, to know that change as ours. */
    property string stripped: ""

    anchors.fill: parent
    // Under the glyphs, and under the view's own selection, which is drawn with them.
    z: -1

    function strip(): void {
        if (root.stripping)
            return;
        const view = root.target;
        const text = view.getText(0, view.length);
        // The removals below report their textChanged after the guard is released,
        // with the brackets already gone. Taken as new text, that cleared every pill
        // on the frame it was made.
        if (text === root.stripped)
            return;
        const marks = [];
        for (let at = text.indexOf("\u2063"); at !== -1; at = text.indexOf("\u2063", at + 1))
            marks.push(at);
        // Removing from the end keeps the earlier offsets valid, and the guard keeps
        // each removal's own textChanged from re-entering here halfway through.
        root.stripping = true;
        for (let i = marks.length - 1; i >= 0; i--)
            view.remove(marks[i], marks[i] + 1);
        root.stripping = false;
        root.stripped = view.getText(0, view.length);
        const ranges = [];
        for (let k = 0; k + 1 < marks.length; k += 2)
            ranges.push([marks[k] - k, marks[k + 1] - k - 1]);
        root.ranges = ranges;
        root.layoutRects();
    }

    /**
     * One rectangle per visual line of each span. The line's last character is found
     * by bisecting on the y `positionToRectangle` reports, as SpeechHighlight does.
     */
    function layoutRects(): void {
        const view = root.target;
        const out = [];
        for (const [start, end] of root.ranges) {
            let pos = start;
            while (pos < end && out.length < 64) {
                const first = view.positionToRectangle(pos);
                let lo = pos;
                let hi = end - 1;
                while (lo < hi) {
                    const mid = Math.ceil((lo + hi) / 2);
                    if (Math.abs(view.positionToRectangle(mid).y - first.y) < 1)
                        lo = mid;
                    else
                        hi = mid - 1;
                }
                const after = view.positionToRectangle(end);
                // The span's own end carries `gap` of letter-spacing, so the glyph ends
                // that far before the caret after it. A line the span wraps off ends
                // where its last character's advance does.
                const right = lo === end - 1 && Math.abs(after.y - first.y) < 1
                    ? after.x - root.gap + root.pad
                    : view.positionToRectangle(lo).x + metrics.advanceWidth(view.getText(lo, lo + 1)) + root.pad;
                // A pixel off each line's top and bottom, so a span wrapping across two
                // lines is two pills and not one shape.
                out.push(Qt.rect(first.x - root.pad, first.y + 1, right - first.x + root.pad, first.height - 2));
                pos = lo + 1;
            }
        }
        root.rects = out;
    }

    FontMetrics {
        id: metrics
        font.family: Appearance.font.family.monospace
        font.pixelSize: root.target.font.pixelSize
    }

    Component.onCompleted: root.strip()

    Connections {
        target: root.target
        function onTextChanged(): void {
            root.strip();
        }
        function onWidthChanged(): void {
            root.layoutRects();
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
            color: root.fill
            border.width: 1
            border.color: root.border
        }
    }
}
