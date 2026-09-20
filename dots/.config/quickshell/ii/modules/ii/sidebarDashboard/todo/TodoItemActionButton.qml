import qs.modules.common
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: button
    property string materialIcon

    implicitHeight: 30
    implicitWidth: implicitHeight
    buttonRadius: Appearance.rounding.small

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: button.materialIcon
        iconSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colOnLayer1
    }
}
