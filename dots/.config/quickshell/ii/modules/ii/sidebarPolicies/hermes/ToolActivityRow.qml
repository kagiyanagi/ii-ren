pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarPolicies.aiChat
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts

/**
 * One tool invocation, rendered the way the CLI narrates its own work:
 * a status dot, the tool name, and a one-line argument summary.
 * Clicking expands the full command that ran, with buttons to copy the command
 * and view what was returned to the assistant.
 */
Item {
    id: root

    required property var part

    property bool expanded: false

    readonly property string commandText: {
        const full = (root.part?.toolFullInput ?? "").trim();
        return full.length > 0 ? full : (root.part?.toolInput ?? "").trim();
    }
    readonly property string resultText: (root.part?.toolResult ?? "").trim();
    readonly property bool hasResult: root.resultText.length > 0
    readonly property bool isRunning: root.part?.toolRunning ?? false
    readonly property bool hasFailed: root.part?.toolFailed ?? false
    readonly property bool canExpand: root.commandText.length > 0 || root.hasResult || root.isRunning

    /*
     * A command's output is the point of opening its row, so it is shown there
     * rather than behind a second toggle -- but a single `pacman -Q` is sixteen
     * hundred lines, which in a sidebar is the whole visible height and then
     * some. Only the head is laid out until asked for, the way every agentic
     * transcript handles a long return.
     */
    property bool outputExpanded: false
    readonly property int previewLineCount: 12
    // Ceiling on what is ever handed to a Text at once: past this the line count
    // stops being the thing that costs, and the characters start to.
    readonly property int maxShownChars: 8000

    readonly property var resultLines: root.hasResult ? root.resultText.split("\n") : []
    // Only when expanding would actually reveal something: one enormous single
    // line reads the same either way, and says so with its own truncation mark.
    readonly property bool resultClipped: root.resultLines.length > root.previewLineCount
    readonly property string shownResult: {
        const body = root.outputExpanded ? root.resultText : root.resultLines.slice(0, root.previewLineCount).join("\n");
        return body.length > root.maxShownChars ? `${body.slice(0, root.maxShownChars)}\n${Translation.tr("… truncated")}` : body;
    }

    // What the call cost, for the expanded header. A zero exit is the silent
    // default; only a failing one is worth the space.
    readonly property string metaText: {
        const parts = [];
        const code = root.part?.toolExitCode ?? null;
        if (code !== null && code !== 0)
            parts.push(Translation.tr("exit %1").arg(code));
        const seconds = root.part?.duration ?? 0;
        if (seconds >= 0.05)
            parts.push(seconds < 1 ? Translation.tr("%1 ms").arg(Math.round(seconds * 1000)) : Translation.tr("%1 s").arg(seconds.toFixed(1)));
        return parts.join("  ·  ");
    }

    function toolIcon(name): string {
        switch ((name ?? "").toLowerCase()) {
        case "run_command":
        case "bash":
        case "shell":
        case "execute_command":
        case "command_execution":
            return "terminal";
        case "search_web":
        case "web_search":
        case "google_search":
        case "brave_search":
        case "internet_search":
            return "search";
        case "view_file":
        case "read_file":
        case "cat":
        case "read_document":
            return "description";
        case "write_to_file":
        case "create_file":
        case "write_file":
            return "edit_document";
        case "replace_file_content":
        case "edit_file":
        case "str_replace_editor":
        case "multi_replace_file_content":
        case "sed_file":
            return "edit";
        case "find_by_name":
        case "list_dir":
        case "ls":
        case "find":
            return "folder_open";
        case "grep_search":
        case "search":
        case "rg":
        case "ripgrep":
            return "manage_search";
        case "read_url_content":
        case "fetch_url":
        case "browse":
        case "open_browser_url":
        case "read_browser_page":
            return "public";
        case "capture_browser_screenshot":
        case "screenshot":
            return "screenshot";
        case "generate_image":
            return "image";
        case "run_python":
        case "python":
        case "execute_python":
        case "notebook_execution":
            return "code";
        case "call_mcp_tool":
        case "mcp":
            return "electrical_services";
        case "send_message":
        case "invoke_subagent":
        case "define_subagent":
            return "group";
        case "ask_question":
        case "ask_permission":
        case "ask_custom_permission":
            return "contact_support";
        case "write_to_file":
            return "edit_document";
        case "manage_task":
        case "schedule":
            return "schedule";
        case "desktop_do":
        case "desktop_look":
        case "desktop_state":
            return "desktop_windows";
        case "view_calendar":
        case "get_calendar":
            return "calendar_month";
        case "computer":
            return "computer";
        default:
            return "smart_toy";
        }
    }

    implicitHeight: layout.implicitHeight
    implicitWidth: layout.implicitWidth

    // Expanding is a size change, so it runs on a spatial spec. It matters more now
    // that rows sit between paragraphs rather than in one block above them: without
    // this, opening a row snaps every word below it down the page.
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    ColumnLayout {
        id: layout
        width: root.width
        spacing: 4

        RippleButton {
            id: headerButton
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + 10
            buttonRadius: Appearance.rounding.verysmall
            colBackground: "transparent"
            enabled: root.canExpand
            onClicked: root.expanded = !root.expanded

            RowLayout {
                id: headerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                // Tool icon with tiny status dot overlay
                Item {
                    implicitWidth: Appearance.font.pixelSize.normal
                    implicitHeight: Appearance.font.pixelSize.normal

                    MaterialSymbol {
                        anchors.fill: parent
                        text: root.toolIcon(root.part?.toolName)
                        iconSize: Appearance.font.pixelSize.normal
                        color: {
                            if (root.hasFailed) return Appearance.colors.colError;
                            if (root.isRunning) return Appearance.colors.colSubtext;
                            return Appearance.colors.colPrimary;
                        }
                    }

                    // Small state overlay dot: only shown during running or failure
                    Rectangle {
                        visible: root.isRunning || root.hasFailed
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -2
                        anchors.bottomMargin: -2
                        width: 7
                        height: 7
                        radius: Appearance.rounding.full
                        color: root.hasFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                        border.width: 1
                        border.color: Appearance.colors.colLayer1Base
                    }
                }

                StyledText { // Tool name
                    text: root.part?.toolName ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                StyledText { // Argument summary
                    Layout.fillWidth: true
                    // Without this the row is as wide as the untruncated command,
                    // and a long one pushes the whole transcript card off-screen.
                    Layout.minimumWidth: 0
                    text: root.part?.toolInput ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideMiddle
                }

                MaterialSymbol {
                    visible: headerButton.enabled
                    text: root.expanded ? "expand_less" : "expand_more"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Rectangle { // Expanded command details & return value
            id: detailsCard
            Layout.fillWidth: true
            visible: root.expanded
            implicitHeight: detailsColumn.implicitHeight + 16
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: detailsColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 8

                // Header bar of the command box
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.normal
                        text: root.toolIcon(root.part?.toolName)
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: root.part?.toolName ?? Translation.tr("Command")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText { // What the call cost
                        visible: root.metaText.length > 0
                        text: root.metaText
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.numbers
                        color: root.hasFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                    }

                    // Button to copy command
                    ButtonGroup {
                        AiMessageControlButton {
                            id: copyCommandButton
                            buttonIcon: activated ? "check" : "content_copy"
                            enabled: root.commandText.length > 0

                            onClicked: {
                                Quickshell.clipboardText = root.commandText;
                                copyCommandButton.activated = true;
                                copyCommandResetTimer.restart();
                            }

                            Timer {
                                id: copyCommandResetTimer
                                interval: 1500
                                onTriggered: copyCommandButton.activated = false
                            }

                            StyledToolTip {
                                extraVisibleCondition: copyCommandButton.hovered
                                text: copyCommandButton.activated ? Translation.tr("Copied command!") : Translation.tr("Copy command")
                            }
                        }
                    }
                }

                // Full command content
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: commandDisplay.implicitHeight + 16
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colLayer3

                    StyledText {
                        id: commandDisplay
                        anchors.fill: parent
                        anchors.margins: 8
                        wrapMode: Text.WrapAnywhere
                        textFormat: Text.PlainText
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colOnLayer3
                        text: root.commandText
                    }
                }

                // What the tool returned, under the command that produced it.
                Rectangle {
                    id: outputBox
                    visible: root.hasResult || root.isRunning
                    Layout.fillWidth: true
                    implicitHeight: outputColumn.implicitHeight + 16
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colLayer3

                    ColumnLayout {
                        id: outputColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.small
                                text: root.hasFailed ? "error" : root.isRunning && !root.hasResult ? "pending" : "reply"
                                color: root.hasFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                text: {
                                    if (root.hasFailed)
                                        return Translation.tr("Returned error");
                                    const lines = root.resultLines.length;
                                    return lines > 1 ? Translation.tr("Output  ·  %1 lines").arg(lines) : Translation.tr("Output");
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: root.hasFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                            }

                            ButtonGroup {
                                AiMessageControlButton {
                                    id: copyOutputButton
                                    visible: root.hasResult
                                    buttonIcon: activated ? "check" : "content_copy"

                                    onClicked: {
                                        // The whole return, never the clipped preview.
                                        Quickshell.clipboardText = root.resultText;
                                        copyOutputButton.activated = true;
                                        copyOutputResetTimer.restart();
                                    }

                                    Timer {
                                        id: copyOutputResetTimer
                                        interval: 1500
                                        onTriggered: copyOutputButton.activated = false
                                    }

                                    StyledToolTip {
                                        extraVisibleCondition: copyOutputButton.hovered
                                        text: copyOutputButton.activated ? Translation.tr("Copied output!") : Translation.tr("Copy the whole output")
                                    }
                                }
                            }
                        }

                        StyledText {
                            id: resultDisplay
                            Layout.fillWidth: true
                            // Wrapped output is as wide as its longest line unless the
                            // layout is told it may be narrower, and one `ls -l` line
                            // is enough to widen the card past the sidebar.
                            Layout.minimumWidth: 0
                            visible: root.hasResult
                            // Breaks on spaces where it can and mid-token where it
                            // cannot, so a long path wraps instead of overflowing.
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.monospace
                            color: root.hasFailed ? Appearance.colors.colError : Appearance.colors.colOnLayer3
                            text: root.shownResult
                        }

                        StyledText { // Nothing back yet
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            visible: !root.hasResult && root.isRunning
                            text: Translation.tr("Running…")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        RippleButton { // The rest of a long return
                            id: moreOutputButton
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            visible: root.resultClipped
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.verysmall
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            colRipple: Appearance.colors.colLayer3Active
                            onClicked: root.outputExpanded = !root.outputExpanded

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    iconSize: Appearance.font.pixelSize.small
                                    text: root.outputExpanded ? "expand_less" : "expand_more"
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    text: {
                                        if (root.outputExpanded)
                                            return Translation.tr("Show less");
                                        const lines = root.resultLines.length;
                                        return lines > root.previewLineCount
                                            ? Translation.tr("Show all %1 lines").arg(lines)
                                            : Translation.tr("Show more");
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
