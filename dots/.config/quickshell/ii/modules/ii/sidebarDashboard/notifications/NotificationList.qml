import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    readonly property int count: Notifications.list.length

    NotificationListView { // Scrollable window
        id: listview
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: footer.top
        anchors.bottomMargin: 4

        // Clipped to the stack's own outer corners, so a card scrolled under the
        // edge keeps the corners it has at rest.
        clip: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: listview.width
                height: listview.height
                radius: Appearance.rounding.small
            }
        }

        popup: false
    }

    PagePlaceholder {
        shown: root.count === 0
        icon: "notifications_active"
        description: Translation.tr("No notifications")
        shape: MaterialShape.Shape.Ghostish
        descriptionHorizontalAlignment: Text.AlignHCenter

        triggerAnimationOn: GlobalStates.dashboardPanelOpen
        rotateToRight: GlobalStates.dashboardOnLeft
    }

    RowLayout {
        id: footer
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        spacing: 8

        RippleButton {
            implicitWidth: 40
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            toggled: Notifications.silent
            onClicked: Notifications.silent = !Notifications.silent

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "notifications_paused"
                iconSize: Appearance.font.pixelSize.larger
                color: Notifications.silent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                // In step with the background RippleButton animates under it.
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            StyledToolTip {
                text: Translation.tr("Silent")
            }
        }

        // Fades rather than blinking out as the last card leaves; the
        // placeholder says "No notifications" by then. One spec both ways, the
        // one "Clear all" dims on, so the two go together.
        StyledText {
            Layout.fillWidth: true
            opacity: root.count > 0 ? 1 : 0
            text: root.count === 1 ? Translation.tr("1 notification") : Translation.tr("%1 notifications").arg(root.count)
            color: Appearance.colors.colSubtext
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        // Stays put and dims to disabled, on RippleButton's own fade.
        RippleButtonWithIcon {
            enabled: root.count > 0
            implicitHeight: 40
            horizontalPadding: 16
            buttonRadius: Appearance.rounding.full
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            colText: Appearance.colors.colOnLayer2
            materialIcon: "clear_all"
            mainText: Translation.tr("Clear all")
            onClicked: Notifications.discardAllNotifications()
        }
    }
}
