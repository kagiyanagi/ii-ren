import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 640

    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0 B";
        const units = ["B", "KB", "MB", "GB", "TB"];
        const i = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
        return (bytes / Math.pow(1024, i)).toFixed(1) + " " + units[i];
    }

    Component.onCompleted: {
        Network.fetchHotspotConfig();
        if (Network.hotspotToggled) {
            Network.fetchHotspotUsage();
        }
    }

    Connections {
        target: Network
        function onHotspotConfigSsidChanged() {
            if (!ssidField.activeFocus) {
                ssidField.text = Network.hotspotConfigSsid;
            }
        }
        function onHotspotConfigPasswordChanged() {
            if (!passwordField.activeFocus) {
                passwordField.text = Network.hotspotConfigPassword;
            }
        }
    }

    Timer {
        interval: 2000
        running: root.show && Network.hotspotToggled
        repeat: true
        onTriggered: Network.fetchHotspotUsage()
    }

    property bool showPassword: false

    readonly property bool passwordValid: {
        const item = securityCombo.model[securityCombo.currentIndex];
        const sec = (item && item.value) ? item.value : "wpa-psk";
        if (sec === "none") return true;
        return passwordField.text.length >= 8;
    }

    readonly property bool canSave: ssidField.text.trim().length > 0 && passwordValid

    WindowDialogTitle {
        text: Translation.tr("Hotspot configuration")
    }

    StyledFlickable {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(scrollColumn.implicitHeight, 490)
        contentHeight: scrollColumn.implicitHeight
        contentWidth: width
        clip: true

        ColumnLayout {
            id: scrollColumn
            width: parent.width
            spacing: 16

            WindowDialogSectionHeader {
                text: Translation.tr("Status")
            }

            ConfigSwitch {
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.large
                iconSize: Appearance.font.pixelSize.larger
                buttonIcon: "wifi_tethering"
                text: Translation.tr("Enable hotspot")
                checked: Network.hotspotToggled
                enabled: Network.hotspotSupported
                onCheckedChanged: {
                    if (checked !== Network.hotspotToggled) {
                        Network.enableHotspot(checked);
                    }
                }
            }

            WindowDialogSectionHeader {
                text: Translation.tr("Activity & Usage")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 64
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: Translation.tr("Connected Devices")
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer2
                            text: Network.hotspotToggled ? String(Network.hotspotClientCount) : "--"
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 64
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: Translation.tr("Data Transferred")
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer2
                            text: Network.hotspotToggled
                                ? `↓ ${root.formatBytes(Network.hotspotRxBytes)}  ↑ ${root.formatBytes(Network.hotspotTxBytes)}`
                                : "--"
                        }
                    }
                }
            }

            WindowDialogSectionHeader {
                text: Translation.tr("Network Settings")
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                // SSID Field
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        text: Translation.tr("Network Name (SSID)")
                    }

                    MaterialTextField {
                        id: ssidField
                        Layout.fillWidth: true
                        text: Network.hotspotConfigSsid || "Hotspot"
                        placeholderText: Translation.tr("Enter hotspot name")
                    }
                }

                // Password Field
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: {
                        const secItem = securityCombo.model[securityCombo.currentIndex];
                        return (secItem ? secItem.value : "wpa-psk") !== "none";
                    }

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        text: Translation.tr("Password (min. 8 characters)")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialTextField {
                            id: passwordField
                            Layout.fillWidth: true
                            text: Network.hotspotConfigPassword
                            echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                            placeholderText: Translation.tr("Enter password")
                        }

                        RippleButton {
                            implicitWidth: 44
                            implicitHeight: 44
                            buttonRadius: Appearance.rounding.normal
                            colBackground: Appearance.colors.colLayer2
                            onClicked: root.showPassword = !root.showPassword
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer2
                                text: root.showPassword ? "visibility_off" : "visibility"
                            }
                        }
                    }

                    StyledText {
                        visible: !root.passwordValid
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colError
                        text: Translation.tr("Password must be at least 8 characters long")
                    }
                }

                // Band Selection
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        text: Translation.tr("Band")
                    }

                    StyledComboBox {
                        id: bandCombo
                        buttonIcon: "wifi"
                        textRole: "displayName"
                        model: [
                            { displayName: Translation.tr("2.4 GHz (bg) - Broader compatibility"), value: "bg" },
                            { displayName: Translation.tr("5 GHz (a) - Faster speed"), value: "a" }
                        ]
                        currentIndex: Math.max(0, model.findIndex(item => item.value === Network.hotspotConfigBand))
                    }
                }

                // Security Type Selection
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        text: Translation.tr("Security Type")
                    }

                    StyledComboBox {
                        id: securityCombo
                        buttonIcon: "lock"
                        textRole: "displayName"
                        model: [
                            { displayName: Translation.tr("WPA2-Personal (Standard)"), value: "wpa-psk" },
                            { displayName: Translation.tr("WPA3-Personal (Modern)"), value: "sae" },
                            { displayName: Translation.tr("Open (No Password)"), value: "none" }
                        ]
                        currentIndex: Math.max(0, model.findIndex(item => item.value === Network.hotspotConfigSecurity))
                    }
                }
            }
        }
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: root.dismiss()
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Save & Apply")
            enabled: root.canSave
            opacity: root.canSave ? 1.0 : 0.4
            onClicked: {
                const ssid = ssidField.text.trim();
                const pass = passwordField.text;
                const bandItem = bandCombo.model[bandCombo.currentIndex];
                const band = (bandItem && bandItem.value) ? bandItem.value : "bg";
                const secItem = securityCombo.model[securityCombo.currentIndex];
                const sec = (secItem && secItem.value) ? secItem.value : "wpa-psk";
                Network.applyHotspotConfig(ssid, pass, band, sec);
                root.dismiss();
            }
        }
    }
}
