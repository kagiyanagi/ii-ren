pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: previewPopup

    // Path of the crop on disk. Left pointing at a deleted file while the card
    // slides out - the image is already decoded by then, so it keeps drawing.
    property string path: ""
    property bool shown: false

    // Which corner the card lives in, straight from the setting.
    readonly property string corner: Config.options.screenSnip.previewCorner
    readonly property bool atRight: previewPopup.corner.endsWith("right")
    readonly property bool atBottom: previewPopup.corner.startsWith("bottom")

    Binding {
        target: GlobalStates
        property: "screenshotPreviewCorner"
        value: previewPopup.corner
    }

    Binding {
        target: GlobalStates
        property: "screenshotPreviewHeight"
        value: root.visible ? card.height + card.gutter : 0
    }

    signal save()
    signal edit()
    signal discard()

    PanelWindow {
        id: root

        // Stays mapped until the card has finished sliding back off-screen.
        visible: (previewPopup.shown || card.onScreen) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        color: "transparent"

        WlrLayershell.namespace: "quickshell:screenshotPreview"
        WlrLayershell.layer: WlrLayer.Overlay
        // Reserve nothing, but sit clear of whatever the bar and a pinned dock do.
        exclusiveZone: 0

        // Full height on purpose, like NotificationPopup and the pairing card:
        // the card's height follows the crop, and resizing a layer surface as
        // that settles is what makes it stutter. The mask keeps the slack
        // click-through.
        anchors {
            left: !previewPopup.atRight
            right: previewPopup.atRight
            top: true
            bottom: true
        }

        // Slide inwards so a sidebar on this side can have the corner, and drift
        // back out once it closes. This has to move the card rather than the
        // window's margin: changing margins does not reconfigure an already
        // committed layer surface, so the window stays put and is made wide
        // enough to cover both positions.
        readonly property real sidebarInset: (previewPopup.atRight ? GlobalStates.effectiveRightOpen : GlobalStates.effectiveLeftOpen)
            ? Appearance.sizes.sidebarWidth : 0

        // Notifications own the top right corner, so drop below them rather than
        // overlapping. card.y adds the gutter on top of this, leaving the same
        // gap here as the card keeps from the screen edge. Clamped so a tall
        // stack cannot push the card off screen.
        readonly property real notificationInset: {
            if (previewPopup.atBottom || !previewPopup.atRight || GlobalStates.notificationPopupHeight <= 0)
                return 0;
            const room = root.height - card.height - card.gutter * 2;
            return Math.max(0, Math.min(GlobalStates.notificationPopupHeight, room));
        }

        readonly property real fastPairInset: {
            if (GlobalStates.fastPairPopupCorner !== previewPopup.corner || GlobalStates.fastPairPopupHeight <= 0)
                return 0;
            const room = root.height - card.height - card.gutter * 2 - root.notificationInset;
            return Math.max(0, Math.min(GlobalStates.fastPairPopupHeight, room));
        }

        readonly property real clipboardInset: {
            if (GlobalStates.clipboardToastCorner !== previewPopup.corner || GlobalStates.clipboardToastHeight <= 0)
                return 0;
            const room = root.height - card.height - card.gutter * 2 - root.notificationInset - root.fastPairInset;
            return Math.max(0, Math.min(GlobalStates.clipboardToastHeight, room));
        }

        // Gutter to the screen edge, elevationMargin of slack on the far side
        // for the shadow, plus the room the card needs to dodge a sidebar.
        implicitWidth: card.width + card.gutter + Appearance.sizes.elevationMargin + Appearance.sizes.sidebarWidth

        mask: Region {
            item: card
        }

        Item {
            id: card

            readonly property real gutter: Appearance.sizes.hyprlandGapsOut
            readonly property real framePadding: 6
            readonly property real thumbWidth: 240

            width: thumbWidth + framePadding * 2
            height: content.implicitHeight
            // Still poking in from its own edge, so the window must stay mapped.
            readonly property bool onScreen: previewPopup.atRight ? (x < root.width) : (x > -width)

            y: previewPopup.atBottom
                ? root.height - card.height - card.gutter - root.fastPairInset - root.clipboardInset
                : card.gutter + root.notificationInset + root.fastPairInset + root.clipboardInset
            // Slides out past the nearest screen edge, so there is nothing to clip.
            x: previewPopup.shown
                ? (previewPopup.atRight
                    ? root.width - card.width - card.gutter - root.sidebarInset
                    : card.gutter + root.sidebarInset)
                : (previewPopup.atRight ? root.width + card.gutter : -card.width - Appearance.sizes.elevationMargin)

            Behavior on x {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }

            Behavior on y {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }

            // Hovering holds the card open - the same courtesy a notification
            // gets. A HoverHandler rather than a MouseArea so the buttons on top
            // keep their own hover states instead of stealing this one.
            HoverHandler {
                id: cardHover
            }

            // No restart() anywhere: assigning running imperatively would kill
            // this binding, and re-arming on unhover is exactly what a Timer does
            // when running goes false and back to true.
            Timer {
                interval: Config.options.screenSnip.previewTimeout * 1000
                running: previewPopup.shown && !cardHover.hovered
                onTriggered: previewPopup.discard()
            }

            ColumnLayout {
                id: content
                width: parent.width
                spacing: 8

                Item {
                    Layout.preferredWidth: card.width
                    Layout.preferredHeight: thumbFrame.height

                    StyledRectangularShadow {
                        target: thumbFrame
                    }

                    Rectangle {
                        id: thumbFrame
                        width: card.width
                        // Follows the crop's shape, but a very tall or very wide
                        // snip is not allowed to run away with the card.
                        height: Math.round(thumb.height) + card.framePadding * 2
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer0

                        Image {
                            id: thumb
                            x: card.framePadding
                            y: card.framePadding
                            width: card.thumbWidth
                            height: (implicitWidth > 0 && implicitHeight > 0)
                                ? Math.max(80, Math.min(200, card.thumbWidth * implicitHeight / implicitWidth))
                                : 135
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            // A screenshot is only ever shown once; caching one
                            // full-size decode per snip is pure waste.
                            cache: false
                            source: previewPopup.path === "" ? "" : `file://${previewPopup.path}`

                            // Square corners inside a rounded frame read as a
                            // mistake as soon as the shot is light. Stepping the
                            // radius in by the padding keeps the two concentric.
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: thumb.width
                                    height: thumb.height
                                    radius: Appearance.rounding.large - card.framePadding
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.preferredWidth: pill.width
                    Layout.preferredHeight: pill.height
                    Layout.bottomMargin: Appearance.sizes.elevationMargin

                    StyledRectangularShadow {
                        target: pill
                    }

                    Rectangle {
                        id: pill
                        width: pillRow.implicitWidth + 12
                        height: 52
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer0

                        RowLayout {
                            id: pillRow
                            anchors.centerIn: parent
                            spacing: 4

                            RippleButtonWithIcon {
                                implicitHeight: 40
                                horizontalPadding: 16
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colSecondaryContainer
                                materialIcon: "save"
                                mainText: Translation.tr("Save")
                                onClicked: previewPopup.save()
                            }

                            component IconButton: RippleButton {
                                implicitWidth: 40
                                implicitHeight: 40
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colLayer1
                            }

                            IconButton {
                                onClicked: previewPopup.edit()
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "edit"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnLayer1
                                }
                            }

                            IconButton {
                                onClicked: previewPopup.discard()
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "delete"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colError
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
