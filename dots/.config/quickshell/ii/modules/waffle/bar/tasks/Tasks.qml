pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.waffle.looks

MouseArea {
    id: root

    Layout.fillHeight: true
    implicitHeight: appRow.implicitHeight
    implicitWidth: appRow.implicitWidth
    hoverEnabled: true

    function showPreviewPopup(appEntry, button) {
        previewPopup.show(appEntry, button);
    }

    Behavior on implicitWidth {
        animation: Looks.transition.move.createObject(this)
    }

    WListView {
        id: appRow
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        orientation: Qt.Horizontal
        spacing: 0
        implicitWidth: contentWidth
        clip: true
        interactive: false
        model: ScriptModel {
            objectProp: "appId"
            values: (TaskbarApps.apps ?? []).filter(app => app?.appId !== "SEPARATOR")
        }
        delegate: TaskAppButton {
            id: taskButton
            required property var modelData
            appEntry: modelData

            onHoverPreviewRequested: {
                root.showPreviewPopup(taskButton.appEntry, taskButton);
            }
            onHoverPreviewDismissed: {
                previewPopup.close();
            }
        }
    }

    // Previews popup
    TaskPreview {
        id: previewPopup
        tasksHovered: root.containsMouse
        anchor.window: root.QsWindow.window
    }
}
