import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root

    property bool show: false
    default property alias contentData: contentColumn.data
    property real backgroundHeight: dialogBackground.implicitHeight
    property real backgroundWidth: 350
    property real backgroundAnimationMovementDistance: 60
    // A dialog pads 12-16 (DESIGN.md 5.2). It used to reuse the container radius
    // as its padding, so bumping the radius to verylarge would have pushed the
    // content 30px off every edge; the two are separate numbers now.
    readonly property real dialogPadding: 16
    // Opacity must not overshoot, so the body fades on the effects specs, and
    // the exit takes the faster one (DESIGN.md 2.1, 2.5). Assigned from inside
    // the binding that writes opacity, per DESIGN.md 2.9 -- a Behavior reading
    // `show` directly bakes the spec one trigger late and exits on the enter.
    property AnimSpec fadeSpec: Appearance.animation.elementMoveFast

    signal dismiss()
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.dismiss();
            event.accepted = true;
        }
    }

    color: root.show ? Appearance.colors.colScrim : ColorUtils.transparentize(Appearance.colors.colScrim)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    visible: dialogBackground.implicitHeight > 0

    onShowChanged: {
        // Enter decelerates over the full spec, exit accelerates at about half
        // of it (DESIGN.md 2.5). Both are written here rather than bound, for
        // the same reason as fadeSpec above.
        dialogBackgroundHeightAnimation.duration = show ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMoveFast.duration / 2
        dialogBackgroundHeightAnimation.easing.bezierCurve = (show ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel)
        dialogBackground.implicitHeight = show ? backgroundHeight : 0
    }

    radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    MouseArea { // Clicking outside the dialog should dismiss
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.dismiss()
        onWheel: (wheel) => wheel.accepted = true
    }

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => event.accepted = true
    }

    // A dialog sits at elevation 5 (DESIGN.md 6.2). Declared before the surface
    // so it paints behind it, and cached, so the scrim costs one effect total.
    StyledRectangularShadow {
        target: dialogBackground
    }

    Rectangle {
        id: dialogBackground
        anchors.horizontalCenter: parent.horizontalCenter
        radius: Appearance.rounding.verylarge
        color: Appearance.m3colors.m3surfaceContainerHigh // Use opaque version of layer3

        property real targetY: root.height / 2 - root.backgroundHeight / 2
        y: root.show ? targetY : (targetY - root.backgroundAnimationMovementDistance)
        implicitWidth: root.backgroundWidth
        implicitHeight: contentColumn.implicitHeight + root.dialogPadding * 2
        Behavior on implicitHeight {
            NumberAnimation {
                id: dialogBackgroundHeightAnimation
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: dialogBackgroundHeightAnimation.duration
                easing.type: dialogBackgroundHeightAnimation.easing.type
                easing.bezierCurve: dialogBackgroundHeightAnimation.easing.bezierCurve
            }
        }

        MouseArea { // So clicking inside the dialog won't dismiss
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onWheel: (wheel) => wheel.accepted = true
        }

        ColumnLayout {
            id: contentColumn
            anchors {
                fill: parent
                margins: root.dialogPadding
            }
            spacing: 16
            opacity: {
                root.fadeSpec = root.show ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
                return root.show ? 1 : 0;
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: root.fadeSpec.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.fadeSpec.bezierCurve
                }
            }

        }
    }
}
