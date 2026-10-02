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
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    // Intent is GlobalStates.sessionOpen; `rendered` is whether the surface is
    // mapped. Set on the open edge and never bound: `active` must not read the
    // intent, not even as one half of an `||`, or the binding and the handler race
    // on one change signal (OnScreenKeyboard.qml measured it). The dialog clears it
    // once its exit has played, which is what gives this surface an exit at all.
    property bool rendered: false

    // Android's power menu, GlobalActionsDialogLite: circular icon buttons with the
    // label under each, on one card. The tile is M3E's Large icon button
    // (LargeIconButtonTokens.kt: 96 container, 32 icon). Gaps are the menu's
    // global_actions_lite_padding (24), and a label sits 8 under its tile
    // (global_actions_grid_container_bottom_margin). AOSP caps it at two columns for
    // a portrait phone; a landscape desktop gets the same eight tiles in two rows.
    readonly property int columns: 4
    readonly property real tileSize: 96
    readonly property real tileIconSize: 32
    readonly property real tileGap: 24
    readonly property real labelGap: 8

    // The top row keeps your work and the bottom row closes every window. `can` is
    // the logind method that says whether this machine can do it at all; `fade`
    // takes the screen to black first, for the ones that switch it off.
    readonly property var actions: [
        { icon: "lock", name: Translation.tr("Lock"), run: () => Session.lock() },
        { icon: "dark_mode", name: Translation.tr("Sleep"), can: "CanSuspend", fade: true, run: () => Session.suspend() },
        { icon: "downloading", name: Translation.tr("Hibernate"), can: "CanHibernate", fade: true, run: () => Session.hibernate() },
        { icon: "browse_activity", name: Translation.tr("Task Manager"), run: () => Session.launchTaskManager() },
        { icon: "logout", name: Translation.tr("Logout"), fade: true, run: () => Session.logout() },
        { icon: "power_settings_new", name: Translation.tr("Shutdown"), can: "CanPowerOff", fade: true, run: () => Session.poweroff() },
        { icon: "restart_alt", name: Translation.tr("Reboot"), can: "CanReboot", fade: true, run: () => Session.reboot() },
        { icon: "settings_applications", name: Translation.tr("Reboot to firmware settings"), can: "CanRebootToFirmwareSetup", fade: true, run: () => Session.rebootToFirmware() },
    ]

    // Held until the exit has played: lock, suspend and logout take the screen
    // away at once, so firing on the press cut the close off before its first frame.
    property var pendingAction: null
    // The screen is going, or has gone, black for a `fade` action.
    property bool blackout: false

    function run(action) {
        // The window keeps the keyboard while it leaves; a second Enter must not
        // fire a second action.
        if (!GlobalStates.sessionOpen)
            return;
        root.pendingAction = action;
        root.blackout = action.fade === true;
        GlobalStates.sessionOpen = false;
    }

    // Left and right stay in their row, up and down on the grid.
    function inReach(from, to, step) {
        return to >= 0 && to < root.actions.length && (Math.abs(step) !== 1 || Math.floor(to / root.columns) === Math.floor(from / root.columns));
    }

    Connections {
        target: GlobalStates
        function onSessionOpenChanged() {
            if (!GlobalStates.sessionOpen)
                return;
            // Reopened mid-exit: the close never finishes, and the choice is dropped.
            root.pendingAction = null;
            root.blackout = false;
            root.rendered = true;
            SessionWarnings.refresh();
        }
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                GlobalStates.sessionOpen = false;
        }
    }

    Loader {
        active: root.rendered

        sourceComponent: PanelWindow {
            id: window
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:session"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            // Flipped after creation, so the scrim's Behavior is live for the enter.
            property bool shown: false

            function sync() {
                window.shown = GlobalStates.sessionOpen;
                if (window.shown)
                    motion.open();
                else
                    motion.close();
            }

            Component.onCompleted: window.sync()

            Connections {
                target: GlobalStates
                function onSessionOpenChanged() {
                    window.sync();
                }
            }

            // The scrim (DESIGN.md 6.2), and a press anywhere off the card puts the
            // menu away.
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colScrim
                opacity: window.shown ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onPressed: GlobalStates.sessionOpen = false
                }
            }

            StyledRectangularShadow {
                target: card
                scale: card.scale
                transformOrigin: card.transformOrigin
                opacity: card.opacity
            }

            Rectangle {
                id: card
                // A dialog pads 12-16 (DESIGN.md 5.2).
                readonly property real padding: 16

                anchors.centerIn: parent
                width: root.columns * (root.tileSize + root.tileGap) + card.padding * 2
                implicitHeight: content.implicitHeight + card.padding * 2
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
                radius: Appearance.rounding.verylarge
                // Layer 2, opaque, as WindowDialog paints its card: the labels are
                // colOnLayer2, and nothing is beneath the card but the scrim.
                color: Appearance.colors.colLayer2Base

                // It pops out of the middle of the screen on the shell's popup motion,
                // not WindowDialog's slide. It is opened from a keybind or from a
                // button nowhere near where it appears, so the centre is the only
                // honest origin (DESIGN.md 2.6).
                transformOrigin: Item.Center
                scale: Appearance.animationCurves.arrowPopupScale
                opacity: 0

                ArrowPopupMotion {
                    id: motion
                    target: card
                    // The close is what unmaps the window, not the request.
                    onClosed: {
                        // The blackout fires its own action and releases the window.
                        if (root.blackout)
                            return;
                        const action = root.pendingAction;
                        root.pendingAction = null;
                        action?.run();
                        if (!GlobalStates.sessionOpen)
                            root.rendered = false;
                    }
                }

                Keys.onEscapePressed: GlobalStates.sessionOpen = false

                // A press on the card is not a press on the scrim.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                }

                ColumnLayout {
                    id: content
                    anchors {
                        fill: parent
                        margins: card.padding
                    }
                    spacing: 16

                    GridLayout {
                        id: grid
                        Layout.alignment: Qt.AlignHCenter
                        columns: root.columns
                        columnSpacing: 0
                        rowSpacing: root.tileGap

                        function move(from, step) {
                            for (let to = from + step; root.inReach(from, to, step); to += step) {
                                const tile = tiles.itemAt(to).tile;
                                if (tile.enabled) {
                                    tile.forceActiveFocus();
                                    return;
                                }
                            }
                        }

                        Repeater {
                            id: tiles
                            model: root.actions

                            delegate: ColumnLayout {
                                id: action
                                required property var modelData
                                required property int index
                                property alias tile: tile

                                // A column is a tile plus the gap either side of it, so the
                                // label can run as wide as the tiles are far apart.
                                Layout.preferredWidth: root.tileSize + root.tileGap
                                Layout.alignment: Qt.AlignTop
                                spacing: root.labelGap

                                RippleButton {
                                    id: tile
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: root.tileSize
                                    implicitHeight: root.tileSize
                                    padding: 0
                                    focus: action.index === 0
                                    enabled: SessionWarnings.can(action.modelData.can)

                                    // Focus is selection here: the one primary, round tile
                                    // is the one Enter fires (SelectedContainerShapeSquare is
                                    // CornerFull). Hover only tints, and never takes focus --
                                    // the pointer is usually resting where the card opens.
                                    toggled: tile.activeFocus
                                    buttonRadius: tile.toggled ? Math.min(tile.height / 2, Appearance.rounding.full) : Appearance.rounding.large
                                    colBackground: Appearance.colors.colSecondaryContainer
                                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                    colRipple: Appearance.colors.colSecondaryContainerActive
                                    colStateLayer: tile.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                    // A press selects too, so the tile lit while the dialog
                                    // leaves is the one that was chosen. That is also why there
                                    // is no pressed shape: the pressed tile always rests round,
                                    // and squaring a circle on press reads as a glitch (4.3).
                                    downAction: () => tile.forceActiveFocus()
                                    onClicked: root.run(action.modelData)

                                    Keys.onPressed: event => {
                                        switch (event.key) {
                                        case Qt.Key_Return:
                                        case Qt.Key_Enter:
                                            tile.click();
                                            break;
                                        case Qt.Key_Left:
                                            grid.move(action.index, -1);
                                            break;
                                        case Qt.Key_Right:
                                            grid.move(action.index, 1);
                                            break;
                                        case Qt.Key_Up:
                                            grid.move(action.index, -root.columns);
                                            break;
                                        case Qt.Key_Down:
                                            grid.move(action.index, root.columns);
                                            break;
                                        default:
                                            return; // Esc goes on to the card
                                        }
                                        event.accepted = true;
                                    }

                                    contentItem: MaterialSymbol {
                                        horizontalAlignment: Text.AlignHCenter
                                        iconSize: root.tileIconSize
                                        text: action.modelData.icon
                                        color: tile.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                        Behavior on color {
                                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    color: Appearance.colors.colOnLayer2
                                    opacity: tile.enabled ? 1 : 0.4
                                    Behavior on opacity {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                    text: action.modelData.name
                                }
                            }
                        }
                    }

                    // Killing every window is what both of these are about, so they sit
                    // under the row that does it, in the error tone NoticeBox keeps for
                    // failures -- a "warning" icon alone would make them neutral notices.
                    // Their own column, at ContentGroup's row gap: NoticeBox joins the
                    // siblings it finds into one run, and at the dialog's 16 the joined
                    // seams read as two cards with squared-off corners.
                    ColumnLayout {
                        visible: SessionWarnings.packageManagerRunning || SessionWarnings.downloadRunning
                        Layout.fillWidth: true
                        spacing: 4

                        NoticeBox {
                            visible: SessionWarnings.packageManagerRunning
                            error: true
                            materialIcon: "warning"
                            text: Translation.tr("Your package manager is running")
                        }
                        NoticeBox {
                            visible: SessionWarnings.downloadRunning
                            error: true
                            materialIcon: "warning"
                            text: Translation.tr("There might be a download in progress. Check your Downloads folder.")
                        }
                    }
                }
            }

            // Fade to black, then act. Sleep and hibernate wake up to this black, so
            // any key or pointer motion afterwards fades it back out and unmaps.
            Rectangle {
                id: blackout
                // Armed once the action has fired; input before that is the dialog's.
                property bool armed: false

                anchors.fill: parent
                color: Appearance.m3colors.m3scrim
                opacity: 0
                visible: opacity > 0

                Connections {
                    target: root
                    function onBlackoutChanged() {
                        if (root.blackout) {
                            fadeOut.stop();
                            fadeIn.restart();
                            return;
                        }
                        blackout.armed = false;
                        fadeIn.stop();
                        fadeOut.restart();
                    }
                }

                // Sleep locks on the way down, and the lock surface is see-through
                // to the wallpaper: left up, this black is the lock screen's wallpaper,
                // and the input that would clear it goes to the lock instead.
                Connections {
                    target: GlobalStates
                    function onScreenLockedChanged() {
                        if (GlobalStates.screenLocked && blackout.armed)
                            root.blackout = false;
                    }
                }

                NumberAnimation {
                    id: fadeIn
                    target: blackout
                    property: "opacity"
                    to: 1
                    duration: Appearance.animationCurves.expressiveSlowEffectsDuration
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                    onFinished: {
                        const action = root.pendingAction;
                        root.pendingAction = null;
                        action?.run();
                        blackout.armed = true;
                        blackout.forceActiveFocus();
                    }
                }

                NumberAnimation {
                    id: fadeOut
                    target: blackout
                    property: "opacity"
                    to: 0
                    duration: Appearance.animationCurves.expressiveFastEffectsDuration
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                    // The card closed long ago; this is the exit finishing now.
                    onFinished: motion.closed()
                }

                Keys.onPressed: event => {
                    if (blackout.armed)
                        root.blackout = false;
                    event.accepted = true;
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    hoverEnabled: true
                    onPositionChanged: {
                        if (blackout.armed)
                            root.blackout = false;
                    }
                    onPressed: {
                        if (blackout.armed)
                            root.blackout = false;
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }

        function close(): void {
            GlobalStates.sessionOpen = false;
        }

        function open(): void {
            GlobalStates.sessionOpen = true;
        }
    }

    GlobalShortcut {
        name: "sessionToggle"
        description: "Toggles session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }
    }

    GlobalShortcut {
        name: "sessionOpen"
        description: "Opens session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = true;
        }
    }

    GlobalShortcut {
        name: "sessionClose"
        description: "Closes session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = false;
        }
    }
}
