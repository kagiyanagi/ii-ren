pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

/**
 * Android 16's clipboard overlay: copy some text and a card slides into the
 * bottom-left corner with a preview of it and the couple of things worth doing
 * with it. Clicking the preview opens the clipboard history, and it auto-hides
 * on a timeout the way SystemUI's ClipboardOverlayController does.
 */
Scope {
    id: root

    // Latched on copy rather than read live off the clipboard: the card has to
    // keep showing what it showed while it animates out.
    property string copiedText: ""
    property bool shown: false

    readonly property string corner: Config.options.clipboard.copyToast.corner
    readonly property bool atTop: root.corner.startsWith("top")
    readonly property bool atRight: root.corner.endsWith("right")

    // The newest cliphist id the card has already shown. Deleting or wiping
    // entries refreshes the list too, and that is not a copy.
    property int lastEntryId: -1

    // Android's clipboard preview sets the type to the content: a couple of words
    // come up large so they are readable across the room, a sentence shrinks, and
    // only at the floor does it wrap and ellipsise. Qt's fontSizeMode cannot do
    // this - Text.Fit with wrapping maximises to fill the height and lets the width
    // wrap mid-word, which is how "overlay" ended up as "overla/y".
    // ponytail: character metrics for this family (~0.55 and ~1.33 of the pixel
    // size per advance and per line) rather than a pixel-exact search. Measure with
    // a hidden Text and bisect if it ever misjudges a string.
    readonly property real previewBox: 64 // the tile's text box, square
    readonly property int previewFontSize: {
        if (root.copiedText === "")
            return Appearance.font.pixelSize.smallest;
        const longestWord = Math.max(...root.copiedText.split(/\s+/).map(word => word.length));
        // Big enough that the longest word still fits one line...
        const byWord = root.previewBox / (0.55 * longestWord);
        // ...and that the whole string still fits the box, wrapping at spaces
        // costing about a quarter of the area.
        const byArea = Math.sqrt(root.previewBox * root.previewBox * 0.75 / (0.55 * 1.33 * root.copiedText.length));
        return Math.max(Appearance.font.pixelSize.smallest, Math.min(Appearance.font.pixelSize.huge, Math.floor(Math.min(byWord, byArea))));
    }

    // The one extra action worth offering for a link, and the only one that needs
    // no other service running.
    readonly property bool urlLike: /^(https?:\/\/|www\.)\S+$/i.test(root.copiedText)

    // The reference's action buttons: solid filled circles, distinctly darker than
    // the preview tile they sit beside, with the icon in the on-colour. 48 is the
    // M3 icon button size and matches the ~46 measured off the screenshot.
    component CircleButton: RippleButton {
        id: circleButton

        required property string materialIcon

        implicitWidth: 48
        implicitHeight: 48
        padding: 0
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive

        // The Control lays the contentItem out across the whole button, and a Text
        // draws at the top left of whatever rect it is given - so the alignments,
        // not anchors, are what centre the glyph. Anchoring here fights the Control
        // and is what left the icons sitting high and left.
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: circleButton.materialIcon
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnPrimary
        }
    }

    // Qt only hears about clipboard changes while a window has focus, and a layer
    // surface never does - Quickshell.clipboardTextChanged never fires here. The
    // `wl-paste --watch` in execs.lua already tells Cliphist about every copy, so
    // ride that rather than starting a second watcher.
    Connections {
        target: Cliphist

        function onEntriesChanged(): void {
            const entry = Cliphist.entries[0] ?? "";
            const id = parseInt(entry);
            if (!isFinite(id))
                return;
            const firstRefresh = root.lastEntryId < 0;
            if (id === root.lastEntryId)
                return;
            root.lastEntryId = id;
            // The list the shell starts up with is history, not something the user
            // just did.
            if (firstRefresh)
                return;
            // Android previews a copied image as a thumbnail; here that is the
            // clipboard history's job.
            if (Cliphist.entryIsImage(entry))
                return;
            // cliphist's own preview: the id, a tab, then the first ~100 chars with
            // the newlines flattened out. Exactly what fits on a card - and the
            // actions below read the real clipboard rather than this.
            const text = entry.replace(/^\s*\S+\s+/, "").trim();
            if (text === "")
                return;
            root.copiedText = text;
            root.shown = true;
            if (hideTimer.interval > 0)
                hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: Config.options.clipboard.copyToast.dismissAfter * 1000
        onTriggered: root.shown = false
    }

    PanelWindow {
        id: toastWindow

        // Same outer spacing as the sidebars, notifications and bar popups.
        readonly property real gutter: Appearance.sizes.hyprlandGapsOut

        // Stays mapped until the card has finished fading out. Whatever is on the
        // clipboard when the screen locks is nobody's business.
        visible: (root.shown || card.opacity > 0) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        color: "transparent"

        WlrLayershell.namespace: "quickshell:clipboardToast"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Reserve nothing, but do respect what the bar and a pinned dock reserve -
        // that is what keeps the card clear of both without special casing either.
        exclusiveZone: 0

        // Full height on purpose, like NotificationPopup and the pairing card: the
        // card has to slide clear of a sidebar and of a notification stack, and
        // changing a committed layer surface's margins does not reconfigure it - so
        // the window stays put, is made big enough to cover every position the card
        // can take, and the card moves inside it. The mask keeps the slack
        // click-through.
        anchors {
            left: !root.atRight
            right: root.atRight
            top: true
            bottom: true
        }

        // Slide inwards so a sidebar on this side can have the corner, and drift
        // back out once it closes.
        readonly property real sidebarInset: (root.atRight ? GlobalStates.effectiveRightOpen : GlobalStates.effectiveLeftOpen) ? Appearance.sizes.sidebarWidth : 0

        // Notifications own the top right corner, so drop below them there rather
        // than overlapping. Clamped so a tall stack cannot push the card off screen.
        readonly property real notificationInset: {
            if (!root.atTop || !root.atRight || GlobalStates.notificationPopupHeight <= 0)
                return 0;
            const room = toastWindow.height - card.height - toastWindow.gutter * 2;
            return Math.max(0, Math.min(GlobalStates.notificationPopupHeight, room));
        }

        // Gutter to the screen edge, elevationMargin of slack on the far side for
        // the shadow, plus the room the card needs to dodge a sidebar.
        implicitWidth: card.width + toastWindow.gutter + Appearance.sizes.elevationMargin + Appearance.sizes.sidebarWidth

        // Only the two surfaces, so the empty corner above the pill stays
        // click-through.
        mask: Region {
            item: previewFrame

            // Null when there is nothing to act on, so the hidden pill's strip does
            // not go on swallowing clicks in an empty corner.
            Region {
                item: pill.visible ? pill : null
            }
        }

        Item {
            id: card

            // A bound property with a change handler, not a Connections: a
            // Connections declared inside a PanelWindow never sees the signal.
            readonly property bool cardShown: root.shown

            // Measured off the reference screenshot, then snapped to the 4dp grid
            // with the buttons at M3's 48dp icon-button size:
            //   a 56 tall action pill, and the preview card overlapping it - taller
            //   than the pill, standing 28 clear of it on the side away from the
            //   screen edge, with the pill's rounded end tucked in behind the card.
            readonly property int gap: 12
            readonly property int circleSize: 48
            readonly property int pillHeight: 56
            readonly property int tileSize: 80 // 72 preview plus its 4 frame
            readonly property int tileLeft: 8
            readonly property int tileBottomInset: 4

            readonly property int buttonCount: (root.urlLike ? 1 : 0) + (KdeConnectService.activeReachable ? 2 : 0)
            readonly property int rowWidth: card.buttonCount === 0 ? 0 : card.buttonCount * card.circleSize + (card.buttonCount - 1) * card.gap

            // x/y rather than anchors: an anchor line is not cleared by assigning
            // undefined to it, so switching corners at runtime left the card
            // anchored to both sides at once and stretched it.
            x: root.atRight ? toastWindow.width - card.width - toastWindow.gutter - toastWindow.sidebarInset : toastWindow.gutter + toastWindow.sidebarInset
            y: root.atTop ? toastWindow.gutter + toastWindow.notificationInset : toastWindow.height - card.height - toastWindow.gutter

            // Glides out of the way when a sidebar opens or a notification lands,
            // rather than jumping. Position, so a spatial spec.
            Behavior on x {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }

            Behavior on y {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }
            // With nothing to act on, the pill goes and the card stands alone.
            implicitWidth: card.tileLeft + card.tileSize + (card.buttonCount === 0 ? 0 : card.gap + card.rowWidth + card.gap)
            implicitHeight: card.tileSize + card.tileBottomInset
            width: implicitWidth
            height: implicitHeight

            opacity: 0
            scale: 0.8
            // It lives in this corner, so it grows out of it.
            transformOrigin: root.atTop ? (root.atRight ? Item.TopRight : Item.TopLeft) : (root.atRight ? Item.BottomRight : Item.BottomLeft)

            onCardShownChanged: {
                if (card.cardShown) {
                    closeAnim.stop();
                    openAnim.restart();
                } else {
                    openAnim.stop();
                    closeAnim.restart();
                }
            }

            // A second copy landing while the card is still up resizes the preview
            // rather than reopening it.
            Behavior on implicitWidth {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            // Enter: decelerating on default spatial, with the fade landing first
            // so the content is legible while the card is still growing.
            ParallelAnimation {
                id: openAnim

                NumberAnimation {
                    target: card
                    property: "scale"
                    to: 1
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
                NumberAnimation {
                    target: card
                    property: "opacity"
                    to: 1
                    duration: Appearance.animation.elementMoveFast.duration
                }
            }

            // Exit: accelerating, on the fast effects spec - the user has already
            // moved on, so it leaves in 130ms against the 500ms it took to arrive.
            ParallelAnimation {
                id: closeAnim

                NumberAnimation {
                    target: card
                    property: "scale"
                    to: 0.8
                    duration: Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                }
                NumberAnimation {
                    target: card
                    property: "opacity"
                    to: 0
                    duration: Appearance.animation.elementMoveExit.duration
                }
            }

            // The action pill, behind the preview card. Its left end runs on under
            // the card, which is where the reference's sliver of rounded edge
            // beside the tile comes from.
            StyledRectangularShadow {
                target: pill
            }

            Rectangle {
                id: pill
                visible: card.buttonCount > 0
                x: 0
                y: root.atTop ? 0 : card.height - card.pillHeight
                width: card.width
                height: card.pillHeight
                radius: Appearance.rounding.full
                // colLayer0 is the opaque one: colLayer1..4 come out of
                // solveOverlayColor carrying the content transparency as alpha, so
                // they only work over another shell surface, not over a window.
                color: Appearance.colors.colLayer0
            }

            RowLayout {
                id: buttonRow
                visible: pill.visible
                x: root.atRight ? card.gap : card.width - card.gap - buttonRow.width
                y: pill.y + (card.pillHeight - buttonRow.height) / 2
                // Keeps the icon order running inward from the screen edge.
                layoutDirection: root.atRight ? Qt.RightToLeft : Qt.LeftToRight
                spacing: card.gap

                CircleButton {
                    materialIcon: "open_in_new"
                    visible: root.urlLike
                    onClicked: {
                        // The clipboard, not the preview: a long link is cut off at
                        // about 100 characters by the time it reaches here.
                        Quickshell.execDetached(["bash", "-c", 'xdg-open "$(wl-paste --no-newline)"']);
                        root.shown = false;
                    }


                    StyledToolTip {
                        text: Translation.tr("Open link")
                    }
                }

                // The reference's two actions: share, then send to the device. Both
                // need a phone on the other end, so both go when there is none - the
                // same way Nearby Share drops out of the real one.
                CircleButton {
                    materialIcon: "share"
                    visible: KdeConnectService.activeReachable
                    onClicked: {
                        KdeConnectService.shareText(root.copiedText);
                        root.shown = false;
                    }


                    StyledToolTip {
                        text: Translation.tr("Share to %1").arg(KdeConnectService.activeDevice?.name ?? Translation.tr("phone"))
                    }
                }

                CircleButton {
                    materialIcon: "phonelink"
                    visible: KdeConnectService.activeReachable
                    onClicked: {
                        // Pushes the clipboard itself, so the phone gets the whole
                        // thing rather than the trimmed preview.
                        KdeConnectService.sendClipboard();
                        root.shown = false;
                    }


                    StyledToolTip {
                        text: Translation.tr("Send to %1's clipboard").arg(KdeConnectService.activeDevice?.name ?? Translation.tr("phone"))
                    }
                }
            }

            // The preview card sits on top of the pill and is the taller of the two,
            // so it reads as a raised thumbnail rather than another chip in a row.
            StyledRectangularShadow {
                target: previewFrame
            }

            Rectangle {
                id: previewFrame

                readonly property real border: 4

                x: root.atRight ? card.width - card.tileSize - card.tileLeft : card.tileLeft
                // Always overhangs away from the edge the pill is pinned to.
                y: root.atTop ? card.height - card.tileSize : 0
                width: card.tileSize
                height: card.tileSize
                radius: Appearance.rounding.normal + previewFrame.border
                // One state-layer step off the pill, mixed rather than taken from
                // colLayer1 because that token is only opaque over another surface.
                // This is the light mat the reference has round its thumbnail.
                color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colOnLayer0, 0.9)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: previewFrame.border
                    radius: Appearance.rounding.normal
                    clip: true
                    color: previewArea.pressed ? Appearance.colors.colSecondaryContainerActive : previewArea.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    StyledText {
                        // Fills the tile, because Text.Fit needs a bounded height to
                        // pick a size against. 4 inside the 4 frame: eight all told
                        // from the card's edge.
                        anchors {
                            fill: parent
                            margins: 4
                        }
                        text: root.copiedText
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignLeft
                        verticalAlignment: Text.AlignTop
                        font.pixelSize: root.previewFontSize
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                MouseArea {
                    id: previewArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // The launcher's clipboard query is the closest thing here to
                        // Android's clipboard editor.
                        Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "search", "clipboardToggle"]);
                        root.shown = false;
                    }
                }

                StyledToolTip {
                    // A Rectangle has no `hovered`, which the tooltip reads as
                    // "always show".
                    extraVisibleCondition: previewArea.containsMouse
                    text: Translation.tr("Open clipboard history")
                }
            }
        }
    }
}
