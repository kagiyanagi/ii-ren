import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root

    property real buttonSize: Appearance.sizes.dockButtonSize

    width: buttonSize
    height: buttonSize
    buttonRadius: Appearance.rounding.normal
    background.implicitWidth: buttonSize
    background.implicitHeight: buttonSize
    padding: 0

    rippleEnabled: false
    colBackground: "transparent"
    colBackgroundHover: "transparent"
    colBackgroundToggled: "transparent"
    colBackgroundToggledHover: "transparent"

    // Click feedback: squish in, then spring back - clickBounce's curve
    // overshoots past 1, so the pop back out comes for free.
    function bounce() {
        bounceAnim.restart()
    }

    SequentialAnimation {
        id: bounceAnim
        NumberAnimation {
            target: root
            property: "scale"
            to: 0.88
            duration: 90
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "scale"
            to: 1.0
            duration: Appearance.animation.clickBounce.duration
            easing.type: Appearance.animation.clickBounce.type
            easing.bezierCurve: Appearance.animation.clickBounce.bezierCurve
        }
    }
}
