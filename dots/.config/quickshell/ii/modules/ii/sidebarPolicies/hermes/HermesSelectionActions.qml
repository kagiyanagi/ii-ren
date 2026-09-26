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
 *
 * The Android floating text-selection toolbar: a pill that grows out of the
 * selection's edge on ArrowPopupMotion, from a zero-size pivot (DESIGN.md §9).
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

    readonly property bool selecting: TextSelectionService.active && root.inScope

    /**
     * The selection's bounding box in `anchorItem` coordinates.
     *
     * `positionToRectangle` is per-character, so a selection spanning lines gives
     * a start on one line and an end on another: the box is the union, and the
     * toolbar centres on the start for a single-line selection and on the view for
     * anything taller, which is the only placement that stays over the text.
     */
    readonly property rect liveRect: {
        root.repositionTrigger; // re-evaluate as the transcript scrolls
        root.anchorItem.width;  // ...and as it is resized

        const item = root.selectionSource;
        if (!root.selecting || !item || !item.positionToRectangle)
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

    // Not while the selection is scrolled out of the transcript: the toolbar
    // would hang off an edge over text it does not belong to.
    readonly property bool shown: root.selecting && root.liveRect.y + root.liveRect.height > 0 && root.liveRect.y < root.height

    // Latched while shown. Through the exit the selection is already gone and
    // the live rect is empty, which would drag the pivot into the corner.
    property rect selectionRect
    onLiveRectChanged: {
        if (root.shown)
            root.selectionRect = root.liveRect;
    }
    onShownChanged: {
        if (root.shown)
            motion.open();
        else
            motion.close();
    }

    readonly property real gap: 8
    readonly property real edgeMargin: 4
    // Above the selection by preference -- a toolbar below it covers the line
    // the user is most likely reading next -- and flipped under when the
    // selection starts too near the top to fit.
    readonly property bool below: root.selectionRect.y - toolbar.height - root.gap < 0

    // The container itself holds no input, so everything else in the transcript
    // stays clickable; only the toolbar's buttons take a press.
    anchors.fill: parent

    // At the selection's top centre, or its bottom centre when flipped under.
    Item {
        id: pivot
        x: root.selectionRect.x + root.selectionRect.width / 2
        y: root.below ? root.selectionRect.y + root.selectionRect.height : root.selectionRect.y
        opacity: 0
        scale: Appearance.animationCurves.arrowPopupScale
        visible: opacity > 0

        ArrowPopupMotion {
            id: motion
            target: pivot
        }

        StyledRectangularShadow {
            target: toolbar
        }

        Rectangle {
            id: toolbar

            // Centred on the selection, then clamped inside the transcript.
            x: Math.max(root.edgeMargin - pivot.x, Math.min(-width / 2, root.width - root.edgeMargin - width - pivot.x))
            y: root.below ? root.gap : -height - root.gap

            implicitWidth: buttons.implicitWidth + 8
            implicitHeight: buttons.implicitHeight + 8
            radius: Appearance.rounding.full
            // The raw M3 colour, not `colors.colSurfaceContainerHigh`: that one
            // carries `1 - contentTransparency` as its alpha because it is solved to
            // composite onto a known layer underneath. This floats over message text,
            // so the words it covers would read straight through it.
            readonly property color base: Appearance.m3colors.m3surfaceContainerHigh
            color: Qt.rgba(base.r, base.g, base.b, 1)

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
}
