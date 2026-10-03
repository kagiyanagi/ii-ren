import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

// A tap does what the device most needs: connect, disconnect, or pair and then
// connect, as in Android's Bluetooth tile dialog. Forget is behind the chevron,
// a deliberate second tap away.
DialogListItem {
    id: root
    required property BluetoothDevice device
    property bool expanded: false
    // What this row's last connect attempt said. It stays until the next tap.
    property string failure: ""

    readonly property bool paired: device?.paired ?? false
    readonly property bool pairing: BluetoothStatus.pairTarget === device
    readonly property bool connecting: device?.state === BluetoothDeviceState.Connecting
    readonly property bool busy: pairing || connecting || device?.state === BluetoothDeviceState.Disconnecting
    readonly property bool failed: failure !== "" || BluetoothStatus.pairFailed === device

    pointingHandCursor: !busy
    // A tap mid-transition does nothing, so it must not look accepted.
    rippleEnabled: !busy
    onPairedChanged: if (!paired) expanded = false
    // Quickshell puts a failed connect() straight back to Disconnected.
    onConnectingChanged: if (!connecting && device?.state === BluetoothDeviceState.Disconnected) failure = Translation.tr("Couldn't connect")

    onClicked: {
        if (busy || !device)
            return;
        failure = "";
        if (!device.paired)
            BluetoothStatus.pair(device);
        else if (device.connected)
            device.disconnect();
        else
            device.connect();
    }
    altAction: () => { if (root.paired) root.expanded = !root.expanded; }

    contentItem: ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 0

        RowLayout {
            spacing: 10

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                text: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon || "")
                color: root.device?.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideRight
                    text: root.device?.name || Translation.tr("Unknown device")
                    textFormat: Text.PlainText
                }
                StyledText {
                    id: statusText
                    visible: text !== ""
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.failed && !root.busy ? Appearance.colors.colError : Appearance.colors.colSubtext
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    elide: Text.ElideRight
                    // What the device is doing now comes first, then how the last
                    // attempt went, then what it is.
                    text: {
                        if (root.pairing)
                            return Translation.tr("Pairing…");
                        if (root.connecting)
                            return Translation.tr("Connecting…");
                        if (root.busy)
                            return Translation.tr("Disconnecting…");
                        if (BluetoothStatus.pairFailed === root.device)
                            return BluetoothStatus.agentUnavailable ? Translation.tr("Can't pair: bluetoothctl not available") : Translation.tr("Couldn't pair");
                        if (root.failure !== "")
                            return root.failure;
                        if (root.device?.connected) {
                            const connected = Translation.tr("Connected");
                            return root.device.batteryAvailable ? `${connected} • ${Math.round(root.device.battery * 100)}%` : connected;
                        }
                        return root.paired ? Translation.tr("Paired") : "";
                    }
                }
            }

            RippleButton {
                visible: root.paired
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer4)
                colBackgroundHover: Appearance.colors.colLayer4Hover
                colRipple: Appearance.colors.colLayer4Active
                colStateLayer: Appearance.colors.colOnLayer4
                onClicked: root.expanded = !root.expanded

                // RippleButton sizes the content box, and a glyph is drawn at its
                // start, so it sat off-centre. The rotation then mirrored the offset
                // and slid the arrow sideways as it flipped. Centre it in the box.
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer3
                    rotation: root.expanded ? 180 : 0
                    // The row's height change runs on elementMove, so the flip rides
                    // the same spec and reads as one gesture. elementMoveSmall's
                    // curve overshoots hardest of any token, and over 180 degrees
                    // that was a visible wobble.
                    Behavior on rotation {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }

                StyledToolTip {
                    text: root.expanded ? Translation.tr("Hide options") : Translation.tr("Show options")
                }
            }
        }

        // Fades out before the row's height drops, rather than vanishing on the
        // collapse's first frame. The height itself is DialogListItem's.
        DialogButton {
            id: forgetButton
            property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
            opacity: {
                forgetButton.fadeSpec = root.expanded ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
                return root.expanded ? 1 : 0;
            }
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation {
                    duration: forgetButton.fadeSpec.duration
                    easing.type: forgetButton.fadeSpec.type
                    easing.bezierCurve: forgetButton.fadeSpec.bezierCurve
                }
            }
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: 8
            buttonText: Translation.tr("Forget")
            colEnabled: Appearance.colors.colError
            // The row under it is already painting layer 3's hover.
            colBackgroundHover: Appearance.colors.colLayer4Hover
            colRipple: Appearance.colors.colLayer4Active
            onClicked: root.device?.forget()
        }
    }
}
