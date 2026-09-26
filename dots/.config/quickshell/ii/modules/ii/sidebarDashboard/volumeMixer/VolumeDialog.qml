import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    property bool isSink: true
    // The Wi-Fi dialog's height: a share of the sidebar, so it scales with the screen
    // (about 600 at 1080p), and fixed while open, so a stream arriving or a device
    // joining scrolls the body instead of re-centring the card under the pointer.
    backgroundHeight: Math.round(root.height * 0.6)

    WindowDialogTitle {
        text: root.isSink ? Translation.tr("Audio output") : Translation.tr("Audio input")
    }

    VolumeDialogContent {
        isSink: root.isSink
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.volumeMixer}`]);
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
