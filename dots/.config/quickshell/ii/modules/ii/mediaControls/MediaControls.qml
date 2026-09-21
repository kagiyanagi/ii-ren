pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var realPlayers: MprisController.players
    // `realPlayers` is already filtered by MprisController.isRealPlayer, which knows
    // the specific buses that duplicate each other. This second pass is the generic
    // one, and it is the setting's to switch off -- it ran unconditionally, so the
    // switch in Settings > Services did nothing here and the placeholder below told
    // the user to go and use it.
    readonly property var meaningfulPlayers: Config.options.media.filterDuplicatePlayers ? filterDuplicatePlayers(realPlayers) : realPlayers
    readonly property real osdWidth: Appearance.sizes.osdWidth
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    property real popupRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
    property list<real> visualizerPoints: []

    function filterDuplicatePlayers(players) {
        let filtered = [];
        let used = new Set();

        for (let i = 0; i < players.length; ++i) {
            if (used.has(i))
                continue;
            let p1 = players[i];
            let group = [i];

            // Same title, or the same place in a track of the same length. The
            // second test was written unsigned -- `p1.position - p2.position <= 2`
            // is true whenever p1 is *behind* p2 at all, by any amount, so any
            // player earlier in its track than another was merged into it and
            // vanished from the stack. Three live players collapsed to one.
            for (let j = i + 1; j < players.length; ++j) {
                let p2 = players[j];
                let sameTitle = p1.trackTitle && p2.trackTitle && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle));
                let samePlace = Math.abs(p1.position - p2.position) <= 2 && Math.abs(p1.length - p2.length) <= 2;
                if (sameTitle || samePlace) {
                    group.push(j);
                }
            }

            // Pick the one with non-empty trackArtUrl, or fallback to the first
            let chosenIdx = group.find(idx => players[idx].trackArtUrl && players[idx].trackArtUrl.length > 0);
            if (chosenIdx === undefined)
                chosenIdx = group[0];

            filtered.push(players[chosenIdx]);
            group.forEach(idx => used.add(idx));
        }
        return filtered;
    }

    Process {
        id: cavaProc
        running: mediaControlsLoader.active
        onRunningChanged: {
            if (!cavaProc.running) {
                root.visualizerPoints = [];
            }
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                // Parse `;`-separated values into the visualizerPoints array
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                root.visualizerPoints = points;
            }
        }
    }

    Loader {
        id: mediaControlsLoader

        // The request. `active` is deliberately not bound to it: the surface would
        // then be destroyed on the frame the flag flips and the close animation
        // would play to nobody -- the popup just vanishes, with no other symptom.
        readonly property bool wantOpen: GlobalStates.mediaControlsOpen && (!GlobalStates.dockMediaPresent || GlobalStates.barMediaPresent)

        // The mapping, set explicitly rather than bound, so the order in which a
        // binding and a change handler run cannot decide whether the exit is seen.
        property bool alive: false
        active: alive

        onWantOpenChanged: {
            if (wantOpen) {
                if (item)
                    item.startOpen();
                else
                    alive = true; // Component.onCompleted runs the open
            } else if (item) {
                item.startClose();
            } else {
                alive = false;
            }
        }

        onActiveChanged: {
            if (!mediaControlsLoader.active && root.realPlayers.length === 0) {
                GlobalStates.mediaControlsOpen = false;
            }
        }

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: true
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: root.widgetWidth
            implicitHeight: playerColumnLayout.implicitHeight
            color: "transparent"
            WlrLayershell.namespace: "quickshell:mediaControls"
            
            readonly property var rect: Qt.rect(Persistent.states.media.popupX, Persistent.states.media.popupY, Persistent.states.media.popupWidth, Persistent.states.media.popupHeight)
            readonly property real barThickness: {
                if (Config.options.bar.vertical) {
                    return Config.options.bar.sizes.width || 40;
                } else {
                    return Config.options.bar.sizes.height || 40;
                }
            }
            anchors {
                top: true
                left: !Config.options.bar.vertical || !Config.options.bar.bottom
                right: Config.options.bar.vertical && Config.options.bar.bottom
            }
            margins {
                top: {
                    if (rect.width === 0) return barThickness + Appearance.sizes.hyprlandGapsOut;
                    if (Config.options.bar.vertical) {
                        let targetY = rect.y + (rect.height / 2) - (panelWindow.implicitHeight / 2);
                        return Math.max(0, Math.min(targetY, screen.height - panelWindow.implicitHeight));
                    } else {
                        if (!Config.options.bar.bottom) {
                            return barThickness;
                        } else {
                            return screen.height - barThickness - panelWindow.implicitHeight;
                        }
                    }
                }
                left: {
                    if (rect.width === 0) return Math.max(0, (screen.width - panelWindow.implicitWidth) / 2);
                    if (Config.options.bar.vertical) {
                        if (!Config.options.bar.bottom) {
                            return barThickness;
                        }
                        return 0;
                    } else {
                        let targetX = rect.x + (rect.width / 2) - (panelWindow.implicitWidth / 2);
                        return Math.max(0, Math.min(targetX, screen.width - panelWindow.implicitWidth));
                    }
                }
                right: {
                    if (rect.width === 0) return 0;
                    if (Config.options.bar.vertical && Config.options.bar.bottom) {
                        return barThickness;
                    }
                    return 0;
                }
            }

            // Launcher3 ArrowPopup.setPivotForOpenCloseAnimation(): the stack grows
            // out of the bar edge it is placed against, from the same four booleans
            // the margins above already read.
            readonly property int pivot: {
                if (Config.options.bar.vertical)
                    return Config.options.bar.bottom ? Item.Right : Item.Left;
                return Config.options.bar.bottom ? Item.Bottom : Item.Top;
            }

            function startOpen(): void {
                motion.open();
            }

            function startClose(): void {
                motion.close();
            }

            // No `mask:` here. The column is `anchors.fill: parent` inside a window
            // sized to that column, so a Region over it was the whole window and did
            // nothing -- but Region bakes the masked item's transform and refreshes
            // only on a geometry change, so the open animation below would have
            // frozen the input region at arrowPopupScale and left half the card
            // clicking through to the window behind (tools/check-mask-regions.py).

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(panelWindow);
                motion.open();
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.mediaControlsOpen = false;
                }
            }

            // ArrowPopup.animateOpen() / animateClose(), from the one composite the
            // whole shell shares (DESIGN.md 9). The column owns the transformOrigin,
            // because that is the per-surface half of the recipe.
            ArrowPopupMotion {
                id: motion
                target: playerColumnLayout
                onClosed: mediaControlsLoader.alive = false
            }

            ColumnLayout {
                id: playerColumnLayout
                anchors.fill: parent
                spacing: -Appearance.sizes.elevationMargin // Shadow overlap okay

                transformOrigin: panelWindow.pivot

                // Resting state, so a popup that survives a close animates from a
                // known one next time rather than from whatever the last close left
                // behind (DESIGN.md 2.7).
                opacity: 0
                scale: Appearance.animationCurves.arrowPopupScale

                Repeater {
                    model: ScriptModel {
                        values: root.meaningfulPlayers
                    }
                    delegate: PlayerControl {
                        required property MprisPlayer modelData
                        player: modelData
                        visualizerPoints: root.visualizerPoints
                        implicitWidth: root.widgetWidth
                        radius: root.popupRounding
                        // Only worth a control when there is something to pick.
                        canPickPlayer: root.meaningfulPlayers.length > 1
                    }
                }

                Item {
                    // No player placeholder
                    Layout.alignment: {
                        if (panelWindow.anchors.left)
                            return Qt.AlignLeft;
                        if (panelWindow.anchors.right)
                            return Qt.AlignRight;
                        return Qt.AlignHCenter;
                    }
                    Layout.leftMargin: Appearance.sizes.hyprlandGapsOut
                    Layout.rightMargin: Appearance.sizes.hyprlandGapsOut
                    visible: root.meaningfulPlayers.length === 0
                    implicitWidth: placeholderBackground.implicitWidth + Appearance.sizes.elevationMargin
                    implicitHeight: placeholderBackground.implicitHeight + Appearance.sizes.elevationMargin

                    StyledRectangularShadow {
                        target: placeholderBackground
                    }

                    Rectangle {
                        id: placeholderBackground
                        anchors.centerIn: parent
                        color: Appearance.colors.colLayer0
                        radius: root.popupRounding
                        // PagePlaceholder anchors itself to its parent and has no
                        // implicit size of its own, so the card is what carries the
                        // geometry -- a player card's width, and the shell's own
                        // placeholder height. Sizing the card from the placeholder
                        // instead is a binding loop that resolves to nothing.
                        implicitWidth: root.widgetWidth - Appearance.sizes.elevationMargin * 2
                        implicitHeight: Appearance.sizes.pagePlaceholderHeight

                        // The shell's one empty state (DESIGN.md 9), rather than a
                        // second hand-rolled pair of labels.
                        PagePlaceholder {
                            id: placeholder
                            icon: "music_off"
                            title: Translation.tr("No active player")
                            description: Translation.tr("Make sure your player has MPRIS support\nor try turning off duplicate player filtering")
                            descriptionHorizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "mediaControls"

        function toggle(): void {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
            if (GlobalStates.mediaControlsOpen)
                Notifications.timeoutAll();
        }

        function close(): void {
            GlobalStates.mediaControlsOpen = false;
        }

        function open(): void {
            GlobalStates.mediaControlsOpen = true;
            Notifications.timeoutAll();
        }
    }

    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
        }
    }
    GlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = true;
        }
    }
    GlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = false;
        }
    }
}
