import QtQuick
import qs.modules.common

Item {
    id: effect
    property Item frontImg
    property Item backImg
    // Parameterised on purpose -- TransitionImage always binds this from
    // Config.options.background, so the default only matters for a caller
    // that instantiates the effect directly. expressiveSlowSpatialDuration:
    // this is a full-screen crossing, same category as the other wipes.
    property int duration: Appearance.animationCurves.expressiveSlowSpatialDuration

    property bool hideFront: false
    property bool waitForReady: false
    signal finished()

    function start() {
        frontImg.opacity = 0
        fadeAnim.restart()
    }

    function cleanup() {
        fadeAnim.stop()
    }

    NumberAnimation {
        id: fadeAnim
        target: effect.frontImg
        property: "opacity"
        from: 0
        to: 1
        duration: effect.duration
        // Linear: the two images are weighted evenly across the duration, which
        // is what a crossfade is and what AOSP's own wallpaper crossfade does.
        // expressiveEffects was 90% faded by the halfway point, so the second
        // half was the old wallpaper sitting under 10% opacity -- invisible, but
        // still counted against the duration. Never overshoots, as opacity must
        // not (DESIGN.md 3).
        easing.type: Easing.Linear
        onFinished: effect.finished()
    }
}
