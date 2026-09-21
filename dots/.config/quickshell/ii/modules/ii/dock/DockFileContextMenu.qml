import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import qs.services
import "./widgets"

DockContextMenuBase {
    id: root

    property string filePath: ""
    
    headerText: {
        const parts = (filePath ?? "").split("/").filter(s => s.length > 0)
        return parts[parts.length - 1] ?? filePath
    }
    headerSymbol: root.anchorItem?.mimeIcon ?? "insert_drive_file"

    readonly property string containingDir: {
        const idx = (filePath ?? "").lastIndexOf("/")
        return idx > 0 ? filePath.substring(0, idx) : ""
    }

    contentComponent: ColumnLayout {
        spacing: 0

        DockMenuButton {
            Layout.fillWidth: true
            symbolName: "open_in_new"
            labelText: qsTr("Open")
            onTriggered: {
                Qt.openUrlExternally("file://" + root.filePath)
                root.close()
            }
        }

        DockMenuButton {
            Layout.fillWidth: true
            symbolName: "folder_open"
            labelText: qsTr("Open containing folder")
            visible: root.containingDir !== ""
            onTriggered: {
                Qt.openUrlExternally("file://" + root.containingDir)
                root.close()
            }
        }

        // Law 11: whitespace, not a rule, holds the destructive row apart.
        Item {
            implicitHeight: 12
        }

        DockMenuButton {
            Layout.fillWidth: true
            symbolName: "do_not_disturb_on"
            labelText: qsTr("Remove from dock")
            isDestructive: true
            onTriggered: {
                TaskbarApps.removePinnedFile(root.filePath)
                root.close()
            }
        }
    }
}
