pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.waffle.looks

// TODO: Swipe to dismiss
MouseArea {
    id: root

    required property var notificationGroup
    readonly property var notifications: notificationGroup?.notifications ?? []
    property bool expanded: false

    implicitWidth: contentLayout.implicitWidth
    implicitHeight: contentLayout.implicitHeight

    ListView.delayRemove: removeAnimation.running

    function dismissAll() {
        removeAnimation.start();
    }

    WNotificationDismissAnim {
        id: removeAnimation
        target: root
        onDismissed: {
            root.notifications.forEach(notif => {
                Notifications.discardNotification(notif.notificationId);
            });
        }
    }

    property real dragDismissThreshold: 100
    drag {
        axis: Drag.XAxis
        target: contentLayout
        minimumX: 0
        onActiveChanged: {
            if (drag.active)
                return;
            if (contentLayout.x > root.dragDismissThreshold) {
                root.dismissAll();
            } else {
                contentLayout.x = 0;
            }
        }
    }

    ColumnLayout {
        id: contentLayout
        spacing: 4
        width: root.width

        Behavior on x {
            enabled: !root.drag.active && !removeAnimation.running
            animation: Looks.transition.enter.createObject(this)
        }

        GroupHeader {
            id: notifHeader
            Layout.fillWidth: true
            Layout.margins: 12
        }

        WListView {
            Layout.leftMargin: -Math.min(36, contentLayout.x)
            Layout.rightMargin: -Layout.leftMargin
            Layout.fillWidth: true
            implicitWidth: notifHeader.implicitWidth
            implicitHeight: contentHeight
            interactive: false
            spacing: 4
            model: ScriptModel {
                values: root.expanded ? root.notifications.slice().reverse() : root.notifications.slice(-1)
                objectProp: "notificationId"
            }
            delegate: WSingleNotification {
                id: singleNotif
                required property int index
                required property var modelData

                width: ListView.view.width
                notification: modelData

                groupExpandControlMessage: {
                    if ((root.notifications?.length ?? 0) <= 1)
                        return "";
                    if (!root.expanded)
                        return Translation.tr("+%1 notifications").arg((root.notifications?.length ?? 1) - 1);
                    if (index === (root.notifications?.length ?? 0) - 1)
                        return Translation.tr("See fewer");
                    return "";
                }
                onGroupExpandToggle: {
                    root.expanded = !root.expanded;
                }
            }
        }
    }

    component GroupHeader: MouseArea {
        id: headerMouseArea
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        implicitWidth: appHeader.implicitWidth
        implicitHeight: appHeader.implicitHeight

        RowLayout {
            id: appHeader
            anchors.fill: parent
            spacing: 8

            WNotificationAppIcon {
                Layout.alignment: Qt.AlignVCenter
                icon: root.notificationGroup?.appIcon ?? ""
            }

            WText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignLeft
                elide: Text.ElideRight
                text: root.notificationGroup?.appName ?? ""
            }

            NotificationHeaderButton {
                visible: headerMouseArea.containsMouse
                Layout.rightMargin: 4
                icon.name: "dismiss"
                onClicked: {
                    root.dismissAll();
                }
            }
        }
    }
}
