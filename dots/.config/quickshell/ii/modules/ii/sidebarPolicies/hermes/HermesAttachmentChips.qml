pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The chips behind the attachment tokens in the Hermes composer, and what makes
 * each token one character to the editor: a deletion that touches any part of one
 * takes all of it, and unstages what it carried.
 *
 * HermesService._addMarker builds the tokens. This draws a pill behind each and an
 * image thumbnail or file icon over its leading figure spaces, the way InlineCode
 * draws behind code spans. A `z: -1` child of the field, not its `background`, for
 * the reason given there.
 */
Item {
    id: root

    required property TextEdit target
    property var rects: []
    property string previous: ""

    anchors.fill: parent
    z: -1

    function tokenRanges(text: string): var {
        const out = [];
        for (const token of Object.keys(HermesService.composerMarkers)) {
            const at = text.indexOf(token);
            if (at >= 0)
                out.push({ token: token, start: at, end: at + token.length });
        }
        return out;
    }

    /** A change the composer makes itself, which is whole and needs no mending. */
    function setText(text: string, cursor: int): void {
        root.previous = text;
        root.target.text = text;
        root.target.cursorPosition = cursor;
    }

    function onEdit(): void {
        const prev = root.previous;
        const cur = root.target.text;
        root.previous = cur;
        if (prev === cur) {
            root.layoutRects();
            return;
        }
        // Where the edit was. Every token opens with the same characters, so a
        // prefix/suffix diff alone can put a deletion in the neighbouring token;
        // the caret, which sits where the edit ended, says which one it was.
        const grow = cur.length - prev.length;
        const at = root.target.cursorPosition;
        let head = -1;
        if (grow < 0 && prev.slice(0, at) + prev.slice(at - grow) === cur)
            head = at;
        else if (grow > 0 && at - grow >= 0 && cur.slice(0, at - grow) + cur.slice(at) === prev)
            head = at - grow;
        let tail = cur.length - at;
        if (head < 0) {
            head = 0;
            while (head < prev.length && head < cur.length && prev[head] === cur[head])
                head++;
            tail = 0;
            while (tail < prev.length - head && tail < cur.length - head && prev[prev.length - 1 - tail] === cur[cur.length - 1 - tail])
                tail++;
        }
        let from = head;
        let to = prev.length - tail;
        // A pure insert inside a token moves out past it
        if (from === to) {
            const inside = root.tokenRanges(prev).find(range => range.start < from && range.end > from);
            if (inside) {
                const typed = cur.slice(head, cur.length - tail);
                const fixed = prev.slice(0, inside.end) + typed + prev.slice(inside.end);
                root.previous = fixed;
                root.target.text = fixed;
                root.target.cursorPosition = inside.end + typed.length;
            }
        } else {
            const hit = root.tokenRanges(prev).filter(range => range.start < to && range.end > from);
            if (hit.length > 0) {
                hit.forEach(range => {
                    from = Math.min(from, range.start);
                    to = Math.max(to, range.end);
                });
                const typed = cur.slice(head, cur.length - tail);
                const fixed = prev.slice(0, from) + typed + prev.slice(to);
                if (fixed !== cur) {
                    root.previous = fixed;
                    root.target.text = fixed;
                    root.target.cursorPosition = from + typed.length;
                }
                // Later, so a send clearing the field has already taken the tokens
                // it expanded and this finds nothing of theirs left to unstage.
                Qt.callLater(() => hit.forEach(range => {
                    if (!root.target.text.includes(range.token))
                        HermesService.dropMarker(range.token);
                }));
            }
        }
        root.layoutRects();
    }

    function layoutRects(): void {
        const view = root.target;
        root.rects = root.tokenRanges(view.text).map(range => {
            const first = view.positionToRectangle(range.start);
            const after = view.positionToRectangle(range.end);
            const right = Math.abs(after.y - first.y) < 1 ? after.x : view.width - view.rightPadding;
            return {
                token: range.token,
                x: first.x,
                y: first.y,
                width: right - first.x,
                height: first.height
            };
        });
    }

    Connections {
        target: root.target
        function onTextChanged(): void {
            root.onEdit();
        }
        function onWidthChanged(): void {
            root.layoutRects();
        }
    }

    Connections {
        target: HermesService
        function onComposerMarkersChanged(): void {
            root.layoutRects();
        }
    }

    Repeater {
        model: root.rects

        delegate: Rectangle {
            id: chip
            required property var modelData
            readonly property var marker: HermesService.composerMarkers[modelData.token] ?? null

            x: modelData.x
            y: modelData.y
            width: modelData.width
            height: modelData.height
            // The pill InlineCode draws behind the same chip in a sent bubble
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colLayer4Base
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            // Square, not clipped round: a clip is a layer, and this is a delegate
            StyledImage {
                id: thumb
                x: 5
                anchors.verticalCenter: parent.verticalCenter
                width: chip.height - 6
                height: chip.height - 6
                visible: chip.marker?.kind === "image"
                source: visible ? Qt.resolvedUrl(chip.marker.thumb) : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: width
                sourceSize.height: height
            }

            MaterialSymbol {
                x: 5
                anchors.verticalCenter: parent.verticalCenter
                visible: !thumb.visible
                text: chip.marker?.icon ?? "draft"
                iconSize: chip.height - 6
                color: Appearance.colors.colPrimary
            }
        }
    }
}
