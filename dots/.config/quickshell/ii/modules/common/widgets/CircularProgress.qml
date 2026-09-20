import QtQuick
import QtQuick.Shapes
import qs.modules.common

/**
 * Material 3 circular progress. See https://m3.material.io/components/progress-indicators/specs
 */
Item {
    id: root

    property int implicitSize: 30
    property int lineWidth: 2
    property real value: 0
    property color colPrimary: Appearance.m3colors.m3onSecondaryContainer
    property color colSecondary: Appearance.colors.colSecondaryContainer
    property real gapAngle: 360 / 18
    property bool fill: false
    property bool enableAnimation: true

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    property real degree: value * 360
    property real centerX: root.width / 2
    property real centerY: root.height / 2
    property real arcRadius: root.implicitSize / 2 - root.lineWidth
    property real startAngle: -90

    // The sweep is geometry, so 2.1 would put it on a spatial spec - but a
    // determinate indicator must not overshoot. AOSP animates progress with
    // ProgressIndicatorDefaults.ProgressAnimationSpec, a DampingRatioNoBouncy
    // spring (ProgressIndicator.kt), because a ring that swings past the value
    // and comes back is reporting a number that never happened.
    // elementMoveFast is this repo's critically damped spec.
    Behavior on degree {
        enabled: root.enableAnimation
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Loader {
        active: root.fill
        anchors.fill: parent

        sourceComponent: Rectangle {
            radius: Appearance.rounding.full
            color: root.colSecondary
        }
    }

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            id: secondaryPath
            strokeColor: root.colSecondary
            strokeWidth: root.lineWidth
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.centerX
                centerY: root.centerY
                radiusX: root.arcRadius
                radiusY: root.arcRadius
                startAngle: root.startAngle - root.gapAngle
                sweepAngle: -(360 - root.degree - 2 * root.gapAngle)
            }
        }
        ShapePath {
            id: primaryPath
            strokeColor: root.colPrimary
            strokeWidth: root.lineWidth
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.centerX
                centerY: root.centerY
                radiusX: root.arcRadius
                radiusY: root.arcRadius
                startAngle: root.startAngle
                sweepAngle: root.degree
            }
        }
    }

}
