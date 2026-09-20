pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ListView {
    id: root
    required property var directory
    property var breadcrumbDirectory: ""
    Component.onCompleted: breadcrumbDirectory = directory;
    onDirectoryChanged: {
        if (breadcrumbDirectory.startsWith(directory)) return;
        breadcrumbDirectory = directory
    }

    signal navigateToDirectory(string path)

    orientation: ListView.Horizontal
    clip: true
    spacing: 2

    model: breadcrumbDirectory.split("/")
    delegate: SelectionGroupButton {
        id: folderButton
        required property var modelData
        required property int index
        buttonText: folderButton.index === 0 ? "/" : folderButton.modelData
        toggled: {
            if (root.directory.trim() === "/") return folderButton.index === 0;
            return folderButton.index === root.directory.split("/").length - 1
        }
        leftmost: folderButton.index === 0
        rightmost: folderButton.index === root.breadcrumbDirectory.split("/").length - 1

        onClicked: {
            root.navigateToDirectory(root.breadcrumbDirectory.split("/").slice(0, folderButton.index + 1).join("/"))
        }
    }
}
