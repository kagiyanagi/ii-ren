pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Icon Packs (Apps & Folders)")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Icon Packs")
            icon: "category"

            // Informational explanation card
            Rectangle {
                Layout.fillWidth: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                implicitHeight: infoLayout.implicitHeight + 24

                RowLayout {
                    id: infoLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignTop
                        iconSize: Appearance.font.pixelSize.larger
                        text: "palette"
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("System Icon Themes")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.family: Appearance.font.family.title
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: Translation.tr("Select icon packs for apps and folders across KDE (Dolphin, Qt) and GTK. Packs marked with ✦ (like Breeze and Breeze Plus) natively adapt their folder colors to your wallpaper.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // Current Active System Status
            Rectangle {
                Layout.fillWidth: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                implicitHeight: statusLayout.implicitHeight + 20

                RowLayout {
                    id: statusLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.large
                        text: IconThemes.isCurrentDynamic ? "auto_awesome" : "folder"
                        color: IconThemes.isCurrentDynamic ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: Translation.tr("Active System Theme")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            text: IconThemes.currentSystemTheme.length > 0 ? IconThemes.currentSystemTheme : Translation.tr("Detecting…")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.family: Appearance.font.family.title
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    Rectangle {
                        radius: Appearance.rounding.full
                        color: IconThemes.isCurrentDynamic ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                        implicitHeight: 28
                        implicitWidth: dynamicBadgeText.implicitWidth + 16

                        StyledText {
                            id: dynamicBadgeText
                            anchors.centerIn: parent
                            text: IconThemes.isCurrentDynamic ? Translation.tr("Dynamic") : Translation.tr("Static")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: IconThemes.isCurrentDynamic ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }
                }
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Enable icon theme management")
                checked: IconThemes.enableThemed
                onCheckedChanged: IconThemes.setThemed(checked)

                StyledToolTip {
                    text: Translation.tr("Synchronizes icon packs across KDE and GTK with light and dark mode switching.")
                }
            }

            ConfigSwitch {
                visible: IconThemes.enableThemed
                buttonIcon: "dark_mode"
                text: Translation.tr("Auto-switch between light and dark packs")
                checked: IconThemes.autoSwitchWithDarkMode
                onCheckedChanged: {
                    IconThemes.autoSwitchWithDarkMode = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Automatically toggles between your light and dark icon pack selections when night light or dark mode toggles.")
                }
            }

            ContentSubsection {
                visible: IconThemes.enableThemed
                title: Translation.tr("Light Mode Icon Pack")
                icon: "light_mode"
                Layout.fillWidth: true
                tooltip: Translation.tr("Icon pack applied during Light Mode. Marked with ✦ are dynamic packs that recolor folders with your wallpaper.")

                ConfigSelectionArray {
                    currentValue: IconThemes.lightTheme
                    onSelected: (newValue) => {
                        IconThemes.lightTheme = newValue;
                    }
                    options: IconThemes.availableThemes.map((theme) => {
                        return ({
                            "displayName": (theme.dynamic ? "✦ " : "") + theme.name,
                            "value": theme.id,
                            "icon": theme.dynamic ? "auto_awesome" : "folder"
                        });
                    })
                }
            }

            ContentSubsection {
                visible: IconThemes.enableThemed
                title: Translation.tr("Dark Mode Icon Pack")
                icon: "dark_mode"
                Layout.fillWidth: true
                tooltip: Translation.tr("Icon pack applied during Dark Mode. Marked with ✦ are dynamic packs that recolor folders with your wallpaper.")

                ConfigSelectionArray {
                    currentValue: IconThemes.darkTheme
                    onSelected: (newValue) => {
                        IconThemes.darkTheme = newValue;
                    }
                    options: IconThemes.availableThemes.map((theme) => {
                        return ({
                            "displayName": (theme.dynamic ? "✦ " : "") + theme.name,
                            "value": theme.id,
                            "icon": theme.dynamic ? "auto_awesome" : "folder"
                        });
                    })
                }
            }

            RippleButtonWithIcon {
                id: applyButton
                property bool appliedRecently: false
                materialIcon: appliedRecently ? "check" : "magic_button"
                mainText: appliedRecently ? Translation.tr("Applied to Dolphin & GTK!") : Translation.tr("Apply Theme Now")
                buttonRadius: Appearance.rounding.small
                implicitHeight: 48
                Layout.fillWidth: true
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                colText: Appearance.colors.colOnPrimaryContainer
                onClicked: {
                    IconThemes.applyCurrent();
                    appliedRecently = true;
                    feedbackTimer.restart();
                }

                Timer {
                    id: feedbackTimer
                    interval: 2000
                    onTriggered: {
                        applyButton.appliedRecently = false;
                    }
                }
            }
        }
    }
}
