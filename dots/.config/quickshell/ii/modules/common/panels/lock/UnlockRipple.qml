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
 * RippleShader it drives (shaders/unlockRipple.frag); none were tuned.
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

    // Linear play fraction; the ValueAnimator's currentPlayTime.
    property real t: 0
    // The ValueAnimator sets no interpolator, so it is Android's default,
    // AccelerateDecelerate -- which is exactly InOutSine.
    readonly property real rawProgress: 0.5 - Math.cos(Math.PI * t) / 2
    // RippleShader.progress: Interpolators.STANDARD over rawProgress.
    readonly property real progress: standard(rawProgress)

    // PathInterpolator(0.2, 0, 0, 1). x(u) only rises, so halving the interval
    // finds u to well under a pixel in 16 steps.
    function standard(x) {
        let lo = 0, hi = 1;
        for (let i = 0; i < 16; i++) {
            const u = (lo + hi) / 2;
            if (0.6 * u * (1 - u) * (1 - u) + u * u * u < x) lo = u; else hi = u;
        }
        const u = (lo + hi) / 2;
        return 3 * u * u - 2 * u * u * u;
    }
    // RippleShader.getFade: linear in, linear out, on rawProgress.
    function fade(inStart, inEnd, outStart, outEnd) {
        const sub = (a, b) => a === b ? (rawProgress > a ? 1 : 0) : (Math.min(Math.max(rawProgress, a), b) - a) / (b - a);
        return Math.min(sub(inStart, inEnd), 1 - sub(outStart, outEnd));
    }

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

                ShaderEffect {
                    anchors.fill: parent
                    fragmentShader: Qt.resolvedUrl("../../widgets/shaders/unlockRipple.frag.qsb")

                    property vector2d resolution: Qt.vector2d(width * win.dpr, height * win.dpr)
                    property vector2d center: Qt.vector2d(win.origin.x * win.dpr, win.origin.y * win.dpr)
                    // AuthRippleView.radius: 0.9 of the farthest edge from the origin.
                    property real radius: 0.9 * Math.max(win.origin.x, win.origin.y, width - win.origin.x, height - win.origin.y) * win.dpr * root.progress
                    property real time: root.t * root.duration
                    // AuthRippleView.updateRippleFadeParams; the sparkle ring keeps RippleShader's default.
                    property real fadeSparkle: root.fade(0, 0.1, 0.4, 1)
                    property real fadeFill: root.fade(0, 0.15, 0.15, 0.56)
                    property real fadeRing: root.fade(0, 0.2, 0.2, 1)
                    property real blur: 1.25 + (0.5 - 1.25) * root.progress
                    property real pixelDensity: win.dpr
                    property color color: root.color
                    // AuthRippleView's RIPPLE_SPARKLE_STRENGTH
                    property real sparkleStrength: 0.3
                }
            }
        }
    }
}
