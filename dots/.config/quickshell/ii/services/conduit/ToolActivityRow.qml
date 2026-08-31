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
    property bool showOutput: root.hasFailed

    readonly property string commandText: {
        const full = (root.part?.toolFullInput ?? "").trim();
        return full.length > 0 ? full : (root.part?.toolInput ?? "").trim();
    }
    readonly property string resultText: (root.part?.toolResult ?? "").trim();
    readonly property bool hasResult: root.resultText.length > 0
    readonly property bool isRunning: root.part?.toolRunning ?? false
    readonly property bool hasFailed: root.part?.toolFailed ?? false
    readonly property bool canExpand: root.commandText.length > 0 || root.hasResult || root.isRunning

    onHasFailedChanged: {
        if (root.hasFailed) root.showOutput = true;
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
                        text: "terminal"
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: root.part?.toolName ?? Translation.tr("Command")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }

                    Item { Layout.fillWidth: true }

                    // Button to see what it returned to the assistant
                    RippleButton {
                        id: outputToggleButton
                        visible: root.hasResult || root.isRunning
                        enabled: root.hasResult
                        implicitHeight: 28
                        implicitWidth: outputButtonContent.implicitWidth + 16
                        buttonRadius: Appearance.rounding.verysmall
                        colBackground: root.showOutput
                            ? (root.hasFailed ? Appearance.m3colors.m3errorContainer : Appearance.colors.colSecondaryContainer)
                            : "transparent"
                        onClicked: root.showOutput = !root.showOutput

                        RowLayout {
                            id: outputButtonContent
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.small
                                text: {
                                    if (root.isRunning && !root.hasResult) return "pending";
                                    if (root.showOutput) return "visibility_off";
                                    if (root.hasFailed) return "error";
                                    return "output";
                                }
                                color: {
                                    if (root.hasFailed) return Appearance.colors.colError;
                                    if (root.showOutput) return Appearance.colors.colOnSecondaryContainer;
                                    return Appearance.colors.colSubtext;
                                }
                            }

                            StyledText {
                                text: {
                                    if (root.isRunning && !root.hasResult) return Translation.tr("Running…");
                                    if (root.hasFailed) return root.showOutput ? Translation.tr("Hide error") : Translation.tr("See error");
                                    return root.showOutput ? Translation.tr("Hide return") : Translation.tr("See return");
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: {
                                    if (root.hasFailed) return Appearance.colors.colError;
                                    if (root.showOutput) return Appearance.colors.colOnSecondaryContainer;
                                    return Appearance.colors.colSubtext;
                                }
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: outputToggleButton.hovered
                            text: root.hasFailed
                                ? (root.showOutput ? Translation.tr("Hide error details") : Translation.tr("See error returned to model"))
                                : (root.showOutput ? Translation.tr("Hide return output") : Translation.tr("See what was returned to model"))
                        }
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
                    color: Appearance.colors.colLayer1Base

                    StyledText {
                        id: commandDisplay
                        anchors.fill: parent
                        anchors.margins: 8
                        wrapMode: Text.WrapAnywhere
                        textFormat: Text.PlainText
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colOnLayer2
                        text: root.commandText
                    }
                }

                // Return value / output section
                Rectangle {
                    id: outputBox
                    visible: root.showOutput && root.hasResult
                    Layout.fillWidth: true
                    implicitHeight: outputColumn.implicitHeight + 16
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colLayer1Base

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
                                text: root.hasFailed ? "error" : "reply"
                                color: root.hasFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                            }

                            StyledText {
                                text: root.hasFailed ? Translation.tr("Returned error") : Translation.tr("Returned output")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: root.hasFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                            }

                            Item { Layout.fillWidth: true }

                            ButtonGroup {
                                AiMessageControlButton {
                                    id: copyOutputButton
                                    buttonIcon: activated ? "check" : "content_copy"

                                    onClicked: {
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
                                        text: copyOutputButton.activated ? Translation.tr("Copied output!") : Translation.tr("Copy returned output")
                                    }
                                }
                            }
                        }

                        StyledText {
                            id: resultDisplay
                            Layout.fillWidth: true
                            wrapMode: Text.WrapAnywhere
                            textFormat: Text.PlainText
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.monospace
                            color: root.hasFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                            text: {
                                const full = root.resultText;
                                return full.length > 8000 ? full.slice(0, 8000) + "\n\n… truncated" : full;
                            }
                        }
                    }
                }
            }
        }
    }
}
