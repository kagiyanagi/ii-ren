pragma ComponentBehavior: Bound

import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

StyledListView { // Scrollable window
    id: root
    property bool popup: false

    spacing: 8

    model: ScriptModel {
        values: root.popup ? Notifications.popupAppNameList : Notifications.appNameList
    }
    // No PagePlaceholder here: the sidebar's NotificationList already owns the
    // empty state as a sibling, and the popup window hides itself when the list
    // is empty, so one added here would be a second ghost behind the first.
    delegate: NotificationGroup {
        id: group
        required property int index
        required property var modelData
        popup: root.popup
        // Handed down rather than read off `parent.children`: SwipeDismissible
        // nudges the neighbouring groups by it.
        itemIndex: group.index
        width: ListView.view.width // https://doc.qt.io/qt-6/qml-qtquick-listview.html
        notificationGroup: group.popup ?
            Notifications.popupGroupsByAppName[group.modelData] :
            Notifications.groupsByAppName[group.modelData]
    }
}
