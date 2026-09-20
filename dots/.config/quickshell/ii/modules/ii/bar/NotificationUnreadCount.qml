import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

MaterialSymbol {
    id: root
    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount
    text: Notifications.silent ? "notifications_paused" : "notifications"
    iconSize: Appearance.font.pixelSize.larger
    color: rightSidebarButton.colText

    Rectangle {
        id: notifPing

        readonly property bool shown: !Notifications.silent && Notifications.unread > 0

        // The badge grows out of the icon it is pinned to, so the origin is the
        // corner facing it, not the centre (2.6). Enter decelerating on the
        // default spatial spec, exit accelerating on fast effects at about half
        // (2.5); the spec is picked inside the binding that drives the change,
        // which is the only order a Behavior reads in time (2.9, as Revealer).
        property AnimSpec pingSpec: Appearance.animation.elementMoveEnter
        transformOrigin: Item.BottomLeft
        scale: {
            notifPing.pingSpec = notifPing.shown ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveExit;
            return notifPing.shown ? 1 : 0;
        }
        opacity: notifPing.shown ? 1 : 0
        visible: scale > 0

        Behavior on scale {
            NumberAnimation {
                alwaysRunToEnd: false
                duration: notifPing.pingSpec.duration
                easing.type: notifPing.pingSpec.type
                easing.bezierCurve: notifPing.pingSpec.bezierCurve
            }
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(notifPing)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(notifPing)
        }

        anchors {
            right: parent.right
            top: parent.top
            rightMargin: root.showUnreadCount ? 0 : 1
            topMargin: root.showUnreadCount ? 0 : 3
        }
        radius: Appearance.rounding.full
        color: Appearance.colors.colOnLayer0
        z: 1

        implicitHeight: root.showUnreadCount ? Math.max(notificationCounterText.implicitWidth, notificationCounterText.implicitHeight) : 8
        implicitWidth: implicitHeight

        StyledText {
            id: notificationCounterText
            visible: root.showUnreadCount
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colLayer0
            text: Notifications.unread
        }
    }
}
