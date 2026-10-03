pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.modules.common
import qs.modules.waffle.looks

SequentialAnimation {
    id: root

    required property Item target
    signal dismissed

    NumberAnimation {
        target: root.target
        property: "x"
        to: root.target.width
        duration: Looks.duration.fast
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
    }
    ScriptAction {
        script: root.dismissed()
    }
}
