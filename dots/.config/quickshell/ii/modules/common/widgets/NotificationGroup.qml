import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

/**
 * A group of notifications from the same app.
 * Similar to Android's notifications
 */
MouseArea { // Notification group area
    id: root
    property var notificationGroup
    property var notifications: notificationGroup?.notifications ?? []
    property int notificationCount: notifications.length
    property bool multipleNotifications: notificationCount > 1
    property bool expanded: false
    property bool popup: false
    property real padding: 10
    implicitHeight: background.implicitHeight

    hoverEnabled: true
    onContainsMouseChanged: {
        if (!root.popup) return;
        if (root.containsMouse) root.notifications.forEach(notif => {
            Notifications.cancelTimeout(notif.notificationId);
        });
        else root.notifications.forEach(notif => {
            Notifications.timeoutNotification(notif.notificationId);
        });
    }

    function toggleExpanded() {
        if (expanded) implicitHeightAnim.enabled = true;
        else implicitHeightAnim.enabled = false;
        root.expanded = !root.expanded;
    }

    SwipeDismissible { // Drag manager
        id: dragManager
        owner: root
        target: background
        itemIndex: root.index ?? root.parent.children.indexOf(root)

        anchors.fill: parent
        interactive: !expanded
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: {
            if (mouse.button === Qt.RightButton)
                root.toggleExpanded();
        }

        onDismissed: root.notifications.forEach((notif) => {
            Qt.callLater(() => {
                Notifications.discardNotification(notif.notificationId);
            });
        })
    }

    StyledRectangularShadow {
        target: background
        visible: popup
    }
    Rectangle { // Background of the notification
        id: background
        anchors.left: parent.left
        width: parent.width
        color: popup ? Appearance.colors.colBackgroundSurfaceContainer : Appearance.colors.colLayer2
        radius: Appearance.rounding.normal
        anchors.leftMargin: dragManager.xOffset

        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        
        clip: true
        implicitHeight: root.expanded ? 
            row.implicitHeight + padding * 2 :
            Math.min(80, row.implicitHeight + padding * 2)

        Behavior on implicitHeight {
            id: implicitHeightAnim
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout { // Left column for icon, right column for content
            id: row
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            spacing: 10

            NotificationAppIcon { // Icons
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: false
                image: root?.multipleNotifications ? "" : notificationGroup?.notifications[0]?.image ?? ""
                appIcon: root.notificationGroup?.appIcon
                summary: root.notificationGroup?.notifications[root.notificationCount - 1]?.summary
                urgency: root.notifications.some(n => n.urgency === NotificationUrgency.Critical.toString()) ? 
                    NotificationUrgency.Critical : NotificationUrgency.Normal
            }

            ColumnLayout { // Content
                Layout.fillWidth: true
                spacing: expanded ? (root.multipleNotifications ? 
                    (notificationGroup?.notifications[root.notificationCount - 1].image != "") ? 35 : 
                    5 : 0) : 0
                // spacing: 00
                Behavior on spacing {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item { // App name (or summary when there's only 1 notif) and time
                    id: topRow
                    // spacing: 0
                    Layout.fillWidth: true
                    property real fontSize: Appearance.font.pixelSize.smaller
                    property bool showAppName: root.multipleNotifications
                    implicitHeight: Math.max(topTextRow.implicitHeight, expandButton.implicitHeight)

                    RowLayout {
                        id: topTextRow
                        anchors.left: parent.left
                        anchors.right: expandButton.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        StyledText {
                            id: appName
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            text: (topRow.showAppName ?
                                notificationGroup?.appName :
                                notificationGroup?.notifications[0]?.summary) || ""
                            font.pixelSize: topRow.showAppName ?
                                topRow.fontSize :
                                Appearance.font.pixelSize.small
                            color: topRow.showAppName ?
                                Appearance.colors.colSubtext :
                                Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            id: timeText
                            // Layout.fillWidth: true
                            Layout.rightMargin: 10
                            horizontalAlignment: Text.AlignLeft
                            text: NotificationUtils.getFriendlyNotifTimeString(notificationGroup?.time)
                            font.pixelSize: topRow.fontSize
                            color: Appearance.colors.colSubtext
                        }
                    }
                    NotificationGroupExpandButton {
                        id: expandButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        count: root.notificationCount
                        expanded: root.expanded
                        fontSize: topRow.fontSize
                        onClicked: { root.toggleExpanded() }
                        altAction: () => { root.toggleExpanded() }

                        StyledToolTip {
                            text: Translation.tr("Tip: right-clicking a group\nalso expands it")
                        }
                    }
                }

                StyledListView { // Notification body (expanded)
                    id: notificationsColumn
                    implicitHeight: contentHeight
                    Layout.fillWidth: true
                    spacing: expanded ? 5 : 3
                    // clip: true
                    interactive: false
                    Behavior on spacing {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    model: ScriptModel {
                        values: root.expanded ? root.notifications.slice().reverse() : 
                            root.notifications.slice().reverse().slice(0, 2)
                    }
                    delegate: NotificationItem {
                        required property int index
                        required property var modelData
                        notificationObject: modelData
                        expanded: root.expanded
                        onlyNotification: (root.notificationCount === 1)
                        opacity: (!root.expanded && index == 1 && root.notificationCount > 2) ? 0.5 : 1
                        visible: root.expanded || (index < 2)
                        anchors.left: parent?.left
                        anchors.right: parent?.right
                    }
                }

            }
        }
    }
}
