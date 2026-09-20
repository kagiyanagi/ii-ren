import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: root
    property bool active: false

    // Was Appearance.rounding.large, which is a radius token: sharp mode zeroes
    // the rounding scale, so the row lost all of its horizontal padding and the
    // text sat flush against the dialog. 16 is the dialog padding (DESIGN.md 5.2).
    horizontalPadding: 16
    verticalPadding: 12

    clip: true
    pointingHandCursor: !active
    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
    implicitHeight: contentItem.implicitHeight + verticalPadding * 2
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3)
    colBackgroundHover: active ? colBackground : Appearance.colors.colLayer3Hover
    colRipple: Appearance.colors.colLayer3Active
    // The state film composites over layer 3, which is what this row paints on;
    // the default reads layer 1 and would be the wrong tone here. Focus and the
    // pressed film come from RippleButton itself.
    colStateLayer: Appearance.colors.colOnLayer3
    buttonRadius: 0
}
