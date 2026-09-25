import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarDashboard.notifications
import QtQuick

Rectangle {
    id: root
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    NotificationList {
        anchors.fill: parent
        anchors.margins: 4
    }
}
