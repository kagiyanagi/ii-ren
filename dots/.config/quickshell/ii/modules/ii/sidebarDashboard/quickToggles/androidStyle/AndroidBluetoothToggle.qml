import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Bluetooth

AndroidQuickToggleButton {
    id: root

    toggleModel: BluetoothToggle {}

    // The 2x2 and 1x2 tiles are one layout at two icon sizes. The icon is its own
    // target in both, so a tap there switches Bluetooth and the rest of the tile
    // opens the dialog: the 2x2 used to open the dialog wherever it was tapped.
    wide2x2OverrideComponent: btLayout
    tall1x2OverrideComponent: btLayout

    readonly property var device: BluetoothStatus.connected ? BluetoothStatus.firstActiveDevice : null
    readonly property string deviceName: root.device?.name ?? ""
    readonly property string deviceIcon: root.device?.icon ?? ""
    readonly property string customImg: {
        if (!root.device)
            return "";
        const custom = Config.options.bluetoothDeviceImages.find(d => d.mac === root.device.address);
        return custom ? "file://" + Directories.shellConfig + "/bluetooth_images/" + custom.image : "";
    }
    readonly property bool hasCustomImg: root.customImg !== ""
    readonly property bool isEarbud: {
        const ic = root.deviceIcon.toLowerCase();
        const nm = root.deviceName.toLowerCase();
        return !root.hasCustomImg && (ic.includes("headset") || ic.includes("headphone")
            || ic.includes("audio") || nm.includes("buds"));
    }
    readonly property real batteryFraction: root.device?.battery ?? -1
    readonly property bool hasBattery: (root.device?.batteryAvailable ?? false) && root.batteryFraction >= 0

    // Same depth as ExpressiveBluetoothDevicesPopup
    readonly property string pathCushion: "../../../../../assets/images/devices/earbuds_cushion.svg"
    readonly property string pathStem: "../../../../../assets/images/devices/earbuds_stem.svg"

    // On is colPrimary whether or not anything is connected, like the Wi-Fi tile
    // beside it. The disconnected icon used to be two greys, on and off.
    readonly property color colIconBase: root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
    readonly property color colOnIcon: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3

    component EarbudHalf: Item {
        id: half
        property bool mirrored: false
        width: root.isWide ? 22 : 18
        height: root.isWide ? 36 : 28
        anchors.verticalCenter: parent.verticalCenter

        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: ColorOverlay { color: root.colOnIcon }
            Image {
                anchors.fill: parent
                source: root.pathCushion
                sourceSize: Qt.size(width, height)
                mirror: half.mirrored
            }
        }
        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: ColorOverlay { color: Appearance.colors.colOnPrimaryContainer }
            Image {
                anchors.fill: parent
                source: root.pathStem
                sourceSize: Qt.size(width, height)
                mirror: half.mirrored
            }
        }
    }

    Component {
        id: btLayout

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(parent.height * 0.60)

                MouseArea {
                    id: btIconMouseArea
                    readonly property real size: root.isWide ? 66 : 54
                    width: size
                    height: size
                    anchors.centerIn: parent
                    hoverEnabled: true
                    acceptedButtons: root.altAction ? Qt.LeftButton : Qt.NoButton
                    cursorShape: Qt.PointingHandCursor

                    onClicked: root.mainAction()

                    MaterialShape {
                        anchors.fill: parent
                        shapeString: "Clover8Leaf"
                        // The state film is mixed into the fill rather than laid over it:
                        // a Rectangle over a ShapeCanvas paints a square (3.1, 10.8).
                        color: !root.altAction ? root.colIconBase
                            : btIconMouseArea.containsPress ? ColorUtils.mix(root.colOnIcon, root.colIconBase, 0.10)
                            : btIconMouseArea.containsMouse ? ColorUtils.mix(root.colOnIcon, root.colIconBase, 0.08)
                            : root.colIconBase

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        Image {
                            anchors.centerIn: parent
                            visible: root.hasCustomImg
                            source: root.customImg
                            width: parent.width - 12
                            height: parent.height - 12
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 2
                            visible: root.isEarbud
                            EarbudHalf {
                                mirrored: true
                            }
                            EarbudHalf {}
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !root.hasCustomImg && !root.isEarbud
                            fill: root.toggled ? 1 : 0
                            text: root.device ? Icons.getBluetoothDeviceMaterialSymbol(root.deviceIcon) : root.buttonIcon
                            iconSize: root.isWide ? 28 : 26
                            color: root.colOnIcon
                            horizontalAlignment: Text.AlignHCenter

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                text: root.device ? root.deviceName : root.name
                // The Wi-Fi tile's sizes, which sits beside this one at both sizes
                font.pixelSize: root.isWide ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.smallie
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.bottomMargin: 8
                visible: text !== ""
                text: root.device ? (root.hasBattery ? Translation.tr("%1% battery").arg(Math.round(root.batteryFraction * 100)) : "")
                    : BluetoothStatus.enabled ? Translation.tr("No devices") : Translation.tr("Off")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }
}
