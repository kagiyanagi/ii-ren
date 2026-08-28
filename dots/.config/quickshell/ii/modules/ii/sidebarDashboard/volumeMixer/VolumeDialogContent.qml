import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

ColumnLayout {
    id: root
    required property bool isSink
    readonly property list<var> appPwNodes: isSink ? Audio.outputAppNodes : Audio.inputAppNodes
    readonly property list<var> devices: isSink ? Audio.outputDevices : Audio.inputDevices
    readonly property bool hasApps: appPwNodes.length > 0
    spacing: 16

    DialogSectionListView {
        Layout.fillHeight: true
        topMargin: 14

        model: ScriptModel {
            values: root.appPwNodes
        }
        delegate: VolumeMixerEntry {
            anchors {
                left: parent?.left
                right: parent?.right
            }
            required property var modelData
            node: modelData
        }
        PagePlaceholder {
            icon: "widgets"
            title: Translation.tr("No applications")
            shown: !root.hasApps
            shape: MaterialShape.Shape.Cookie7Sided
        }
    }

    Flow { // A click picks one device; with "Multiple" on, it adds or drops one
        Layout.fillWidth: true
        Layout.bottomMargin: 6
        spacing: 4

        Repeater {
            model: ScriptModel {
                values: root.devices
            }
            delegate: SelectionGroupButton {
                required property var modelData
                leftmost: true
                rightmost: true
                buttonText: Audio.friendlyDeviceName(modelData)
                toggled: Audio.isActiveDevice(modelData, root.isSink)
                onClicked: Audio.pickDevice(modelData, root.isSink)
            }
        }

        SelectionGroupButton {
            leftmost: true
            rightmost: true
            buttonIcon: "speaker_group"
            buttonText: Translation.tr("Multiple")
            toggled: Audio.multiDeviceEnabled(root.isSink)
            onClicked: Audio.setMultiDeviceEnabled(root.isSink, !toggled)
        }
    }

    component DialogSectionListView: StyledListView {
        Layout.fillWidth: true
        Layout.topMargin: -22
        Layout.bottomMargin: -16
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
        topMargin: 12
        bottomMargin: 12
        leftMargin: 20
        rightMargin: 20

        clip: true
        spacing: 4
        animateAppearance: false
    }

    Component {
        id: listElementComp
        ListElement {}
    }
}
