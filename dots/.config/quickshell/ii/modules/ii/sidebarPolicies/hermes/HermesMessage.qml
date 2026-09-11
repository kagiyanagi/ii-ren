pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarPolicies.aiChat
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * One turn in the Hermes transcript.
 *
 * Content rendering is the AiChat message pipeline unchanged -- the same block
 * splitter and the same text/code/think blocks -- so markdown, LaTeX and code
 * fences behave identically across both agents. What differs is the header
 * (Hermes reports its own model per turn), the tool rows, and the usage footer.
 */
Rectangle {
    id: root

    required property var messageData
    property string messageId: ""

    // Retry replays from the last user message onward, so it only makes sense on
    // the reply that is actually last.
    readonly property bool isLastMessage: HermesService.messageIDs.length > 0
        && HermesService.messageIDs[HermesService.messageIDs.length - 1] === root.messageId

    property real messagePadding: 12
    property real contentSpacing: 8

    property bool enableMouseSelection: true
    property bool renderMarkdown: true

    readonly property bool isUser: root.messageData?.role === "user"
    readonly property bool isInterface: root.messageData?.role === "interface"

    // splitMarkdownBlocks() returns a fresh array each call, so binding it
    // straight to `content` would rebuild every segment delegate per streamed
    // token. Re-split on a throttle instead (same fix as AiMessage.qml).
    property list<var> messageBlocks: []

    readonly property bool showToolCalls: Config.options.hermes?.showToolCalls ?? true

    /*
     * Tool ids that have already played their entrance.
     *
     * resplit() runs on a 60ms throttle while text streams, and hands the model a
     * freshly built array each pass. Tying the fade to delegate creation alone
     * would replay it on every rebuild -- sixteen times a second -- so a row that
     * has been seen once comes back already at full opacity. Mutated in place: this
     * must not re-evaluate the bindings that read it.
     */
    property var seenTools: ({})

    function toolSeen(key: string): bool {
        return root.seenTools[key] ?? false;
    }

    function markToolSeen(key: string): void {
        root.seenTools[key] = true;
    }

    /**
     * A mark that would land inside a fenced code block is moved past the fence.
     * Cutting there would hand the splitter an unterminated ``` on one side and an
     * orphaned closer on the other, and render both halves as broken text.
     */
    function safeMark(content: string, mark: int): int {
        const at = Math.max(0, Math.min(mark, content.length));
        const fences = (content.slice(0, at).match(/```/g) ?? []).length;
        if (fences % 2 === 0)
            return at;
        const close = content.indexOf("```", at);
        return close === -1 ? content.length : close + 3;
    }

    /**
     * The turn as one timeline, in the order it actually happened: prose, then the
     * tools that prose led to, then the prose that followed them.
     *
     * Tool calls carry the content offset they fired at, so the text is cut at
     * those offsets and the runs dropped into the gaps. Consecutive calls with no
     * text between them stay one expandable group -- a sidebar is too narrow to
     * spend nine rows on nine `read_file`s -- but a group only ever covers calls
     * that really did run back to back.
     */
    function resplit(): void {
        const content = root.messageData?.content ?? "";
        const calls = root.showToolCalls ? (root.messageData?.toolCalls ?? []) : [];
        if (calls.length === 0) {
            root.messageBlocks = StringUtils.splitMarkdownBlocks(content);
            return;
        }

        const groups = [];
        calls.forEach(call => {
            const at = root.safeMark(content, call.contentMark ?? content.length);
            const last = groups[groups.length - 1];
            if (last && last.at === at)
                last.calls.push(call);
            else
                groups.push({ at: at, calls: [call] });
        });

        let timeline = [];
        let cursor = 0;
        groups.forEach(group => {
            // Never walks backwards: an out-of-order mark would otherwise reprint
            // text that has already been laid down.
            const at = Math.max(cursor, group.at);
            if (at > cursor)
                timeline = timeline.concat(StringUtils.splitMarkdownBlocks(content.slice(cursor, at)));
            timeline.push(group.calls.length === 1 ? { type: "tool", call: group.calls[0] } : { type: "tools", calls: group.calls });
            cursor = at;
        });
        if (cursor < content.length)
            timeline = timeline.concat(StringUtils.splitMarkdownBlocks(content.slice(cursor)));

        root.messageBlocks = timeline;
    }

    Component.onCompleted: root.resplit()
    onMessageDataChanged: root.resplit()
    onShowToolCallsChanged: root.resplit()

    Timer {
        id: resplitThrottle
        interval: 60
        onTriggered: root.resplit()
    }

    Connections {
        target: root.messageData ?? null
        function onContentChanged() {
            if (!resplitThrottle.running)
                resplitThrottle.start();
        }
        // A tool starting or finishing changes the timeline, not just the text, and
        // is rare enough to redraw at once rather than wait out the throttle.
        function onToolCallsChanged() {
            resplitThrottle.stop();
            root.resplit();
        }
        // The last delta and `done` can arrive in either order, so a finished
        // message always gets one final split at the full text.
        function onDoneChanged() {
            if (root.messageData?.done) {
                resplitThrottle.stop();
                root.resplit();
            }
        }
    }

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: columnLayout.implicitHeight + root.messagePadding * 2

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: columnLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.messagePadding
        spacing: root.contentSpacing

        Item { // Header
            Layout.fillWidth: true
            implicitHeight: headerRowLayout.implicitHeight

            RowLayout {
                id: headerRowLayout
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                // Your own turns are mirrored: controls on the left, identity on the
                // right. layoutDirection reverses the row order only -- it does not
                // touch how the children themselves render, the way LayoutMirroring
                // would.
                layoutDirection: root.isUser ? Qt.RightToLeft : Qt.LeftToRight

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                    text: root.isUser ? "person" : root.isInterface ? "settings" : "auto_awesome"
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    // Follows the row it sits in, so the name stays beside its icon
                    // instead of drifting across to the buttons.
                    horizontalAlignment: root.isUser ? Text.AlignRight : Text.AlignLeft
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: root.isUser ? (SystemInfo.username.length > 0 ? SystemInfo.username : Translation.tr("You")) : root.isInterface ? Translation.tr("Hermes") : (root.messageData?.model ?? Translation.tr("Hermes"))
                }

                MaterialSymbol {
                    // Interface notes are shell-side output, never sent upstream.
                    visible: root.isInterface
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: "visibility_off"

                    // StyledToolTip reads `parent.hovered`, and treats a parent that
                    // has no such property as hovered -- a MaterialSymbol is a Text,
                    // so the tip would stand open on every interface row at once.
                    // Drive it from a real hover area instead.
                    MouseArea {
                        id: hiddenFromAgentHover
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                    }

                    StyledToolTip {
                        extraVisibleCondition: false
                        alternativeVisibleCondition: hiddenFromAgentHover.containsMouse
                        text: Translation.tr("Not visible to the agent")
                    }
                }

                ButtonGroup {
                    spacing: 4

                    AiMessageControlButton {
                        id: copyButton
                        buttonIcon: activated ? "inventory" : "content_copy"
                        onClicked: {
                            Quickshell.clipboardText = root.messageData?.content ?? "";
                            copyButton.activated = true;
                            copyIconTimer.restart();
                        }

                        Timer {
                            id: copyIconTimer
                            interval: 1500
                            onTriggered: copyButton.activated = false
                        }

                        StyledToolTip {
                            text: Translation.tr("Copy")
                        }
                    }

                    AiMessageControlButton {
                        id: speakButton
                        // Nothing to read out of a user's own message, and the agent
                        // has to have a working voice stack behind it.
                        visible: !root.isUser

                        readonly property bool speakingThis: HermesService.speakingMessageId === root.messageId

                        activated: speakButton.speakingThis
                        buttonIcon: speakButton.speakingThis ? "stop" : "graphic_eq"

                        onClicked: {
                            if (speakButton.speakingThis)
                                HermesService.stopSpeaking();
                            else
                                HermesService.speakMessage(root.messageId);
                        }

                        StyledToolTip {
                            text: speakButton.speakingThis ? Translation.tr("Stop reading") : Translation.tr("Read this out loud")
                        }
                    }

                    AiMessageControlButton {
                        visible: !root.isUser && !root.isInterface && root.isLastMessage
                        enabled: !HermesService.busy
                        buttonIcon: "refresh"
                        onClicked: HermesService.regenerate()

                        StyledToolTip {
                            text: Translation.tr("Retry this reply")
                        }
                    }

                    AiMessageControlButton {
                        activated: !root.renderMarkdown
                        buttonIcon: "code"
                        onClicked: root.renderMarkdown = !root.renderMarkdown

                        StyledToolTip {
                            text: Translation.tr("View Markdown source")
                        }
                    }
                }
            }
        }

        ColumnLayout { // Message content
            id: messageContentColumnLayout
            Layout.fillWidth: true
            spacing: 0

            Item {
                Layout.fillWidth: true
                implicitHeight: loadingIndicatorLoader.shown ? loadingIndicatorLoader.implicitHeight : 0
                implicitWidth: loadingIndicatorLoader.implicitWidth
                visible: implicitHeight > 0

                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                FadeLoader {
                    id: loadingIndicatorLoader
                    anchors.centerIn: parent
                    // The page's activity line already covers "started, nothing to
                    // show yet", and says what it is doing rather than only that it
                    // is doing something -- so this stands in only when that is off.
                    shown: (root.messageBlocks.length < 1) && !(root.messageData?.done ?? true)
                        && !(Config.options.hermes?.showStatusLine ?? true)
                    sourceComponent: MaterialLoadingIndicator {
                        loading: true
                    }
                }
            }

            Repeater {
                model: ScriptModel {
                    values: root.messageBlocks
                }
                delegate: DelegateChooser {
                    role: "type"

                    DelegateChoice {
                        roleValue: "tool"
                        ToolActivityRow {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            Layout.bottomMargin: 4
                            part: modelData.call

                            // Fades in where it lands, like the text lines around
                            // it -- a row appearing mid-stream at full opacity reads
                            // as a jump in a transcript that is otherwise settling.
                            readonly property string entranceKey: modelData.call?.toolId ?? ""
                            opacity: root.toolSeen(entranceKey) ? 1 : 0
                            Component.onCompleted: {
                                opacity = 1;
                                root.markToolSeen(entranceKey);
                            }
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }
                    DelegateChoice {
                        roleValue: "tools"
                        HermesToolSummary {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            Layout.bottomMargin: 4
                            toolCalls: modelData.calls

                            readonly property string entranceKey: modelData.calls[0]?.toolId ?? ""
                            opacity: root.toolSeen(entranceKey) ? 1 : 0
                            Component.onCompleted: {
                                opacity = 1;
                                root.markToolSeen(entranceKey);
                            }
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }
                    DelegateChoice {
                        roleValue: "code"
                        MessageCodeBlock {
                            required property var modelData
                            renderMarkdown: root.renderMarkdown
                            enableMouseSelection: root.enableMouseSelection
                            segmentContent: modelData.content
                            segmentLang: modelData.lang
                            messageData: root.messageData
                        }
                    }
                    DelegateChoice {
                        roleValue: "think"
                        MessageThinkBlock {
                            required property var modelData
                            renderMarkdown: root.renderMarkdown
                            enableMouseSelection: root.enableMouseSelection
                            segmentContent: modelData.content
                            messageData: root.messageData
                            done: root.messageData?.done ?? false
                            completed: modelData.completed ?? false
                        }
                    }
                    DelegateChoice {
                        roleValue: "text"
                        MessageTextBlock {
                            required property var modelData
                            renderMarkdown: root.renderMarkdown
                            enableMouseSelection: root.enableMouseSelection
                            segmentContent: modelData.content
                            messageData: root.messageData
                            done: root.messageData?.done ?? false
                            forceDisableChunkSplitting: root.messageData?.content.includes("```") ?? true
                        }
                    }
                }
            }
        }

        Rectangle { // Error
            Layout.fillWidth: true
            visible: (root.messageData?.error ?? "").length > 0
            implicitHeight: errorRow.implicitHeight + 8 * 2
            radius: Appearance.rounding.small
            color: Appearance.m3colors.m3errorContainer

            RowLayout {
                id: errorRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: 8
                }
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.m3colors.m3onErrorContainer
                    text: "error"
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.m3colors.m3onErrorContainer
                    text: root.messageData?.error ?? ""
                }
            }
        }

        StyledText { // Usage footer
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: root.messageData?.usage?.total > 0
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colSubtext
            text: {
                const usage = root.messageData?.usage;
                if (!usage)
                    return "";
                const parts = [Translation.tr("%1 in / %2 out").arg(usage.input ?? 0).arg(usage.output ?? 0)];
                if ((usage.context_percent ?? 0) > 0)
                    parts.push(Translation.tr("%1% context").arg(usage.context_percent));
                return parts.join("  ·  ");
            }
        }
    }
}
