pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: fastPairPopup

    readonly property string corner: Config.options.bluetooth.fastPair.popupCorner
    readonly property bool atTop: fastPairPopup.corner.startsWith("top")
    readonly property bool atRight: fastPairPopup.corner.endsWith("right")

    Binding {
        target: GlobalStates
        property: "fastPairPopupCorner"
        value: fastPairPopup.corner
    }

    Binding {
        target: GlobalStates
        property: "fastPairPopupHeight"
        value: root.visible ? card.height + card.gutter : 0
    }

    // Opens the card with no candidate, so the layout can be seen without
    // waiting for a pair of earbuds to leave their case.
    IpcHandler {
        target: "fastPair"

        function toggle(): void {
            FastPair.popupShown = !FastPair.popupShown;
        }
    }

    PanelWindow {
        id: root

        // Stays mapped until the card has finished sliding back off-screen.
        visible: (FastPair.popupShown || (fastPairPopup.atRight ? card.x < root.width : card.x > -card.width)) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        color: "transparent"

        WlrLayershell.namespace: "quickshell:fastPairPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        // Reserve nothing, but do respect what the bar reserves. That is what
        // puts the card the same distance from the edge as every other panel,
        // and it handles a vertical or bottom bar without special-casing it.
        exclusiveZone: 0

        // Full height on purpose, like NotificationPopup: the card changes height
        // when the options expand, and resizing a layer surface every animation
        // frame is what makes that stutter. The mask keeps the slack
        // click-through.
        anchors {
            left: !fastPairPopup.atRight
            right: fastPairPopup.atRight
            top: true
            bottom: true
        }

        // Slide inwards so the right sidebar can have the corner, and drift back
        // out once it closes. This has to move the card rather than the window's
        // right margin: changing margins does not reconfigure an already
        // committed layer surface, so the window instead stays put and is made
        // wide enough to cover both positions. The mask keeps the slack
        // click-through.
        readonly property real sidebarInset: (fastPairPopup.atRight ? GlobalStates.effectiveRightOpen : GlobalStates.effectiveLeftOpen) ? Appearance.sizes.sidebarWidth : 0

        // Notifications own this corner, so drop below them rather than
        // overlapping. card.y adds the gutter on top of this, which is what
        // leaves the same gap here as the card keeps from the screen edge.
        // Clamped so a tall stack cannot push the card off screen.
        readonly property real notificationInset: {
            if (!fastPairPopup.atTop || !fastPairPopup.atRight || GlobalStates.notificationPopupHeight <= 0)
                return 0;
            const room = root.height - card.height - card.gutter * 2;
            return Math.max(0, Math.min(GlobalStates.notificationPopupHeight, room));
        }

        // Gutter to the screen edge, elevationMargin of slack on the far side
        // for the shadow: the same split SidebarDashboard uses.
        implicitWidth: card.width + card.gutter + Appearance.sizes.elevationMargin + Appearance.sizes.sidebarWidth

        mask: Region {
            item: card
        }

        Item {
            id: card

            // Same outer spacing as the sidebars, notifications and bar popups.
            readonly property real gutter: Appearance.sizes.hyprlandGapsOut
            readonly property real padding: 16
            property bool optionsOpen: false

            readonly property bool shown: FastPair.popupShown
            onShownChanged: {
                if (!card.shown)
                    return;
                card.optionsOpen = false;
                swipe.reset();
                body.opacity = 1;
            }

            readonly property string statusText: {
                // Names the binary rather than any one distro's package name.
                if (FastPair.agentUnavailable)
                    return Translation.tr("Can't pair: bluetoothctl not available");
                if (FastPair.failed)
                    return Translation.tr("Couldn't connect, try again");
                if (!FastPair.busy)
                    return Translation.tr("Nearby and ready to pair");
                if (FastPair.candidate?.connected)
                    return Translation.tr("Connected");
                if (FastPair.candidate?.paired)
                    return Translation.tr("Connecting...");
                return Translation.tr("Pairing...");
            }

            readonly property var snoozePresets: [
                { label: Translation.tr("10m"), ms: 600000 },
                { label: Translation.tr("30m"), ms: 1800000 },
                { label: Translation.tr("1h"), ms: 3600000 },
                { label: Translation.tr("6h"), ms: 21600000 }
            ]

            // Enter decelerating, exit accelerating at half the duration (DESIGN
            // 2.5). Assigned from inside the binding that writes x, the shape
            // BarComponent uses: a Behavior bakes its spec at the instant of the
            // write, so a spec read from a binding of its own is a frame late
            // and the exit runs on the enter's curve.
            property AnimSpec slideSpec: Appearance.animation.elementMoveEnter

            width: Appearance.sizes.fastPairPopupWidth
            height: content.implicitHeight + card.padding * 2
            y: fastPairPopup.atTop ? card.gutter + root.notificationInset : root.height - card.height - card.gutter
            // Slides out past the screen edge, so there is nothing to clip.
            x: {
                card.slideSpec = FastPair.popupShown ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveExit;
                if (FastPair.popupShown)
                    return fastPairPopup.atRight ? root.width - card.width - card.gutter - root.sidebarInset : card.gutter + root.sidebarInset;
                return fastPairPopup.atRight ? root.width + card.gutter : -card.width - card.gutter;
            }

            Behavior on x {
                NumberAnimation {
                    duration: card.slideSpec.duration
                    easing.type: card.slideSpec.type
                    easing.bezierCurve: card.slideSpec.bezierCurve
                }
            }

            Behavior on y {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            // The window masks `card`, so `card` owns the geometry and nothing
            // else: a mask bakes a transform on the item it follows
            // (check-mask-regions.py). The swipe moves and fades this body.
            Item {
                id: body
                anchors.fill: parent

                transform: Translate {
                    x: swipe.offset
                }

                SwipeToDismiss {
                    id: swipe
                    onDismissed: FastPair.dismiss(FastPair.options.snoozeSeconds * 1000)
                }

                StyledRectangularShadow {
                    target: background
                }

                Rectangle {
                    id: background
                    anchors.fill: parent
                    radius: Appearance.rounding.verylarge
                    color: Appearance.colors.colLayer0
                }

                component Chip: DialogButton {
                    padding: 8
                    implicitHeight: 32
                }

                // DESIGN 9 icon button: square, full radius, size the button not
                // the padding.
                component IconButton: DialogButton {
                    id: iconButton
                    property alias symbol: iconSymbol.text
                    property alias iconRotation: iconSymbol.rotation
                    implicitWidth: 40
                    implicitHeight: 40
                    padding: 0

                    contentItem: MaterialSymbol {
                        id: iconSymbol
                        // Fill and align, not centerIn: a Text's box is a line
                        // height, so centring the box leaves the glyph low.
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        iconSize: Appearance.font.pixelSize.huge
                        color: iconButton.colEnabled

                        Behavior on rotation {
                            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                        }
                    }
                }

                IconButton {
                    anchors {
                        top: parent.top
                        right: parent.right
                        margins: card.padding
                    }
                    symbol: "close"
                    onClicked: FastPair.dismiss(FastPair.options.snoozeSeconds * 1000)

                    StyledToolTip {
                        text: Translation.tr("Close")
                    }
                }

                ColumnLayout {
                    id: content
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: card.padding
                        rightMargin: card.padding
                    }
                    spacing: 4

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        shape: MaterialShape.Shape.Cookie12Sided
                        iconSize: 48
                        padding: 24
                        text: Icons.getBluetoothDeviceMaterialSymbol(FastPair.candidate?.icon ?? "")
                    }

                    // The strip is always reserved so the card does not jump when a
                    // connect starts; the bar itself only sweeps while busy.
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 8
                        implicitWidth: progress.implicitWidth
                        implicitHeight: progress.implicitHeight

                        StyledIndeterminateProgressBar {
                            id: progress
                            anchors.fill: parent
                            visible: FastPair.busy || progress.opacity > 0
                            opacity: FastPair.busy ? 1 : 0

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: FastPair.candidate?.name || Translation.tr("Bluetooth device")
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: FastPair.failed || FastPair.agentUnavailable ? Appearance.colors.colError : Appearance.colors.colSubtext
                        textFormat: Text.PlainText
                        text: card.statusText

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }

                    // Revealer clips and animates the reveal rather than snapping the
                    // card to a new height. Held visible at zero height so the
                    // layout's spacing does not pop once it finishes collapsing.
                    Revealer {
                        Layout.fillWidth: true
                        vertical: true
                        reveal: card.optionsOpen
                        visible: true

                        ColumnLayout {
                            // Explicit width: taking it from the Revealer would make
                            // the Revealer's implicitWidth depend on its own child.
                            width: card.width - card.padding * 2
                            spacing: 4

                            StyledText {
                                Layout.topMargin: 12
                                text: Translation.tr("Snooze this device")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Repeater {
                                    model: card.snoozePresets

                                    Chip {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        buttonText: modelData.label
                                        onClicked: FastPair.dismiss(modelData.ms)
                                    }
                                }
                            }

                            Chip {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                colText: Appearance.colors.colError
                                buttonText: Translation.tr("Never show this device")
                                onClicked: FastPair.ignoreCandidate()
                            }

                            StyledText {
                                Layout.topMargin: 8
                                text: Translation.tr("Mute all pairing popups")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Repeater {
                                    model: card.snoozePresets

                                    Chip {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        buttonText: modelData.label
                                        onClicked: FastPair.muteAll(modelData.ms)
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        spacing: 8

                        IconButton {
                            symbol: "expand_more"
                            iconRotation: card.optionsOpen ? 180 : 0
                            onClicked: card.optionsOpen = !card.optionsOpen

                            StyledToolTip {
                                text: Translation.tr("More options")
                            }
                        }

                        DialogButton {
                            Layout.fillWidth: true
                            implicitHeight: 40
                            enabled: !FastPair.busy && !FastPair.agentUnavailable
                            // Disabled is the whole control at 0.4 (DESIGN 6), not a
                            // filled primary with outline-coloured text.
                            opacity: enabled ? 1 : 0.4
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colRipple: Appearance.colors.colPrimaryActive
                            colEnabled: Appearance.colors.colOnPrimary
                            colDisabled: Appearance.colors.colOnPrimary
                            buttonText: Translation.tr("Connect")
                            onClicked: FastPair.connectCandidate()

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }
            }
            }
        }
    }
}
