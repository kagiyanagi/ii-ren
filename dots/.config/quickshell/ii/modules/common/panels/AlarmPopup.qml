pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    readonly property bool wanted: Config.ready && Config.options.time.alarms.useFullscreenPopup
        && GlobalStates.alarmRinging && !GlobalStates.screenLocked
    property bool rendered: false
    // Hold the text while the service clears ringingAlarm during the exit.
    property var displayedAlarm: ({})

    function sync() {
        if (!root.wanted) return;
        root.displayedAlarm = AlarmService.ringingAlarm ?? {};
        root.rendered = true;
    }

    onWantedChanged: root.sync()
    Component.onCompleted: root.sync()

    Loader {
        active: root.rendered
        sourceComponent: PanelWindow {
            id: window
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:alarm"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Component.onCompleted: {
                dialog.show = root.wanted;
                stopButton.forceActiveFocus();
            }

            Connections {
                target: root
                function onWantedChanged() {
                    dialog.show = root.wanted;
                    if (root.wanted) stopButton.forceActiveFocus();
                }
            }

            WindowDialog {
                id: dialog
                anchors.fill: parent
                radius: 0
                backgroundWidth: Math.min(400, window.width - 32)
                onDismiss: AlarmService.stopRinging()
                onVisibleChanged: {
                    if (!visible && !root.wanted)
                        root.rendered = false;
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.displayedAlarm.time ?? ""
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.displayLarge
                    color: Appearance.colors.colPrimary
                }

                WindowDialogTitle {
                    text: root.displayedAlarm.label || Translation.tr("Alarm")
                    horizontalAlignment: Text.AlignHCenter
                }

                WindowDialogButtonRow {
                    Item { Layout.fillWidth: true }
                    DialogButton {
                        id: stopButton
                        buttonText: Translation.tr("Stop alarm")
                        onClicked: AlarmService.stopRinging()
                    }
                }
            }
        }
    }
}
