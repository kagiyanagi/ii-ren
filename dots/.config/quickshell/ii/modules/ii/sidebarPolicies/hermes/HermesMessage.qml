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
 * Content goes through the block splitter and the text/code/think blocks in
 * `aiChat/`, so markdown, LaTeX and code fences render there. Around them sit
 * the header (Hermes reports its own model per turn), the tool rows, and the
 * run time and action buttons at the bottom.
 *
 * Your own turns are a bubble that hugs its text at the right, with a control
 * row below it; the agent's turns are the full-width card. That split is
 * the one thing a transcript has to show at a glance.
 */
Item {
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

    readonly property bool isUser: root.messageData?.role === "user"
    readonly property bool isInterface: root.messageData?.role === "interface"

    // splitMarkdownBlocks() returns a fresh array each call, so binding it
    // straight to `content` would rebuild every segment delegate per streamed
    // token. Re-split on a throttle instead.
    property list<var> messageBlocks: []

    /*
     * The passage to mark, when this turn is the one being read.
     *
     * Reading a selection belongs to no particular turn -- the service only has
     * the text -- so every message offers the passage and the one whose own text
     * holds it is the one that finds anything to mark. Two turns with the same
     * sentence in them would both mark it; a transcript where that happens is
     * one where either answer is the right place to look.
     */
    readonly property string speakingPhrase: (HermesService.speakingMessageId === root.messageId
        || HermesService.speakingMessageId === HermesService.selectionSpeechId)
        ? HermesService.speakingPassage : ""
    // Only bound while this turn is the one being read: otherwise every message in
    // the transcript re-checks itself ten times a second for a mark it cannot hold.
    readonly property real speakingProgress: root.speakingPhrase.length > 0 ? HermesService.speakingProgress : -1
    readonly property int speakingOffset: root.speakingPhrase.length > 0 ? HermesService.speakingOffset : -1

    /** What a transcript search is looking for, passed down to every block. */
    property string searchQuery: ""
    /** Whether this turn is the hit the search has stepped to. */
    property bool searchCurrent: false

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
    /**
     * Your turn with each attachment's reference drawn as the chip the composer
     * showed: its icon, then the name, bracketed with U+2063 for InlineCode's pill
     * and spaced on its last character the way styleCodeSpans spaces a code span.
     * An icon, even for an image, whose picture is in the tile above: Qt breaks a
     * line after any inline `<img>`, whatever joins it to the name, so a picture
     * split its chip at a wrap. tools/check-hermes-composer.py runs this.
     */
    function withChips(content: string, attachments: var): string {
        const escape = text => text.replace(/([!"#$%'()*+,\-./:;=?@\[\\\]^_`{|}~])/g, "\\$1")
            .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const px = Appearance.font.pixelSize.normal;
        return (attachments ?? []).reduce((text, item) => {
            if (!item.send || !text.includes(item.send))
                return text;
            const icon = `<span style="font-family:'${Appearance.font.family.iconMaterial}'; font-size:${px}px;">${item.icon}</span>`;
            const name = item.name || "file";
            // Led by a no-break space, which InlineCode takes as the pill's own left
            // padding, so a chip starting a line lines up with the text under it.
            // The word before gets letter-spacing for the gap, as styleCodeSpans
            // gives a code span's; at a wrap it ends the line above instead.
            const chip = `\u2063&nbsp;${icon}&nbsp;${escape(name.slice(0, -1))}<span style="letter-spacing:${root.chipGap}px;">${escape(name.slice(-1))}</span>\u2063`;
            const ref = item.send.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            return text.replace(new RegExp(`([A-Za-z0-9\\u00C0-\\u2062\\u2064-\\uFFFF.,;:!?'")\\]])?(\\s*)${ref}`, "g"),
                (match, before, gap) => (before ? `<span style="letter-spacing:${root.chipGap / 2}px;">${escape(before)}</span>` : "") + gap + chip);
        }, content);
    }
    // InlineCode's gap: its pad on either side of the text
    readonly property real chipGap: 8

    function resplit(): void {
        const content = root.isUser ? root.withChips(root.messageData?.content ?? "", root.messageData?.attachments) : (root.messageData?.content ?? "");
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

        // splitMarkdownBlocks() keys each slice from zero and tool rows carry no
        // key at all, so the assembled timeline is keyed as a whole.
        timeline.forEach((block, i) => block.key = block.type + "-" + i);
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
    // A bubble carries its padding inside itself; the agent's card around everything.
    implicitHeight: columnLayout.implicitHeight + (root.isUser ? 0 : root.messagePadding * 2)

    /*
     * The bubble's width: the text's own, capped at a share of the transcript.
     * TextEdit reports its unwrapped width as implicitWidth, so a two-word prompt
     * asks for two words and a long one asks for the cap and wraps inside it.
     */
    FontMetrics {
        id: userLineMetrics
        font.family: Appearance.font.family.reading
        font.pixelSize: Appearance.font.pixelSize.small
    }

    TextMetrics {
        id: userTextMetrics
        font.family: Appearance.font.family.reading
        font.pixelSize: Appearance.font.pixelSize.small
        // A chip measures as its name after two and a half em spaces, about its icon
        // and padding, whatever the reference it stands for spells
        text: root.isUser ? (root.messageData?.attachments ?? []).reduce((text, item) => item.send ? text.split(item.send).join(`\u2003\u2003\u2002${item.name}`) : text, root.messageData?.content ?? "") : ""
    }

    readonly property real bubbleMaxWidth: root.width * 0.85
    readonly property real bubbleWidth: Math.min(root.bubbleMaxWidth, messageContentColumnLayout.implicitWidth + root.messagePadding * 2)

    /** How long the reply took, once it is finished. */
    readonly property real elapsedSeconds: {
        const started = root.messageData?.createdAt ?? 0;
        const finished = root.messageData?.completedAt ?? 0;
        return started > 0 && finished > started ? (finished - started) / 1000 : -1;
    }

    // Same scale ToolActivityRow reports a call's cost on, so a turn and the
    // tools inside it read in the same units.
    readonly property string elapsedText: {
        const seconds = root.elapsedSeconds;
        if (seconds < 0)
            return "";
        if (seconds < 1)
            return Translation.tr("%1 ms").arg(Math.round(seconds * 1000));
        if (seconds < 60)
            return Translation.tr("%1 s").arg(seconds.toFixed(1));
        return Translation.tr("%1m %2s").arg(Math.floor(seconds / 60)).arg(Math.round(seconds % 60));
    }

    Rectangle { // The turn's card, or your bubble
        x: root.isUser ? root.width - width : 0
        y: root.isUser ? body.y - root.messagePadding : 0
        width: root.isUser ? root.bubbleWidth : root.width
        height: root.isUser ? body.height + root.messagePadding * 2 : root.height
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
    }

    ColumnLayout {
        id: columnLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.isUser ? 0 : root.messagePadding
        spacing: root.contentSpacing

        Item { // Header (agent turns only)
            visible: !root.isUser
            Layout.fillWidth: true
            implicitWidth: headerRowLayout.implicitWidth
            implicitHeight: headerRowLayout.implicitHeight

            RowLayout {
                id: headerRowLayout
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                    text: root.isInterface ? "settings" : "auto_awesome"
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: root.isInterface ? Translation.tr("Hermes") : (root.messageData?.model ?? Translation.tr("Hermes"))
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
            }
        }

        HermesAttachmentStrip { // On your turns, what was attached, above the bubble
            // In the order attached, the row flush right like the bubble
            Layout.alignment: Qt.AlignRight
            Layout.preferredWidth: Math.min(implicitWidth, root.bubbleMaxWidth)
            visible: root.isUser && attachments.length > 0
            attachments: root.isUser ? (root.messageData?.attachments ?? []) : []
            tileColor: Appearance.colors.colLayer2
        }

        ColumnLayout { // Everything under the header; on your turns, the bubble's inside
            id: body
            Layout.fillWidth: !root.isUser
            Layout.alignment: Qt.AlignRight
            Layout.preferredWidth: root.isUser ? root.bubbleWidth - root.messagePadding * 2 : -1
            Layout.topMargin: root.isUser ? root.messagePadding : 0
            Layout.bottomMargin: root.isUser ? root.messagePadding : 0
            Layout.rightMargin: root.isUser ? root.messagePadding : 0
            spacing: root.contentSpacing

            Item { // Message content
                id: messageContentColumnLayout
                Layout.fillWidth: true
                // advanceWidth, not width, which rounds 56.6 down and wrapped "prove it";
                // 16 is the text area's own left and right padding (10 + 6)
                implicitWidth: root.isUser ? Math.max(20, Math.ceil(userTextMetrics.advanceWidth) + 16) : contentColumnLayout.implicitWidth
                implicitHeight: userClamp.implicitHeight

                // ClampBox has no motion of its own; on your turns the bubble is
                // the fold, so Show more opens it on the spatial spec
                Behavior on implicitHeight {
                    enabled: root.isUser
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                // A long turn of yours stops at ten lines, with Show more under it
                ClampBox {
                    id: userClamp
                    width: parent.width
                    maxHeight: root.isUser ? userLineMetrics.lineSpacing * 10 : Number.MAX_VALUE
                    colBase: Appearance.colors.colLayer2
                    colHover: Appearance.colors.colLayer2Hover
                    colActive: Appearance.colors.colLayer2Active

                ColumnLayout {
                    id: contentColumnLayout
                    width: parent.width
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
                        objectProp: "key"
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
                                searchQuery: root.searchQuery

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
                                searchQuery: root.searchQuery

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
                                enableMouseSelection: root.enableMouseSelection
                                segmentContent: modelData.content
                                segmentLang: modelData.lang
                                messageData: root.messageData
                                // This page has the console a run would report into.
                                enableRunActions: true
                                searchQuery: root.searchQuery
                                searchCurrent: root.searchCurrent
                            }
                        }
                        DelegateChoice {
                            roleValue: "think"
                            MessageThinkBlock {
                                required property var modelData
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
                                enableMouseSelection: root.enableMouseSelection
                                segmentContent: modelData.content
                                messageData: root.messageData
                                done: root.messageData?.done ?? false
                                searchQuery: root.searchQuery
                                searchCurrent: root.searchCurrent
                                speakingPhrase: root.speakingPhrase
                                speakingProgress: root.speakingProgress
                                speakingOffset: root.speakingOffset
                                forceDisableChunkSplitting: root.messageData?.content.includes("```") ?? true
                            }
                        }
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

            RowLayout { // Bottom control row and elapsed time
                id: assistantFooterRow
                visible: !root.isUser
                Layout.fillWidth: true
                spacing: 8

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
                        visible: !root.isInterface && root.isLastMessage
                        enabled: !HermesService.busy
                        buttonIcon: "refresh"
                        onClicked: HermesService.regenerate()

                        StyledToolTip {
                            text: Translation.tr("Retry this reply")
                        }
                    }
                }

                Item { // Spacer
                    Layout.fillWidth: true
                }

                StyledText { // How long it took
                    Layout.alignment: Qt.AlignVCenter
                    visible: text.length > 0
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    color: Appearance.colors.colSubtext
                    text: root.elapsedText
                }
            }
        }

        Item { // On your turns, the control row below the bubble
            visible: root.isUser
            Layout.alignment: Qt.AlignRight
            implicitWidth: userFooterRowLayout.implicitWidth
            implicitHeight: userFooterRowLayout.implicitHeight

            RowLayout {
                id: userFooterRowLayout
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    visible: text.length > 0
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    color: Appearance.colors.colSubtext
                    text: (root.messageData?.createdAt ?? 0) > 0
                        ? Qt.formatDateTime(new Date(root.messageData.createdAt), "HH:mm") : ""
                }

                ButtonGroup {
                    spacing: 4

                    AiMessageControlButton {
                        id: userCopyButton
                        buttonIcon: activated ? "inventory" : "content_copy"
                        onClicked: {
                            Quickshell.clipboardText = root.messageData?.content ?? "";
                            userCopyButton.activated = true;
                            userCopyIconTimer.restart();
                        }

                        Timer {
                            id: userCopyIconTimer
                            interval: 1500
                            onTriggered: userCopyButton.activated = false
                        }

                        StyledToolTip {
                            text: Translation.tr("Copy")
                        }
                    }

                    AiMessageControlButton {
                        // Editing a sent turn IS rewinding to it: the agent drops
                        // this turn and everything after, and hands its text back
                        // to the composer. The gateway refuses a rewind mid-run,
                        // so this greys out rather than failing on the click.
                        enabled: !HermesService.busy
                        buttonIcon: "edit"
                        onClicked: HermesService.rewindTo(root.messageId, true)

                        StyledToolTip {
                            text: Translation.tr("Edit and send again from here")
                        }
                    }
                }
            }
        }
    }
}
