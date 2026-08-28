import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

Scope {
    id: root

    readonly property int tileSize: 92
    readonly property int iconSize: 58
    readonly property int tileSpacing: 4

    property bool open: false
    property var windows: []
    // ponytail: read once at startup, not on every Hyprland config reload.
    property bool userNoWarps: false
    property int selectedIndex: 0
    readonly property var selectedWindow: windows[selectedIndex] ?? null

    // Hyprland already keeps the MRU order for us in focusHistoryID (0 = focused).
    function snapshot() {
        const workspace = Hyprland.focusedWorkspace?.id;
        root.windows = HyprlandData.windowList
            .filter(win => win.mapped && !win.hidden)
            .filter(win => !Config.options.altTab.currentWorkspaceOnly || win.workspace?.id === workspace)
            .sort((a, b) => a.focusHistoryID - b.focusHistoryID);
    }

    // Hyprland warps the pointer to the focused window's center unless
    // cursor:no_warps is set, so flip it for the duration of the switch.
    function setNoWarps(value) {
        if (!Config.options.altTab.keepCursorInPlace || root.userNoWarps) return;
        Quickshell.execDetached(["hyprctl", "eval", `hl.config({cursor = {no_warps = ${value}}})`]);
    }

    function step(delta) {
        if (!Config.options.altTab.enable) return;
        if (!root.open) {
            root.snapshot();
            if (root.windows.length === 0) return;
            root.selectedIndex = (delta > 0 ? 1 : root.windows.length - 1) % root.windows.length;
            root.setNoWarps(true);
            root.open = true;
            return;
        }
        const n = root.windows.length;
        root.selectedIndex = (root.selectedIndex + delta + n) % n;
    }

    function confirm() {
        if (!root.open) return;
        root.open = false;
        restoreWarpsTimer.restart();
        const address = root.selectedWindow?.address;
        if (!address) return;
        Hyprland.dispatch(`hl.dsp.focus({window = "address:${address}"})`);
    }

    Timer {
        id: restoreWarpsTimer
        interval: 200
        onTriggered: root.setNoWarps(false)
    }

    Process {
        running: true
        command: ["hyprctl", "getoption", "cursor:no_warps", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.userNoWarps = JSON.parse(text)?.bool === true
        }
    }

    GlobalShortcut {
        name: "altTabNext"
        description: "Switch to next window (hold Alt)"
        onPressed: root.step(1)
    }
    GlobalShortcut {
        name: "altTabPrev"
        description: "Switch to previous window (hold Alt)"
        onPressed: root.step(-1)
    }
    GlobalShortcut {
        name: "altTabConfirm"
        description: "Focus the window picked in the Alt+Tab switcher"
        onReleased: root.confirm()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData

            screen: modelData
            visible: root.open && Hyprland.focusedMonitor?.name === modelData?.name
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:altTab"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            implicitWidth: card.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: card.implicitHeight + Appearance.sizes.elevationMargin * 2

            StyledRectangularShadow { target: card }

            Rectangle {
                id: card
                anchors.centerIn: parent
                readonly property int padding: 18

                implicitWidth: Math.min(panel.screen.width * 0.9, layout.implicitWidth + padding * 2)
                implicitHeight: layout.implicitHeight + padding * 2
                radius: Appearance.rounding.verylarge
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                scale: root.open ? 1 : 0.92
                opacity: root.open ? 1 : 0
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
                }

                ColumnLayout {
                    id: layout
                    anchors.centerIn: parent
                    spacing: 6

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: tiles.implicitWidth
                        implicitHeight: root.tileSize

                        Rectangle { // One highlight that slides, instead of every tile fading
                            width: root.tileSize
                            height: root.tileSize
                            x: root.selectedIndex * (root.tileSize + root.tileSpacing)
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colSecondaryContainer
                            visible: root.windows.length > 0

                            Behavior on x {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }

                        Row {
                            id: tiles
                            spacing: root.tileSpacing

                            Repeater {
                                model: root.windows

                                Item {
                                    id: tile
                                    required property var modelData
                                    required property int index

                                    implicitWidth: root.tileSize
                                    implicitHeight: root.tileSize

                                    IconImage {
                                        anchors.centerIn: parent
                                        implicitSize: root.iconSize
                                        source: Quickshell.iconPath(TaskbarApps.getCachedIcon(tile.modelData.class), "image-missing")
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        // Not onEntered: the panel pops up under a resting
                                        // pointer and would steal the selection instantly.
                                        onPositionChanged: root.selectedIndex = tile.index
                                        onClicked: root.confirm()
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        // A single tile would otherwise squeeze the title to nothing.
                        Layout.preferredWidth: Math.min(Math.max(tiles.implicitWidth, 260), panel.screen.width * 0.9 - card.padding * 2)
                        Layout.bottomMargin: 4
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer0
                        text: root.selectedWindow?.title ?? ""
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "altTab"

        function next(): void { root.step(1) }
        function prev(): void { root.step(-1) }
        function confirm(): void { root.confirm() }
    }
}
