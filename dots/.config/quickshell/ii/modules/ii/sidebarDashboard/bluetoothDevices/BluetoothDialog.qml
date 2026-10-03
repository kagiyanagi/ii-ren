import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Widgets

WindowDialog {
    id: root
    backgroundHeight: 600

    // Refreshing restarts discovery: it starts again only once BlueZ has confirmed the
    // stop, since a StartDiscovery sent while it is still stopping is refused.
    property bool restartPending: false
    function restartDiscovery(): void {
        const adapter = Bluetooth.defaultAdapter;
        if (!adapter?.enabled) return;
        root.restartPending = adapter.discovering;
        adapter.discovering = !adapter.discovering;
    }
    Connections {
        target: Bluetooth.defaultAdapter
        function onDiscoveringChanged() {
            if (!root.restartPending || Bluetooth.defaultAdapter.discovering) return;
            root.restartPending = false;
            Bluetooth.defaultAdapter.discovering = true;
        }
    }
    onRefreshRequested: root.restartDiscovery()

    WindowDialogTitle {
        text: Translation.tr("Bluetooth devices")
    }
    StyledIndeterminateProgressBar {
        visible: Bluetooth.defaultAdapter?.discovering ?? false
        Layout.fillWidth: true
        Layout.bottomMargin: -8
    }
    // ClippingRectangle: plain `clip` only clips to the bounding box, so a
    // row's hover fill would square off the card's corners.
    ClippingRectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainerHigh

        StyledListView {
            // Pull to refresh: let go after dragging the list 80px past its top
            // (AOSP PullToRefreshDefaults.PositionalThreshold).
            onDragEnded: if (-verticalOvershoot >= 80) root.restartDiscovery()
            anchors.fill: parent
            topMargin: 8
            bottomMargin: 8
            spacing: 0
            animateAppearance: false

            model: ScriptModel {
                values: BluetoothStatus.friendlyDeviceList
            }
            delegate: BluetoothDeviceItem {
                required property BluetoothDevice modelData
                device: modelData
                width: ListView.view.width
            }
        }

        PagePlaceholder {
            shown: BluetoothStatus.friendlyDeviceList.length === 0
            icon: "bluetooth_searching"
            title: !BluetoothStatus.available ? Translation.tr("Bluetooth unavailable")
                : Bluetooth.defaultAdapter?.discovering ? Translation.tr("Searching for devices")
                : Translation.tr("No devices found")
            shape: MaterialShape.Shape.Cookie7Sided
        }
    }
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`]);
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
