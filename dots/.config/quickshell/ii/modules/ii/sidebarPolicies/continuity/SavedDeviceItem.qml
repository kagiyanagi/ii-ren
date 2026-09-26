pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

/**
 * A paired bluetooth device that is not connected. The card is a layout; the
 * Connect pill is the one target, so a stray click on the card does nothing.
 * Once it connects the device leaves this list, and turns up under Audio if
 * it reports a battery.
 */
Rectangle {
    id: root
    required property BluetoothDevice modelData
    // What the last attempt said. It stays until the next one.
    property string failure: ""

    readonly property bool connecting: root.modelData?.state === BluetoothDeviceState.Connecting
    readonly property real padding: 12

    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + root.padding * 2
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    // Quickshell puts a failed connect() straight back to Disconnected, with no signal of its own.
    onConnectingChanged: if (!root.connecting && root.modelData?.state === BluetoothDeviceState.Disconnected)
        root.failure = Translation.tr("Couldn't connect")

    RowLayout {
        id: row
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 12

        MaterialSymbol {
            Layout.preferredWidth: 24
            horizontalAlignment: Text.AlignHCenter
            text: Icons.getBluetoothDeviceMaterialSymbol(root.modelData?.icon ?? "")
            iconSize: 20
            fill: 1
            color: Appearance.colors.colSubtext
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: root.modelData?.name ?? ""
                // Names come from the devices themselves; rich text would let one fetch an <img>.
                textFormat: Text.PlainText
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: root.connecting ? Translation.tr("Connecting…") : root.failure !== "" ? root.failure : Translation.tr("Saved")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.failure !== "" && !root.connecting ? Appearance.colors.colError : Appearance.colors.colSubtext
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                elide: Text.ElideRight
            }
        }

        CardAction {
            // A tap mid-attempt does nothing, so it must not look accepted.
            enabled: !root.connecting
            materialIcon: "link"
            mainText: Translation.tr("Connect")
            onClicked: {
                root.failure = "";
                root.modelData?.connect();
            }
        }
    }
}
