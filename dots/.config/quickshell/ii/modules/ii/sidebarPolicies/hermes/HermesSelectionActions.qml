pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarPolicies.aiChat
import QtQuick
import QtQuick.Controls
import Quickshell

/**
 * The actions offered over a highlighted passage in the transcript.
 *
 * Floats above the selection rather than living in the message header, because
 * the header's buttons act on a whole turn: reading out a four-paragraph answer
 * to hear one sentence, or copying all of it to quote a line, is the thing this
 * exists to avoid.
 *
 * Positioned in `anchorItem`'s coordinates from the selection rectangle the
 * source view reports, and re-evaluated whenever `repositionTrigger` changes --
 * scrolling moves a selection without changing it, so a binding on the selection
 * alone would leave the toolbar behind.
 */
Item {
    id: root

    /** Coordinate space the toolbar is placed in; the selection is mapped into it. */
    required property Item anchorItem
    /**
     * Only selections made inside this subtree get a toolbar. The sidebar hosts
     * more than one transcript and they must not answer for each other's text.
     */
    required property Item scopeItem

    /** Bumped by the host on scroll, so the toolbar tracks the text it belongs to. */
    property real repositionTrigger: 0

    signal quoteRequested(string text)

    readonly property string selectedText: TextSelectionService.text
    readonly property Item selectionSource: TextSelectionService.source

    readonly property bool inScope: {
        let item = root.selectionSource;
        while (item) {
            if (item === root.scopeItem)
                return true;
            item = item.parent;
        }
        return false;
    }

    readonly property bool shown: TextSelectionService.active && root.inScope

    /**
     * The selection's bounding box in `anchorItem` coordinates.
     *
     * `positionToRectangle` is per-character, so a selection spanning lines gives
     * a start on one line and an end on another: the box is the union, and the
     * toolbar centres on the start for a single-line selection and on the view for
     * anything taller, which is the only placement that stays over the text.
     */
    readonly property rect selectionRect: {
        root.repositionTrigger; // re-evaluate as the transcript scrolls
        root.anchorItem.width;  // ...and as it is resized

        const item = root.selectionSource;
        if (!root.shown || !item || !item.positionToRectangle)
            return Qt.rect(0, 0, 0, 0);

        const start = item.positionToRectangle(item.selectionStart);
        const end = item.positionToRectangle(item.selectionEnd);
        const topLeft = item.mapToItem(root.anchorItem, start.x, start.y);
        const bottomRight = item.mapToItem(root.anchorItem, end.x, end.y + end.height);
        const sameLine = Math.abs(start.y - end.y) < 1;
        const left = sameLine ? topLeft.x : item.mapToItem(root.anchorItem, 0, 0).x;
        const right = sameLine ? bottomRight.x : left + item.width;
        return Qt.rect(left, topLeft.y, Math.max(0, right - left), Math.max(0, bottomRight.y - topLeft.y));
    }

    anchors.fill: parent
    // The toolbar is the only thing here; everything else in the transcript has to
    // stay clickable, so the container itself must not swallow input.
    visible: root.shown

    Rectangle {
        id: toolbar

        readonly property real gap: 6
        readonly property real edgeMargin: 4
        // Above the selection by preference -- a toolbar below it covers the line
        // the user is most likely reading next -- and flipped under when the
        // selection starts too near the top to fit.
        readonly property bool below: root.selectionRect.y - height - gap < 0

        x: Math.max(edgeMargin, Math.min(root.width - width - edgeMargin,
            root.selectionRect.x + root.selectionRect.width / 2 - width / 2))
        y: below ? root.selectionRect.y + root.selectionRect.height + gap
                 : root.selectionRect.y - height - gap

        implicitWidth: buttons.implicitWidth + 8
        implicitHeight: buttons.implicitHeight + 8
        radius: Appearance.rounding.small
        // The raw M3 colour, not `colors.colSurfaceContainerHighest`: that one
        // carries `1 - contentTransparency` as its alpha because it is solved to
        // composite onto a known layer underneath. This floats over message text,
        // so the words it covers would read straight through it.
        color: Appearance.m3colors.m3surfaceContainerHighest

        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        StyledRectangularShadow {
            target: toolbar
            z: -1
        }

        ButtonGroup {
            id: buttons
            anchors.centerIn: parent
            spacing: 4

            AiMessageControlButton {
                id: speakSelectionButton

                readonly property bool speakingThis: HermesService.speakingMessageId === HermesService.selectionSpeechId

                // Focus would move off the text view, and a view that is not focused
                // stops drawing its highlight -- the selection these buttons act on
                // would vanish the moment one was pressed.
                focusPolicy: Qt.NoFocus
                activated: speakSelectionButton.speakingThis
                buttonIcon: speakSelectionButton.speakingThis ? "stop" : "graphic_eq"

                onClicked: {
                    if (speakSelectionButton.speakingThis)
                        HermesService.stopSpeaking();
                    else
                        HermesService.speakText(root.selectedText);
                }

                StyledToolTip {
                    text: speakSelectionButton.speakingThis ? Translation.tr("Stop reading") : Translation.tr("Read selection out loud")
                }
            }

            AiMessageControlButton {
                id: copySelectionButton

                focusPolicy: Qt.NoFocus
                buttonIcon: activated ? "inventory" : "content_copy"

                onClicked: {
                    Quickshell.clipboardText = root.selectedText;
                    copySelectionButton.activated = true;
                    copyIconTimer.restart();
                }

                Timer {
                    id: copyIconTimer
                    interval: 1500
                    onTriggered: copySelectionButton.activated = false
                }

                StyledToolTip {
                    text: Translation.tr("Copy selection")
                }
            }

            AiMessageControlButton {
                id: quoteSelectionButton

                focusPolicy: Qt.NoFocus
                buttonIcon: "format_quote"

                // The quote goes to the composer, not to the agent: it is the
                // opening of a reply the user still has to write.
                onClicked: {
                    root.quoteRequested(root.selectedText);
                    TextSelectionService.dismiss();
                }

                StyledToolTip {
                    text: Translation.tr("Quote and reply")
                }
            }
        }
    }
}
