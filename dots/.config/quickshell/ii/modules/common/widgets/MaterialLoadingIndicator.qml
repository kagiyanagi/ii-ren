pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root

    property bool loading: true
    property double pullProgress: 0

    // Size, color
    property double implicitSize: 48
    implicitWidth: implicitSize
    implicitHeight: implicitSize
    radius: Math.min(width, height) / 2
    color: Appearance.colors.colPrimaryContainer
    property double baseShapeSize: root.implicitSize * 0.7
    property double leapZoomSize: root.baseShapeSize * 1.2
    property double leapZoomProgress: 0
    property color shapeColor: Appearance.colors.colOnPrimaryContainer

    // Shape
    property list<var> shapes: [
        MaterialShape.Shape.SoftBurst,
        MaterialShape.Shape.Cookie9Sided,
        MaterialShape.Shape.Pentagon,
        MaterialShape.Shape.Pill,
        MaterialShape.Shape.Sunny,
        MaterialShape.Shape.Cookie4Sided,
        MaterialShape.Shape.Oval,
    ]
    property int shapeIndex: 0
    property double pullRotation: root.loading ? 0 : -(root.pullProgress * 360)
    property double continuousRotation: 0
    property double leapRotation: 0
    rotation: pullRotation + continuousRotation + leapRotation

    // Hidden is not loading. One parked behind `visible: false` -- the Hermes
    // page's activity line, for as long as the shell ran -- kept turning and
    // morphing, and ticked the GUI thread every frame for it.
    readonly property bool animating: root.loading && root.visible

    // One full turn, repeating. The 12000 this replaces was a hand pick.
    RotationAnimation on continuousRotation {
        running: root.animating
        // AOSP LoadingIndicator.kt: GlobalRotationDurationMillis, LinearEasing.
        duration: 4666
        easing.type: Easing.Linear
        loops: Animation.Infinite
        from: 0
        to: 360
    }

    // AOSP MorphIntervalMillis: a morph starts every 650ms, and its spring is
    // required to have settled before the next one does. Both animations below
    // run on elementMoveSmall (350), so they do.
    Timer {
        interval: 650
        running: root.animating
        repeat: true
        onTriggered: leapAnimation.start()
    }
    ParallelAnimation {
        id: leapAnimation
        PropertyAction { target: root; property: "shapeIndex"; value: (root.shapeIndex + 1) % root.shapes.length }

        // AOSP turns by QuarterRotation per morph on a dampingRatio 0.6 /
        // stiffness 200 spring. 0.6 is the fast-spatial scheme's damping, so
        // elementMoveSmall is the token that carries this shape.
        RotationAnimation {
            target: root
            direction: RotationAnimation.Shortest
            property: "leapRotation"
            to: (root.leapRotation + 90) % 360
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }

        // The zoom pulse stands in for AOSP's shape morph, so it has to be done
        // before the next interval - at the old 750 against a 650 interval it
        // would be cut off mid-shrink and snap back to the base size.
        NumberAnimation {
            target: root
            property: "leapZoomProgress"
            from: 0
            to: 1
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.standard
        }
    }

    MaterialShape {
        id: shape
        anchors.centerIn: parent
        shape: root.shapes[root.shapeIndex]
        implicitSize: {
            const leapZoomDiff = root.leapZoomSize - root.baseShapeSize
            const progressFirstHalf = Math.min(root.leapZoomProgress, 0.5) * 2;
            const progressSecondHalf = Math.max(root.leapZoomProgress - 0.5, 0) * 2;
            return root.baseShapeSize + leapZoomDiff * progressFirstHalf - leapZoomDiff * progressSecondHalf;
        }
        color: root.shapeColor

        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
}
