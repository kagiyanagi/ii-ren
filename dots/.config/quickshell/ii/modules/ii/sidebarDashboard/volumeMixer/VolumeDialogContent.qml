import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// Where the sound goes first, since the dialog is named for it, then one row per
// app. Top-aligned in whatever height its host gives it, and scrolls past that.
StyledFlickable {
    id: root
    required property bool isSink
    readonly property list<var> appPwNodes: isSink ? Audio.outputAppNodes : Audio.inputAppNodes
    readonly property list<var> devices: isSink ? Audio.outputDevices : Audio.inputDevices
    readonly property bool multiple: Audio.multiDeviceEnabled(isSink)
    // Nothing to combine with one device, but a leftover set must stay switchable off.
    readonly property bool showMultiple: devices.length > 1 || multiple
    // Two or more members: a combined device exists and each member has a balance slider.
    readonly property bool combined: Audio.combinedNames(isSink).length > 1

    implicitHeight: body.implicitHeight
    contentHeight: body.implicitHeight
    contentWidth: width
    clip: true

    PwObjectTracker { // a device's volume is only readable and writable while tracked
        objects: root.devices
    }

    function deviceIcon(node) {
        const name = node?.name ?? "";
        if (name.startsWith("bluez")) return "headphones";
        if (name.includes("hdmi")) return "tv";
        return root.isSink ? "speaker" : "mic";
    }

    ColumnLayout {
        id: body
        width: parent.width
        // At least the host's height, so the apps card can take what the devices leave.
        height: Math.max(implicitHeight, root.height)
        spacing: 12

        DialogCard {
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

                    contentItem: ColumnLayout {
                        spacing: 4
                        RowLayout {
                            spacing: 10
                            MaterialSymbol {
                                id: deviceIcon
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
                            // With devices combined a tap adds or drops one, so each row says which.
                            MaterialSymbol {
                                visible: root.multiple
                                iconSize: Appearance.font.pixelSize.larger
                                fill: deviceRow.inUse ? 1 : 0
                                text: deviceRow.inUse ? "check_circle" : "radio_button_unchecked"
                                color: deviceRow.inUse ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                        }
                        // A member's own volume is its balance against the others; the
                        // combined device, which the sidebar's volume slider drives, is the
                        // master over all of them.
                        RowLayout {
                            visible: root.combined && deviceRow.inUse
                            Layout.leftMargin: deviceIcon.width + 10
                            spacing: 8
                            StyledSlider {
                                Layout.fillWidth: true
                                configuration: StyledSlider.Configuration.S
                                value: deviceRow.modelData?.audio?.volume ?? 0
                                onMoved: deviceRow.modelData.audio.volume = value
                            }
                            StyledText {
                                Layout.preferredWidth: 36
                                horizontalAlignment: Text.AlignRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: `${Math.round((deviceRow.modelData?.audio?.volume ?? 0) * 100)}%`
                            }
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

        DialogCard { // stretches, like the Wi-Fi dialog's list card
            padding: 8
            Layout.fillHeight: true

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

            Item { // keeps the rows at the top of a card taller than they are
                visible: root.appPwNodes.length > 0
                Layout.fillHeight: true
            }

            EmptyLine {
                visible: root.appPwNodes.length === 0
                Layout.fillHeight: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.isSink ? Translation.tr("No apps are playing sound") : Translation.tr("No apps are recording")
            }
        }
    }

    component EmptyLine: StyledText {
        Layout.fillWidth: true
        Layout.margins: 8
        color: Appearance.colors.colSubtext
        elide: Text.ElideRight
    }
}
