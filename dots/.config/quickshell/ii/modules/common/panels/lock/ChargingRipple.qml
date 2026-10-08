pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland

/**
 * Android's wired charging ripple: a ring of sparkles out of the charger port
 * as the cable goes in, across the whole screen. A laptop's port is wherever
 * battery.chargingRipple says. Every number is AOSP's
 * WiredChargingRippleController and the RippleView it plays (SparkleRipple);
 * none were tuned.
 *
 * Its own click-through overlay on the desktop, as on the phone. A session
 * lock hides every layer, so while locked the lock surface hosts `effect`
 * instead (LockScreen.qml).
 */
Scope {
    id: root

    // RippleView.duration
    readonly property int duration: 1750
    property real t: 0
    readonly property bool running: rippleAnim.running
    // physical_charger_port_location_normalized_x/y for the side it plays from.
    property string from
    readonly property point port: ({ bottomLeft: Qt.point(0, 1), bottomRight: Qt.point(1, 1) })[from] ?? Qt.point(0.5, 0.5)

    property Component effect: SparkleRipple {
        t: root.t
        duration: root.duration
        origin: Qt.point(width * root.port.x, height * root.port.y)
        // layoutRipple: setMaxSize(max(width, height) * 2), a diameter.
        maxRadius: Math.max(width, height)
        distorted: true
        // colorAccent at RippleShader.RIPPLE_DEFAULT_ALPHA.
        color: Qt.alpha(Appearance.m3colors.m3primary, 115 / 255)
    }

    // startRipple: ignored while one is still playing.
    function play(from) {
        if (rippleAnim.running)
            return;
        root.from = from;
        rippleAnim.start();
    }

    // registerCallbacks: only the edge into plugged in. UPower says Unknown
    // before anything else, so a shell started on the charger would read as
    // one; it counts only after the battery was seen discharging.
    property bool wasOnBattery: false
    Connections {
        target: Battery
        function onChargeStateChanged() {
            if (Battery.chargeState === UPowerDeviceState.Discharging || Battery.chargeState === UPowerDeviceState.Empty)
                root.wasOnBattery = true;
        }
        function onIsPluggedInChanged() {
            if (!Battery.isPluggedIn || !root.wasOnBattery)
                return;
            root.wasOnBattery = false;
            if (Config.options.battery.chargingRipple !== "off")
                root.play(Config.options.battery.chargingRipple);
        }
    }

    // AOSP's `cmd statusbar charging-ripple`; settings previews a side with it.
    // A preview restarts from the newly picked side rather than being dropped
    // while the last one still plays.
    IpcHandler {
        target: "chargingRipple"
        function play(from: string): void {
            root.from = from;
            rippleAnim.restart();
        }
    }

    NumberAnimation {
        id: rippleAnim
        target: root
        property: "t"
        from: 0
        to: 1
        duration: root.duration
    }

    LazyLoader {
        active: rippleAnim.running && !GlobalStates.screenLocked

        Variants {
            model: Quickshell.screens

            PanelWindow {
                required property ShellScreen modelData

                screen: modelData
                color: "transparent"
                WlrLayershell.namespace: "quickshell:chargingRipple"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                anchors {
                    left: true
                    right: true
                    top: true
                    bottom: true
                }
                mask: Region {}

                Loader {
                    anchors.fill: parent
                    sourceComponent: root.effect
                }
            }
        }
    }
}
