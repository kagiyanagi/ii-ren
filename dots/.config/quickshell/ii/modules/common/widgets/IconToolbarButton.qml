import QtQuick
import QtQuick.Layouts
import qs.modules.common

ToolbarButton {
    id: iconBtn
    implicitWidth: height

    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    // The film RippleButton composites for focus and for a press with no colour
    // of its own is the content colour of whatever the button is filled with.
    colStateLayer: toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
    property color colText: toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
    property bool iconFill: false

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        iconSize: Appearance.font.pixelSize.huge
        text: iconBtn.text
        fill: iconBtn.iconFill ? 1 : 0
        color: iconBtn.colText
        animateChange: true
    }
}
