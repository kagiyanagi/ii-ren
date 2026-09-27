pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks

BarPopup {
    id: root
    property var model: [
        { iconName: "start-here", text: "Start", action: () => { print("hello"); } },
        { type: "separator" },
    ]
    readonly property bool hasIcons: (root.model ?? []).some(item => item?.iconName !== undefined && item?.iconName !== "")
    padding: 2

    contentItem: ColumnLayout {
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: root.model
            delegate: DelegateChooser {
                role: "type"
                DelegateChoice {
                    roleValue: "separator"
                    Rectangle {
                        Layout.topMargin: 2
                        Layout.bottomMargin: 2
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Looks.colors.bg0Border
                    }
                }
                DelegateChoice {
                    roleValue: undefined
                    WButton {
                        id: btn
                        Layout.fillWidth: true
                        inset: 2

                        required property var modelData
                        forceShowIcon: root.hasIcons
                        icon.name: btn.modelData?.iconName ? btn.modelData.iconName : ""
                        monochromeIcon: btn.modelData?.monochromeIcon ?? true
                        text: btn.modelData?.text ? btn.modelData.text : ""

                        onClicked: {
                            if (btn.modelData?.action) btn.modelData.action();
                            root.close();
                        }
                    }
                }
            }
        }
    }
}
