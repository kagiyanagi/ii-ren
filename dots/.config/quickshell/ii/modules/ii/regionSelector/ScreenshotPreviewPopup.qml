pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
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

    signal save()
    signal edit()
    signal discard()

    PanelWindow {
        id: root

        // Stays mapped until the card has finished sliding back off-screen.
        visible: (previewPopup.shown || card.x > -card.width) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        color: "transparent"

        WlrLayershell.namespace: "quickshell:screenshotPreview"
        WlrLayershell.layer: WlrLayer.Overlay
        // Reserve nothing, but sit clear of whatever the bar and a pinned dock do.
        exclusiveZone: 0

        anchors {
            left: true
            bottom: true
        }

        implicitWidth: card.width + card.gutter + Appearance.sizes.elevationMargin
        implicitHeight: card.height + card.gutter + Appearance.sizes.elevationMargin

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
            y: root.height - card.height - card.gutter
            // Slides out past the screen edge, so there is nothing to clip.
            x: previewPopup.shown ? card.gutter : -card.width - Appearance.sizes.elevationMargin

            Behavior on x {
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
                interval: 6000
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
