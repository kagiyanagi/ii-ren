import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property var tabButtonList: [{
        "icon": "checklist",
        "name": Translation.tr("Unfinished")
    }, {
        "name": Translation.tr("Done"),
        "icon": "check_circle"
    }]

    // Each task keeps its index into Todo.list, which is what the service takes,
    // and a key for the lists' models: its text, plus how many identical tasks
    // came before it so duplicates stay distinct.
    readonly property var tasks: {
        const seen = {};
        return Todo.list.map((item, i) => {
            seen[item.content] = (seen[item.content] ?? 0) + 1;
            return Object.assign({}, item, {
                "originalIndex": i,
                "key": `${seen[item.content]}:${item.content}`
            });
        });
    }

    function addTask() {
        const text = todoInput.text.trim();
        if (text.length === 0)
            return;
        Todo.addTask(text);
        todoInput.text = "";
        tabBar.setCurrentIndex(0);
        // append() lands the task after the last one, so that is where to look
        Qt.callLater(unfinishedList.jumpToEnd);
    }

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown)
                tabBar.incrementCurrentIndex();
            else if (event.key === Qt.Key_PageUp)
                tabBar.decrementCurrentIndex();
            event.accepted = true;
        } else if (event.key === Qt.Key_N) {
            todoInput.forceActiveFocus();
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        SecondaryTabBar {
            id: tabBar

            currentIndex: swipeView.currentIndex

            Repeater {
                model: root.tabButtonList

                delegate: SecondaryTabButton {
                    buttonText: modelData.name
                    buttonIcon: modelData.icon
                }
            }
        }

        SwipeView {
            id: swipeView

            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8
            clip: true
            currentIndex: tabBar.currentIndex
            // Tabs change from the tab bar only: a sideways touchpad swipe paged it
            interactive: false

            TaskList {
                id: unfinishedList
                emptyPlaceholderIcon: "check_circle"
                emptyPlaceholderText: Translation.tr("Nothing here!")
                taskList: root.tasks.filter(item => !item.done)
            }

            TaskList {
                emptyPlaceholderIcon: "checklist"
                emptyPlaceholderText: Translation.tr("Finished tasks will go here")
                taskList: root.tasks.filter(item => item.done)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ToolbarTextField {
                id: todoInput
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: 40
                colBackground: Appearance.colors.colLayer2
                placeholderText: Translation.tr("Add a task")
                onAccepted: root.addTask()
                // Clears first; an empty field lets Escape through to close the sidebar
                Keys.onEscapePressed: (event) => {
                    event.accepted = text.length > 0;
                    text = "";
                }
            }

            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                enabled: todoInput.text.trim().length > 0
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colStateLayer: Appearance.colors.colOnPrimary
                onClicked: root.addTask()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "add"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }
}
