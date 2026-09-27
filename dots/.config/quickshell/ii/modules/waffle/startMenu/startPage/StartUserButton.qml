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

WBorderlessButton {
    id: userButton
    implicitWidth: userButtonRow.implicitWidth + 12 * 2
    implicitHeight: 40

    contentItem: Item {
        RowLayout {
            id: userButtonRow
            anchors.centerIn: parent
            spacing: 12

            WUserAvatar {
                sourceSize: Qt.size(32, 32)
            }
            WText {
                Layout.alignment: Qt.AlignVCenter
                text: SystemInfo.username
            }
        }
    }

    onClicked: {
        userMenu.open();
    }

    WToolTip {
        text: SystemInfo.username
    }

    Popup {
        id: userMenu
        x: -52
        y: -userMenu.implicitHeight + userButton.implicitHeight / 2 - 8

        background: null

        Connections {
            target: GlobalStates
            function onSearchOpenChanged() {
                if (!GlobalStates.searchOpen && userMenu.opened) {
                    userMenu.close();
                }
            }
        }
        
        WToolTipContent {
            id: popupContent
            horizontalPadding: 12
            verticalPadding: 8
            radius: Looks.radius.large
            realContentItem: Item {
                implicitWidth: userMenuContentLayout.implicitWidth
                implicitHeight: userMenuContentLayout.implicitHeight
                
                ColumnLayout {
                    id: userMenuContentLayout
                    anchors {
                        fill: parent
                        leftMargin: popupContent.horizontalPadding
                        rightMargin: popupContent.horizontalPadding
                        topMargin: popupContent.verticalPadding
                        bottomMargin: popupContent.verticalPadding
                    }
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        FluentIcon {
                            Layout.alignment: Qt.AlignVCenter
                            implicitSize: 20
                            icon: "corporation"
                            monochrome: false
                        }
                        WText {
                            Layout.alignment: Qt.AlignVCenter
                            text: "Megahard"
                            font.pixelSize: Looks.font.pixelSize.large
                            font.weight: Looks.font.weight.strong
                        }
                        Item { Layout.fillWidth: true }
                        WBorderlessButton {
                            Layout.alignment: Qt.AlignVCenter
                            implicitHeight: 36
                            implicitWidth: textItem.implicitWidth + 12 * 2
                            contentItem: WText {
                                id: textItem
                                text: Translation.tr("Sign out")
                                font.pixelSize: Looks.font.pixelSize.large
                            }
                            onClicked: {
                                GlobalStates.searchOpen = false;
                                Session.logout();
                            }
                        }
                    }
                    Item { // Force min width 360 (using min on the item somehow doesn't work)
                        implicitWidth: 336
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 8
                        Layout.leftMargin: 8
                        spacing: 12
                        WUserAvatar {
                            sourceSize: Qt.size(56, 56)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4
                            WText {
                                text: SystemInfo.username
                                font.pixelSize: Looks.font.pixelSize.larger
                                font.weight: Looks.font.weight.strong
                            }
                            WText {
                                color: Looks.colors.fg1
                                text: Translation.tr("Local account")
                            }
                            WText {
                                color: Looks.colors.accent
                                text: Translation.tr("Manage my account")
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Quickshell.execDetached(["bash", "-c", Config.options.apps.manageUser]);
                                        GlobalStates.searchOpen = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
