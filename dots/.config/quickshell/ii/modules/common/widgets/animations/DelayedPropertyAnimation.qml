import QtQuick
import QtQuick.Layouts
import qs.modules.common

// Duration/easing are parameterised on purpose (a caller runs this on whatever
// property needs a head start), but an unparameterised caller should not fall
// through to Qt's bare 250ms-linear PropertyAnimation default -- that is a
// duration nobody chose. elementMove ("the default for position and size",
// DESIGN.md 2.3) is the neutral default; callers still override freely.
SequentialAnimation {
    id: root

    property alias target: anim.target
    property alias property: anim.property

    property int delay: 0
    property alias from: anim.from
    property alias to: anim.to
    property alias duration: anim.duration
    property alias easing: anim.easing

    PauseAnimation {
        duration: root.delay
    }

    PropertyAnimation {
        id: anim
        duration: Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
    }
}