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
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.expressiveEffects // opacity: never overshoot
        onFinished: effect.finished()
    }
}
