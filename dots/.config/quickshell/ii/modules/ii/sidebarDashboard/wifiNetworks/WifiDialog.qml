import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

WindowDialog {
    id: root

    Component.onCompleted: if (Config.options.networking.wifiPowerSave.enable) Network.fetchWifiPowerSave()

    WindowDialogTitle {
        id: title
        text: Translation.tr("Connect to Wi-Fi")
    }
    StyledIndeterminateProgressBar {
        id: scanBar
        visible: Network.wifiScanning
        Layout.fillWidth: true
        Layout.bottomMargin: -8
    }
    // ClippingRectangle: plain `clip` only clips to the bounding box, so a
    // row's hover fill would square off the card's corners.
    // It fits its rows, and scrolls only where the sidebar is too short for them.
    // It was a fixed 600px dialog, a third of it empty with four networks in range.
    ClippingRectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(
            Math.max(list.contentHeight + list.topMargin + list.bottomMargin, placeholder.shown ? placeholder.iconWidget.implicitHeight + placeholder.titleWidget.implicitHeight + 4 + root.dialogPadding * 2 : 0),
            root.height - title.implicitHeight - (scanBar.visible ? scanBar.implicitHeight : 0)
                - (powerSaveCard.visible ? powerSaveCard.implicitHeight : 0) - buttonRow.implicitHeight - root.dialogPadding * 7)
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainerHigh

        StyledListView {
            id: list
            anchors.fill: parent
            topMargin: 8
            bottomMargin: 8
            spacing: 0
            animateAppearance: false

            model: ScriptModel {
                values: Network.friendlyWifiNetworks
            }
            delegate: WifiNetworkItem {
                required property WifiAccessPoint modelData
                wifiNetwork: modelData
                width: ListView.view.width
            }
        }

        PagePlaceholder {
            id: placeholder
            shown: Network.friendlyWifiNetworks.length === 0
            icon: "wifi_find"
            title: !Network.wifiEnabled ? Translation.tr("Wi-Fi is off")
                : Network.wifiScanning ? Translation.tr("Searching for networks")
                : Translation.tr("No networks found")
            shape: MaterialShape.Shape.Cookie7Sided
        }
    }
    // The network rows' card and row, so it reads as part of this list rather
    // than a settings row dropped in under it. A plain Rectangle: nothing scrolls
    // under these corners, and the row's own mask already rounds its fill.
    Rectangle {
        id: powerSaveCard
        visible: Config.options.networking.wifiPowerSave.enable
        Layout.fillWidth: true
        implicitHeight: powerSaveRow.implicitHeight
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainerHigh

        DialogListItem {
            id: powerSaveRow
            readonly property bool saving: Network.wifiPowerSave === "on"
            anchors.fill: parent
            buttonRadius: Appearance.rounding.large
            enabled: Network.wifiPowerSave !== ""
            onClicked: Network.setWifiPowerSave(!saving)

            contentItem: RowLayout {
                spacing: 10
                MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.larger
                    text: "energy_savings_leaf"
                    color: Appearance.colors.colOnSurfaceVariant
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                        text: Translation.tr("Power saving")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                        // "" is no station to set it on: no adapter, or the hotspot has it.
                        text: !powerSaveRow.enabled ? Translation.tr("Unavailable")
                            : powerSaveRow.saving ? Translation.tr("Saves battery, adds latency")
                            : Translation.tr("Full speed, uses more battery")
                    }
                }
                StyledSwitch {
                    // The row owns the state: a switch that toggled itself would
                    // break this binding, and a cancelled prompt could not undo it.
                    checkable: false
                    checked: powerSaveRow.saving
                    down: powerSaveRow.down
                    focusPolicy: Qt.NoFocus
                    opacity: 1 // the row already dims to 0.4 when disabled (3.1)
                    onClicked: powerSaveRow.clicked()
                }
            }
        }
    }
    WindowDialogButtonRow {
        id: buttonRow
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
                GlobalStates.sidebarRightOpen = false;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}