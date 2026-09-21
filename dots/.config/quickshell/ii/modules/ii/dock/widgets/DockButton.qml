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

    // Launcher3 FastBitmapDrawable: HOVERED_SCALE 1.1 over HOVER_FEEDBACK_DURATION,
    // which is what Appearance.animation.iconHover holds.
    property real hoverScale: root.hovered ? 1.1 : 1.0
    // Launcher3 puts PRESSED_SCALE at 1.1 too, so on a pointer -- which is always hovering
    // before it clicks -- the press would be invisible. Keep the squish and multiply it in
    // on top of the hover scale instead, so both read.
    property real pressScale: 1.0
    scale: root.hoverScale * root.pressScale

    Behavior on hoverScale {
        animation: Appearance.animation.iconHover.numberAnimation.createObject(root)
    }

    // Click feedback: squish in, then spring back - clickBounce's curve
    // overshoots past 1, so the pop back out comes for free.
    function bounce() {
        bounceAnim.restart()
    }

    SequentialAnimation {
        id: bounceAnim
        NumberAnimation {
            target: root
            property: "pressScale"
            to: 0.88
            duration: Appearance.animation.iconPressSquish.duration
            easing.type: Appearance.animation.iconPressSquish.type
            easing.bezierCurve: Appearance.animation.iconPressSquish.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "pressScale"
            to: 1.0
            duration: Appearance.animation.clickBounce.duration
            easing.type: Appearance.animation.clickBounce.type
            easing.bezierCurve: Appearance.animation.clickBounce.bezierCurve
        }
    }
}
