import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarPolicies.hermes
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * Hermes agent page.
 *
 * Slash completions, the provider/model inventory and the tool list are all
 * pulled from the running agent rather than mirrored here, so skills, plugins and
 * providers the user adds to Hermes show up without a shell change.
 */
Item {
    id: root

    property real padding: 4
    property var inputField: messageInputField
    readonly property string commandPrefix: "/"

    property var suggestionList: []
    property bool historyShown: false
    property bool workShown: false

    // The gateway boots a Python agent and its MCP fleet, so it starts when this
    // page is first built rather than at login.
    Component.onCompleted: {
        HermesService.ensureStarted();
        HermesService.prewarmTts();
    }

    onFocusChanged: focus => {
        if (focus)
            root.inputField.forceActiveFocus();
    }

    // Type-anywhere: a stray keystroke goes to the composer rather than nowhere.
    // It must not fire on a modifier's own key-down, though - Ctrl arrives here as
    // Key_Control before the C does, and stealing focus on it wipes a selection in
    // the transcript just as the user reaches for copy. Shortcut combinations are
    // left alone for the same reason: they belong to whatever is focused.
    readonly property var modifierKeys: [Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta,
                                         Qt.Key_AltGr, Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_Super_L, Qt.Key_Super_R]

    Keys.onPressed: event => {
        const bareKey = (event.modifiers & ~Qt.ShiftModifier & ~Qt.KeypadModifier) === 0;
        if (bareKey && root.modifierKeys.indexOf(event.key) === -1)
            messageInputField.forceActiveFocus();
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                messageListView.followingEnd = false;
                messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown) {
                messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2);
                event.accepted = true;
            }
        }
        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            HermesService.newSession();
            event.accepted = true;
        }
    }

    function handleInput(inputText: string): void {
        const text = inputText.trim();
        if (text.length === 0)
            return;

        if (text.startsWith(root.commandPrefix))
            HermesService.runSlashCommand(text);
        else
            HermesService.sendMessage(text);

        root.suggestionList = [];
        messageListView.positionViewAtEnd();
    }

    /**
     * Stage a quoted passage in the composer for the user to answer under.
     *
     * Goes in as a Markdown blockquote so the agent can tell the quote from the
     * new question, and lands in the box rather than being sent: a quote is the
     * opening of a reply, not the reply.
     */
    function quoteToComposer(text: string): void {
        const quoted = text.trim();
        if (quoted.length === 0)
            return;
        const block = quoted.split("\n").map(line => `> ${line}`).join("\n");
        const existing = messageInputField.text.replace(/\s+$/, "");
        messageInputField.text = existing.length > 0 ? `${existing}\n\n${block}\n\n` : `${block}\n\n`;
        messageInputField.cursorPosition = messageInputField.text.length;
        messageInputField.forceActiveFocus();
    }

    // A finished transcript goes into the box rather than straight to the agent:
    // STT mishears, and an unreviewed send cannot be taken back.
    Connections {
        target: HermesService
        // A prefill directive (/undo) hands text back to edit, not to send.
        function onComposerPrefill(text) {
            messageInputField.text = text;
            messageInputField.cursorPosition = messageInputField.text.length;
            messageInputField.forceActiveFocus();
        }
        // Each staged file adds its own reference; dropping several has to leave
        // all of them in the box, not just the last one to come back.
        function onComposerAppend(text) {
            const existing = messageInputField.text.replace(/\s+$/, "");
            // A block -- anything carrying a line break, such as a command's
            // output -- has to start its own line or a fence stops being a fence.
            // A bare `@file:` ref just follows whatever was already typed.
            const block = text.includes("\n");
            const gap = block ? "\n\n" : " ";
            const tail = block ? "\n" : " ";
            messageInputField.text = (existing.length > 0 ? `${existing}${gap}${text}` : text) + tail;
            messageInputField.cursorPosition = messageInputField.text.length;
            messageInputField.forceActiveFocus();
        }
        function onDictationTranscript(text) {
            const existing = messageInputField.text.trim();
            messageInputField.text = existing.length > 0 ? `${existing} ${text}` : text;
            messageInputField.cursorPosition = messageInputField.text.length;
            messageInputField.forceActiveFocus();
        }
    }

    // Completions come from the agent, which ranks them against its own skill
    // usage; debounced so a fast typist does not queue one RPC per keystroke.
    Timer {
        id: suggestionDebounce
        interval: 120
        onTriggered: {
            const text = messageInputField.text;
            if (!text.startsWith(root.commandPrefix)) {
                root.suggestionList = [];
                return;
            }
            HermesService.completeSlash(text, items => {
                // A reply that lands after the box moved on is stale.
                if (!messageInputField.text.startsWith(root.commandPrefix)) {
                    root.suggestionList = [];
                    return;
                }
                root.suggestionList = items.slice(0, Config.options.hermes?.maxSuggestions ?? 12);
            });
        }
    }

    component StatusItem: MouseArea {
        id: statusItem
        property string icon
        property string statusText
        property string description
        hoverEnabled: true
        implicitHeight: statusItemRowLayout.implicitHeight
        implicitWidth: statusItemRowLayout.implicitWidth

        RowLayout {
            id: statusItemRowLayout
            spacing: 0

            MaterialSymbol {
                text: statusItem.icon
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colSubtext
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                text: statusItem.statusText
                color: Appearance.colors.colSubtext
                animateChange: true
            }
        }

        StyledToolTip {
            text: statusItem.description
            extraVisibleCondition: false
            alternativeVisibleCondition: statusItem.containsMouse
        }
    }

    /** The compact icon controls that sit beside the command buttons. */
    component InputIconButton: RippleButton {
        id: iconButton
        required property string symbol
        property string tooltip: ""
        property int badge: 0

        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.small

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            iconSize: Appearance.font.pixelSize.larger
            color: iconButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
            text: iconButton.symbol
        }

        Rectangle {
            id: badgeDot
            anchors.top: parent.top
            anchors.right: parent.right
            implicitWidth: 16
            implicitHeight: 16
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary
            visible: iconButton.badge > 0
            // Grows out of the corner it sits in.
            transformOrigin: Item.TopRight
            scale: iconButton.badge > 0 ? 1 : 0

            Behavior on scale {
                NumberAnimation {
                    duration: iconButton.badge > 0 ? Appearance.animation.elementMoveEnter.duration : Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: iconButton.badge > 0 ? Appearance.animation.elementMoveEnter.bezierCurve : Appearance.animation.elementMoveExit.bezierCurve
                }
            }

            StyledText {
                anchors.centerIn: parent
                text: iconButton.badge
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.m3colors.m3onPrimary
            }
        }

        StyledToolTip {
            text: iconButton.tooltip
            extraVisibleCondition: iconButton.tooltip.length > 0
        }
    }

    component StatusSeparator: Rectangle {
        implicitWidth: 4
        implicitHeight: 4
        radius: implicitWidth / 2
        color: Appearance.colors.colOutlineVariant
    }

    ColumnLayout {
        id: columnLayout
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        Item { // Transcript
            id: transcriptItem
            Layout.fillWidth: true
            Layout.fillHeight: true
            // A ListView does not clip, so delegates keep painting past the
            // viewport and show through the input bar -- colLayer2 is deliberately
            // semi-transparent so it composites onto colLayer1. A scissor rect is
            // not a layer, so this stays inside the effect budget.
            clip: true

            StyledRectangularShadow {
                z: 1
                target: statusBg
                opacity: messageListView.atYBeginning ? 0 : 1
                visible: opacity > 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            Rectangle {
                id: statusBg
                z: 2
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: 4
                }
                implicitWidth: statusRowLayout.implicitWidth + 10 * 2
                implicitHeight: Math.max(statusRowLayout.implicitHeight, 38)
                radius: Appearance.rounding.normal - root.padding
                color: messageListView.atYBeginning ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Base

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                RowLayout {
                    id: statusRowLayout
                    anchors.centerIn: parent
                    spacing: 10

                    StatusItem {
                        icon: HermesService.ready ? "cloud_done" : HermesService.missing ? "cloud_off" : "cloud_sync"
                        statusText: ""
                        description: HermesService.missing ? Translation.tr("hermes-agent is not installed") : HermesService.ready ? Translation.tr("Connected to the Hermes agent") : Translation.tr("Starting the Hermes agent…")
                    }
                    StatusSeparator {
                        visible: HermesService.approvalMode.length > 0
                    }
                    HermesApprovalModeMenu {
                        visible: HermesService.approvalMode.length > 0
                    }
                    StatusSeparator {
                        visible: (HermesService.usage?.total ?? 0) > 0
                    }
                    StatusItem {
                        visible: (HermesService.usage?.total ?? 0) > 0
                        icon: "token"
                        statusText: HermesService.usage?.total ?? 0
                        description: Translation.tr("Tokens this session\nInput: %1\nOutput: %2").arg(HermesService.usage?.input ?? 0).arg(HermesService.usage?.output ?? 0)
                    }
                }
            }

            ScrollEdgeFade {
                z: 1
                target: messageListView
                vertical: true
            }

            StyledListView {
                id: messageListView
                z: 0
                anchors.fill: parent
                spacing: 16
                popin: false
                topMargin: statusBg.implicitHeight + statusBg.anchors.topMargin * 2

                touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
                mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

                add: null // Keeps streaming from looking janky

                // Follows the reply as it streams; the reader takes that away by
                // scrolling up, and gets it back at the end or from the button.
                followsEnd: true

                model: ScriptModel {
                    values: HermesService.messageIDs.filter(id => HermesService.messageByID[id]?.visibleToUser ?? true)
                }

                delegate: HermesMessage {
                    required property var modelData
                    messageData: HermesService.messageByID[modelData]
                    messageId: modelData
                }
            }

            PagePlaceholder {
                z: 2
                icon: "auto_awesome"
                shape: MaterialShape.Shape.PixelCircle
                title: Translation.tr("Hermes")

                rotateIconWithShape: true
                shown: HermesService.messageIDs.length === 0
                description: HermesService.missing ? Translation.tr("hermes-agent was not found in ~/.hermes\nInstall it, then reopen this tab") : Translation.tr("Ask anything, or type %1 for commands\nThe agent brings its own tools, skills and providers").arg(root.commandPrefix)

                triggerAnimationOn: GlobalStates.policiesPanelOpen
                rotateToRight: GlobalStates.policiesOnLeft
            }

            ScrollToBottomButton {
                z: 3
                target: messageListView
            }

            HermesSelectionActions {
                z: 3
                anchorItem: transcriptItem
                // Scoped to this list so a selection made in a sibling tab's
                // transcript does not raise Hermes' toolbar over Hermes' text.
                scopeItem: messageListView
                repositionTrigger: messageListView.contentY

                onQuoteRequested: text => root.quoteToComposer(text)
            }

            HermesHistoryPanel {
                id: historyPanel
                z: 4
                anchors.fill: parent

                // Enter decelerating on spatial, exit accelerating on fast effects at
                // about half the duration (DESIGN.md 2.5). Scale grows from the top,
                // which is the edge the button that opens it sits under.
                opacity: root.historyShown ? 1 : 0
                scale: root.historyShown ? 1 : 0.96
                visible: opacity > 0
                transformOrigin: Item.Top

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.historyShown ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMoveExit.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: root.historyShown ? Appearance.animation.elementMoveEnter.duration : Appearance.animation.elementMoveExit.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.historyShown ? Appearance.animation.elementMoveEnter.bezierCurve : Appearance.animation.elementMoveExit.bezierCurve
                    }
                }

                onRequestClose: root.historyShown = false
            }

            HermesWorkPanel {
                id: workPanel
                z: 4
                anchors.fill: parent

                // Same enter/exit pairing and top origin as the history panel:
                // both grow from under the control row that opens them.
                opacity: root.workShown ? 1 : 0
                scale: root.workShown ? 1 : 0.96
                visible: opacity > 0
                transformOrigin: Item.Top

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.workShown ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMoveExit.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: root.workShown ? Appearance.animation.elementMoveEnter.duration : Appearance.animation.elementMoveExit.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.workShown ? Appearance.animation.elementMoveEnter.bezierCurve : Appearance.animation.elementMoveExit.bezierCurve
                    }
                }

                onRequestClose: root.workShown = false
            }
        }

        HermesApprovalCard {
            Layout.fillWidth: true
            request: HermesService.pendingApproval
        }

        HermesClarifyCard {
            Layout.fillWidth: true
            request: HermesService.pendingClarify
        }

        RowLayout { // Activity line
            Layout.fillWidth: true
            // Shown for the whole of a turn, not only while there is a caption:
            // it is now the only "working" indicator, so a gap in it would read as
            // the agent having stopped.
            visible: (Config.options.hermes?.showStatusLine ?? true) && (HermesService.busy || HermesService.dictating || HermesService.speakingMessageId.length > 0)
            spacing: 8

            MaterialLoadingIndicator {
                // implicitSize drives both the layout box and the shape it paints
                // (baseShapeSize is 0.7 of it) -- setting implicitWidth/Height only
                // shrinks the box and leaves a 34px blob spilling out of it.
                // 20 is the inline icon size, so the shape lands at 14 next to the
                // 12px caption beside it.
                implicitSize: 20
                loading: true
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: HermesService.voiceState === "listening" ? Translation.tr("Listening…") : HermesService.voiceState === "transcribing" ? Translation.tr("Transcribing…") : HermesService.speakingMessageId.length > 0 && !HermesService.busy ? Translation.tr("Reading aloud…") : HermesService.statusText.length > 0 ? HermesService.statusText : Translation.tr("Working…")
            }

            InputIconButton { // Silence playback without hunting for the message
                visible: HermesService.speakingMessageId.length > 0
                symbol: "stop"
                tooltip: Translation.tr("Stop reading")
                releaseAction: () => HermesService.stopSpeaking()
            }
        }

        DescriptionBox {
            text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""
            showArrows: root.suggestionList.length > 1
        }

        HermesModelPicker { // Only worth the room before a conversation starts
            Layout.fillWidth: true
            Layout.maximumWidth: 330
            Layout.alignment: Qt.AlignHCenter
            visible: HermesService.messageIDs.length === 0 && HermesService.providers.length > 0
        }

        FlowButtonGroup {
            id: suggestions
            visible: root.suggestionList.length > 0 && messageInputField.text.startsWith(root.commandPrefix)
            property int selectedIndex: 0
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                id: suggestionRepeater
                model: {
                    suggestions.selectedIndex = 0;
                    return root.suggestionList;
                }

                delegate: ApiCommandButton {
                    id: commandButton
                    required property var modelData
                    required property int index

                    colBackground: suggestions.selectedIndex === commandButton.index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                    bounce: false

                    contentItem: StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                        text: commandButton.modelData.displayName
                    }

                    onHoveredChanged: {
                        if (commandButton.hovered)
                            suggestions.selectedIndex = commandButton.index;
                    }
                    onClicked: suggestions.acceptSuggestion(commandButton.modelData.name)
                }
            }

            function acceptSuggestion(name: string): void {
                messageInputField.text = `${root.commandPrefix}${name} `;
                messageInputField.cursorPosition = messageInputField.text.length;
                messageInputField.forceActiveFocus();
            }

            function acceptSelectedWord(): void {
                const suggestion = root.suggestionList[suggestions.selectedIndex];
                if (suggestion)
                    suggestions.acceptSuggestion(suggestion.name);
            }
        }

        ColumnLayout { // Staged attachments
            // A sibling of the input surface, not a child of it: AttachedFileIndicator
            // derives its height from its width, so nesting it inside a Rectangle whose
            // implicitHeight depended on that height was a circular constraint -- the
            // layout gave up and the whole page collapsed to nothing.
            id: attachmentStrip
            Layout.fillWidth: true
            spacing: 4
            visible: HermesService.attachedImages.length > 0

            Repeater {
                model: ScriptModel {
                    values: HermesService.attachedImages
                }

                delegate: AttachedFileIndicator {
                    required property var modelData
                    Layout.fillWidth: true
                    filePath: modelData
                    onRemove: HermesService.detachImage(modelData)
                }
            }
        }

        Rectangle { // Input area
            id: inputWrapper
            property real spacing: 4
            Layout.fillWidth: true
            radius: Appearance.rounding.normal - root.padding
            color: Appearance.colors.colLayer2
            implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + inputWrapper.spacing, 45)
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            RowLayout {
                id: inputFieldRowLayout
                anchors {
                    bottom: commandButtonsRow.top
                    left: parent.left
                    right: parent.right
                    bottomMargin: 4
                }
                spacing: 0

                ScrollView {
                    id: inputScrollView
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(root.height * 3 / 5, messageInputField.height)
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    StyledTextArea {
                        id: messageInputField
                        anchors.fill: parent
                        wrapMode: TextArea.Wrap
                        padding: 10
                        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                        placeholderText: Translation.tr('Message Hermes... "%1" for commands').arg(root.commandPrefix)

                        background: null

                        onTextChanged: {
                            if (!messageInputField.text.startsWith(root.commandPrefix)) {
                                root.suggestionList = [];
                                suggestionDebounce.stop();
                                return;
                            }
                            suggestionDebounce.restart();
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Tab && suggestions.visible) {
                                suggestions.acceptSelectedWord();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up && suggestions.visible) {
                                suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down && suggestions.visible) {
                                suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                                if (event.modifiers & Qt.ShiftModifier) {
                                    messageInputField.insert(messageInputField.cursorPosition, "\n");
                                } else if (event.modifiers & Qt.ControlModifier) {
                                    // Hand the whole turn to its own agent, leaving this
                                    // conversation free to carry on while it runs.
                                    const backgroundText = messageInputField.text;
                                    messageInputField.clear();
                                    HermesService.runInBackground(backgroundText);
                                    root.suggestionList = [];
                                } else {
                                    const inputText = messageInputField.text;
                                    messageInputField.clear();
                                    root.handleInput(inputText);
                                }
                                event.accepted = true;
                            } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_Z && messageInputField.text.length === 0) {
                                // An empty box has nothing of its own to undo, so
                                // Ctrl+Z there means the conversation: back up a
                                // turn and put it in the composer to be reworded.
                                HermesService.undoTurns(1);
                                event.accepted = true;
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                if (event.modifiers & Qt.ShiftModifier)
                                    return; // Shift+Ctrl+V stays a plain text paste.
                                // Only divert when the clipboard really holds an
                                // image; clipboard.paste answers "nothing to attach"
                                // otherwise, which would be noise on a text paste.
                                const entry = Cliphist.entries[0] ?? "";
                                if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry)) {
                                    HermesService.attachClipboardImage();
                                    event.accepted = true;
                                    return;
                                }
                                const cleaned = StringUtils.cleanCliphistEntry(entry);
                                if (cleaned.startsWith("file://")) {
                                    HermesService.attachImage(decodeURIComponent(cleaned));
                                    event.accepted = true;
                                    return;
                                }
                                event.accepted = false;
                            } else if (event.key === Qt.Key_Escape) {
                                if (HermesService.speakingMessageId.length > 0) {
                                    HermesService.stopSpeaking();
                                    event.accepted = true;
                                } else if (HermesService.attachedImages.length > 0) {
                                    HermesService.detachAll();
                                    event.accepted = true;
                                } else if (root.historyShown) {
                                    root.historyShown = false;
                                    event.accepted = true;
                                } else if (root.workShown) {
                                    root.workShown = false;
                                    event.accepted = true;
                                } else if (HermesService.pendingApproval !== null) {
                                    HermesService.respondToApproval("deny");
                                    event.accepted = true;
                                } else if (root.suggestionList.length > 0) {
                                    root.suggestionList = [];
                                    event.accepted = true;
                                } else if (HermesService.busy) {
                                    HermesService.interrupt();
                                    event.accepted = true;
                                } else {
                                    event.accepted = false;
                                }
                            }
                        }
                    }
                }

                RippleButton { // Dictate
                    id: micButton
                    Layout.alignment: Qt.AlignBottom
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small

                    // Unknown until the gateway answers voice.toggle; offering it
                    // greyed out before then would read as broken.
                    // Always offered: the recorder downloads its model on first use
                    // and reports its own failure, which is more useful than a
                    // greyed-out button with no explanation.
                    enabled: true
                    toggled: HermesService.dictating

                    releaseAction: () => HermesService.toggleDictation()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        color: micButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
                        text: HermesService.voiceState === "transcribing" ? "pending" : HermesService.voiceState === "listening" ? "graphic_eq" : "mic"
                    }

                    StyledToolTip {
                        text: HermesService.voiceState === "listening" ? Translation.tr("Listening — click to transcribe") : HermesService.voiceState === "transcribing" ? Translation.tr("Transcribing…") : Translation.tr("Dictate (Super+Shift+B)")
                    }
                }

                RippleButton { // Send / stop
                    id: sendButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.rightMargin: 4
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small

                    enabled: HermesService.busy || messageInputField.text.length > 0
                    toggled: enabled

                    releaseAction: () => {
                        if (HermesService.busy) {
                            HermesService.interrupt();
                            return;
                        }
                        const inputText = messageInputField.text;
                        messageInputField.clear();
                        root.handleInput(inputText);
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                        text: HermesService.busy ? "stop" : "arrow_upward"
                    }
                }
            }

            RowLayout { // Controls
                id: commandButtonsRow
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    bottomMargin: 4
                    leftMargin: 10
                    rightMargin: 4
                }
                spacing: 4

                ApiInputBoxIndicator {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: implicitWidth
                    icon: "auto_awesome"
                    text: HermesService.currentModel
                    tooltipText: Translation.tr("Current model: %1\nProvider: %2\nChange it below, or with %3model").arg(HermesService.currentModel).arg(HermesService.currentProvider).arg(root.commandPrefix)
                }


                HermesContextMeter {}

                Item {
                    Layout.fillWidth: true
                }

                InputIconButton {
                    symbol: "play_circle"
                    tooltip: HermesService.runningSideTasks > 0 ? Translation.tr("Hermes work — %1 still running").arg(HermesService.runningSideTasks) : Translation.tr("Hermes work")
                    toggled: root.workShown
                    badge: HermesService.runningSideTasks

                    releaseAction: () => {
                        root.workShown = !root.workShown;
                        if (root.workShown)
                            root.historyShown = false;
                    }
                }

                InputIconButton {
                    symbol: "history"
                    tooltip: Translation.tr("Chat history")
                    toggled: root.historyShown

                    releaseAction: () => {
                        root.historyShown = !root.historyShown;
                        if (root.historyShown) {
                            root.workShown = false;
                            HermesService.refreshRecentSessions();
                            historyPanel.focusSearch();
                        }
                    }
                }

                InputIconButton {
                    symbol: "add_comment"
                    tooltip: Translation.tr("New conversation")
                    releaseAction: () => {
                        root.historyShown = false;
                        HermesService.newSession();
                        messageInputField.forceActiveFocus();
                    }
                }
            }
        }
    }

    // Drop a file anywhere on the page to attach it. `attachImage()` is the same
    // funnel the paste and picker routes use, so an image, a PDF and a plain file
    // each end up where they belong without this having to tell them apart.
    DropArea {
        id: fileDrop
        anchors.fill: parent
        keys: ["text/uri-list"]

        // A drag off a web page arrives as an http(s) url the agent cannot open,
        // and trimFileProtocol hands those back unchanged. Refusing in onEntered
        // means no onDropped fires, so such a drag falls through to whatever is
        // underneath instead of being swallowed here.
        function localPaths(urls: var): var {
            return (urls ?? []).map(url => url.toString())
                .filter(url => FileUtils.trimFileProtocol(url) !== url)
                .map(url => decodeURIComponent(FileUtils.trimFileProtocol(url)));
        }

        property int pendingCount: 0

        onEntered: drag => {
            fileDrop.pendingCount = drag.hasUrls ? fileDrop.localPaths(drag.urls).length : 0;
            if (fileDrop.pendingCount === 0)
                drag.accepted = false;
        }

        onExited: fileDrop.pendingCount = 0

        onDropped: drop => {
            fileDrop.localPaths(drop.urls).forEach(path => HermesService.attachImage(path));
            fileDrop.pendingCount = 0;
            drop.acceptProposedAction();
        }

        FadeLoader {
            anchors.fill: parent
            shown: fileDrop.pendingCount > 0

            sourceComponent: Rectangle {
                // Not fully opaque: the transcript staying faintly visible is what
                // says which conversation the file is about to land in.
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.12)
                radius: Appearance.rounding.normal

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        iconSize: 48
                        color: Appearance.colors.colPrimary
                        text: "upload_file"
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer0
                        text: fileDrop.pendingCount === 1 ? Translation.tr("Drop to attach") : Translation.tr("Drop %1 files to attach").arg(fileDrop.pendingCount)
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: root.width - 32
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Images and PDFs go to the agent; anything else is staged as a file reference.")
                    }
                }
            }
        }
    }
}
