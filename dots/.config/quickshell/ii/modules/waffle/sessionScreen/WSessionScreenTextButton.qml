pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.modules.waffle.looks

WTextButton {
    id: root

    implicitWidth: Math.max(160, contentItem.implicitWidth + horizontalPadding * 2)
    implicitHeight: 40
    horizontalPadding: 8

    property bool keyboardDown: false
    property alias focusRingRadius: focusRing.radius
    focusRingRadius: Looks.radius.medium + 4
    fgColor: (root.pressed || root.keyboardDown) ? Looks.darkColors.fg1 : Looks.darkColors.fg

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            keyboardDown = true;
            event.accepted = true;
        }
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            keyboardDown = false;
            root.clicked();
            event.accepted = true;
        }
    }

    contentItem: Item {
        id: contentItem
        implicitWidth: buttonText.implicitWidth
        implicitHeight: buttonText.implicitHeight

        WText {
            id: buttonText
            anchors.centerIn: parent
            color: root.fgColor
            text: root.text
            font.pixelSize: Looks.font.pixelSize.large
        }
    }

    Rectangle {
        id: focusRing
        visible: root.focus
        anchors {
            fill: parent
            margins: -4
        }
        color: "transparent"
        border.width: 2
        border.color: Looks.darkColors.fg
    }
}
