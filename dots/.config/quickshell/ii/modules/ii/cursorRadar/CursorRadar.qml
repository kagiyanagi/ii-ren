pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

/**
 * Shake to find the pointer (macOS's "shake mouse pointer to locate"): wiggle the
 * mouse and a ring closes in on it, follows it while the shake lasts, then lets go.
 * The shake is spotted inside Hyprland (services/cursorShake.lua), which only talks
 * to the shell while one is live; this draws the ring and installs that half again
 * after every config reload, since a reload starts a fresh Lua state.
 */
Scope {
    id: root

    readonly property string event: "iiCursorShake"
    readonly property string luaPath: FileUtils.trimFileProtocol(Qt.resolvedUrl("../../../services/cursorShake.lua"))
    property bool shown: false
    property point pos

    function hyprEval(lua) {
        Quickshell.execDetached(["hyprctl", "eval", lua]);
    }

    function install() {
        root.hyprEval("ii_cs_lib = dofile([==[" + root.luaPath + "]==]); ii_cs_lib.install()");
    }

    Component.onCompleted: root.install()
    Component.onDestruction: root.hyprEval("if ii_cs_lib then ii_cs_lib.stop() end")

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                root.install();
                return;
            }
            if (event.name !== "custom" || !event.data.startsWith(root.event + ">>"))
                return;
            const data = event.data.slice(root.event.length + 2);
            if (data === "off") {
                root.shown = false;
                return;
            }
            const xy = data.split(" ").map(Number);
            root.pos = Qt.point(xy[0], xy[1]);
            root.shown = true;
        }
    }

    PanelWindow {
        id: radarWindow

        // Whichever screen the pointer is on, in Hyprland's global logical coordinates.
        screen: Quickshell.screens.find(s => root.pos.x >= s.x && root.pos.x < s.x + s.width && root.pos.y >= s.y && root.pos.y < s.y + s.height) ?? null
        visible: root.shown || ring.opacity > 0
        color: "transparent"

        WlrLayershell.namespace: "quickshell:cursorRadar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors {
            left: true
            right: true
            top: true
            bottom: true
        }
        // Draws over everything, takes no input.
        mask: Region {}

        Rectangle {
            id: ring

            // A bound property with a change handler, not a Connections: one declared
            // inside a PanelWindow never sees the signal.
            readonly property bool ringShown: root.shown
            // KWin's Shake Cursor blows the pointer up to 3x (shakecursorconfig.kcfg,
            // Magnification); the ring closes in from that same reach.
            readonly property real startScale: 3

            // Bound straight to the pointer, no Behavior: the ring is the pointer's,
            // and easing it would leave it trailing behind (DESIGN.md 2.9).
            x: root.pos.x - (radarWindow.screen?.x ?? 0) - width / 2
            y: root.pos.y - (radarWindow.screen?.y ?? 0) - height / 2
            width: 128
            height: 128
            radius: Appearance.rounding.full
            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.75)
            border.width: 4
            border.color: Appearance.colors.colPrimary

            // Starts wide and closes in on the pointer, which is the centre.
            transformOrigin: Item.Center
            scale: ring.startScale
            opacity: 0

            onRingShownChanged: {
                if (ring.ringShown) {
                    closeAnim.stop();
                    openAnim.restart();
                } else {
                    openAnim.stop();
                    closeAnim.restart();
                }
            }

            // Enter: default spatial, a component answering input, so the spring fit
            // and its small overshoot as it locks on; the fade lands first so the ring
            // is seen while it is still closing in.
            ParallelAnimation {
                id: openAnim

                NumberAnimation {
                    target: ring
                    property: "scale"
                    to: 1
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                }
                NumberAnimation {
                    target: ring
                    property: "opacity"
                    to: 1
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                }
            }

            // Exit: shrinks into the pointer, accelerating, on fast effects.
            ParallelAnimation {
                id: closeAnim

                NumberAnimation {
                    target: ring
                    property: "scale"
                    to: 0.5
                    duration: Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                }
                NumberAnimation {
                    target: ring
                    property: "opacity"
                    to: 0
                    duration: Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                }

                // Invisible by now: the next shake closes in from wide again (2.7).
                onFinished: ring.scale = ring.startScale
            }
        }
    }
}
