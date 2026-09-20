pragma ComponentBehavior: Bound

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
 *
 * The root stays a plain MouseArea rather than becoming a RippleButton. The card
 * has no left-click action of its own -- right-click expands it, middle-click
 * and a swipe dismiss it -- and 3.2 keeps a ripple off a row that is really a
 * layout, and off any parent of something already rippled, which the expander
 * is. The four states come from a StateOverlay over the card instead: 3.1's
 * second-ranked mechanism, and the one that composites over a translucent
 * surface.
 *
 * The content is a ListView and not a Column because SwipeDismissible reaches
 * its owner's ListView for dragIndex/dragDistance/resetDrag -- that is what
 * makes the neighbouring rows follow a drag at 0.3 and 0.1.
 */
MouseArea { // Notification group area
    id: root
    property var notificationGroup
    property var notifications: root.notificationGroup?.notifications ?? []
    property int notificationCount: root.notifications.length
    property bool expanded: false
    property bool popup: false
    property real padding: 16 // Android's content inset
    // The group's index in the notification list, passed down rather than read
    // off `parent.children`: SwipeDismissible nudges the neighbours by it.
    property int itemIndex: -1
    // The service stores urgency as the enum's decimal string; Number() reads
    // that and the raw enum alike.
    readonly property bool urgent: root.notifications.some(n => Number(n.urgency) === NotificationUrgency.Critical)
    implicitHeight: background.implicitHeight
    acceptedButtons: Qt.NoButton
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

    // Expanding is an enter and collapsing is an exit, so they do not share a
    // spec (2.5), and the card's height is size, so both are spatial and not the
    // effects spec this used to run on (2.1). Set here rather than from a
    // binding on `expanded`, because a Behavior bakes its duration when the
    // property is written and a sibling binding is not necessarily current by
    // then (2.9). Collapsing used to animate and expanding used to snap.
    property AnimSpec expandSpec: Appearance.animation.elementMove

    function toggleExpanded(): void {
        root.expandSpec = root.expanded ?
            Appearance.animation.elementMoveExit : Appearance.animation.elementMove;
        root.expanded = !root.expanded;
    }

    SwipeDismissible { // Drag manager
        id: dragManager
        owner: root
        target: background
        itemIndex: root.itemIndex

        anchors.fill: parent
        // The whole group swipes away until it is expanded; after that each row
        // carries its own SwipeDismissible, as the shade does on Android.
        interactive: !root.expanded
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: (mouse) => {
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
        // 3.6: a dragged card lifts, it does not fade. A popup is raised anyway.
        visible: root.popup || dragManager.dragging
    }
    Rectangle { // Background of the notification
        id: background
        anchors.left: parent.left
        width: parent.width
        color: root.popup ? Appearance.colors.colBackgroundSurfaceContainer : Appearance.colors.colLayer2
        radius: Appearance.rounding.large
        anchors.leftMargin: dragManager.xOffset

        // The snap back after a released swipe: spatial, and on one spec rather
        // than elementMove's duration wearing the fast curve.
        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        clip: true
        implicitHeight: contentColumn.implicitHeight + root.padding * 2

        Behavior on implicitHeight {
            NumberAnimation {
                duration: root.expandSpec.duration
                easing.type: root.expandSpec.type
                easing.bezierCurve: root.expandSpec.bezierCurve
            }
        }

        // Hover, focus, pressed and dragged (3.1, 3.6). The card answers a
        // pointer and a swipe and used to show none of it. Declared before the
        // content so the film sits over the card and under what is written on
        // it, and given the corners explicitly because `clip` only clips to the
        // bounding box. The three pointer states exclude each other: stacked,
        // hover plus pressed composites to 0.18, which is the drag token.
        StateOverlay {
            anchors.fill: parent
            hover: root.containsMouse && !dragManager.pressed
            focused: root.activeFocus
            press: dragManager.pressed && !dragManager.dragging
            drag: dragManager.dragging
            contentColor: Appearance.colors.colOnLayer2
            topLeftRadius: background.radius
            topRightRadius: background.radius
            bottomLeftRadius: background.radius
            bottomRightRadius: background.radius
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
                    Layout.minimumWidth: 0
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
                    // Shown for a lone notification too: expanding it is what
                    // reveals its actions, so a one-item group is not a list
                    // with a dead control on it.
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
                implicitHeight: notificationsColumn.contentHeight
                Layout.fillWidth: true
                spacing: root.expanded ? 16 : 0
                interactive: false
                // Spacing is size, so it rides the same spatial spec the card's
                // height does, in both directions.
                Behavior on spacing {
                    NumberAnimation {
                        duration: root.expandSpec.duration
                        easing.type: root.expandSpec.type
                        easing.bezierCurve: root.expandSpec.bezierCurve
                    }
                }
                model: ScriptModel {
                    values: root.expanded ? root.notifications.slice().reverse() :
                        root.notifications.slice().reverse().slice(0, 1)
                }
                delegate: NotificationItem {
                    required property int index
                    required property var modelData
                    itemIndex: index
                    notificationObject: modelData
                    expanded: root.expanded
                    surfaceColor: background.color
                    // Sized by the view, not anchored into it: a delegate that
                    // anchors itself inside its ListView is undefined behaviour.
                    width: ListView.view.width
                }
            }
        }
    }
}
