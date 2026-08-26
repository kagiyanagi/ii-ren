pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

StyledFlickable {
    id: root

    required property int length
    property int selectionStart
    property int selectionEnd
    property int cursorPosition

    property color color: Appearance.colors.colPrimary
    property color selectedTextColor: Appearance.colors.colOnSecondaryContainer
    property color selectionColor: Appearance.colors.colSecondaryContainer

    property int charSize: 20

    contentWidth: dotsRow.implicitWidth
    contentX: (Math.max(contentWidth - width, 0))
    Behavior on contentX {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    Rectangle {
        id: cursor
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            leftMargin: root.charSize * root.cursorPosition
        }
        color: root.color
        implicitWidth: 2
        implicitHeight: root.charSize
        Behavior on anchors.leftMargin {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(cursor)
        }
    }

    Row {
        id: dotsRow
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
            leftMargin: 4 - 5 // -5 to account for spacing being simulated by char item width
        }
        spacing: 0

        Repeater {
            model: root.length

            delegate: Rectangle {
                id: charItem
                required property int index
                implicitWidth: root.charSize
                implicitHeight: root.charSize
                property bool selected: index >= root.selectionStart && index < root.selectionEnd

                color: ColorUtils.transparentize(root.selectionColor, selected ? 0 : 1)

                Rectangle {
                    anchors.centerIn: parent
                    implicitWidth: 10
                    implicitHeight: 10
                    radius: width / 2
                    color: charItem.selected ? root.selectedTextColor : Appearance.colors.colOnLayer1
                }
            }
        }
    }
}
