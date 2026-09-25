import QtQuick
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property string tooltip: ""

    property color bgColor: Appearance.colors.colSecondaryContainer
    property color fgColor: Appearance.colors.colOnSecondaryContainer

    radius: Appearance.rounding.full
    color: root.bgColor

    // Sized off the label's own implicitWidth: childrenRect.width read the
    // children this width lays out, which was a binding loop on every card.
    implicitWidth: root.icon.length > 0 ? 36 : labelText.implicitWidth + 20
    implicitHeight: 24

    MaterialSymbol {
        visible: root.icon.length > 0
        anchors.centerIn: parent
        text: root.icon
        iconSize: 16
        color: root.fgColor
    }

    StyledText {
        id: labelText
        visible: root.icon.length === 0
        text: root.label
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: root.fgColor
        anchors.centerIn: parent
    }

    HoverHandler {
        id: hover
    }

    StyledToolTip {
        extraVisibleCondition: hover.hovered
        text: root.tooltip
    }
}
