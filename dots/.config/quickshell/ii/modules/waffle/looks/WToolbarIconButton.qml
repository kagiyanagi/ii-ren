pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.waffle.looks

WToolbarButton {
    id: root
    implicitWidth: height
    contentItem: Item {
        FluentIcon {
            anchors.centerIn: parent
            icon: root.icon.name
            implicitSize: 18
            color: root.fgColor
        }
    }
}
