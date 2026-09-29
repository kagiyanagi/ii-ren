import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

WindowDialog {
    id: root

    property string toggleId: ""
    readonly property bool isEditing: root.toggleId.length > 0

    backgroundWidth: 380

    function loadData() {
        if (root.isEditing) {
            var data = CustomToggles.getToggle(root.toggleId);
            if (data) {
                nameField.text = data.name || "";
                iconField.text = data.icon || "terminal";
                startCommandField.text = data.commandStart || "";
                stopCommandField.text = data.commandStop || "";
                return;
            }
        }
        nameField.text = "";
        iconField.text = "terminal";
        startCommandField.text = "";
        stopCommandField.text = "";
    }

    onShowChanged: {
        if (show)
            loadData();
    }

    onToggleIdChanged: {
        if (show)
            loadData();
    }

    function save() {
        var name = nameField.text.trim();
        var icon = iconField.text.trim();
        if (icon.length === 0)
            icon = "terminal";
        var cmdStart = startCommandField.text.trim();
        var cmdStop = stopCommandField.text.trim();

        if (root.isEditing) {
            CustomToggles.updateToggle(root.toggleId, name, icon, cmdStart, cmdStop);
        } else {
            CustomToggles.addToggle(name, icon, cmdStart, cmdStop);
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            WindowDialogTitle {
                text: root.isEditing ? Translation.tr("Edit custom toggle") : Translation.tr("New custom toggle")
            }

            StyledText {
                text: Translation.tr("Run shell commands on start and stop")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        // Form fields container card
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: formColumn.implicitHeight + 24
            radius: Appearance.rounding.large
            color: Appearance.colors.colSurfaceContainerHigh

            ColumnLayout {
                id: formColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 12
                }
                spacing: 12

                // Name field
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Name")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    MaterialTextField {
                        id: nameField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("e.g. Docker, Caffeine, VPN")
                    }
                }

                // Icon field & preview
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        text: Translation.tr("Icon")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            implicitWidth: 44
                            implicitHeight: 44
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colPrimaryContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnPrimaryContainer
                                text: iconField.text.trim().length > 0 ? iconField.text.trim() : "terminal"
                            }
                        }

                        MaterialTextField {
                            id: iconField
                            Layout.fillWidth: true
                            text: "terminal"
                            placeholderText: Translation.tr("Material symbol name")
                        }
                    }

                    // Popular icon suggestion chips
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: ["terminal", "power_settings_new", "rocket_launch", "code", "coffee", "shield", "sports_esports", "tune"]
                            delegate: RippleButton {
                                id: chip
                                required property string modelData
                                Layout.fillWidth: true
                                implicitHeight: 32
                                buttonRadius: Appearance.rounding.full
                                buttonRadiusPressed: height / 2
                                colBackground: iconField.text.trim() === modelData
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSurfaceContainerHighest
                                colBackgroundHover: iconField.text.trim() === modelData
                                    ? Appearance.colors.colPrimaryHover
                                    : Appearance.colors.colSurfaceContainerHighestHover
                                colRipple: Appearance.colors.colPrimaryActive
                                onClicked: iconField.text = chip.modelData
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: iconField.text.trim() === chip.modelData
                                        ? Appearance.colors.colOnPrimary
                                        : Appearance.colors.colOnSurface
                                    text: chip.modelData
                                }
                                StyledToolTip {
                                    text: chip.modelData
                                }
                            }
                        }
                    }
                }

                // Start command (ON)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Start command (ON)")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    MaterialTextField {
                        id: startCommandField
                        Layout.fillWidth: true
                        font.family: Appearance.font.family.monospace
                        placeholderText: Translation.tr("e.g. systemctl start docker")
                    }
                }

                // Stop command (OFF)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Stop command (OFF)")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    MaterialTextField {
                        id: stopCommandField
                        Layout.fillWidth: true
                        font.family: Appearance.font.family.monospace
                        placeholderText: Translation.tr("e.g. systemctl stop docker (optional)")
                    }
                }
            }
        }
    }

    WindowDialogButtonRow {
        DialogButton {
            visible: root.isEditing
            buttonText: Translation.tr("Delete")
            colEnabled: Appearance.colors.colError
            onClicked: {
                CustomToggles.removeToggle(root.toggleId);
                root.dismiss();
            }
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: root.dismiss()
        }

        DialogButton {
            buttonText: root.isEditing ? Translation.tr("Save") : Translation.tr("Add")
            enabled: nameField.text.trim().length > 0
            onClicked: {
                root.save();
                root.dismiss();
            }
        }
    }
}
