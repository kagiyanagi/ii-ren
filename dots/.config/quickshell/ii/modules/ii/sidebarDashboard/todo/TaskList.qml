import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var taskList
    property string emptyPlaceholderIcon
    property string emptyPlaceholderText

    function jumpToEnd() {
        listView.jumpToEnd();
    }

    StyledListView {
        id: listView
        anchors.fill: parent
        spacing: 4
        popin: false
        model: ScriptModel {
            // Todo.list is reparsed on every write, so every object is new. Keyed,
            // a tick is one remove here instead of a rebuild of every row.
            objectProp: "key"
            values: root.taskList
        }
        delegate: Rectangle {
            id: taskRow
            required property var modelData
            readonly property bool done: modelData.done

            width: ListView.view.width
            implicitHeight: rowLayout.implicitHeight + rowLayout.anchors.margins * 2
            color: Appearance.colors.colLayer2
            radius: Appearance.rounding.small

            RowLayout {
                id: rowLayout
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                TodoItemActionButton {
                    Layout.alignment: Qt.AlignTop
                    materialIcon: taskRow.done ? "check_circle" : "radio_button_unchecked"
                    iconFill: taskRow.done ? 1 : 0
                    colIcon: taskRow.done ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                    onClicked: {
                        if (taskRow.done)
                            Todo.markUnfinished(taskRow.modelData.originalIndex);
                        else
                            Todo.markDone(taskRow.modelData.originalIndex);
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumHeight: 32 // One line centres on the buttons
                    verticalAlignment: Text.AlignVCenter
                    text: taskRow.modelData.content
                    wrapMode: Text.Wrap
                    color: taskRow.done ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer2
                    font.strikeout: taskRow.done
                }
                TodoItemActionButton {
                    Layout.alignment: Qt.AlignTop
                    materialIcon: "delete"
                    colIcon: Appearance.colors.colSubtext
                    onClicked: Todo.deleteItem(taskRow.modelData.originalIndex)
                }
            }
        }
    }

    PagePlaceholder {
        shown: root.taskList.length === 0
        icon: root.emptyPlaceholderIcon
        description: root.emptyPlaceholderText
        descriptionHorizontalAlignment: Text.AlignHCenter
    }
}
