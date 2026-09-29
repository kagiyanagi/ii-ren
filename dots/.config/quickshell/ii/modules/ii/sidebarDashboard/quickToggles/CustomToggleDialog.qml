import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

WindowDialog {
    id: root

    property string toggleId: ""
    readonly property bool isEditing: root.toggleId.length > 0
    property string icon: "terminal"

    backgroundWidth: 380
    // The sidebar dialogs' fixed height: the grid takes what the fields leave.
    backgroundHeight: Math.round(root.height * 0.6)

    // Shown before anything is searched: what a command toggle is usually for.
    readonly property list<string> suggestedIcons: ["terminal", "code", "deployed_code", "rocket_launch", "power_settings_new", "restart_alt", "play_arrow", "sync", "backup", "cloud", "dns", "storage", "database", "lan", "vpn_key", "shield", "lock", "key", "bolt", "speed", "memory", "build", "bug_report", "science", "coffee", "dark_mode", "light_mode", "bedtime", "timer", "notifications", "visibility", "headphones", "music_note", "mic", "videocam", "screen_share", "cast", "monitor", "keyboard", "wallpaper", "print", "sports_esports", "tune", "home", "public", "favorite", "star"]

    // Every name the installed font can draw (tools/gen-material-symbols.py).
    FileView {
        id: symbolsFile
        path: `${Directories.assetsPath}/material-symbols.txt`
        blockLoading: true
    }
    readonly property list<string> allIcons: symbolsFile.text().split("\n").filter(name => name.length > 0)

    readonly property string query: searchField.text.trim().toLowerCase().replace(/[\s-]+/g, "_")
    // Names that start with the query first: "lock" should lead with lock, not clock.
    readonly property list<string> shownIcons: {
        if (root.query.length === 0)
            return root.suggestedIcons;
        const matches = root.allIcons.filter(name => name.includes(root.query));
        return matches.filter(name => name.startsWith(root.query)).concat(matches.filter(name => !name.startsWith(root.query)));
    }

    readonly property bool canSave: nameField.text.trim().length > 0 && startCommandField.text.trim().length > 0

    function loadData() {
        const data = root.isEditing ? CustomToggles.getToggle(root.toggleId) : null;
        nameField.text = data?.name ?? "";
        root.icon = data?.icon || "terminal";
        startCommandField.text = data?.commandStart ?? "";
        stopCommandField.text = data?.commandStop ?? "";
        searchField.text = "";
        iconGrid.positionViewAtBeginning();
        nameField.forceActiveFocus();
    }

    onShowChanged: {
        if (show)
            loadData();
    }

    onToggleIdChanged: {
        if (show)
            loadData();
    }

    function save() {
        if (!root.canSave)
            return;
        if (root.isEditing)
            CustomToggles.updateToggle(root.toggleId, nameField.text, root.icon, startCommandField.text, stopCommandField.text);
        else
            CustomToggles.addToggle(nameField.text, root.icon, startCommandField.text, stopCommandField.text);
        root.dismiss();
    }

    WindowDialogTitle {
        text: root.isEditing ? Translation.tr("Edit custom toggle") : Translation.tr("New custom toggle")
    }

    // The tile's face: the chosen icon beside the name it will show.
    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        // As tall as the field's outline, which starts below its floating label.
        Rectangle {
            Layout.alignment: Qt.AlignBottom
            implicitWidth: nameField.height - nameField.topInset
            implicitHeight: implicitWidth
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary

            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnPrimary
                text: root.icon
            }
        }

        MaterialTextField {
            id: nameField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Name")
            KeyNavigation.tab: searchField
            onAccepted: root.save()
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 8

        MaterialTextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Search icons")
            KeyNavigation.tab: startCommandField
            // Enter takes the best match; Down walks into the grid.
            onAccepted: {
                if (root.shownIcons.length > 0)
                    root.icon = root.shownIcons[0];
            }
            Keys.onDownPressed: {
                iconGrid.currentIndex = Math.max(0, root.shownIcons.indexOf(root.icon));
                iconGrid.forceActiveFocus();
            }
        }

        GridView {
            id: iconGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.shownIcons
            cellWidth: width / 8
            cellHeight: cellWidth
            keyNavigationEnabled: true
            Keys.onReturnPressed: root.icon = root.shownIcons[currentIndex]
            Keys.onSpacePressed: root.icon = root.shownIcons[currentIndex]
            Keys.onUpPressed: event => {
                if (currentIndex < 8)
                    searchField.forceActiveFocus();
                else
                    event.accepted = false;
            }

            delegate: Item {
                id: cell
                required property string modelData
                required property int index
                readonly property bool selected: cell.modelData === root.icon
                readonly property bool focused: iconGrid.activeFocus && iconGrid.currentIndex === cell.index
                width: iconGrid.cellWidth
                height: iconGrid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    // Selection morphs the cell to a circle (DESIGN 4.3).
                    radius: cell.selected ? Appearance.rounding.full : Appearance.rounding.small
                    color: cell.selected ? Appearance.colors.colPrimary
                        : (cellMouse.pressed || cell.focused) ? Appearance.colors.colLayer2Active
                        : cellMouse.containsMouse ? Appearance.colors.colLayer2Hover
                        : "transparent"

                    Behavior on radius {
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: Appearance.font.pixelSize.larger
                        color: cell.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        text: cell.modelData
                    }
                }

                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.icon = cell.modelData;
                        iconGrid.currentIndex = cell.index;
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.shownIcons.length === 0
                text: Translation.tr("No icons match \"%1\"").arg(searchField.text.trim())
                color: Appearance.colors.colSubtext
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        MaterialTextField {
            id: startCommandField
            Layout.fillWidth: true
            font.family: Appearance.font.family.monospace
            placeholderText: Translation.tr("Command to turn on")
            KeyNavigation.tab: stopCommandField
            onAccepted: root.save()
        }

        MaterialTextField {
            id: stopCommandField
            Layout.fillWidth: true
            font.family: Appearance.font.family.monospace
            placeholderText: Translation.tr("Command to turn off (optional)")
            KeyNavigation.tab: nameField
            onAccepted: root.save()
        }
    }

    WindowDialogButtonRow {
        DialogButton {
            visible: root.isEditing
            buttonText: Translation.tr("Delete")
            colEnabled: Appearance.colors.colError
            onClicked: {
                CustomToggles.removeToggle(root.toggleId);
                root.dismiss();
            }
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: root.dismiss()
        }

        DialogButton {
            buttonText: root.isEditing ? Translation.tr("Save") : Translation.tr("Add")
            enabled: root.canSave
            onClicked: root.save()
        }
    }
}
