import qs.modules.common
import QtQuick

RippleButton {
    id: root

    buttonRadius: 0
    implicitHeight: 36
    implicitWidth: buttonTextWidget.implicitWidth + root.padding * 2

    padding: 16

    contentItem: StyledText {
        id: buttonTextWidget
        anchors.fill: parent
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        text: root.buttonText
        horizontalAlignment: Text.AlignLeft
        font.pixelSize: Appearance.font.pixelSize.small
        color: root.enabled ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

}
