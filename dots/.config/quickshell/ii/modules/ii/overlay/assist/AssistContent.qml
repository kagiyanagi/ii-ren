pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.ii.sidebarPolicies.hermes
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay
import Quickshell // ScriptModel

/**
 * Hermes as a floating overlay: ask about whatever is already on screen without
 * going to the sidebar for it. It drives the same singleton, so a conversation
 * started here is the one the sidebar page shows, and pinning the widget leaves it
 * over every window.
 *
 * Nothing here captures the screen. Looking is the agent's own move, through the
 * tools it loaded itself, so the eye toggle costs one line of prompt instead of a
 * screenshot pipeline. Without a tool that can see, it is hidden -- there would be
 * nothing behind it.
 */
OverlayBackground {
    id: root

    readonly property var service: HermesService
    readonly property var messageIDs: (root.service?.messageIDs ?? []).filter(id => root.service?.messageByID[id]?.visibleToUser ?? true)
    readonly property bool responding: root.service?.busy ?? false
    // The agent publishes the toolset it actually loaded, so the eye is offered
    // only when something behind it can really look.
    readonly property bool canLook: {
        const tools = root.service?.sessionTools ?? ({});
        return Object.values(tools).some(group => (group ?? []).some(name => name === "computer_use" || name === "vision_analyze"));
    }
    property bool seeScreen: true

    function ask(text: string): void {
        const trimmed = text.trim();
        if (trimmed.length === 0) return;
        // The agent decides on its own whether a look is worth it, which for a question
        // about the screen is a coin flip; naming the tool settles it.
        const prompt = (root.canLook && root.seeScreen) ? `[Use computer_use to take a screenshot first — the question is about what is on my screen.]\n${trimmed}` : trimmed;
        root.service?.sendMessage(prompt);
    }

    Connections {
        target: OverlayContext
        function onSummoned(identifier: string): void {
            if (identifier === "assist") inputField.forceActiveFocus();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        StyledListView {
            id: transcript
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            // ScriptModel, not the bare array: `root.messageIDs` is a fresh
            // `.filter()` result every time, and assigning a new array to `model`
            // tears down and rebuilds every turn delegate on each turn. Same reason
            // as Hermes.qml -- diff the ids and insert, don't reset the view.
            model: ScriptModel {
                values: root.messageIDs
            }

            onCountChanged: Qt.callLater(transcript.positionViewAtEnd)
            onContentHeightChanged: if (transcript.atYEnd || root.responding) Qt.callLater(transcript.positionViewAtEnd)

            delegate: HermesMessage {
                required property var modelData
                width: transcript.width
                messageData: root.service?.messageByID[modelData] ?? null
                messageId: modelData
            }

            StyledText {
                anchors.centerIn: parent
                visible: transcript.count === 0
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colSubtext
                text: root.canLook ? Translation.tr("Ask about what's on screen") : Translation.tr("Ask anything")
            }
        }

        // One line at rest, growing with the draft to two fifths of the card, then
        // scrolling. A one-line viewport on a wrapped field scrolls the draft out of
        // sight as you type, so the caret sits in what looks like an empty box while the
        // whole thing is still there and still gets sent on Enter.
        //
        // The height lives on this plain Item rather than on the row's own
        // `Layout.preferredHeight`, and it is `contentHeight`, not `implicitHeight`: a
        // `TextArea` inside a `ScrollView` is stretched to the viewport, so its implicit
        // height reports the viewport back at you and never grows.
        //
        // Not animated. It changes only when a line wraps, and that is the frame the
        // caret moves on -- a spring here would leave the text behind the cursor.
        Item {
            id: composer
            Layout.fillWidth: true
            implicitHeight: Math.min(root.height * 2 / 5, Math.max(sendButton.implicitHeight,
                inputField.contentHeight + inputField.topPadding + inputField.bottomPadding))

            RowLayout {
                anchors.fill: parent
                spacing: 2

                IconToolbarButton {
                    visible: root.canLook
                    // `ToolbarButton` declares `Layout.fillHeight: true`, and a composer
                    // button that fills stretches to the grown row -- which also stops it
                    // being square, since `IconToolbarButton` is `implicitWidth: height`.
                    // The bottom edge is where it belongs anyway.
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignBottom
                    text: root.seeScreen ? "visibility" : "visibility_off"
                    toggled: root.seeScreen
                    onClicked: root.seeScreen = !root.seeScreen
                    StyledToolTip {
                        text: Translation.tr("Let it look at the screen")
                    }
                }

                ScrollView {
                    id: inputScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    StyledTextArea {
                        id: inputField
                        // Width, not `anchors.fill`: anchored to the viewport the field is
                        // sized by the thing it is supposed to be measuring, and its width
                        // ran to 680px inside a 460px card, so the wrap points were wrong
                        // as well as the height.
                        width: inputScroll.availableWidth
                        wrapMode: TextArea.Wrap
                        padding: 8
                        background: null
                        placeholderText: root.responding ? Translation.tr("Working…") : Translation.tr("Ask…")

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape && root.responding) {
                                root.service?.interrupt();
                                event.accepted = true;
                                return;
                            }
                            if (event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return) return;
                            if (event.modifiers & Qt.ShiftModifier) {
                                inputField.insert(inputField.cursorPosition, "\n");
                            } else {
                                root.ask(inputField.text);
                                inputField.clear();
                            }
                            event.accepted = true;
                        }
                    }
                }

                IconToolbarButton {
                    id: sendButton
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignBottom
                    text: root.responding ? "stop" : "arrow_upward"
                    onClicked: {
                        if (root.responding) {
                            root.service?.interrupt();
                            return;
                        }
                        root.ask(inputField.text);
                        inputField.clear();
                    }
                }
            }
        }
    }
}
