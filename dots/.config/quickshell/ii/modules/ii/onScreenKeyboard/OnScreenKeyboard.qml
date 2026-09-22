import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool pinned: Config.options?.osk.pinnedOnStartup ?? false

    // The surface has to outlive the request or there is nothing left to play the exit
    // on. `active` must not read `oskOpen` even as one half of an `||`: the binding and
    // the Connections that starts the exit hang off the same change signal in an
    // undefined order, and when the binding wins the component is gone before the
    // handler runs. Measured that way round -- the close handler never executed once,
    // and the layer unmapped 45ms after the request rather than playing a 130ms exit.
    // So nothing but the component itself may clear this.
    property bool rendered: false

    Connections {
        target: GlobalStates
        function onOskOpenChanged() {
            if (GlobalStates.oskOpen)
                root.rendered = true;
        }
    }

    // Round, so a rail button cannot be read as a key. GroupButton squares its corners on
    // press by default, which on a circle reads as a glitch rather than feedback (4.3).
    component OskControlButton: GroupButton {
        baseWidth: Appearance.sizes.pageHeaderButtonSize
        baseHeight: Appearance.sizes.pageHeaderButtonSize
        clickedWidth: baseWidth
        clickedHeight: baseHeight + 10
        buttonRadius: Appearance.rounding.full
        buttonRadiusPressed: buttonRadius
        colBackground: Appearance.colors.colLayer1
    }

    Loader {
        id: oskLoader
        active: root.rendered
        onActiveChanged: {
            if (!oskLoader.active) {
                Ydotool.releaseAllKeys();
            }
        }

        sourceComponent: PanelWindow { // Window
            id: oskRoot
            visible: !GlobalStates.screenLocked

            anchors {
                bottom: true
                left: true
                right: true
            }

            function hide() {
                GlobalStates.oskOpen = false;
            }

            // 0 parked below the screen edge, 1 resting. Enter decelerating on the default
            // spatial spec, exit accelerating on fast effects (DESIGN.md 2.5). The spec is
            // picked inside the binding that writes the property, because a Behavior
            // cannot read its own direction (2.9).
            property real openedProgress: 0
            property AnimSpec openSpec: Appearance.animation.elementMoveEnter

            Behavior on openedProgress {
                NumberAnimation {
                    duration: oskRoot.openSpec.duration
                    easing.type: oskRoot.openSpec.type
                    easing.bezierCurve: oskRoot.openSpec.bezierCurve
                }
            }

            onOpenedProgressChanged: {
                // Re-opening mid-exit keeps the surface: the enter restarts from
                // wherever the card had fallen to rather than from a fresh window.
                if (openedProgress === 0 && !GlobalStates.oskOpen)
                    root.rendered = false;
            }

            onVisibleChanged: {
                // From Component.onCompleted most of the rise plays before the first
                // frame is on screen.
                if (visible && GlobalStates.oskOpen) {
                    oskRoot.openSpec = Appearance.animation.elementMoveEnter;
                    oskRoot.openedProgress = 1;
                }
            }

            Connections {
                target: GlobalStates
                function onOskOpenChanged() {
                    if (GlobalStates.oskOpen) {
                        oskRoot.openSpec = Appearance.animation.elementMoveEnter;
                        oskRoot.openedProgress = 1;
                    } else {
                        oskRoot.openSpec = Appearance.animation.elementMoveExit;
                        oskRoot.openedProgress = 0;
                    }
                }
            }

            exclusiveZone: root.pinned ? implicitHeight - Appearance.sizes.hyprlandGapsOut : 0
            implicitWidth: oskBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: oskBackground.implicitHeight + Appearance.sizes.elevationMargin * 2
            WlrLayershell.namespace: "quickshell:osk"
            WlrLayershell.layer: WlrLayer.Overlay
            // Hyprland 0.49: Focus is always exclusive and setting this breaks mouse focus grab
            // WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            mask: Region {
                item: oskBackground
            }

            // Make it usable with other panels
            Component.onCompleted: {
                GlobalFocusGrab.addPersistent(oskRoot);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removePersistent(oskRoot);
            }

            // Background
            StyledRectangularShadow {
                target: oskBackground
            }
            Rectangle {
                id: oskBackground

                // The rise is an anchor margin, never a transform: the window masks this
                // item, and `mask: Region` bakes a transform into the input region and
                // then refreshes it only on a geometry change (check-mask-regions.py).
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Appearance.sizes.elevationMargin - height * (1 - oskRoot.openedProgress)

                color: Appearance.colors.colLayer0
                radius: Appearance.rounding.large
                property real padding: 12
                implicitWidth: oskRowLayout.implicitWidth + padding * 2
                implicitHeight: oskRowLayout.implicitHeight + padding * 2

                RowLayout {
                    id: oskRowLayout
                    anchors.centerIn: parent
                    spacing: 12

                    VerticalButtonGroup {
                        // The group carries its own `height`, so without this the layout
                        // parks it at an arbitrary offset rather than beside the grid.
                        Layout.alignment: Qt.AlignVCenter
                        OskControlButton { // Pin button
                            toggled: root.pinned
                            downAction: () => root.pinned = !root.pinned
                            contentItem: MaterialSymbol {
                                text: "keep"
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: Appearance.font.pixelSize.larger
                                color: root.pinned ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                        OskControlButton { // Layout cycle. Collapses to nothing when
                            // layouts.js ships one layout, which is not a choice -- the
                            // group sizes itself from baseHeight, so hiding alone would
                            // leave the rail a button taller than its content.
                            baseHeight: oskContent.layoutCount > 1 ? Appearance.sizes.pageHeaderButtonSize : 0
                            visible: baseHeight > 0
                            onClicked: () => oskContent.cycleLayout()
                            contentItem: StyledText {
                                text: oskContent.currentLayout.name_short ?? ""
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                        OskControlButton {
                            onClicked: () => {
                                oskRoot.hide();
                            }
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "keyboard_hide"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                    OskContent {
                        id: oskContent
                        Layout.fillWidth: true
                    }
                }
            }

        }
    }

    IpcHandler {
        target: "osk"

        function toggle(): void {
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
        }

        function close(): void {
            GlobalStates.oskOpen = false
        }

        function open(): void {
            GlobalStates.oskOpen = true
        }
    }

    GlobalShortcut {
        name: "oskToggle"
        description: "Toggles on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
        }
    }

    GlobalShortcut {
        name: "oskOpen"
        description: "Opens on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = true
        }
    }

    GlobalShortcut {
        name: "oskClose"
        description: "Closes on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = false
        }
    }

}
