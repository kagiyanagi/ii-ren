import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Config profiles: named copies of config.json to switch between. The live
 * config always belongs to the active profile, and scripts/profiles/profiles.sh
 * saves it into that profile before every switch, so there is no Save button and
 * nothing to lose. It is laid out like Android's user switcher. Tap a profile to
 * switch to it. Tap the active one, or right-click any, to rename or delete it.
 */
ContentPage {
    id: page
    readonly property int index: 14
    property bool register: parent.register ?? false
    forceWidth: true

    property string active: ""
    property var names: []
    property string switching: ""
    property bool failed: false

    // Intent and mapping are kept apart so the dialog plays its exit (TASTE.md 5.1).
    property bool dialogOpen: false
    property bool dialogActive: false
    property string dialogTarget: "" // "" = a new profile
    onDialogOpenChanged: if (dialogOpen) dialogActive = true

    // The active profile blooms from a circle into its own shape, so each one is
    // recognisable by more than its letter.
    readonly property var shapes: [MaterialShape.Shape.Cookie9Sided, MaterialShape.Shape.Clover4Leaf, MaterialShape.Shape.Sunny, MaterialShape.Shape.Cookie6Sided, MaterialShape.Shape.Pentagon, MaterialShape.Shape.Puffy, MaterialShape.Shape.Gem, MaterialShape.Shape.Flower]
    function shapeFor(name) {
        let h = 0;
        for (const c of name) h = (h * 31 + c.codePointAt(0)) % 9973;
        return page.shapes[h % page.shapes.length];
    }

    function run(...args) {
        if (proc.running) return;
        page.failed = false;
        proc.exec([FileUtils.trimFileProtocol(`${Directories.scriptPath}/profiles/profiles.sh`), `${Directories.shellConfig}/profiles`, Directories.shellConfigPath, ...args]);
    }

    function openDialog(name) {
        page.dialogTarget = name;
        page.dialogOpen = true;
    }

    function nameProblem(name, original) {
        const n = name.trim();
        if (n === original) return "";
        if (n.includes("/") || n.startsWith(".")) return Translation.tr("A name can't contain / or start with a dot");
        if (page.names.includes(n)) return Translation.tr("A profile with this name already exists");
        return "";
    }

    Component.onCompleted: run("list")

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                const [active, wall, ...rest] = text.split("\n");
                const names = rest.filter(n => n.length > 0);
                // Until the first change, the live config is a "Default" with no file yet.
                if (!names.includes(active)) names.unshift(active);
                page.active = active;
                page.names = names;
                // The colours are generated from the wallpaper, not stored in the config.
                if (wall) Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--image", wall]);
            }
        }
        onExited: exitCode => {
            page.failed = exitCode !== 0;
            page.switching = "";
        }
    }

    ContentSection {
        icon: "switch_account"
        title: Translation.tr("Profiles")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Each profile is a full set of shell settings. Changes go into the active profile, which is saved whenever you switch.")
        }

        Item {
            readonly property bool wantsCard: true
            Layout.fillWidth: true
            implicitHeight: grid.contentHeight + 16

            GridView {
                id: grid
                anchors.fill: parent
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                interactive: false
                cellWidth: width / Math.max(1, Math.floor(width / 112))
                cellHeight: 136

                // Keyed by name, so a switch morphs the two tiles instead of rebuilding the grid.
                model: ScriptModel {
                    values: page.names.concat([""])
                }

                delegate: RippleButton {
                    id: tile
                    required property string modelData
                    readonly property bool isNew: modelData === ""
                    readonly property bool isActive: modelData === page.active

                    width: grid.cellWidth
                    height: grid.cellHeight
                    buttonRadius: Appearance.rounding.normal
                    onClicked: {
                        if (tile.isNew || tile.isActive) {
                            page.openDialog(tile.modelData);
                            return;
                        }
                        if (proc.running) return;
                        page.switching = tile.modelData;
                        page.run("switch", tile.modelData);
                    }
                    altAction: () => {
                        if (!tile.isNew) page.openDialog(tile.modelData);
                    }

                    contentItem: ColumnLayout {
                        spacing: 8

                        MaterialShape {
                            Layout.alignment: Qt.AlignHCenter
                            implicitSize: 64
                            shape: tile.isActive ? page.shapeFor(tile.modelData) : MaterialShape.Shape.Circle
                            color: tile.isActive ? Appearance.colors.colPrimary : tile.isNew ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colSecondaryContainer
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            StyledText {
                                anchors.centerIn: parent
                                visible: !tile.isNew
                                text: [...tile.modelData][0]?.toUpperCase() ?? ""
                                font.family: Appearance.font.family.title
                                font.pixelSize: Appearance.font.pixelSize.huge
                                color: tile.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: tile.isNew
                                text: "add"
                                iconSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: tile.isNew ? Translation.tr("New profile") : tile.modelData
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                        // Always laid out, so a status appearing moves nothing (TASTE.md 4.1).
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: !tile.isNew && page.switching === tile.modelData ? Translation.tr("Switching…") : tile.isActive ? Translation.tr("Active") : ""
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledToolTip {
                        extraVisibleCondition: !tile.isNew
                        text: tile.isActive ? Translation.tr("Click to rename") : Translation.tr("Click to switch, right-click to rename or delete")
                    }
                }

                // Tiles pop from their own centre and leave faster than they came (DESIGN.md 2.5).
                add: Transition {
                    animations: [
                        Appearance.animation.elementMoveEnter.numberAnimation.createObject(this, { property: "scale", from: 0.5, to: 1 }),
                        Appearance.animation.elementMoveFast.numberAnimation.createObject(this, { property: "opacity", from: 0, to: 1 })
                    ]
                }
                remove: Transition {
                    animations: [
                        Appearance.animation.elementMoveExit.numberAnimation.createObject(this, { property: "scale", to: 0.5 }),
                        Appearance.animation.elementMoveExit.numberAnimation.createObject(this, { property: "opacity", to: 0 })
                    ]
                }
                displaced: Transition {
                    animations: [
                        Appearance.animation.elementMove.numberAnimation.createObject(this, { properties: "x,y" }),
                        Appearance.animation.elementMove.numberAnimation.createObject(this, { properties: "opacity,scale", to: 1 })
                    ]
                }
            }
        }

        StyledText {
            visible: page.failed
            text: Translation.tr("Couldn't change profiles")
            color: Appearance.colors.colError
        }
    }

    Loader {
        parent: page
        anchors.fill: parent
        z: 100
        active: page.dialogActive

        sourceComponent: WindowDialog {
            id: dialog
            // Copied once, so the exit does not play on a cleared target.
            property string target
            readonly property string name: nameField.text.trim()
            readonly property string problem: page.nameProblem(nameField.text, dialog.target)
            readonly property bool canSave: dialog.name.length > 0 && dialog.problem === "" && dialog.name !== dialog.target

            function accept() {
                if (!dialog.canSave) return;
                if (dialog.target === "") page.run("new", dialog.name);
                else page.run("rename", dialog.target, dialog.name);
                page.dialogOpen = false;
            }

            // Created shut and opened a turn later, so onShowChanged runs and it enters.
            show: false
            Component.onCompleted: {
                dialog.target = page.dialogTarget;
                nameField.text = dialog.target;
                dialog.show = Qt.binding(() => page.dialogOpen);
                nameField.forceActiveFocus();
                nameField.selectAll();
            }
            onVisibleChanged: if (!visible && !show) page.dialogActive = false
            onDismiss: page.dialogOpen = false

            WindowDialogTitle {
                text: dialog.target === "" ? Translation.tr("New profile") : Translation.tr("Edit profile")
            }
            WindowDialogParagraph {
                visible: text !== ""
                text: dialog.target === "" ? Translation.tr("It starts as a copy of your current settings and becomes the active profile.")
                    : dialog.target === page.active ? Translation.tr("This is the active profile. Switch to another one to delete it.")
                    : ""
            }
            MaterialTextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Profile name")
                wrapMode: TextInput.NoWrap
                onAccepted: dialog.accept()
            }
            // Always laid out, so the card keeps its height while typing (TASTE.md 4.1).
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: dialog.problem
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colOnSurfaceVariant
            }
            WindowDialogButtonRow {
                DialogButton {
                    visible: dialog.target !== ""
                    enabled: dialog.target !== page.active
                    buttonText: Translation.tr("Delete")
                    colEnabled: Appearance.colors.colError
                    onClicked: {
                        page.run("delete", dialog.target);
                        page.dialogOpen = false;
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: page.dialogOpen = false
                }
                DialogButton {
                    enabled: dialog.canSave
                    buttonText: dialog.target === "" ? Translation.tr("Create") : Translation.tr("Save")
                    onClicked: dialog.accept()
                }
            }
        }
    }
}
