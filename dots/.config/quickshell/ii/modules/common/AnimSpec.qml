import QtQuick
pragma ComponentBehavior: Bound

/**
 * One entry of Appearance.animation: the easing numbers plus ready-made
 * NumberAnimation/ColorAnimation Components bound to them, so callers can do
 * `Appearance.animation.elementMove.numberAnimation.createObject(this)`.
 */
QtObject {
    id: spec
    property int duration: 200
    property int type: Easing.BezierSpline
    property list<real> bezierCurve
    property int velocity: 650
    property bool alwaysRunToEnd: true

    property Component numberAnimation: Component {
        NumberAnimation {
            alwaysRunToEnd: spec.alwaysRunToEnd
            duration: spec.duration
            easing.type: spec.type
            easing.bezierCurve: spec.bezierCurve
        }
    }

    property Component colorAnimation: Component {
        ColorAnimation {
            duration: spec.duration
            easing.type: spec.type
            easing.bezierCurve: spec.bezierCurve
        }
    }
}
