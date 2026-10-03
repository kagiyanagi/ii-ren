pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Android's unlock ripple: a ring of sparkles that bursts out of where the
 * unlock came from to the edges of the screen, over the desktop coming back.
 * Here it comes out of the password field. Every number is AOSP's
 * AuthRippleView.startUnlockedRipple / AuthRippleController and the
 * RippleShader it drives (SparkleRipple); none were tuned.
 *
 * Its own overlay rather than part of the lock surface, as on the phone where
 * it lives in the shade window: the lock surface is gone a fade after the
 * password is right, and the ripple outlives it by most of its length.
 * Click-through, so the desktop is usable the moment the lock lets go.
 */
Scope {
    id: root
    required property LockContext context

    // AuthRippleController.RIPPLE_ANIMATION_DURATION
    readonly property int duration: 800
    // AuthRippleView.setLockScreenColor: wallpaperTextColorAccent (system
    // primary90 on the dark keyguard) at alpha 62.
    readonly property color color: Qt.alpha(Appearance.m3colors.m3primaryFixed, 62 / 255)

    // Linear play fraction; SparkleRipple derives the rest from it.
    property real t: 0

    Connections {
        target: GlobalStates
        function onScreenLockExitingChanged() {
            if (GlobalStates.screenLockExiting && Config.options.lock.unlockRipple)
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
        active: rippleAnim.running

        Variants {
            model: Quickshell.screens

            PanelWindow {
                id: win
                required property ShellScreen modelData
                readonly property real dpr: modelData.devicePixelRatio
                readonly property point origin: root.context.unlockOrigins[modelData.name] ?? Qt.point(width / 2, height / 2)

                screen: modelData
                color: "transparent"
                WlrLayershell.namespace: "quickshell:unlockRipple"
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

                SparkleRipple {
                    anchors.fill: parent
                    t: root.t
                    duration: root.duration
                    origin: win.origin
                    // AuthRippleView.radius: 0.9 of the farthest edge from the origin.
                    maxRadius: 0.9 * Math.max(win.origin.x, win.origin.y, width - win.origin.x, height - win.origin.y)
                    dpr: win.dpr
                    color: root.color
                    // AuthRippleView.updateRippleFadeParams; the sparkle ring keeps RippleShader's default.
                    fillFade: [0, 0.15, 0.15, 0.56]
                    ringFade: [0, 0.2, 0.2, 1]
                }
            }
        }
    }
}
