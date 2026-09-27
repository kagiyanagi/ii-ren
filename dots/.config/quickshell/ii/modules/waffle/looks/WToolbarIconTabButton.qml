pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.waffle.looks

TabButton {
    id: root

    implicitWidth: 36
    implicitHeight: 32
    padding: 0

    background: null
    contentItem: Item {
        FluentIcon {
            anchors.centerIn: parent
            icon: root.icon.name
            color: root.icon.color
            implicitSize: 18
        }
    }
}
