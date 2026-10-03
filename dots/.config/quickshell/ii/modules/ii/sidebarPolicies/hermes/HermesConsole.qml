pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarPolicies.aiChat
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * The band a `!` command runs in.
 *
 * It sits above the composer rather than in the transcript on purpose. A command
 * you are still answering needs a stable place to type into, and a transcript
 * delegate is rebuilt whenever the list model changes -- which is what would take
 * the cursor out of the input line mid-prompt.
 *
 * Output is not sent to the agent on its own. `!ls` is usually for the user, and
 * the run that is worth spending context on is the one they say so about.
 */
Rectangle {
    id: root

    readonly property var runner: HermesService.runner
    readonly property bool shown: root.runner.running || root.runner.finished
    property real maxOutputHeight: 220

    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.normal
    clip: true

    property AnimSpec implicitHeightSpec: Appearance.animation.elementMoveEnter
    implicitHeight: {
        root.implicitHeightSpec = root.shown ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveExit;
        return root.shown ? consoleColumn.implicitHeight + 16 : 0;
    }
    property AnimSpec opacitySpec: Appearance.animation.elementMoveFast
    opacity: {
        root.opacitySpec = root.shown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
        return root.shown ? 1 : 0;
    }
    visible: implicitHeight > 0

    Behavior on implicitHeight {
        NumberAnimation {
            duration: root.implicitHeightSpec.duration
            easing.type: root.implicitHeightSpec.type
            easing.bezierCurve: root.implicitHeightSpec.bezierCurve
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: root.opacitySpec.duration
            easing.type: root.opacitySpec.type
            easing.bezierCurve: root.opacitySpec.bezierCurve
        }
    }

    ColumnLayout {
        id: consoleColumn
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 8
        }
        spacing: 8

        RowLayout { // What is running, and what can be done about it
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                iconSize: Appearance.font.pixelSize.large
                color: root.runner.running ? Appearance.colors.colPrimary : root.runner.exitCode === 0 ? Appearance.colors.colSubtext : Appearance.m3colors.m3error
                text: root.runner.running ? "terminal" : root.runner.exitCode === 0 ? "check_circle" : "error"
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colOnLayer2
                text: root.runner.command
            }

            StyledText {
                visible: !root.runner.running && root.runner.finished
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.runner.exitCode === 0 ? Appearance.colors.colSubtext : Appearance.m3colors.m3error
                text: root.runner.interrupted ? Translation.tr("stopped") : Translation.tr("exit %1").arg(root.runner.exitCode)
            }

            ButtonGroup {
                spacing: 4

                AiMessageControlButton {
                    // Stop stays a Ctrl+C rather than a kill: a command that traps
                    // SIGINT gets to clean up, the same as it would in a terminal.
                    visible: root.runner.running
                    buttonIcon: "stop_circle"
                    onClicked: root.runner.interrupt()

                    StyledToolTip {
                        text: Translation.tr("Stop (Ctrl+C)")
                    }
                }

                AiMessageControlButton {
                    visible: !root.runner.running && root.runner.finished
                    buttonIcon: "forum"
                    onClicked: {
                        HermesService.shareCommandOutput(root.runner.command, root.runner.output, root.runner.exitCode);
                        root.runner.clear();
                    }

                    StyledToolTip {
                        text: Translation.tr("Put this in the message box for Hermes")
                    }
                }

                AiMessageControlButton {
                    visible: !root.runner.running && root.runner.finished
                    buttonIcon: "close"
                    onClicked: root.runner.clear()

                    StyledToolTip {
                        text: Translation.tr("Dismiss")
                    }
                }
            }
        }

        Flickable { // Output
            id: outputFlickable
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(root.maxOutputHeight, outputText.implicitHeight)
            contentWidth: width
            contentHeight: outputText.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            clip: true
            visible: root.runner.output.length > 0

            // Follow the newest line, but let go the moment the reader scrolls off
            // the bottom themselves -- the same rule the transcript follows.
            property bool following: true

            onMovementEnded: outputFlickable.following = outputFlickable.contentY >= outputFlickable.contentHeight - outputFlickable.height - 8
            onContentHeightChanged: if (outputFlickable.following)
                outputFlickable.contentY = Math.max(0, outputFlickable.contentHeight - outputFlickable.height)

            ScrollBar.vertical: StyledScrollBar {}

            TextEdit {
                id: outputText
                width: outputFlickable.width
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                renderType: Text.NativeRendering
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.hintingPreference: Font.PreferNoHinting
                color: Appearance.colors.colOnLayer2
                selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                selectionColor: Appearance.colors.colSecondaryContainer
                text: root.runner.output
            }
        }

        MaterialTextField { // Answer whatever it is asking
            id: stdinField
            Layout.fillWidth: true
            visible: root.runner.running
            placeholderText: stdinField.askingForSecret ? Translation.tr("Type the password") : Translation.tr("Type here to answer the command")

            // sudo and ssh turn off echo on the pty, so a password never comes
            // back in the output -- but it would still be sitting in plain sight
            // in this box while it was typed. The prompt is the only thing that
            // says one is being asked for, so the prompt is what decides.
            readonly property bool askingForSecret: /(password|passphrase)\s*(for [^:]*)?:\s*$/i.test(root.runner.output)
            echoMode: stdinField.askingForSecret ? TextInput.Password : TextInput.Normal

            onAccepted: {
                root.runner.send(stdinField.text);
                stdinField.text = "";
            }

            Keys.onPressed: event => {
                // Ctrl+C in the input line means what it means in a terminal, but
                // only when there is nothing selected to copy instead.
                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && stdinField.selectedText.length === 0) {
                    root.runner.interrupt();
                    event.accepted = true;
                }
            }
        }
    }

    // A new run steals the caret: the command is usually asking something, and
    // hunting for the box to answer in is the one thing this band exists to avoid.
    Connections {
        target: root.runner
        function onRunningChanged() {
            if (root.runner.running)
                stdinField.forceActiveFocus();
        }
    }
}
