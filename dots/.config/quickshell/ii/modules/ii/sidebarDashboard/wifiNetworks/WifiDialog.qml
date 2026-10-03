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
    // A share of the sidebar rather than the Bluetooth dialog's fixed 600, so it
    // scales with the screen (about 600 at 1080p). Fixed while open: a card that
    // followed its rows re-centred on every scan and when a password field opened,
    // and moved the rows out from under the pointer.
    backgroundHeight: Math.round(root.height * 0.6)

    Component.onCompleted: if (Config.options.networking.wifiPowerSave.enable) Network.fetchWifiPowerSave()

    onRefreshRequested: Network.rescanWifi()

    WindowDialogTitle {
        text: Translation.tr("Connect to Wi-Fi")
    }
    // ClippingRectangle: plain `clip` only clips to the bounding box, so a
    // row's hover fill would square off the card's corners.
    ClippingRectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainerHigh

        // On the card's top edge, over the list's top margin (M3: a linear
        // indicator sits on its container's edge). It used to be a row of its
        // own that came and went with every scan and moved the list 12px.
        StyledIndeterminateProgressBar {
            id: scanBar
            readonly property bool scanning: Network.wifiScanning
            property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
            anchors { top: parent.top; left: parent.left; right: parent.right }
            z: 1
            opacity: {
                scanBar.fadeSpec = scanBar.scanning ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
                return scanBar.scanning ? 1 : 0;
            }
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation {
                    duration: scanBar.fadeSpec.duration
                    easing.type: scanBar.fadeSpec.type
                    easing.bezierCurve: scanBar.fadeSpec.bezierCurve
                }
            }
        }

        StyledListView {
            // Pull to refresh: let go after dragging the list 80px past its top
            // (AOSP PullToRefreshDefaults.PositionalThreshold).
            onDragEnded: if (-verticalOvershoot >= 80) Network.rescanWifi()
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