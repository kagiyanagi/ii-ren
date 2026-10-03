pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    // `a?.b * 0.7 ?? 0` parses as `(a?.b * 0.7) ?? 0`, and `??` does not catch
    // NaN -- so the fallback never fired and an unparented page measured NaN.
    implicitWidth: (QsWindow?.window?.screen.width ?? 0) * 0.7
    implicitHeight: (QsWindow?.window?.screen.height ?? 0) * 0.7

    property string query: ""

    // One key-column width for the whole sheet. It used to be per-category, which
    // was fine while a category was always one block; now that a long one is cut
    // across columns, two halves of the same category would have disagreed about
    // where their comments start, side by side.
    property int maxBindWidth: 0
    readonly property real columnSpacing: 12
    readonly property real rowSpacing: 4

    // The packing has to know the row pitch before it can lay anything out, and
    // both of these follow live config -- the keycap font size and the title
    // size. Measured off real widgets rather than recomputed from font metrics
    // that would drift the moment KeyboardKey changes its padding.
    KeyboardKey {
        id: rowProbe
        visible: false
        key: "M"
        pixelSize: Config.options.cheatsheet.fontSize.key
    }
    StyledText {
        id: commentProbe
        visible: false
        text: "Mg"
        font.pixelSize: Config.options.cheatsheet.fontSize.comment || Appearance.font.pixelSize.smaller
    }
    StyledText {
        id: headerProbe
        visible: false
        text: "Mg"
        font.pixelSize: Appearance.font.pixelSize.title
    }

    readonly property real rowHeight: Math.max(rowProbe.implicitHeight, commentProbe.implicitHeight)
    readonly property real headerBlockHeight: headerProbe.implicitHeight + root.rowSpacing * 2

    // How many bind rows fit under one header inside the viewport. A column that
    // holds no rows at all is not a column, so it floors at one -- the flickable
    // keeps its Math.max content bounds for that case.
    readonly property int rowsPerColumn: Math.max(1, Math.floor(
        (flickable.height - root.headerBlockHeight + root.rowSpacing) / (root.rowHeight + root.rowSpacing)))

    /** Description, modifiers and key -- so "super shift w" finds it as readily as "typing". */
    function matches(bind) {
        const q = root.query.trim().toLowerCase();
        if (q.length === 0)
            return true;
        const haystack = `${bind.description} ${UserKeybinds.modNames(bind.modmask).join(" ")} ${bind.key}`.toLowerCase();
        // Every whitespace-separated word has to appear, so the order the user
        // types the modifiers in does not matter.
        return q.split(/\s+/).every(word => haystack.indexOf(word) !== -1);
    }

    // A category longer than a column is cut into as many blocks as it needs,
    // each carrying the heading again, instead of running off the bottom of the
    // sheet. Every block fits, so the sheet only ever scrolls sideways.
    readonly property var blocks: {
        const perColumn = root.rowsPerColumn;
        const named = bind => bind.description?.length > 0 && root.matches(bind);
        const out = [];

        const add = (name, binds) => {
            for (let i = 0; i < binds.length; i += perColumn)
                out.push({
                    name: name,
                    binds: binds.slice(i, i + perColumn),
                    continued: i > 0
                });
        };

        for (const category of HyprlandKeybinds.keybindCategories) {
            add(category, HyprlandKeybinds.keybinds.filter(bind => named(bind)
                && bind.description.substring(0, bind.description.indexOf(":")) === category));
        }
        add("", HyprlandKeybinds.keybinds.filter(bind => named(bind)
            && bind.description.indexOf(":") === -1));
        return out;
    }

    readonly property int matchCount: {
        let total = 0;
        for (const block of root.blocks)
            total += block.binds.length;
        return total;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // --- toolbar ---------------------------------------------------------
        // The same strip the Elements tab wears, so the sheet reads as one
        // surface rather than three that were built on different days.
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 260
                Layout.preferredHeight: 36
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 4
                    spacing: 8

                    MaterialSymbol {
                        text: "search"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }
                    MaterialTextField {
                        id: search
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        background: null
                        leftPadding: 0
                        rightPadding: 0
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        placeholderText: Translation.tr("Search keys or actions")
                        onTextChanged: root.query = text
                    }
                    RippleButton {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        visible: root.query.length > 0
                        buttonRadius: Appearance.rounding.full
                        onClicked: search.clear()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.large
                            text: "close"
                        }

                        StyledToolTip {
                            text: Translation.tr("Clear search")
                        }
                    }
                }
            }

            StyledText {
                visible: root.query.length > 0
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: root.matchCount === 1 ? Translation.tr("1 match")
                    : Translation.tr("%1 matches").arg(root.matchCount)
            }

            Item { Layout.fillWidth: true }

            RippleButtonWithIcon {
                materialIcon: "add"
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                mainText: Translation.tr("Add binding")
                onClicked: GlobalStates.cheatsheetKeybindEditorOpen = true
            }
        }

        // --- the columns -----------------------------------------------------
        StyledFlickable {
            id: flickable
            Layout.fillWidth: true
            Layout.fillHeight: true

            // The blocks are packed to fit, so childrenRect should never exceed
            // the viewport vertically -- this is the floor that covers a window
            // too short to hold even one row.
            contentHeight: Math.max(height, flow.childrenRect.height)
            contentWidth: Math.max(width, flow.childrenRect.width)
            ScrollBar.horizontal: StyledScrollBar {}

            Flow {
                id: flow
                height: flickable.height
                flow: Flow.TopToBottom
                spacing: root.columnSpacing
                Repeater {
                    model: root.blocks
                    delegate: CheatsheetKeybindsCategory {
                        required property var modelData
                        categoryName: modelData.name
                        binds: modelData.binds
                        continued: modelData.continued
                        rowSpacing: root.rowSpacing
                        sharedBindWidth: root.maxBindWidth
                        onMeasuredBindWidthChanged: root.maxBindWidth = Math.max(root.maxBindWidth, measuredBindWidth)
                    }
                }
            }

            PagePlaceholder {
                anchors.centerIn: parent
                shown: root.query.length > 0 && root.matchCount === 0
                icon: "search_off"
                title: Translation.tr("No keybind matches")
                description: Translation.tr("Try a key name, or part of what it does")
                descriptionHorizontalAlignment: Text.AlignHCenter
            }
        }
    }

}
