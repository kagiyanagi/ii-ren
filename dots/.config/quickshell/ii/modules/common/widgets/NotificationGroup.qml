import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

/**
 * A group of notifications from the same app, laid out like an Android
 * notification: one header line (app icon, app name, time, expander), then the
 * content beneath it. Collapsed shows the newest notification only, the count
 * lives in the expander.
 */
MouseArea { // Notification group area
    id: root
    property var notificationGroup
    property var notifications: notificationGroup?.notifications ?? []
    property int notificationCount: notifications.length
    property bool multipleNotifications: notificationCount > 1
    property bool expanded: false
    property bool popup: false
    property real padding: 16 // Android's content inset
    readonly property bool urgent: notifications.some(n => n.urgency === NotificationUrgency.Critical.toString())
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
        radius: Appearance.rounding.large
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
        implicitHeight: contentColumn.implicitHeight + root.padding * 2

        Behavior on implicitHeight {
            id: implicitHeightAnim
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        ColumnLayout {
            id: contentColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: root.padding
            }
            spacing: 6

            RowLayout { // Header: icon, app name, time, expander
                id: header
                Layout.fillWidth: true
                spacing: 6
                property real fontSize: Appearance.font.pixelSize.smaller

                NotificationAppIcon {
                    Layout.alignment: Qt.AlignVCenter
                    implicitSize: 22
                    materialIconScale: 0.66
                    appIconScale: 0.85
                    appIcon: root.notificationGroup?.appIcon ?? ""
                    summary: root.notifications[root.notificationCount - 1]?.summary ?? ""
                    urgency: root.urgent ? NotificationUrgency.Critical : NotificationUrgency.Normal
                }
                TextMetrics {
                    // An eliding Text reports the *elided* width as its
                    // implicitWidth once the layout gives it one, so measure
                    // the full string separately or the name shrinks to "a...".
                    id: appNameMetrics
                    font: appNameText.font
                    text: appNameText.text
                }
                StyledText {
                    // Grows to its natural width at most, shrinks (and elides)
                    // when the header runs out of room.
                    id: appNameText
                    Layout.fillWidth: true
                    Layout.maximumWidth: appNameMetrics.width
                    elide: Text.ElideRight
                    text: root.notificationGroup?.appName || ""
                    font.pixelSize: header.fontSize
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    visible: timeText.text.length > 0
                    text: "•"
                    font.pixelSize: header.fontSize
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    id: timeText
                    text: NotificationUtils.getFriendlyNotifTimeString(root.notificationGroup?.time)
                    font.pixelSize: header.fontSize
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillWidth: true }
                NotificationGroupExpandButton {
                    Layout.alignment: Qt.AlignVCenter
                    count: root.notificationCount
                    expanded: root.expanded
                    fontSize: header.fontSize
                    onClicked: { root.toggleExpanded() }
                    altAction: () => { root.toggleExpanded() }

                    StyledToolTip {
                        text: Translation.tr("Tip: right-clicking a group\nalso expands it")
                    }
                }
            }

            StyledListView { // Notification content
                id: notificationsColumn
                implicitHeight: contentHeight
                Layout.fillWidth: true
                spacing: root.expanded ? 16 : 0
                interactive: false
                Behavior on spacing {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                model: ScriptModel {
                    values: root.expanded ? root.notifications.slice().reverse() :
                        root.notifications.slice().reverse().slice(0, 1)
                }
                delegate: NotificationItem {
                    required property int index
                    required property var modelData
                    notificationObject: modelData
                    expanded: root.expanded
                    anchors.left: parent?.left
                    anchors.right: parent?.right
                }
            }
        }
    }
}
