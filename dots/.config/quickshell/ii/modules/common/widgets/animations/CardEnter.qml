import QtQuick
import qs.modules.common

// One card's entrance, for a surface whose cards come in together: the weather
// popup and the cheatsheet's weather page. Siblings are offset by staggerStep
// and capped (DESIGN.md 2.8), each with opacity on an effects spec and exactly
// one transform on a spatial one (2.1). The two PropertyActions are the reset
// 2.7 asks for, at the head of the animation rather than in a handler
// somewhere - the previous entrance's final frame is what a replay would
// otherwise show for the length of the stagger.
//
// There is no matching exit, deliberately: both callers leave as one surface
// (the popup scales and fades out, the cheatsheet page slides), and a second
// fade inside it reads as a stutter rather than as the content leaving.
SequentialAnimation {
    id: entrance

    required property Item card
    required property Translate shift
    required property int slot

    // How far the card travels into place: a short move toward where it
    // belongs, not a slide in from off the surface.
    property int travel: 12

    PropertyAction {
        target: entrance.card
        property: "opacity"
        value: 0
    }
    PropertyAction {
        target: entrance.shift
        property: "y"
        value: entrance.travel
    }
    PauseAnimation {
        duration: Appearance.animation.staggerStep * Math.min(entrance.slot, Appearance.animation.staggerCap)
    }
    ParallelAnimation {
        NumberAnimation {
            target: entrance.card
            property: "opacity"
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
        NumberAnimation {
            target: entrance.shift
            property: "y"
            to: 0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
        }
    }
}
