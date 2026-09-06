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

    function resplit(): void {
        root.messageBlocks = StringUtils.splitMarkdownBlocks(root.messageData?.content);
    }

    Component.onCompleted: root.resplit()
    onMessageDataChanged: root.resplit()

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

        HermesToolSummary { // The whole run as one line, expandable
            Layout.fillWidth: true
            visible: (root.messageData?.toolCalls?.length ?? 0) > 0 && (Config.options.hermes?.showToolCalls ?? true)
            toolCalls: root.messageData?.toolCalls ?? []
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
