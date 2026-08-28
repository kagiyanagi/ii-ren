pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.services.conduit
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

/**
 * Conduit as a floating overlay: ask about whatever is already on screen without
 * going to the sidebar for it. It drives the same singleton, so a conversation
 * started here is the one the sidebar page shows, and pinning the widget leaves it
 * over every window.
 *
 * Nothing here captures the screen. Looking is the agent's own move, through the
 * desktop MCP server that also gives it the pointer and the keyboard, so the eye
 * toggle costs one line of prompt instead of a screenshot pipeline. With desktop
 * control off it is hidden, because then there is nothing behind it.
 */
OverlayBackground {
    id: root

    readonly property var service: ConduitService
    readonly property var messageIDs: (root.service?.messageIDs ?? []).filter(id => root.service?.messageByID[id]?.visibleToUser ?? true)
    readonly property bool responding: root.service?.responding ?? false
    readonly property bool canLook: Config.options.conduit.enableTools && Config.options.conduit.desktopControl
    property bool seeScreen: true

    function ask(text: string): void {
        const trimmed = text.trim();
        if (trimmed.length === 0) return;
        // The agent decides on its own whether a look is worth it, which for a question
        // about the screen is a coin flip; naming the tool settles it.
        const prompt = (root.canLook && root.seeScreen) ? `[Use desktop_look first — the question is about what is on my screen.]\n${trimmed}` : trimmed;
        root.service?.sendUserMessage(prompt);
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
            model: root.messageIDs

            onCountChanged: Qt.callLater(transcript.positionViewAtEnd)
            onContentHeightChanged: if (transcript.atYEnd || root.responding) Qt.callLater(transcript.positionViewAtEnd)

            delegate: ConduitTurn {
                required property var modelData
                width: transcript.width
                messageData: root.service?.messageByID[modelData] ?? null
                messageId: modelData
                service: root.service
            }

            StyledText {
                anchors.centerIn: parent
                visible: transcript.count === 0
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colSubtext
                text: root.canLook ? Translation.tr("Ask about what's on screen") : Translation.tr("Ask anything")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            spacing: 2

            IconToolbarButton {
                visible: root.canLook
                text: root.seeScreen ? "visibility" : "visibility_off"
                toggled: root.seeScreen
                onClicked: root.seeScreen = !root.seeScreen
                StyledToolTip {
                    text: Translation.tr("Let it look at the screen")
                }
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                StyledTextArea {
                    id: inputField
                    anchors.fill: parent
                    wrapMode: TextArea.Wrap
                    padding: 8
                    background: null
                    placeholderText: root.responding ? Translation.tr("Working…") : Translation.tr("Ask…")

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape && root.responding) {
                            root.service?.stop();
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
                text: root.responding ? "stop" : "arrow_upward"
                onClicked: {
                    if (root.responding) {
                        root.service?.stop();
                        return;
                    }
                    root.ask(inputField.text);
                    inputField.clear();
                }
            }
        }
    }
}
