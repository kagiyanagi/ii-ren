import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

WindowDialog {
    id: root

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
    // Bound until a group button is picked, so the config nmcli reports after
    // opening still lands.
    property string band: Network.hotspotConfigBand
    property string security: Network.hotspotConfigSecurity
    readonly property bool openNetwork: security === "none"
    readonly property bool passwordValid: openNetwork || passwordField.text.length >= 8
    readonly property bool changed: ssidField.text.trim() !== Network.hotspotConfigSsid
        || band !== Network.hotspotConfigBand
        || security !== Network.hotspotConfigSecurity
        || (!openNetwork && passwordField.text !== Network.hotspotConfigPassword)
    readonly property bool canSave: changed && ssidField.text.trim().length > 0 && passwordValid

    readonly property string status: {
        if (!Network.hotspotSupported) return Translation.tr("Not supported by this Wi-Fi adapter");
        if (Network.hotspotSwitching) return Network.hotspotToggled ? Translation.tr("Turning off…") : Translation.tr("Turning on…");
        if (Network.hotspotToggled) {
            const n = Network.hotspotClientCount;
            const devices = n === 0 ? Translation.tr("No devices connected")
                : n === 1 ? Translation.tr("1 device connected")
                : Translation.tr("%1 devices connected").arg(n);
            return `${devices} · ${Translation.tr("%1 used").arg(root.formatBytes(Network.hotspotRxBytes + Network.hotspotTxBytes))}`;
        }
        // The hotspot takes the adapter, so a Wi-Fi uplink goes with it.
        if (Network.wifiStatus === "connected" && Network.networkName.length > 0) return Translation.tr("Disconnects from %1").arg(Network.networkName);
        return Translation.tr("Off");
    }

    WindowDialogTitle {
        text: Translation.tr("Hotspot")
    }

    // The Wi-Fi dialog's power-saving row, so the two network dialogs read as
    // one family.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: switchRow.implicitHeight
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainerHigh

        DialogListItem {
            id: switchRow
            anchors.fill: parent
            buttonRadius: Appearance.rounding.large
            enabled: Network.hotspotSupported
            // A busy row stays at full opacity: 0.4 means disabled, and this is working.
            onClicked: if (!Network.hotspotSwitching) Network.toggleHotspot()

            contentItem: RowLayout {
                spacing: 10
                MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.larger
                    text: "wifi_tethering"
                    color: Network.hotspotToggled ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                        text: Translation.tr("Use hotspot")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                        text: root.status
                    }
                }
                StyledSwitch {
                    // The row owns the state: a switch that toggled itself broke
                    // this binding, so a hotspot that failed to start showed as on.
                    checkable: false
                    checked: Network.hotspotToggled
                    down: switchRow.down
                    focusPolicy: Qt.NoFocus
                    opacity: 1 // the row already dims to 0.4 when disabled (3.1)
                    onClicked: switchRow.clicked()
                }
            }
        }
    }

    MaterialTextField {
        id: ssidField
        Layout.fillWidth: true
        text: Network.hotspotConfigSsid
        placeholderText: Translation.tr("Hotspot name")
    }

    // Dimmed rather than hidden for an open network: hiding it shrank the card,
    // which re-centres, and moved the security buttons out from under the pointer.
    ColumnLayout {
        Layout.fillWidth: true
        enabled: !root.openNetwork
        opacity: enabled ? 1 : 0.4
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        spacing: 4

        MaterialTextField {
            id: passwordField
            Layout.fillWidth: true
            text: Network.hotspotConfigPassword
            echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
            placeholderText: Translation.tr("Password")
            rightPadding: revealButton.width + 12

            // M3's trailing icon, inside the field. Centred on the outline, not the
            // control: the outlined style reserves the floating label's room above it.
            RippleButton {
                id: revealButton
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.background.verticalCenter
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                // It paints on the dialog, so its films come off layer 3 like
                // DialogButton's, and the column already dims it to 0.4 (3.1).
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3)
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colRipple: Appearance.colors.colLayer3Active
                colStateLayer: Appearance.colors.colOnLayer3
                opacity: 1
                onClicked: root.showPassword = !root.showPassword
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    text: root.showPassword ? "visibility_off" : "visibility"
                }
            }
        }

        // M3 supporting text: always there, so the rule is said before it is broken.
        StyledText {
            Layout.leftMargin: 16
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: !root.passwordValid && passwordField.text.length > 0 ? Appearance.colors.colError : Appearance.colors.colSubtext
            text: root.openNetwork ? Translation.tr("Not used by an open network") : Translation.tr("At least 8 characters")
        }
    }

    OptionGroup {
        title: Translation.tr("Band")
        value: root.band
        options: [
            { displayName: Translation.tr("2.4 GHz"), value: "bg" },
            { displayName: Translation.tr("5 GHz"), value: "a" }
        ]
        onPicked: v => root.band = v
    }

    OptionGroup {
        title: Translation.tr("Security")
        value: root.security
        options: [
            { displayName: "WPA2", value: "wpa-psk" },
            { displayName: "WPA3", value: "sae" },
            { displayName: Translation.tr("None"), value: "none" }
        ]
        onPicked: v => root.security = v
    }

    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: root.dismiss()
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Save")
            enabled: root.canSave
            onClicked: {
                Network.applyHotspotConfig(ssidField.text.trim(), root.openNetwork ? "" : passwordField.text, root.band, root.security);
                root.dismiss();
            }
        }
    }

    // A label and a connected button group, as in KeybindEditor.
    component OptionGroup: ColumnLayout {
        id: group
        required property string title
        required property var options
        required property string value
        signal picked(string value)
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: group.title
        }
        RowLayout {
            spacing: 2 // M3 Expressive connected group gap
            Repeater {
                model: group.options
                delegate: SelectionGroupButton {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: false
                    leftmost: index === 0
                    rightmost: index === group.options.length - 1
                    buttonText: modelData.displayName
                    toggled: group.value === modelData.value
                    onClicked: group.picked(modelData.value)
                }
            }
        }
    }
}
