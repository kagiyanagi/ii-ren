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
    // The card's height while shown. The dialogs built around a list set a fixed
    // one; the default follows the content, live. It used to read the card's own
    // height, which onShowChanged then overwrote with a snapshot, so a row that
    // appeared after the dialog opened -- KeybindEditor's conflict warning,
    // polkit's status line -- was laid out past the card's bottom edge, and a
    // dialog reopened without a Loader came back at zero.
    property real backgroundHeight: contentColumn.implicitHeight + root.dialogPadding * 2
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
    // Ctrl+R; a dialog with a list to reload handles it, the rest ignore it.
    signal refreshRequested()
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.dismiss();
            event.accepted = true;
        } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
            root.refreshRequested();
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
        dialogBackground.implicitHeight = show ? Qt.binding(() => root.backgroundHeight) : 0
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

    // A dialog sits at elevation 3, M3's dialog level (DESIGN.md 6.2). Declared before the surface
    // so it paints behind it, and cached, so the scrim costs one effect total.
    StyledRectangularShadow {
        target: dialogBackground
    }

    Rectangle {
        id: dialogBackground
        anchors.horizontalCenter: parent.horizontalCenter
        radius: Appearance.rounding.verylarge
        // Layer 2, opaque -- and it has to be layer 2, because everything written
        // for this dialog paints one step above it: the Wi-Fi, Bluetooth, volume
        // and selection list cards are `colSurfaceContainerHigh`, whose base is
        // `m3surfaceContainer`, and `DialogListItem`, `DialogButton` and every
        // `ContentGroup` card inside a dialog take their fills and state films
        // from layer 3, off the same base. At layer 3 the card was the colour
        // those tokens solve *to*, so a content card composited onto its own
        // parent and vanished; only `1 - contentTransparency` = 0.1 was keeping
        // it apart, and it stopped being 0.1 when transparency was switched off.
        color: Appearance.colors.colLayer2Base

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
