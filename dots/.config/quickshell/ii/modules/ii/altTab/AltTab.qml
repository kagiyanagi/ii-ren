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

    readonly property int tileSize: 80
    readonly property int iconSize: 48
    readonly property int tileSpacing: 4
    // The card comes out of nothing, so it settles in rather than zooms.
    readonly property real closedScale: 0.92
    // GNOME Shell altTab.js POPUP_DELAY_TIMEOUT. A tap-and-release Alt+Tab is
    // over well inside this, and a card for one is a flash on the most common
    // path -- so nothing is drawn until Alt has actually been held.
    readonly property int popupDelay: 150

    property bool open: false // A switch is in progress
    property bool shown: false // The card is on screen
    property var windows: []
    // Read once at startup, which is only trustworthy because we always put the
    // option back (including on shutdown) before the next startup reads it.
    property bool userNoWarps: false
    property bool noWarpsActive: false
    // Latched when the switcher opens: confirming a window on another monitor
    // moves Hyprland's focus, and the card would be unmapped mid-exit.
    property string activeMonitor: ""
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
        if (value && (!Config.options.altTab.keepCursorInPlace || root.userNoWarps)) return;
        if (value === root.noWarpsActive) return;
        root.noWarpsActive = value;
        Quickshell.execDetached(["hyprctl", "eval", `hl.config({cursor = {no_warps = ${value}}})`]);
    }

    // Leaving it on would poison the next startup's read of the user's own value.
    Component.onDestruction: root.setNoWarps(false)

    function step(delta) {
        if (!Config.options.altTab.enable) return;
        if (!root.open) {
            root.snapshot();
            if (root.windows.length === 0) return;
            root.selectedIndex = (delta > 0 ? 1 : root.windows.length - 1) % root.windows.length;
            root.activeMonitor = Hyprland.focusedMonitor?.name ?? "";
            // A second switch inside the restore window would otherwise get
            // the pointer warp back mid-flight.
            restoreWarpsTimer.stop();
            root.setNoWarps(true);
            root.open = true;
            return;
        }
        const n = root.windows.length;
        root.selectedIndex = (root.selectedIndex + delta + n) % n;
    }

    // Everything that ends a switch: the card leaves, the warp comes back.
    function close() {
        root.open = false;
        restoreWarpsTimer.restart();
    }

    function cancel() {
        if (!root.open) return;
        root.close();
    }

    function confirm() {
        if (!root.open) return;
        root.close();
        const target = root.selectedWindow;
        if (!target?.address) return;
        const previous = root.windows[0]; // focusHistoryID 0 when we opened
        Hyprland.dispatch(`hl.dsp.focus({window = "address:${target.address}"})`);

        // Focusing a tiled sibling drops the maximize, which dumps the whole
        // workspace back into the tiling layout. Hand the state over instead,
        // so the window you picked takes the space the old one had. A floating
        // window is only raised over it (Hyprland's FocusState), as a desktop's
        // switcher does: handing it the state would fill the screen with it.
        if (!(previous?.fullscreen > 0)) return;
        if (target.floating) return;
        if (previous.address === target.address) return;
        if (previous.workspace?.id !== target.workspace?.id) return;
        const mode = previous.fullscreen === 2 ? "fullscreen" : "maximized";
        Hyprland.dispatch(`hl.dsp.window.fullscreen({ mode = "${mode}", action = "set" })`);
    }

    onOpenChanged: {
        if (root.open) {
            showTimer.restart();
            return;
        }
        showTimer.stop();
        root.shown = false;
    }

    Timer {
        id: showTimer
        interval: root.popupDelay
        onTriggered: root.shown = true
    }

    Timer {
        id: restoreWarpsTimer
        // Hyprland warps at the end of the workspace-change animation, not when
        // the focus dispatch lands, so this has to outlast that animation.
        interval: 600
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
    GlobalShortcut {
        name: "altTabCancel"
        description: "Dismiss the Alt+Tab switcher without switching"
        onPressed: root.cancel()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData

            screen: modelData
            // Unmapping on `shown` alone means the exit never renders.
            visible: (root.shown || card.reveal > 0) && root.activeMonitor === modelData?.name
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
                readonly property int padding: 16

                implicitWidth: layout.implicitWidth + padding * 2
                implicitHeight: layout.implicitHeight + padding * 2
                radius: Appearance.rounding.verylarge
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                // Screen-centred, with nothing to grow out of (DESIGN.md 2.6).
                transformOrigin: Item.Center

                // Scale and opacity ride one driver, so the enter/exit spec is
                // assigned from the only binding that writes it -- the shape
                // 2.9's Behavior trap requires, without two of everything.
                // Enter decelerates over the full spec, exit accelerates at
                // half of it (2.5), as WindowDialog does for the same card.
                property int revealDuration: Appearance.animation.elementMoveFast.duration
                property list<real> revealCurve: Appearance.animationCurves.emphasizedDecel
                property real reveal: {
                    card.revealDuration = root.shown ? Appearance.animation.elementMoveFast.duration : Math.round(Appearance.animation.elementMoveFast.duration / 2);
                    card.revealCurve = root.shown ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel;
                    return root.shown ? 1 : 0;
                }
                Behavior on reveal {
                    NumberAnimation {
                        duration: card.revealDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: card.revealCurve
                    }
                }

                scale: root.closedScale + (1 - root.closedScale) * card.reveal
                opacity: card.reveal

                ColumnLayout {
                    id: layout
                    anchors.centerIn: parent
                    spacing: 8

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: tiles.implicitWidth
                        implicitHeight: tiles.implicitHeight

                        Rectangle { // One highlight that slides, instead of every tile fading
                            width: root.tileSize
                            height: root.tileSize
                            x: (root.selectedIndex % tiles.columns) * (root.tileSize + root.tileSpacing)
                            y: Math.floor(root.selectedIndex / tiles.columns) * (root.tileSize + root.tileSpacing)
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colSecondaryContainer
                            visible: root.windows.length > 0

                            // Off while the card is hidden, or re-opening slides the
                            // highlight in from wherever the last switch left it (2.7).
                            Behavior on x {
                                enabled: root.shown
                                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                            }
                            Behavior on y {
                                enabled: root.shown
                                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                            }
                        }

                        Grid {
                            id: tiles
                            spacing: root.tileSpacing

                            // What fits across 90% of the screen; a longer list wraps
                            // instead of painting past the card and off the edge.
                            readonly property int maxColumns: Math.max(1, Math.floor((panel.screen.width * 0.9 - card.padding * 2 + root.tileSpacing) / (root.tileSize + root.tileSpacing)))
                            // Balanced, so a wrapped last row is not one orphan tile.
                            columns: root.windows.length > 0 ? Math.ceil(root.windows.length / Math.ceil(root.windows.length / maxColumns)) : 1

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

                                    // Hover and focus are the selection itself -- both
                                    // move the highlight here, which is louder than a
                                    // film. Only the press has nothing else to show it.
                                    StateOverlay {
                                        anchors.fill: parent
                                        // Spelled out rather than left to `radius`, the way
                                        // every other caller but one does it.
                                        topLeftRadius: Appearance.rounding.normal
                                        topRightRadius: Appearance.rounding.normal
                                        bottomLeftRadius: Appearance.rounding.normal
                                        bottomRightRadius: Appearance.rounding.normal
                                        contentColor: Appearance.colors.colOnSecondaryContainer
                                        press: tileArea.pressed
                                    }

                                    MouseArea {
                                        id: tileArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        // Not onEntered: the panel pops up under a resting
                                        // pointer and would steal the selection instantly.
                                        onPositionChanged: root.selectedIndex = tile.index
                                        // A pointer that has not moved never selected this
                                        // tile, and confirm() focuses whatever is selected.
                                        onPressed: root.selectedIndex = tile.index
                                        onClicked: root.confirm()
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        // A one-tile switcher would otherwise squeeze the title
                        // down to the width of a single icon.
                        Layout.preferredWidth: Math.max(tiles.implicitWidth, root.tileSize * 3)
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
        function cancel(): void { root.cancel() }
    }
}
