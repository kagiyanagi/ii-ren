import QtQuick
import QtQuick.Window

/**
 * SystemUI's RippleShader (CIRCLE, shaders/unlockRipple.frag) as RippleView
 * plays it: one linear `t` from 0 to 1, everything else derived from it the
 * way the Kotlin does. UnlockRipple (AuthRippleView) and ChargingRipple
 * (WiredChargingRippleController) differ only in what they set here; the
 * defaults are RippleShader's own.
 */
ShaderEffect {
    id: root

    // Linear play fraction; the ValueAnimator's currentPlayTime over duration.
    property real t: 0
    property int duration
    // Logical px, in this item's coordinates.
    property point origin: Qt.point(width / 2, height / 2)
    // The radius at progress 1 (in_size.x * 0.5), logical px.
    property real maxRadius
    property real dpr: Screen.devicePixelRatio
    property color color
    // FadeParams: [fadeInStart, fadeInEnd, fadeOutStart, fadeOutEnd] on rawProgress.
    property var sparkleFade: [0, 0.1, 0.4, 1]
    property var ringFade: [0, 0.1, 0.3, 1]
    property var fillFade: [0, 0, 0, 0.6]
    // RippleView.startRipple sets distortionStrength to 1 - rawProgress;
    // AuthRippleView runs its own animator and leaves it at 0.
    property bool distorted: false

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
    function fade(f) {
        const sub = (a, b) => a === b ? (rawProgress > a ? 1 : 0) : (Math.min(Math.max(rawProgress, a), b) - a) / (b - a);
        return Math.min(sub(f[0], f[1]), 1 - sub(f[2], f[3]));
    }

    fragmentShader: Qt.resolvedUrl("../../widgets/shaders/unlockRipple.frag.qsb")

    property vector2d resolution: Qt.vector2d(width * dpr, height * dpr)
    property vector2d center: Qt.vector2d(origin.x * dpr, origin.y * dpr)
    property real radius: maxRadius * dpr * progress
    property real time: t * duration
    property real fadeSparkle: fade(sparkleFade)
    property real fadeFill: fade(fillFade)
    property real fadeRing: fade(ringFade)
    property real blur: 1.25 + (0.5 - 1.25) * progress
    property real pixelDensity: dpr
    // RippleShader.RIPPLE_SPARKLE_STRENGTH
    property real sparkleStrength: 0.3
    // RippleShader.distortionStrength, in physical px as on the phone.
    property real distortRadial: distorted ? 75 * rawProgress * (1 - rawProgress) : 0
    property real distortXy: distorted ? 75 * (1 - rawProgress) : 0
}
