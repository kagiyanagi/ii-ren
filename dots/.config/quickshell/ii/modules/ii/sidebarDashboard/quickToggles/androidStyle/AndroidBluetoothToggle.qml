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

    wide2x2OverrideComponent: btWide2x2
    tall1x2OverrideComponent: btTall1x2

    function getDeviceImageSource(device) {
        if (!device)
            return "";
        var custom = Config.options.bluetoothDeviceImages.find(function(d) {
            return d.mac === device.address;
        });
        if (custom)
            return "file://" + Directories.shellConfig + "/bluetooth_images/" + custom.image;
        return "";
    }

    Component {
        id: btWide2x2

        Item {
            anchors.fill: parent

            Item {
                id: connectedView
                anchors.fill: parent
                visible: BluetoothStatus.connected

                readonly property var device: BluetoothStatus.firstActiveDevice
                readonly property string deviceName:   connectedView.device?.name ?? ""
                readonly property string deviceIcon:   connectedView.device?.icon ?? ""
                readonly property string customImg:    root.getDeviceImageSource(connectedView.device)
                readonly property bool   hasCustomImg: connectedView.customImg !== ""
                readonly property bool isEarbud: {
                    var ic = connectedView.deviceIcon.toLowerCase();
                    var nm = connectedView.deviceName.toLowerCase();
                    return !connectedView.hasCustomImg &&
                        (ic.includes("headset") || ic.includes("headphone")
                         || ic.includes("audio") || nm.includes("buds"));
                }
                readonly property real batteryFraction: connectedView.device?.battery ?? -1
                readonly property bool hasBattery:
                    (connectedView.device?.batteryAvailable ?? false)
                    && connectedView.batteryFraction >= 0
                readonly property int batteryPct: Math.round(connectedView.batteryFraction * 100)

                // Same depth as ExpressiveBluetoothDevicesPopup
                readonly property string pathCushion:
                    "../../../../../assets/images/devices/earbuds_cushion.svg"
                readonly property string pathStem:
                    "../../../../../assets/images/devices/earbuds_stem.svg"

                readonly property color colCushion: root.toggled
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnLayer3
                readonly property color colStem: root.toggled
                    ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colOnLayer3

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(connectedView.height * 0.60)

                        MaterialShape {
                            id: connectedWideShape
                            width: 66
                            height: 66
                            anchors.centerIn: parent
                            shapeString: "Clover8Leaf"
                            color: root.toggled
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer3

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            Image {
                                anchors.centerIn: parent
                                visible: connectedView.hasCustomImg
                                source: connectedView.customImg
                                width: parent.width - 12
                                height: parent.height - 12
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                            }

                            Row {
                                anchors.centerIn: parent
                                spacing: 2
                                visible: connectedView.isEarbud

                                Item {
                                    width: 22; height: 36
                                    anchors.verticalCenter: parent.verticalCenter
                                    Item {
                                        anchors.fill: parent
                                        layer.enabled: true
                                        layer.effect: ColorOverlay { color: connectedView.colCushion }
                                        Image {
                                            anchors.fill: parent
                                            source: connectedView.pathCushion
                                            sourceSize: Qt.size(width, height)
                                            mirror: true
                                        }
                                    }
                                    Item {
                                        anchors.fill: parent
                                        layer.enabled: true
                                        layer.effect: ColorOverlay { color: connectedView.colStem }
                                        Image {
                                            anchors.fill: parent
                                            source: connectedView.pathStem
                                            sourceSize: Qt.size(width, height)
                                            mirror: true
                                        }
                                    }
                                }

                                Item {
                                    width: 22; height: 36
                                    anchors.verticalCenter: parent.verticalCenter
                                    Item {
                                        anchors.fill: parent
                                        layer.enabled: true
                                        layer.effect: ColorOverlay { color: connectedView.colCushion }
                                        Image {
                                            anchors.fill: parent
                                            source: connectedView.pathCushion
                                            sourceSize: Qt.size(width, height)
                                        }
                                    }
                                    Item {
                                        anchors.fill: parent
                                        layer.enabled: true
                                        layer.effect: ColorOverlay { color: connectedView.colStem }
                                        Image {
                                            anchors.fill: parent
                                            source: connectedView.pathStem
                                            sourceSize: Qt.size(width, height)
                                        }
                                    }
                                }
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: !connectedView.hasCustomImg && !connectedView.isEarbud
                                fill: root.toggled ? 1 : 0
                                text: Icons.getBluetoothDeviceMaterialSymbol(connectedView.deviceIcon)
                                iconSize: 28
                                color: root.toggled
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnLayer3
                                horizontalAlignment: Text.AlignHCenter

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        text: connectedView.deviceName
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.bottomMargin: 4
                        visible: connectedView.hasBattery
                        text: connectedView.batteryPct + Translation.tr("% battery")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Thin
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: !BluetoothStatus.connected

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialShape {
                        Layout.alignment: Qt.AlignHCenter
                        shapeString: "Clover8Leaf"
                        implicitSize: 66
                        color: BluetoothStatus.enabled
                            ? Appearance.colors.colLayer3
                            : Appearance.colors.colSurfaceContainerLow

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                            iconSize: 28
                            color: BluetoothStatus.enabled
                                ? Appearance.colors.colOnLayer3
                                : Appearance.colors.colOnSurfaceVariant
                            horizontalAlignment: Text.AlignHCenter

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        text: BluetoothStatus.enabled
                            ? Translation.tr("No devices")
                            : Translation.tr("Bluetooth off")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.35)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    Component {
        id: btTall1x2

        Item {
            anchors.fill: parent

            Item {
                id: connectedTall
                anchors.fill: parent
                visible: BluetoothStatus.connected

                readonly property var device: BluetoothStatus.firstActiveDevice
                readonly property string deviceName:   connectedTall.device?.name ?? ""
                readonly property string deviceIcon:   connectedTall.device?.icon ?? ""
                readonly property string customImg:    root.getDeviceImageSource(connectedTall.device)
                readonly property bool   hasCustomImg: connectedTall.customImg !== ""
                readonly property bool isEarbud: {
                    var ic = connectedTall.deviceIcon.toLowerCase();
                    var nm = connectedTall.deviceName.toLowerCase();
                    return !connectedTall.hasCustomImg &&
                        (ic.includes("headset") || ic.includes("headphone")
                         || ic.includes("audio") || nm.includes("buds"));
                }
                readonly property real batteryFraction: connectedTall.device?.battery ?? -1
                readonly property bool hasBattery:
                    (connectedTall.device?.batteryAvailable ?? false)
                    && connectedTall.batteryFraction >= 0
                readonly property int batteryPct: Math.round(connectedTall.batteryFraction * 100)

                readonly property string pathCushion:
                    "../../../../../assets/images/devices/earbuds_cushion.svg"
                readonly property string pathStem:
                    "../../../../../assets/images/devices/earbuds_stem.svg"
                readonly property color colCushion: root.toggled
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnLayer3
                readonly property color colStem: root.toggled
                    ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colOnLayer3

                ColumnLayout {
                    anchors.fill: parent
                    spacing: -4

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(connectedTall.height * 0.60)

                        MouseArea {
                            id: btTallIconMouseArea
                            width: 54
                            height: 54
                            anchors.centerIn: parent
                            hoverEnabled: true
                            acceptedButtons: root.altAction ? Qt.LeftButton : Qt.NoButton
                            cursorShape: Qt.PointingHandCursor

                            onClicked: root.mainAction()

                            MaterialShape {
                                id: connectedTallShape
                                anchors.fill: parent
                                shapeString: "Clover8Leaf"
                                color: root.toggled
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colLayer3

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }

                                Image {
                                    anchors.centerIn: parent
                                    visible: connectedTall.hasCustomImg
                                    source: connectedTall.customImg
                                    width: parent.width - 12
                                    height: parent.height - 12
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true; mipmap: true
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    visible: connectedTall.isEarbud

                                    Item {
                                        width: 18; height: 28
                                        anchors.verticalCenter: parent.verticalCenter
                                        Item {
                                            anchors.fill: parent
                                            layer.enabled: true
                                            layer.effect: ColorOverlay { color: connectedTall.colCushion }
                                            Image {
                                                anchors.fill: parent
                                                source: connectedTall.pathCushion
                                                sourceSize: Qt.size(width, height)
                                                mirror: true
                                            }
                                        }
                                        Item {
                                            anchors.fill: parent
                                            layer.enabled: true
                                            layer.effect: ColorOverlay { color: connectedTall.colStem }
                                            Image {
                                                anchors.fill: parent
                                                source: connectedTall.pathStem
                                                sourceSize: Qt.size(width, height)
                                                mirror: true
                                            }
                                        }
                                    }
                                    Item {
                                        width: 18; height: 28
                                        anchors.verticalCenter: parent.verticalCenter
                                        Item {
                                            anchors.fill: parent
                                            layer.enabled: true
                                            layer.effect: ColorOverlay { color: connectedTall.colCushion }
                                            Image {
                                                anchors.fill: parent
                                                source: connectedTall.pathCushion
                                                sourceSize: Qt.size(width, height)
                                            }
                                        }
                                        Item {
                                            anchors.fill: parent
                                            layer.enabled: true
                                            layer.effect: ColorOverlay { color: connectedTall.colStem }
                                            Image {
                                                anchors.fill: parent
                                                source: connectedTall.pathStem
                                                sourceSize: Qt.size(width, height)
                                            }
                                        }
                                    }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: !connectedTall.hasCustomImg && !connectedTall.isEarbud
                                    fill: root.toggled ? 1 : 0
                                    text: Icons.getBluetoothDeviceMaterialSymbol(connectedTall.deviceIcon)
                                    iconSize: 26
                                    color: root.toggled
                                        ? Appearance.colors.colOnPrimary
                                        : Appearance.colors.colOnLayer3
                                    horizontalAlignment: Text.AlignHCenter

                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                }
                            }

                            Loader {
                                anchors.fill: parent
                                active: root.altAction
                                sourceComponent: Rectangle {
                                    radius: connectedTallShape.radius
                                    color: ColorUtils.transparentize(
                                        root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3,
                                        btTallIconMouseArea.containsPress ? 0.88 : btTallIconMouseArea.containsMouse ? 0.95 : 1
                                    )
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
                        text: connectedTall.deviceName
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        Layout.bottomMargin: 8
                        visible: connectedTall.hasBattery
                        text: connectedTall.batteryPct + Translation.tr("% battery")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Thin
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.4)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: !BluetoothStatus.connected

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    MouseArea {
                        id: btTallDisconnectedMouseArea
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 54
                        Layout.preferredHeight: 54
                        hoverEnabled: true
                        acceptedButtons: root.altAction ? Qt.LeftButton : Qt.NoButton
                        cursorShape: Qt.PointingHandCursor

                        onClicked: root.mainAction()

                        MaterialShape {
                            id: disconnectedTallShape
                            anchors.centerIn: parent
                            shapeString: "Clover8Leaf"
                            implicitSize: 54
                            color: BluetoothStatus.enabled
                                ? Appearance.colors.colLayer3
                                : Appearance.colors.colSurfaceContainerLow
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                                iconSize: 26
                                color: BluetoothStatus.enabled
                                    ? Appearance.colors.colOnLayer3
                                    : Appearance.colors.colOnSurfaceVariant
                                horizontalAlignment: Text.AlignHCenter
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }

                            Loader {
                                anchors.fill: parent
                                active: root.altAction
                                sourceComponent: Rectangle {
                                    radius: disconnectedTallShape.radius
                                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer3, btTallDisconnectedMouseArea.containsPress ? 0.88 : btTallDisconnectedMouseArea.containsMouse ? 0.95 : 1)
                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        text: BluetoothStatus.enabled
                            ? Translation.tr("No devices")
                            : Translation.tr("BT off")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.35)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
