pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarPolicies.aiChat
import Quickshell
import QtQuick
import QtQuick.Layouts

/**
 * One conversation turn.
 *
 * Assistant turns render their ordered `parts`, so tool calls appear inline
 * between text blocks exactly where they happened. Text is handed to the shell's
 * own MessageTextBlock / MessageCodeBlock / MessageThinkBlock, so markdown,
 * syntax highlighting and collapsible reasoning match the built-in chat instead
 * of being reimplemented here.
 *
 * AiMessage.qml itself is not reused: it is coupled to the `Ai` singleton
 * (`Ai.models[messageData.model].icon`, `Ai.regenerate`) and these model ids do
 * not exist in that map.
 */
Item {
    id: root

    required property var messageData

    // Both only needed by the reply actions: speaking a turn is the service's job,
    // and it identifies turns by id.
    property int messageId: -1
    property var service: null

    readonly property bool isUser: root.messageData?.role === "user"
    readonly property bool isInterface: root.messageData?.role === "interface"
    readonly property bool hasError: (root.messageData?.error ?? "").length > 0

    // User turns hug their text; assistant turns use the full column so code
    // blocks and tool rows have room to breathe.
    readonly property real maxBubbleWidth: root.width * (root.isUser ? 0.85 : 1.0)

    implicitHeight: bubble.height

    Rectangle {
        id: bubble

        // Positioned by x rather than anchors: conditional left/right/horizontalCenter
        // anchors are mutually exclusive and Qt warns even when only one is active.
        x: root.isUser ? root.width - bubble.width : 0

        width: {
            if (!root.isUser) return root.width;
            // A turn carrying files needs the full width: the previews are sized by the
            // bubble, so letting the text alone decide would squeeze them.
            if ((root.messageData?.attachments ?? []).length > 0) return root.maxBubbleWidth;
            return Math.min(root.maxBubbleWidth, userText.implicitWidth + 24);
        }
        height: content.implicitHeight + (root.isInterface ? 4 : 20)
        radius: Appearance.rounding.small

        color: {
            if (root.hasError) return Appearance.m3colors.m3errorContainer;
            if (root.isUser) return Appearance.colors.colSecondaryContainer;
            return "transparent";
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: root.isUser ? 12 : 0
            anchors.rightMargin: root.isUser ? 12 : 0
            anchors.topMargin: root.isInterface ? 2 : 10
            spacing: 4

            Repeater { // Files sent with this turn
                model: root.messageData?.attachments ?? []

                delegate: AttachedFileIndicator {
                    required property var modelData
                    Layout.fillWidth: true
                    filePath: modelData
                    highlight: false
                    canRemove: false
                    maxHeight: 160
                }
            }

            StyledText { // User turns: plain text, no markdown pipeline needed
                id: userText
                visible: root.isUser
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSecondaryContainer
                text: root.isUser ? (root.messageData?.content ?? "") : ""
            }

            StyledText { // Local notices
                visible: root.isInterface
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.MarkdownText
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.italic: true
                color: Appearance.colors.colSubtext
                onLinkActivated: link => Qt.openUrlExternally(link)
                text: root.isInterface ? (root.messageData?.content ?? "") : ""
            }

            MaterialLoadingIndicator { // Waiting for the first token
                visible: root.messageData?.thinking ?? false
                implicitSize: 28
                loading: visible
            }

            Repeater { // Assistant turns: ordered text and tool parts
                model: root.isUser || root.isInterface ? [] : (root.messageData?.parts ?? [])

                delegate: ColumnLayout {
                    id: partDelegate
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.maximumWidth: content.width
                    spacing: 2

                    // splitMarkdownBlocks() returns a fresh array of fresh objects, so
                    // binding it straight to the streaming `text` destroyed and rebuilt
                    // every segment delegate -- each code block re-highlighted -- on every
                    // token, which is what made a long reply crawl. Re-split on a timer
                    // that is left alone while it runs instead: a throttle, not a debounce,
                    // since a debounce would show nothing until the stream paused.
                    property var blocks: []

                    function resplit() {
                        partDelegate.blocks = partDelegate.modelData?.kind === "text"
                            ? StringUtils.splitMarkdownBlocks(partDelegate.modelData.text)
                            : [];
                    }

                    Component.onCompleted: partDelegate.resplit()

                    Timer {
                        id: resplitThrottle
                        interval: 60
                        onTriggered: partDelegate.resplit()
                    }

                    Connections {
                        target: partDelegate.modelData
                        function onTextChanged() {
                            if (!resplitThrottle.running)
                                resplitThrottle.start();
                        }
                    }

                    // The last delta and `done` can arrive in either order, so a finished
                    // turn always gets one final split at the full text.
                    Connections {
                        target: root.messageData
                        function onDoneChanged() {
                            if (root.messageData?.done) {
                                resplitThrottle.stop();
                                partDelegate.resplit();
                            }
                        }
                    }

                    ToolActivityRow {
                        visible: partDelegate.modelData?.kind === "tool"
                        Layout.fillWidth: true
                        part: partDelegate.modelData
                    }

                    Repeater { // Markdown segments within one text part
                        model: partDelegate.blocks

                        delegate: Loader {
                            id: segmentLoader
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.maximumWidth: content.width
                            sourceComponent: {
                                if (segmentLoader.modelData.type === "code") return codeComponent;
                                if (segmentLoader.modelData.type === "think") return thinkComponent;
                                return textComponent;
                            }

                            Component {
                                id: textComponent
                                MessageTextBlock {
                                    id: textBlock
                                    segmentContent: segmentLoader.modelData.content
                                    messageData: root.messageData
                                    // Starts false so that a block created for an
                                    // already-finished turn still sees done go true, which
                                    // is what triggers its force-apply of cached LaTeX.
                                    done: false
                                    Component.onCompleted: textBlock.done = Qt.binding(() => root.messageData?.done ?? true)
                                }
                            }
                            Component {
                                id: codeComponent
                                MessageCodeBlock {
                                    segmentContent: segmentLoader.modelData.content
                                    segmentLang: segmentLoader.modelData.lang ?? "txt"
                                    messageData: root.messageData
                                }
                            }
                            Component {
                                id: thinkComponent
                                MessageThinkBlock {
                                    segmentContent: segmentLoader.modelData.content
                                    messageData: root.messageData
                                    done: root.messageData?.done ?? true
                                    completed: segmentLoader.modelData.completed ?? false
                                }
                            }
                        }
                    }
                }
            }

            StyledText { // Errors
                visible: root.hasError
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3onErrorContainer
                text: root.messageData?.error ?? ""
            }

            RowLayout { // Reply actions, bottom-right like a messaging app
                visible: !root.isUser && !root.isInterface
                    && (root.messageData?.done ?? false)
                    && (root.messageData?.content ?? "").length > 0
                Layout.fillWidth: true
                Layout.topMargin: 2

                Item { Layout.fillWidth: true }

                ButtonGroup {
                    spacing: 4

                    AiMessageControlButton {
                        id: copyButton
                        buttonIcon: activated ? "inventory" : "content_copy"

                        onClicked: {
                            Quickshell.clipboardText = root.messageData?.content ?? "";
                            copyButton.activated = true;
                            copyResetTimer.restart();
                        }

                        Timer {
                            id: copyResetTimer
                            interval: 1500
                            onTriggered: copyButton.activated = false
                        }

                        StyledToolTip { text: "Copy this reply" }
                    }

                    AiMessageControlButton {
                        id: speakButton
                        readonly property bool working: (root.service?.ttsSpeakingFor ?? -1) === root.messageId
                        // Disabled only while this turn is being synthesised: a press on
                        // another turn is meant to replace it, not to be swallowed.
                        enabled: !speakButton.working
                        buttonIcon: speakButton.working ? "more_horiz" : "graphic_eq"

                        onClicked: root.service?.speakMessage(root.messageId)

                        StyledToolTip {
                            text: speakButton.working ? "Recording the memo…" : "Read this out loud"
                        }
                    }
                }
            }

            Loader { // Voice memo for this turn, once one has been synthesised
                active: (root.messageData?.audioPath ?? "").length > 0
                visible: active
                Layout.fillWidth: true
                // Capped: a full-width player puts the speed chip a mouse-journey away
                // from the waveform it applies to.
                Layout.maximumWidth: Math.min(content.width, 420)
                Layout.topMargin: 2

                sourceComponent: VoiceMemo {
                    messageId: root.messageId
                    path: root.messageData?.audioPath ?? ""
                    bytes: root.messageData?.audioBytes ?? 0
                    bars: root.messageData?.audioBars ?? []
                    activeId: root.service?.activeMemo ?? -1
                    claimAutoPlay: () => root.service?.takeAutoPlay(root.messageId) ?? -1
                    onClaimed: id => root.service?.claimSpeakers(id)
                }
            }
        }
    }
}
