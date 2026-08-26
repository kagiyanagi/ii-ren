import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton { // Right sidebar button
    id: rightSidebarButton

    property bool vertical: false

    Layout.alignment: vertical ? (Qt.AlignBottom | Qt.AlignHCenter) : (Qt.AlignRight | Qt.AlignVCenter)
    Layout.rightMargin: vertical ? 0 : Appearance.rounding.screenRounding
    Layout.bottomMargin: vertical ? Appearance.rounding.screenRounding : 0
    Layout.fillWidth: false
    Layout.fillHeight: false

    implicitWidth: indicatorsLayout.implicitWidth + (vertical ? 6 : 10) * 2
    implicitHeight: indicatorsLayout.implicitHeight + (vertical ? 4 : 5) * 2

    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.sidebarRightOpen
    property color colText: toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0

    Behavior on colText {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    onPressed: {
        GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
    }

    // GridLayout with an unbounded row/column count is a RowLayout or a
    // ColumnLayout depending on flow, so one layout covers both orientations.
    GridLayout {
        id: indicatorsLayout
        anchors.centerIn: parent
        flow: rightSidebarButton.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rowSpacing: 0
        columnSpacing: 0

        // Gaps are per-item margins rather than layout spacing so a collapsed
        // revealer takes up no space at all.
        property real realSpacing: rightSidebarButton.vertical ? 6 : 15

        Revealer {
            vertical: rightSidebarButton.vertical
            reveal: Idle.inhibit ?? false
            Layout.fillHeight: true
            Layout.rightMargin: rightSidebarButton.vertical ? 0 : (reveal ? indicatorsLayout.realSpacing : 0)
            Layout.bottomMargin: rightSidebarButton.vertical ? (reveal ? indicatorsLayout.realSpacing : 0) : 0
            Behavior on Layout.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            MaterialSymbol {
                text: "coffee"
                iconSize: Appearance.font.pixelSize.larger
                color: rightSidebarButton.colText
            }
        }
        Revealer {
            vertical: rightSidebarButton.vertical
            reveal: Audio.sink?.audio?.muted ?? false
            Layout.fillHeight: !rightSidebarButton.vertical
            Layout.fillWidth: rightSidebarButton.vertical
            Layout.rightMargin: rightSidebarButton.vertical ? 0 : (reveal ? indicatorsLayout.realSpacing : 0)
            Layout.bottomMargin: rightSidebarButton.vertical ? (reveal ? indicatorsLayout.realSpacing : 0) : 0
            Behavior on Layout.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            MaterialSymbol {
                text: "volume_off"
                iconSize: Appearance.font.pixelSize.larger
                color: rightSidebarButton.colText
            }
        }
        Revealer {
            vertical: rightSidebarButton.vertical
            reveal: Audio.source?.audio?.muted ?? false
            Layout.fillHeight: !rightSidebarButton.vertical
            Layout.fillWidth: rightSidebarButton.vertical
            Layout.rightMargin: rightSidebarButton.vertical ? 0 : (reveal ? indicatorsLayout.realSpacing : 0)
            Layout.bottomMargin: rightSidebarButton.vertical ? (reveal ? indicatorsLayout.realSpacing : 0) : 0
            Behavior on Layout.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            MaterialSymbol {
                text: "mic_off"
                iconSize: Appearance.font.pixelSize.larger
                color: rightSidebarButton.colText
            }
        }
        HyprlandXkbIndicator {
            vertical: rightSidebarButton.vertical
            Layout.alignment: rightSidebarButton.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            Layout.rightMargin: rightSidebarButton.vertical ? 0 : indicatorsLayout.realSpacing
            Layout.bottomMargin: rightSidebarButton.vertical ? indicatorsLayout.realSpacing : 0
            color: rightSidebarButton.colText
        }
        Revealer {
            vertical: rightSidebarButton.vertical
            reveal: Notifications.silent || Notifications.unread > 0
            Layout.fillHeight: !rightSidebarButton.vertical
            Layout.fillWidth: rightSidebarButton.vertical
            Layout.rightMargin: rightSidebarButton.vertical ? 0 : (reveal ? indicatorsLayout.realSpacing : 0)
            Layout.bottomMargin: rightSidebarButton.vertical ? (reveal ? indicatorsLayout.realSpacing : 0) : 0
            implicitHeight: reveal ? notificationUnreadCount.implicitHeight : 0
            implicitWidth: reveal ? notificationUnreadCount.implicitWidth : 0
            Behavior on Layout.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            NotificationUnreadCount {
                id: notificationUnreadCount
            }
        }
        MaterialSymbol {
            text: Network.materialSymbol
            iconSize: Appearance.font.pixelSize.larger
            color: rightSidebarButton.colText
        }
        MaterialSymbol {
            Layout.leftMargin: rightSidebarButton.vertical ? 0 : indicatorsLayout.realSpacing
            Layout.topMargin: rightSidebarButton.vertical ? indicatorsLayout.realSpacing : 0
            visible: BluetoothStatus.available
            text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
            iconSize: Appearance.font.pixelSize.larger
            color: rightSidebarButton.colText
        }
    }
}
