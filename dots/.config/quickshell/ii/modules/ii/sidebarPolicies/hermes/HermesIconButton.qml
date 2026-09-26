import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The one icon button of the Hermes sheets: transparent at rest, a film on
 * hover and press, round. Its tokens are layer 1's, the sheet it sits on; a
 * caller on a layer 2 card passes that card's hover and ripple instead.
 */
RippleButton {
    id: root

    required property string symbol
    property string tooltip: ""
    property color iconColor: Appearance.colors.colOnLayer1

    implicitWidth: 32
    implicitHeight: 32
    buttonRadius: Appearance.rounding.full
    colBackground: "transparent"

    contentItem: MaterialSymbol {
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.symbol
        iconSize: Appearance.font.pixelSize.larger
        color: root.iconColor
    }

    StyledToolTip {
        text: root.tooltip
        extraVisibleCondition: root.tooltip.length > 0
    }
}
