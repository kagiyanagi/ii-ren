import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    readonly property bool usePasswordChars: !PolkitService.flow?.responseVisible ?? true

    // The dialog has finished leaving; the window is held mapped until then.
    signal closed()

    // Copied out of the flow while it lives, not bound to it. The flow is deleted
    // on the frame it completes, before the exit plays, and a message bound to it
    // emptied on the exit's first frame and pulled the field up a line.
    property string message
    property string pamMessage
    property bool pamMessageIsError
    property bool failed

    function capture() {
        const flow = PolkitService.flow;
        if (!flow)
            return;
        root.message = PolkitService.cleanMessage;
        root.pamMessage = flow.supplementaryMessage;
        root.pamMessageIsError = flow.supplementaryIsError;
    }

    // Why the password did not work, or cannot, in the lock screen's order. PAM has
    // first claim: pam_faillock refuses a locked account before pam_unix sees the
    // password, and says so -- and its tally is per user, so wrong passwords here
    // count toward the lock screen's too. Then the failure itself, which polkit
    // reports only as a signal, restarting the session with nothing on screen to
    // say so. Then Caps Lock.
    readonly property string status: {
        if (root.pamMessage.length > 0)
            return root.pamMessage;
        if (root.failed)
            return Translation.tr("Incorrect password");
        if (HyprlandXkb.capsLock)
            return Translation.tr("Caps Lock is on");
        return "";
    }
    readonly property bool statusIsError: root.pamMessage.length > 0 ? root.pamMessageIsError : root.failed

    function submit() {
        root.failed = false;
        PolkitService.submit(inputField.text);
    }

    function takeFocus() {
        // A disabled field drops focus, and Esc has to keep working through the
        // two seconds pam_unix waits before it reports a failure.
        if (!PolkitService.interactionAvailable) {
            dialog.forceActiveFocus();
            return;
        }
        inputField.text = "";
        inputField.forceActiveFocus();
    }

    Component.onCompleted: {
        root.capture();
        // Nothing races the compositor here; the key press keeps it current after.
        HyprlandXkb.refreshLockKeys();
        root.takeFocus();
        dialog.show = true;
    }

    Connections {
        target: PolkitService
        function onFlowChanged() {
            // A queued request follows straight on in the same dialog.
            if (!PolkitService.flow)
                return;
            root.failed = false;
            root.capture();
        }
        function onActiveChanged() {
            dialog.show = PolkitService.active;
        }
        function onInteractionAvailableChanged() {
            root.takeFocus();
        }
    }

    Connections {
        target: PolkitService.flow
        function onSupplementaryMessageChanged() {
            root.capture();
        }
        function onSupplementaryIsErrorChanged() {
            root.capture();
        }
        function onAuthenticationFailed() {
            root.failed = true;
        }
    }

    WindowDialog {
        id: dialog
        anchors.fill: parent
        // The scrim covers the whole screen, whose corners are square.
        radius: 0
        backgroundWidth: 450
        onDismiss: PolkitService.cancel()
        onVisibleChanged: {
            if (!visible && !PolkitService.active)
                root.closed();
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            iconSize: 26
            text: "security"
            color: Appearance.colors.colSecondary
        }

        WindowDialogTitle {
            id: titleText
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Authentication")
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignLeft
            text: root.message
        }

        // The status is the field's supporting text, so it sits M3's 4dp under
        // the field rather than a paragraph's 16.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            MaterialTextField {
                id: inputField
                Layout.fillWidth: true
                focus: true
                enabled: PolkitService.interactionAvailable
                placeholderText: PolkitService.cleanPrompt
                echoMode: root.usePasswordChars ? TextInput.Password : TextInput.Normal
                onAccepted: root.submit();

                Keys.onPressed: event => {
                    // The press is the toggle. Asking the compositor here instead
                    // races it -- see HyprlandXkb.noteCapsLockPressed.
                    if (event.key === Qt.Key_CapsLock && !event.isAutoRepeat)
                        HyprlandXkb.noteCapsLockPressed();
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.status.length > 0
                // Wrapped, not elided: faillock's lockout runs to two sentences.
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.statusIsError ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
                text: root.status
            }
        }

        WindowDialogButtonRow {
            Item {
                Layout.fillWidth: true
            }
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: PolkitService.cancel();
            }
            DialogButton {
                enabled: PolkitService.interactionAvailable
                buttonText: Translation.tr("OK")
                onClicked: root.submit();
            }
        }
    }
}
