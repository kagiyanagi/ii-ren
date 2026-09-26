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

    WindowDialogTitle {
        id: title
        text: root.isSink ? Translation.tr("Audio output") : Translation.tr("Audio input")
    }

    VolumeDialogContent {
        isSink: root.isSink
        Layout.fillWidth: true
        // Scrolls only where the sidebar is too short for it; at 1080p it fits.
        Layout.preferredHeight: Math.min(implicitHeight, root.height - title.implicitHeight - buttonRow.implicitHeight - root.dialogPadding * 6)
    }

    WindowDialogButtonRow {
        id: buttonRow

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
