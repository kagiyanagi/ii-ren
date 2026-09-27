pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

WPanelPageColumn {
    id: root

    WPanelSeparator {}

    StartPageApps {
        Layout.fillHeight: true
    }

    WPanelSeparator {}

    StartFooter {
        Layout.fillWidth: true
    }

    component StartFooter: FooterRectangle {
        implicitHeight: 64

        StartUserButton {
            anchors {
                left: parent.left
                leftMargin: 52
                bottom: parent.bottom
                bottomMargin: 12
            }
        }

        PowerButton {
            anchors {
                right: parent.right
                rightMargin: 52
                bottom: parent.bottom
                bottomMargin: 12
            }
        }
    }

    component PowerButton: WBorderlessButton {
        id: powerButton
        implicitWidth: 40
        implicitHeight: 40

        contentItem: Item {
            FluentIcon {
                anchors.centerIn: parent
                icon: "power"
                implicitSize: 20
            }
        }

        WToolTip {
            extraVisibleCondition: !powerMenu.visible
            text: Translation.tr("Power")
        }

        onClicked: {
            powerMenu.open()
        }

        WMenu {
            id: powerMenu
            x: Math.round(-powerMenu.implicitWidth / 2 + powerButton.implicitWidth / 2)
            y: -powerMenu.implicitHeight - 4
            Action {
                icon.name: "lock-closed"
                text: Translation.tr("Lock")
                onTriggered: {
                    GlobalStates.searchOpen = false;
                    Session.lock();
                }
            }
            Action {
                icon.name: "weather-moon"
                text: Translation.tr("Sleep")
                onTriggered: {
                    GlobalStates.searchOpen = false;
                    Session.suspend();
                }
            }
            Action {
                icon.name: "power"
                text: Translation.tr("Shut down")
                onTriggered: {
                    GlobalStates.searchOpen = false;
                    Session.poweroff();
                }
            }
            Action {
                icon.name: "arrow-counterclockwise"
                text: Translation.tr("Restart")
                onTriggered: {
                    GlobalStates.searchOpen = false;
                    Session.reboot();
                }
            }
        }
    }
}
