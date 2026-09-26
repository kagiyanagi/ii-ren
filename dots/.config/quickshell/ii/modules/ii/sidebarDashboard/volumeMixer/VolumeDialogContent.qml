import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Where the sound goes first, since the dialog is named for it, then one row per
// app. Sized by its content; it scrolls only when its host is shorter than that.
StyledFlickable {
    id: root
    required property bool isSink
    readonly property list<var> appPwNodes: isSink ? Audio.outputAppNodes : Audio.inputAppNodes
    readonly property list<var> devices: isSink ? Audio.outputDevices : Audio.inputDevices
    readonly property bool multiple: Audio.multiDeviceEnabled(isSink)
    // Nothing to combine with one device, but a leftover set must stay switchable off.
    readonly property bool showMultiple: devices.length > 1 || multiple

    implicitHeight: body.implicitHeight
    contentHeight: body.implicitHeight
    contentWidth: width
    clip: true

    function deviceIcon(node) {
        const name = node?.name ?? "";
        if (name.startsWith("bluez")) return "headphones";
        if (name.includes("hdmi")) return "tv";
        return root.isSink ? "speaker" : "mic";
    }

    ColumnLayout {
        id: body
        width: parent.width
        spacing: 12

        Card {
            Repeater {
                model: ScriptModel {
                    values: root.devices
                }
                delegate: DialogListItem {
                    id: deviceRow
                    required property var modelData
                    required property int index
                    readonly property bool inUse: Audio.isActiveDevice(modelData, root.isSink)
                    Layout.fillWidth: true
                    // A second tap on the device in use does nothing unless devices are combined.
                    active: inUse && !root.multiple
                    topLeftRadius: index === 0 ? Appearance.rounding.large : 0
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: index === root.devices.length - 1 && !root.showMultiple ? Appearance.rounding.large : 0
                    bottomRightRadius: bottomLeftRadius
                    onClicked: Audio.pickDevice(modelData, root.isSink)

                    contentItem: RowLayout {
                        spacing: 10
                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.larger
                            text: root.deviceIcon(deviceRow.modelData)
                            color: deviceRow.inUse ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            color: deviceRow.inUse ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: Audio.friendlyDeviceName(deviceRow.modelData)
                        }
                    }
                }
            }

            EmptyLine {
                Layout.margins: 16
                visible: root.devices.length === 0
                text: Translation.tr("No devices")
            }

            // The Wi-Fi, hotspot and eye-protection dialogs' switch row: the row owns
            // the state and the switch never toggles itself.
            DialogListItem {
                id: multipleRow
                visible: root.showMultiple
                Layout.fillWidth: true
                topLeftRadius: root.devices.length === 0 ? Appearance.rounding.large : 0
                topRightRadius: topLeftRadius
                bottomLeftRadius: Appearance.rounding.large
                bottomRightRadius: bottomLeftRadius
                onClicked: Audio.setMultiDeviceEnabled(root.isSink, !root.multiple)

                contentItem: RowLayout {
                    spacing: 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnSurfaceVariant
                            elide: Text.ElideRight
                            text: root.isSink ? Translation.tr("Play on several devices") : Translation.tr("Record from several devices")
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: root.multiple
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                            text: Translation.tr("Tap a device to add or remove it")
                        }
                    }
                    StyledSwitch {
                        checkable: false
                        checked: root.multiple
                        down: multipleRow.down
                        focusPolicy: Qt.NoFocus
                        onClicked: multipleRow.clicked()
                    }
                }
            }
        }

        Card {
            padding: 8

            Repeater {
                model: ScriptModel {
                    values: root.appPwNodes
                }
                delegate: VolumeMixerEntry {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.rightMargin: 8
                    node: modelData
                }
            }

            EmptyLine {
                visible: root.appPwNodes.length === 0
                text: root.isSink ? Translation.tr("No apps are playing sound") : Translation.tr("No apps are recording")
            }
        }
    }

    component Card: Rectangle {
        id: card
        default property alias rows: cardColumn.data
        property real padding: 0
        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + padding * 2
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainerHigh

        ColumnLayout {
            id: cardColumn
            anchors {
                fill: parent
                margins: card.padding
            }
            spacing: 0
        }
    }

    component EmptyLine: StyledText {
        Layout.fillWidth: true
        Layout.margins: 8
        color: Appearance.colors.colSubtext
        elide: Text.ElideRight
    }
}
