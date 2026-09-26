pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarPolicies.aiChat
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts
import org.kde.syntaxhighlighting

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

    /*
     * What a transcript search is looking for.
     *
     * A row whose command or output matches opens itself: the search counts hits
     * in tool text, so a hit that stayed folded away would be a number pointing at
     * nothing. The text is not marked -- these draw in StyledText, which
     * SpeechHighlight has no selection API to work with.
     */
    property string searchQuery: ""
    readonly property bool matchesSearch: {
        const needle = root.searchQuery.trim().toLowerCase();
        if (needle.length === 0)
            return false;
        return `${root.part?.toolName ?? ""} ${root.commandText} ${root.resultText}`.toLowerCase().includes(needle);
    }
    readonly property bool open: root.expanded || root.matchesSearch

    readonly property string commandText: {
        const full = (root.part?.toolFullInput ?? "").trim();
        return full.length > 0 ? full : (root.part?.toolInput ?? "").trim();
    }
    readonly property string resultText: (root.part?.toolResult ?? "").trim();
    readonly property bool hasResult: root.resultText.length > 0
    readonly property bool isRunning: root.part?.toolRunning ?? false
    readonly property bool hasFailed: root.part?.toolFailed ?? false
    readonly property bool canExpand: root.commandText.length > 0 || root.hasResult || root.isRunning

    // Ceiling on what is ever handed to a Text at once: past this the line count
    // stops being the thing that costs, and the characters start to. Copy still
    // takes the whole return.
    readonly property int maxShownChars: 8000
    // How much of a long command or return shows before its Show more.
    readonly property int previewLineCount: 12

    readonly property var resultLines: root.hasResult ? root.resultText.split("\n") : []
    readonly property string shownResult: {
        // read_file numbers every line as `12|`, which in front of a line breaks
        // what the highlighter reads there (`#include`, a heredoc, indentation).
        const body = root.resultLines.every(line => /^\s*\d+\|/.test(line))
            ? root.resultLines.map(line => line.replace(/^\s*\d+\|/, "")).join("\n") : root.resultText;
        return body.length > root.maxShownChars ? `${body.slice(0, root.maxShownChars)}\n${Translation.tr("… truncated")}` : body;
    }

    /*
     * The call's arguments, laid out to be read rather than printed as JSON.
     *
     * One argument is usually the call itself (the file a write puts down, the
     * line a shell runs, the code it executes). It becomes the highlighted body, in
     * the language its path or its tool says. The rest are one-line `key value`
     * rows above it. As JSON, a written file was one escaped string wrapped across
     * the whole sidebar.
     */
    readonly property var argLayout: root.layoutArgs(root.part?.toolArgs ?? null, root.part?.toolName ?? "", root.commandText)
    readonly property string bodyLanguage: root.languageFor(root.argLayout.file, root.argLayout.kind)
    readonly property string resultLanguage: {
        if (root.hasFailed)
            return "";
        const path = root.argLayout.lines.find(line => root.pathKeys.includes(line.key))?.value ?? "";
        if (path.length > 0 && root.fileReadTools.includes((root.part?.toolName ?? "").toLowerCase()))
            return root.languageFor(path, "");
        return /^\s*[\[{]/.test(root.shownResult) ? "JSON" : "";
    }

    readonly property var pathKeys: ["path", "file_path", "filepath", "filename", "file", "target_file"]
    readonly property var fileReadTools: ["read_file", "view_file", "cat", "read_document"]

    function languageFor(file: string, kind: string): string {
        if (file.length === 0)
            return kind;
        const byName = Repository.definitionForFileName(file).name ?? "";
        return byName.length > 0 ? byName : kind;
    }

    /**
     * `{ lines: [{key, value}], body, file, kind }` for a call's arguments.
     * `file` is the path whose language the body is written in, when it is a file's
     * text; `kind` is the language the tool implies otherwise ("Bash", "Python").
     * tools/check-hermes-thread.py runs this under node.
     */
    function layoutArgs(args, name, fallback) {
        const tool = (name ?? "").toLowerCase();
        const shell = ["terminal", "shell", "bash", "run_command", "execute_command", "command_execution"].includes(tool);
        if (!args || typeof args !== "object" || Array.isArray(args)) {
            const text = (fallback ?? "").trim();
            return { lines: [], body: text, file: "", kind: shell ? "Bash" : /^[\[{]/.test(text) ? "JSON" : "" };
        }
        const keys = Object.keys(args);
        const isText = key => typeof args[key] === "string" && args[key].length > 0;
        const bodyKey = ["content", "code", "command", "new_string", "patch", "diff", "script", "text", "query"].find(isText)
            ?? keys.filter(key => isText(key) && args[key].includes("\n")).sort((a, b) => args[b].length - args[a].length)[0]
            ?? "";
        const lines = keys.filter(key => key !== bodyKey && args[key] !== null && args[key] !== undefined && args[key] !== "")
            .map(key => ({ key: key, value: typeof args[key] === "string" ? args[key] : JSON.stringify(args[key]) }));
        const path = keys.find(key => ["path", "file_path", "filepath", "filename", "file", "target_file"].includes(key) && isText(key)) ?? "";
        let kind = "";
        if (bodyKey === "command" || (shell && bodyKey !== ""))
            kind = "Bash";
        else if (bodyKey === "code")
            kind = typeof args.language === "string" && args.language.length > 0 ? args.language
                : ["execute_code", "run_python", "python", "execute_python"].includes(tool) ? "Python" : "";
        else if (bodyKey === "patch" || bodyKey === "diff")
            kind = "Diff";
        const fileBody = ["content", "new_string", "text", "script"].includes(bodyKey) || (bodyKey === "code" && kind === "");
        return { lines: lines, body: bodyKey ? args[bodyKey] : "", file: fileBody && path ? args[path] : "", kind: kind };
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

    /** `read_file` as "Read file": the row names what ran, not its identifier. */
    function toolLabel(name): string {
        const raw = (name ?? "").replace(/[_-]+/g, " ").trim();
        if (raw.length === 0)
            return "";
        return raw.charAt(0).toUpperCase() + raw.slice(1);
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

    // The details are built the first time the row opens and kept after, so a
    // close collapses over them instead of over nothing.
    property bool built: false
    onOpenChanged: if (root.open) root.built = true
    Component.onCompleted: if (root.open) root.built = true

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

                    Rectangle {
                        visible: root.isRunning && !root.hasFailed
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -2
                        anchors.bottomMargin: -2
                        width: 7
                        height: 7
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSubtext
                        border.width: 1
                        border.color: Appearance.colors.colLayer2Base
                    }

                    MaterialSymbol {
                        visible: root.hasFailed
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -4
                        anchors.bottomMargin: -4
                        iconSize: Appearance.font.pixelSize.smaller
                        fill: 1
                        color: Appearance.colors.colError
                        text: "error"
                    }
                }

                StyledText { // Tool name
                    text: root.toolLabel(root.part?.toolName)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
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
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext

                    rotation: root.open ? 180 : 0
                    Behavior on rotation {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
            }
        }

        // Opening is a size change between paragraphs, so it is revealed, clipped,
        // on the spatial spec: shown outright, the card painted over the next
        // paragraph while the height grew, and vanished on the first frame of a close.
        Revealer {
            Layout.fillWidth: true
            vertical: true
            reveal: root.open

            Loader {
                width: parent.width
                active: root.built
                sourceComponent: detailsComponent
            }
        }
    }

    FontMetrics {
        id: monoMetrics
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    Component {
        id: detailsComponent

        Rectangle { // Expanded command details & return value
            implicitHeight: detailsColumn.implicitHeight + 16
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer3

            ColumnLayout {
                id: detailsColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 8

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
                        text: root.toolLabel(root.part?.toolName) || Translation.tr("Command")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer3
                    }

                    StyledText { // What the call cost
                        visible: root.metaText.length > 0
                        text: root.metaText
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.numbers
                        color: root.hasFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                    }

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

                Rectangle { // What was called with
                    visible: root.argLayout.lines.length > 0 || root.argLayout.body.length > 0
                    Layout.fillWidth: true
                    implicitHeight: argsColumn.implicitHeight + 16
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colLayer4

                    ColumnLayout {
                        id: argsColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 4

                        Repeater {
                            model: root.argLayout.lines

                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8

                                StyledText {
                                    Layout.alignment: Qt.AlignTop
                                    text: modelData.key
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.family: Appearance.font.family.monospace
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: modelData.value
                                    textFormat: Text.PlainText
                                    elide: Text.ElideMiddle
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.family: Appearance.font.family.monospace
                                    color: Appearance.colors.colOnLayer4
                                }
                            }
                        }

                        ClampBox {
                            visible: root.argLayout.body.length > 0
                            maxHeight: monoMetrics.lineSpacing * root.previewLineCount

                            ToolCode {
                                width: parent.width
                                text: root.argLayout.body.length > root.maxShownChars
                                    ? `${root.argLayout.body.slice(0, root.maxShownChars)}\n${Translation.tr("… truncated")}` : root.argLayout.body
                                language: root.bodyLanguage
                            }
                        }
                    }
                }

                // What the tool returned, under the command that produced it.
                Rectangle {
                    visible: root.hasResult || root.isRunning
                    Layout.fillWidth: true
                    implicitHeight: outputColumn.implicitHeight + 16
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colLayer4

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

                        ClampBox {
                            visible: root.hasResult
                            maxHeight: monoMetrics.lineSpacing * root.previewLineCount

                            ToolCode {
                                width: parent.width
                                text: root.shownResult
                                language: root.resultLanguage
                                color: root.hasFailed ? Appearance.colors.colError : Appearance.colors.colOnLayer4
                            }
                        }

                        StyledText { // Nothing back yet
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            visible: !root.hasResult && root.isRunning
                            text: Translation.tr("Running…")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }
}
