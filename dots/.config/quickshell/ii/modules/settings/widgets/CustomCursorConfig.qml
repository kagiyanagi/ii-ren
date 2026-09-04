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
                text: Translation.tr("Cursor Configuration")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Cursor & Pointer")
            icon: "arrow_selector_tool"

            // Info Card
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
                        text: "ads_click"
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("System-wide Pointer Theme")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.family: Appearance.font.family.title
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: Translation.tr("Configures the cursor theme and size across Hyprland, GTK apps, and Qt/KDE. Changes apply immediately without restarting your compositor.")
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
                        text: "mouse"
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            text: Translation.tr("Active System Cursor")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            text: {
                                if (!CursorTheme.currentSystemTheme) return Translation.tr("Detecting…");
                                const base = `${CursorTheme.currentSystemTheme} · ${CursorTheme.currentSystemSize}px`;
                                if (CursorTheme.currentThemeDetails?.sizes?.length > 0) {
                                    return `${base} (supported: ${CursorTheme.currentThemeDetails.sizes.join(", ")}px)`;
                                }
                                return base;
                            }
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.family: Appearance.font.family.title
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    Rectangle {
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer
                        implicitHeight: 28
                        implicitWidth: activeBadgeText.implicitWidth + 16

                        StyledText {
                            id: activeBadgeText
                            anchors.centerIn: parent
                            text: Translation.tr("Active")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }
            }

            // Theme Selection
            ContentSubsection {
                title: Translation.tr("Installed Cursor Packs")
                icon: "category"
                Layout.fillWidth: true
                tooltip: Translation.tr("Select a cursor theme detected from ~/.icons, ~/.local/share/icons, or /usr/share/icons")

                ConfigSelectionArray {
                    currentValue: CursorTheme.configuredTheme
                    onSelected: (newValue) => {
                        CursorTheme.setCursor(newValue, CursorTheme.configuredSize);
                    }
                    options: CursorTheme.availableThemes.map((theme) => {
                        return ({
                            "displayName": theme.name,
                            "value": theme.id,
                            "icon": "arrow_selector_tool"
                        });
                    })
                }
            }

            // Custom Theme Name Override
            ContentSubsection {
                title: Translation.tr("Custom Cursor Theme Name")
                icon: "edit"
                Layout.fillWidth: true
                tooltip: Translation.tr("Manually enter a cursor theme name if you have a custom pack installed")

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("e.g., macOS-White, Bibata-Modern-Classic")
                    text: CursorTheme.configuredTheme
                    onEditingFinished: {
                        if (text.trim().length > 0) {
                            CursorTheme.setCursor(text.trim(), CursorTheme.configuredSize);
                        }
                    }
                }
            }

            // Size Presets
            ContentSubsection {
                title: Translation.tr("Cursor Size")
                icon: "format_size"
                Layout.fillWidth: true
                tooltip: Translation.tr("Select a standard cursor size or use the spin box for custom sizes")

                ConfigSelectionArray {
                    currentValue: CursorTheme.configuredSize
                    onSelected: (newValue) => {
                        CursorTheme.setCursor(CursorTheme.configuredTheme, newValue);
                    }
                    options: [
                        { "displayName": "16 px", "value": 16, "icon": "mouse" },
                        { "displayName": "20 px", "value": 20, "icon": "mouse" },
                        { "displayName": "24 px", "value": 24, "icon": "mouse" },
                        { "displayName": "28 px", "value": 28, "icon": "mouse" },
                        { "displayName": "32 px", "value": 32, "icon": "mouse" },
                        { "displayName": "36 px", "value": 36, "icon": "mouse" },
                        { "displayName": "48 px", "value": 48, "icon": "mouse" }
                    ]
                }
            }

            ConfigSpinBox {
                icon: "photo_size_select_small"
                text: Translation.tr("Custom size (px)")
                from: 12
                to: 96
                stepSize: 2
                value: CursorTheme.configuredSize
                onValueChanged: {
                    if (value !== CursorTheme.configuredSize) {
                        CursorTheme.setCursor(CursorTheme.configuredTheme, value);
                    }
                }
            }

            // Warning if chosen size is below theme's minimum available bitmap
            NoticeBox {
                Layout.fillWidth: true
                visible: Boolean(CursorTheme.currentThemeDetails?.min_size && (CursorTheme.configuredSize < CursorTheme.currentThemeDetails.min_size))
                materialIcon: "warning"
                text: Translation.tr("The selected theme (%1) only includes bitmaps down to %2px. Hyprland and GTK will display %2px instead of %3px. Switch to a theme with smaller bitmaps (such as macOS-White or Breeze) to use %3px.")
                    .arg(CursorTheme.configuredTheme)
                    .arg(CursorTheme.currentThemeDetails?.min_size ?? 24)
                    .arg(CursorTheme.configuredSize)
            }

            // Apply Button
            RippleButtonWithIcon {
                id: applyButton
                property bool appliedRecently: false
                materialIcon: appliedRecently ? "check" : "magic_button"
                mainText: appliedRecently ? Translation.tr("Applied to Hyprland, GTK & Qt!") : Translation.tr("Apply Cursor Now")
                buttonRadius: Appearance.rounding.small
                implicitHeight: 48
                Layout.fillWidth: true
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                colText: Appearance.colors.colOnPrimaryContainer
                onClicked: {
                    CursorTheme.applyCurrent();
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
