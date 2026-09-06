pragma ComponentBehavior: Bound

import qs.services // Translation
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell // ScriptModel

/**
 * A turn's tool run, as one line.
 *
 * Hermes' own desktop app reduces a whole run to "Explored 9 files, ran 6
 * commands, used 2 tools" and keeps the detail behind it. Printing every call as
 * its own row -- which this used to do -- buries the answer the user actually
 * wanted under twenty lines of `read_file` and `terminal`, and in a sidebar that
 * is the entire visible height.
 */
ColumnLayout {
    id: root

    required property var toolCalls

    property bool expanded: false

    readonly property int total: root.toolCalls?.length ?? 0
    readonly property bool anyRunning: (root.toolCalls ?? []).some(call => call.toolRunning ?? false)
    readonly property bool anyFailed: (root.toolCalls ?? []).some(call => call.toolFailed ?? false)

    // Grouped the way the agent's own summary groups them.
    readonly property var fileTools: ["read_file", "search_files", "write_file", "patch", "view_file", "skill_view", "skills_list", "skill_manage"]
    readonly property var commandTools: ["terminal", "execute_code", "browser_exec", "shell", "bash"]

    function countOf(names: var): int {
        return (root.toolCalls ?? []).filter(call => names.includes((call.toolName ?? "").toLowerCase())).length;
    }

    readonly property string summary: {
        const files = root.countOf(root.fileTools);
        const commands = root.countOf(root.commandTools);
        const others = root.total - files - commands;
        const parts = [];
        if (files > 0)
            parts.push(Translation.tr("Explored %1 files").arg(files));
        if (commands > 0)
            parts.push(Translation.tr("ran %1 commands").arg(commands));
        if (others > 0)
            parts.push(Translation.tr("used %1 tools").arg(others));
        return parts.join(", ");
    }

    spacing: 4

    RippleButton {
        id: summaryButton
        Layout.fillWidth: true
        implicitHeight: 28
        buttonRadius: Appearance.rounding.small
        colBackground: "transparent"

        releaseAction: () => root.expanded = !root.expanded

        contentItem: RowLayout {
            spacing: 6

            MaterialSymbol {
                Layout.leftMargin: 2
                iconSize: Appearance.font.pixelSize.normal
                color: root.anyFailed ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                text: root.anyRunning ? "pending" : root.anyFailed ? "error" : "check"
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: root.summary
            }

            MaterialSymbol {
                Layout.rightMargin: 2
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
                text: "keyboard_arrow_down"

                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }

    ColumnLayout { // The calls themselves, once asked for
        Layout.fillWidth: true
        Layout.leftMargin: 8
        spacing: 4
        visible: root.expanded

        Repeater {
            model: ScriptModel {
                values: root.expanded ? (root.toolCalls ?? []) : []
            }

            delegate: ToolActivityRow {
                required property var modelData
                Layout.fillWidth: true
                part: modelData
            }
        }
    }
}
