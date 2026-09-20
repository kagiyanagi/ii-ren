pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import org.kde.syntaxhighlighting

ColumnLayout {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    // On by default: no call site ever set this, so nothing in a reply was
    // selectable and the only way to copy anything was the whole-block button.
    property bool enableMouseSelection: true
    property var segmentContent: ({})
    property var segmentLang: "txt"
    // `{}` parses as an empty block, not an empty object, so this was undefined
    // and every read of it threw -- same fix as MessageTextBlock.qml.
    property var messageData: null
    // Running a block executes what a model wrote, so it is offered only where a
    // console exists to run it in and to show what it did. Off for every other caller.
    property bool enableRunActions: false
    /** What a transcript search is looking for. A match in code counts like any other. */
    property string searchQuery: ""
    property bool searchCurrent: false
    property bool isCommandRequest: segmentLang === "command"
    property var displayLang: (isCommandRequest ? "bash" : segmentLang)

    property real codeBlockBackgroundRounding: Appearance.rounding.small
    property real codeBlockHeaderPadding: 3
    property real codeBlockComponentSpacing: 2

    spacing: codeBlockComponentSpacing

    Rectangle { // Code background
        Layout.fillWidth: true
        topLeftRadius: codeBlockBackgroundRounding
        topRightRadius: codeBlockBackgroundRounding
        bottomLeftRadius: Appearance.rounding.unsharpen
        bottomRightRadius: Appearance.rounding.unsharpen
        color: Appearance.colors.colSurfaceContainerHighest
        implicitHeight: codeBlockTitleBarRowLayout.implicitHeight + codeBlockHeaderPadding * 2

        RowLayout { // Language and buttons
            id: codeBlockTitleBarRowLayout
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: codeBlockHeaderPadding
            anchors.rightMargin: codeBlockHeaderPadding
            spacing: 5

            StyledText {
                id: codeBlockLanguage
                Layout.alignment: Qt.AlignLeft
                Layout.fillWidth: false
                Layout.topMargin: 7
                Layout.bottomMargin: 7
                Layout.leftMargin: 10
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                text: root.displayLang ? Repository.definitionForName(root.displayLang).name : "plain"
            }

            Item { Layout.fillWidth: true }

            ButtonGroup {
                AiMessageControlButton {
                    id: copyCodeButton
                    buttonIcon: activated ? "inventory" : "content_copy"

                    onClicked: {
                        Quickshell.clipboardText = segmentContent
                        copyCodeButton.activated = true
                        copyIconTimer.restart()
                    }

                    Timer {
                        id: copyIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            copyCodeButton.activated = false
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Copy code")
                    }
                }
                AiMessageControlButton {
                    id: saveCodeButton
                    buttonIcon: activated ? "check" : "save"

                    onClicked: {
                        // Every block used to be written to the same `code.<ext>`,
                        // so saving a second one silently replaced the first. The
                        // name carries a timestamp now, and the write is a heredoc
                        // rather than an `echo` that mangled backslashes.
                        HermesService.runner.saveToFile(segmentContent, segmentLang,
                            FileUtils.trimFileProtocol(Directories.downloads))
                        saveCodeButton.activated = true
                        saveIconTimer.restart()
                    }

                    Timer {
                        id: saveIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            saveCodeButton.activated = false
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Save to Downloads")
                    }
                }
                AiMessageControlButton {
                    buttonIcon: "open_in_new"
                    onClicked: HermesService.runner.openInEditor(segmentContent, segmentLang)

                    StyledToolTip {
                        text: Translation.tr("Open in editor")
                    }
                }
                AiMessageControlButton {
                    // Hidden, not greyed, when nothing here can run this language:
                    // a button that could only ever fail is worse than no button.
                    visible: root.enableRunActions && HermesService.runner.canRun(root.segmentLang)
                    enabled: !HermesService.runner.running
                    buttonIcon: "play_arrow"
                    onClicked: HermesService.runner.runCode(segmentContent, segmentLang)

                    StyledToolTip {
                        text: Translation.tr("Run this")
                    }
                }
            }
        }
    }

    RowLayout { // Line numbers and code
        spacing: codeBlockComponentSpacing

        Rectangle { // Line numbers
            implicitWidth: 40
            implicitHeight: lineNumberColumnLayout.implicitHeight
            Layout.fillHeight: true
            Layout.fillWidth: false
            topLeftRadius: Appearance.rounding.unsharpen
            bottomLeftRadius: codeBlockBackgroundRounding
            topRightRadius: Appearance.rounding.unsharpen
            bottomRightRadius: Appearance.rounding.unsharpen
            color: Appearance.colors.colLayer3

            ColumnLayout {
                id: lineNumberColumnLayout
                anchors {
                    left: parent.left
                    right: parent.right
                    rightMargin: 5
                    top: parent.top
                    topMargin: 6
                }
                spacing: 0
                
                Repeater {
                    model: codeTextArea.text.split("\n").length
                    Text {
                        required property int index
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        horizontalAlignment: Text.AlignRight
                        text: index + 1
                    }
                }
            }
        }

        Rectangle { // Code background
            Layout.fillWidth: true
            topLeftRadius: Appearance.rounding.unsharpen
            bottomLeftRadius: Appearance.rounding.unsharpen
            topRightRadius: Appearance.rounding.unsharpen
            bottomRightRadius: codeBlockBackgroundRounding
            color: Appearance.colors.colLayer3
            implicitHeight: codeColumnLayout.implicitHeight

            ColumnLayout {
                id: codeColumnLayout
                anchors.fill: parent
                spacing: 0
                // Deliberately a bare Flickable and not a ScrollView. ScrollView is a
                // Control, and QQuickControl::wheelEvent accepts every wheel event that
                // lands on it whenever `wheelEnabled` is set -- which ScrollView does in
                // its own constructor -- whether or not it has anywhere to scroll. A code
                // block therefore ate the entire scroll gesture and the transcript behind
                // it never moved. Measured on a 41-line block: a two-finger scroll that
                // moves the message list 324px anywhere else moved it 0px over the block.
                //
                // A Flickable is not a Control, and one locked to a single axis ignores a
                // wheel on the other axis, so the vertical scroll reaches the list. Neither
                // `interactive: false`, `flickableDirection` nor `wheelEnabled: false` on
                // the ScrollView fixes it; only not being a Control does.
                Flickable {
                    id: codeFlickable
                    Layout.fillWidth: true
                    implicitHeight: codeTextArea.implicitHeight
                    contentWidth: codeTextArea.width
                    contentHeight: codeTextArea.implicitHeight
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true

                    // No anchors: attached to a Flickable directly, the bar lays itself
                    // out along the bottom edge, and anchoring it fights that.
                    ScrollBar.horizontal: ScrollBar {
                        padding: 5
                        policy: ScrollBar.AsNeeded
                        opacity: visualSize == 1 ? 0 : 1
                        visible: opacity > 0

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        contentItem: Rectangle {
                            implicitHeight: 6
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer3Active
                        }
                    }

                    TextArea { // Code
                        id: codeTextArea
                        readOnly: !editing
                        selectByMouse: enableMouseSelection || editing
                        renderType: Text.NativeRendering
                        font.family: Appearance.font.family.monospace
                        font.hintingPreference: Font.PreferNoHinting // Prevent weird bold text
                        font.pixelSize: Appearance.font.pixelSize.small
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        color: root.messageData?.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer3

                        text: segmentContent
                        onTextChanged: {
                            segmentContent = text
                        }

                        // See MessageTextBlock: the transcript offers actions on
                        // whatever is selected, and only this delegate knows.
                        onSelectedTextChanged: TextSelectionService.report(codeTextArea)
                        Component.onDestruction: TextSelectionService.release(codeTextArea)

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Tab) {
                                // Insert 4 spaces at cursor
                                const cursor = codeTextArea.cursorPosition;
                                codeTextArea.insert(cursor, "    ");
                                codeTextArea.cursorPosition = cursor + 4;
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_C) && event.modifiers == Qt.ControlModifier) {
                                codeTextArea.copy();
                                event.accepted = true;
                            }
                        }

                        MouseArea { // Cursor, and the right button; the rest passes through
                            // Spelled out rather than left to TextEdit, which sets the
                            // cursor itself from `readOnly && !selectByMouse` and so was
                            // actively forcing an arrow over the code.
                            // The right button is taken so Qt 6.9+'s stock editing menu
                            // does not open over a read-only block -- the header already
                            // has Copy and Save buttons for what it would offer.
                            anchors.fill: parent
                            acceptedButtons: root.editing ? Qt.NoButton : Qt.RightButton
                            hoverEnabled: true
                            cursorShape: (root.enableMouseSelection || root.editing) ? Qt.IBeamCursor : Qt.ArrowCursor
                        }

                        SpeechHighlight { // Search hits inside the code
                            target: codeTextArea
                            query: root.searchQuery
                            // Both translucent: the stepped-to hit is stronger, not solid.
                            markColor: ColorUtils.applyAlpha(Appearance.colors.colPrimaryContainer, root.searchCurrent ? 0.4 : 0.18)
                        }

                        SyntaxHighlighter {
                            id: highlighter
                            textEdit: codeTextArea
                            repository: Repository
                            definition: Repository.definitionForName(root.displayLang || "plaintext")
                            theme: Appearance.syntaxHighlightingTheme
                        }
                    }
                }
                Loader {
                    active: root.isCommandRequest && (root.messageData?.functionPending ?? false)
                    visible: active
                    Layout.fillWidth: true
                    Layout.margins: 6
                    Layout.topMargin: 0
                    sourceComponent: RowLayout {
                        Item { Layout.fillWidth: true }
                        ButtonGroup {
                            GroupButton {
                                contentItem: StyledText {
                                    text: Translation.tr("Reject")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer2
                                }
                                onClicked: Ai.rejectCommand(root.messageData)
                            }
                            GroupButton {
                                toggled: true
                                contentItem: StyledText {
                                    text: Translation.tr("Approve")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnPrimary
                                }
                                onClicked: Ai.approveCommand(root.messageData)
                            }
                        }
                    }
                }
            }

        }
    }
}