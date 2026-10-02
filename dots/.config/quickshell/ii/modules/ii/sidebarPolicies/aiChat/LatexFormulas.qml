pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import Quickshell

/**
 * The LaTeX formulas of one text view, each in a scroller of its own.
 *
 * Qt's rich text draws an image where it falls and cannot clip or scroll one, so a
 * formula wider than its line (a list item's indent alone takes 40px) ran off the
 * card. MessageTextBlock puts a blank of the formula's size in the text, with the
 * formula's path as its alt, and this draws the formula over that space: as it is
 * when it fits, and scrolling sideways, alone, when it does not.
 *
 * A bare Flickable for the reason MessageCodeBlock gives: locked to one axis, it
 * lets a vertical wheel through to the transcript.
 */
Item {
    id: root

    required property TextEdit target
    /** The markup the view was given, to tell which of its images are formulas. */
    required property string markup
    property var boxes: []

    anchors.fill: parent

    /** Every image is a U+FFFC in the view's text, in the order of the markup's tags. */
    function layout(): void {
        const view = root.target;
        const text = view.getText(0, view.length);
        const out = [];
        const tags = /<img\b[^>]*>|!\[/g; // No matchAll in QML's engine
        let at = -1;
        for (let match; (match = tags.exec(root.markup)) !== null;) {
            const tag = match[0];
            at = text.indexOf("\ufffc", at + 1);
            if (at === -1)
                break;
            if (!tag.includes(LatexRenderer.placeholder))
                continue;
            const rect = view.positionToRectangle(at);
            out.push({ key: out.length, source: /\balt="([^"]*)"/.exec(tag)[1], x: rect.x, y: rect.y });
        }
        root.boxes = out;
    }

    FontMetrics {
        id: metrics
        font: root.target.font
    }

    // Once per event loop, not per textChanged: InlineCode strips its brackets one
    // remove() at a time, each its own textChanged, and every pass here forces the
    // whole document's layout. A reply with 234 formulas froze the shell for 10s.
    Component.onCompleted: Qt.callLater(root.layout)

    Connections {
        target: root.target
        function onTextChanged(): void {
            Qt.callLater(root.layout);
        }
        function onWidthChanged(): void {
            Qt.callLater(root.layout);
        }
    }

    Repeater {
        // Keyed by position, so a fresh `boxes` moves the scrollers already built
        // and adds the one new formula, instead of rebuilding every one of them
        // each time a streamed formula lands.
        model: ScriptModel {
            objectProp: "key"
            values: root.boxes
        }

        delegate: Flickable {
            id: scroller
            required property var modelData

            x: modelData.x
            // The caret's rect is the line's. Qt centres the image on the x-height, so
            // one shorter than the text's ascent starts below the line's top.
            y: modelData.y + Math.max(0, metrics.ascent - (formula.implicitHeight + metrics.xHeight) / 2)
            width: Math.min(formula.implicitWidth, root.target.width - root.target.rightPadding - x)
            height: formula.implicitHeight
            contentWidth: formula.implicitWidth
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            // One that fits leaves a drag to the text's selection
            interactive: contentWidth > width
            clip: interactive

            // Sits in the render's bottom padding
            ScrollBar.horizontal: StyledScrollBar {}

            Image {
                id: formula
                // Off the GUI thread: the text already holds the formula's space, and
                // a turn rebuilt as it scrolls back in decoded every one of its SVGs
                // on the frame it came back, 234 of them in one reply.
                asynchronous: true
                source: scroller.modelData.source
            }
        }
    }
}
