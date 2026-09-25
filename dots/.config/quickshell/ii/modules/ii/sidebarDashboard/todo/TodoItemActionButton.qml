import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// An icon button on a task row, which is a layer-2 card: 32px is the minimum
// hit area (DESIGN.md 3.4), round per the icon-button recipe (9).
RippleButton {
    id: button
    property string materialIcon
    property real iconFill: 0
    property color colIcon: Appearance.colors.colOnLayer2

    implicitHeight: 32
    implicitWidth: implicitHeight
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    colStateLayer: Appearance.colors.colOnLayer2

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: button.materialIcon
        iconSize: Appearance.font.pixelSize.larger
        fill: button.iconFill
        color: button.colIcon
    }
}
