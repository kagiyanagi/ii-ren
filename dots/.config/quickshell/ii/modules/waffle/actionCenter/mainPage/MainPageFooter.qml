pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.actionCenter

FooterRectangle {
    id: root

    // Battery button / indicator
    WBorderlessButton {
        id: batteryButton
        visible: Battery.available
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 12

        WToolTip {
            text: Battery.isCharging ? Translation.tr("Charging") : Translation.tr("Battery")
        }

        contentItem: Row {
            spacing: 4

            FluentIcon {
                anchors.verticalCenter: parent.verticalCenter
                icon: WIcons.batteryLevelIcon
                FluentIcon {
                    anchors.fill: parent
                    icon: WIcons.batteryIcon
                }
            }
            WText {
                anchors.verticalCenter: parent.verticalCenter
                text: `${Math.round(Battery.percentage * 100) || 0}%`
            }
        }
    }

    // Settings button
    WBorderlessButton {
        id: settingsButton
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 12

        WToolTip {
            text: Translation.tr("All settings")
        }

        onClicked: {
            GlobalStates.sidebarLeftOpen = false;
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")]);
        }

        contentItem: FluentIcon {
            icon: "settings"
        }
    }
}
