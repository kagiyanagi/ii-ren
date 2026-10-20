import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarPolicies.agent
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * The agent page: Claude Code, Codex or Antigravity, chatting from the sidebar.
 *
 * Slash completions and the model list are pulled from the running agent rather
 * than mirrored here, so commands and skills the user adds to their CLI show up
 * without a shell change. Controls an agent cannot back (retry, undo) are hidden
 * for it -- AgentService.can().
 */
Item {
    id: root

    property real padding: 4
    property var inputField: messageInputField
    readonly property string commandPrefix: "/"

    property var suggestionList: []
    property bool historyShown: false

    // ── Finding something said earlier ───────────────────────────────
    //
    // The search bar takes over the pill already floating at the top of the
    // transcript rather than arriving as a control of its own. That pill is the
    // only surface over the list, it is where the eye already is when reading
    // back, and status is exactly what you stop caring about while searching.
    property bool searchShown: false
    property string searchQuery: ""
    property int searchIndex: 0

    // The rows the list actually shows. Hits index into this and not into
    // AgentService.messageIDs, or a hidden turn anywhere above would put every
    // jump one row out.
    readonly property var visibleIds: AgentService.messageIDs.filter(id => AgentService.messageByID[id]?.visibleToUser ?? true)

    // Enough hits to step through; past this the count stops being useful and
    // the scan starts to cost. Reported as "500+" rather than a wrong total.
    readonly property int searchHitLimit: 500

    /** A turn's prose plus what its tools ran and returned. */
    function searchHaystack(id: string): string {
        const message = AgentService.messageByID[id];
        if (!message)
            return "";
        // Tool text is searched but cannot be marked -- a tool row draws in
        // StyledText, which SpeechHighlight has no selection API to work with.
        // A row that matches opens itself instead, so the hit is at least visible.
        const tools = (message.toolCalls ?? []).map(call =>
            `${call.toolName ?? ""} ${call.toolInput ?? ""} ${call.toolFullInput ?? ""} ${call.toolResult ?? ""}`);
        return [message.content ?? ""].concat(tools).join("\n").toLowerCase();
    }

    // One entry per occurrence, each holding the row it sits in: the count is
    // then what a reader would count, and stepping still has a row to scroll to.
    readonly property var searchHits: {
        const needle = root.searchQuery.trim().toLowerCase();
        if (needle.length === 0)
            return [];
        const hits = [];
        root.visibleIds.forEach((id, row) => {
            const hay = root.searchHaystack(id);
            for (let at = hay.indexOf(needle); at !== -1 && hits.length < root.searchHitLimit; at = hay.indexOf(needle, at + needle.length))
                hits.push(row);
        });
        return hits;
    }

    // Clamped, not raw: typing another character can shrink the hit list under a
    // step that already happened, and "7/3" would be the visible result.
    readonly property int searchPosition: root.searchHits.length > 0 ? Math.min(root.searchIndex, root.searchHits.length - 1) : -1
    readonly property int searchRow: root.searchPosition >= 0 ? root.searchHits[root.searchPosition] : -1

    onSearchQueryChanged: {
        root.searchIndex = 0;
        if (root.searchHits.length > 0)
            root.showSearchRow(root.searchHits[0]);
    }

    // Whether the transcript was riding the live end when the search opened, so
    // a search that found nothing can hand it back.
    property bool searchResumeAtEnd: false

    function openSearch(): void {
        root.searchResumeAtEnd = messageListView.followingEnd;
        root.searchShown = true;
        searchField.forceActiveFocus();
        searchField.selectAll();
    }

    function closeSearch(): void {
        const wentSomewhere = root.searchRow >= 0;
        root.searchShown = false;
        searchField.text = "";
        root.searchQuery = "";
        messageInputField.forceActiveFocus();
        // Closing on a hit means you went there to read it. Closing without one
        // means the search was a detour, so give the live end back.
        if (root.searchResumeAtEnd && !wentSomewhere)
            messageListView.jumpToEnd();
    }

    function showSearchRow(row: int): void {
        // The list follows the end while a reply streams. Jumping to something
        // forty turns back has to take that away, or it snaps straight back down.
        messageListView.followingEnd = false;
        messageListView.positionViewAtIndex(row, ListView.Contain);
    }

    /** Step to the next hit, wrapping at either end. */
    function stepSearch(delta: int): void {
        if (root.searchHits.length === 0)
            return;
        root.searchIndex = (root.searchIndex + delta + root.searchHits.length) % root.searchHits.length;
        root.showSearchRow(root.searchHits[root.searchIndex]);
    }

    // The bridge starts the agent's CLI and its desktop tools, and tts.py a voice
    // client, so both start the first time this page is on screen - not when it is
    // built: a page kept loaded, or built for a detached window still hidden, is not
    // being looked at. Its window, not the sidebar flag, so a detached one counts.
    readonly property bool onScreen: root.QsWindow.window?.visible ?? false
    onOnScreenChanged: root.startBackends()
    Component.onCompleted: root.startBackends()

    function startBackends(): void {
        if (!root.onScreen)
            return;
        AgentService.ensureStarted();
        AgentService.prewarmTts();
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
                messageListView.contentY = Math.max(messageListView.originY - messageListView.topMargin, messageListView.contentY - messageListView.height / 2);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown) {
                messageListView.contentY = Math.min(messageListView.endY, messageListView.contentY + messageListView.height / 2);
                event.accepted = true;
            }
        }
        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            AgentService.newSession();
            event.accepted = true;
        }
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            root.openSearch();
            event.accepted = true;
        }
    }

    /**
     * What the question is about, as `class — title`.
     *
     * Hyprland hands over the class and title for free, but opening this
     * sidebar deactivates the window they belong to, so the last activated
     * toplevel is latched while it is still the real one and read back only
     * when there is no live one left to ask.
     */
    property string lastFocusedWindow: ""

    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            const toplevel = ToplevelManager.activeToplevel;
            if (!toplevel?.activated || !toplevel.appId)
                return;
            root.lastFocusedWindow = `${toplevel.appId} — ${toplevel.title}`;
        }
    }

    function focusedWindow(): string {
        const toplevel = ToplevelManager.activeToplevel;
        if (toplevel?.activated && toplevel.appId)
            return `${toplevel.appId} — ${toplevel.title}`;
        return root.lastFocusedWindow;
    }

    /**
     * `@window` stands for the window the question is about.
     *
     * "why is this failing" means nothing to an agent that cannot see the
     * screen, and the class and title are the part that can be handed over
     * without a screenshot. Left as typed when nothing is focused: naming the
     * wrong window is worse than naming none.
     */
    function expandWindowToken(text: string): string {
        const focused = root.focusedWindow();
        if (focused.length === 0)
            return text;
        return text.replace(/@window\b/g, `the focused window (${focused})`);
    }

    function handleInput(inputText: string): void {
        const text = inputText.trim();
        if (text.length === 0)
            return;

        // `!cmd` runs here rather than going to the agent -- the same split a
        // terminal-shaped assistant makes. Nothing about it reaches the model
        // until the console's own button puts it in the box.
        if (text.startsWith("!"))
            AgentService.runner.run(text.slice(1).trim(), AgentService.cwd);
        else if (text.startsWith(root.commandPrefix))
            AgentService.runSlashCommand(text);
        else
            AgentService.sendMessage(root.expandWindowToken(text));

        root.suggestionList = [];
        messageListView.jumpToEnd();
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
        target: AgentService
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
        // At the caret, spaced off whatever touches it, so it reads where it was put.
        function onComposerInsert(text) {
            const at = messageInputField.cursorPosition;
            const before = messageInputField.text.slice(0, at);
            const after = messageInputField.text.slice(at);
            const lead = before.length > 0 && !/\s$/.test(before) ? " " : "";
            const trail = /^\s/.test(after) ? "" : " ";
            attachmentChips.setText(before + lead + text + trail + after, (before + lead + text + trail).length);
            messageInputField.forceActiveFocus();
        }
        function onComposerRemove(text) {
            const current = messageInputField.text;
            const at = current.indexOf(text);
            if (at < 0)
                return;
            const end = at + text.length + (current[at + text.length] === " " ? 1 : 0);
            attachmentChips.setText(current.slice(0, at) + current.slice(end), at);
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
            AgentService.completeSlash(text, items => {
                // A reply that lands after the box moved on is stale.
                if (!messageInputField.text.startsWith(root.commandPrefix)) {
                    root.suggestionList = [];
                    return;
                }
                root.suggestionList = items.slice(0, Config.options.agent?.maxSuggestions ?? 12);
            });
        }
    }

    /** The compact icon controls that sit beside the command buttons. */
    component InputIconButton: RippleButton {
        id: iconButton
        required property string symbol
        property string tooltip: ""

        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.small

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            iconSize: Appearance.font.pixelSize.larger
            color: iconButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
            // M3 toggle icon button: outlined at rest, filled while selected, a
            // second cue beside the container (M3.md 11).
            fill: iconButton.toggled ? 1 : 0
            text: iconButton.symbol
        }

        StyledToolTip {
            text: iconButton.tooltip
            extraVisibleCondition: iconButton.tooltip.length > 0
        }
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
            // Six conditional strips sit under this one -- activity line, hints,
            // model picker, suggestions, attachments, console -- plus two cards.
            // Left to fill alone the transcript was whatever they had not taken.
            Layout.minimumHeight: 100
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
                implicitWidth: (root.searchShown ? searchRowLayout.width + 12 * 2 : statusRowLayout.implicitWidth + 8 * 2)
                implicitHeight: Math.max(root.searchShown ? searchRowLayout.implicitHeight : statusRowLayout.implicitHeight, 40)

                // One surface changing what it holds, so it resizes rather than
                // one pill leaving and another arriving in the same spot.
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                radius: Appearance.rounding.normal - root.padding
                color: messageListView.atYBeginning ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Base

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                RowLayout {
                    id: statusRowLayout
                    anchors.centerIn: parent
                    // Whitespace, not dots, between the readings (DESIGN.md 5.5).
                    spacing: 0
                    opacity: root.searchShown ? 0 : 1
                    visible: opacity > 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    AgentBackendMenu {}
                    AgentApprovalModeMenu {
                        visible: AgentService.approvalMode.length > 0
                    }
                }

                RowLayout {
                    id: searchRowLayout
                    anchors.centerIn: parent
                    // Wide enough to type in, never wider than the transcript.
                    width: Math.min(transcriptItem.width - 20, 320)
                    spacing: 2
                    opacity: root.searchShown ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        Layout.leftMargin: 4
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colSubtext
                        text: "search"
                    }

                    StyledTextArea {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        // Flat inside the pill: an outlined field would be a second
                        // container drawn inside the one already there.
                        background: null
                        padding: 0
                        wrapMode: TextArea.NoWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                        placeholderText: Translation.tr("Find in this chat")

                        onTextChanged: root.searchQuery = text

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                root.closeSearch();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                // A find bar has one line; Enter is "next", never a newline.
                                root.stepSearch((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                                event.accepted = true;
                            }
                        }
                    }

                    StyledText {
                        visible: root.searchQuery.trim().length > 0
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.searchHits.length > 0 ? Appearance.colors.colSubtext : Appearance.m3colors.m3error
                        text: root.searchHits.length > 0
                            ? `${root.searchPosition + 1}/${root.searchHits.length}${root.searchHits.length >= root.searchHitLimit ? "+" : ""}`
                            : Translation.tr("none")
                    }

                    InputIconButton {
                        symbol: "keyboard_arrow_up"
                        tooltip: Translation.tr("Previous match (Shift+Enter)")
                        enabled: root.searchHits.length > 0
                        releaseAction: () => root.stepSearch(-1)
                    }

                    InputIconButton {
                        symbol: "keyboard_arrow_down"
                        tooltip: Translation.tr("Next match (Enter)")
                        enabled: root.searchHits.length > 0
                        releaseAction: () => root.stepSearch(1)
                    }

                    InputIconButton {
                        symbol: "close"
                        tooltip: Translation.tr("Close search (Esc)")
                        releaseAction: () => root.closeSearch()
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

                /*
                 * Every turn built, so the height the scroll bar is drawn from is
                 * measured, not guessed. A ListView sizes the rows it has not built
                 * at the average of those it has, and in a chat where one reply is
                 * 12000px and the rest 100px that guess ran from 15k to 1.1M px over
                 * one scroll, the handle going backwards 77 times. Built a page a
                 * frame from where the view opened, never all at once, which froze
                 * a 337-turn chat for 2s; and again from nothing for each chat.
                 * ponytail: memory grows with the chat; a height cache per turn if
                 * chats ever reach thousands of turns.
                 */
                cacheBuffer: 0
                onCountChanged: if (count === 0) cacheBuffer = 0

                FrameAnimation {
                    running: messageListView.cacheBuffer < messageListView.contentHeight + messageListView.height
                    onTriggered: messageListView.cacheBuffer += messageListView.height
                }

                // Follows the reply as it streams; the reader takes that away by
                // scrolling up, and gets it back at the end or from the button.
                followsEnd: true

                model: ScriptModel {
                    values: root.visibleIds
                }

                delegate: AgentMessage {
                    required property var modelData
                    required property int index
                    messageData: AgentService.messageByID[modelData]
                    messageId: modelData
                    searchQuery: root.searchShown ? root.searchQuery.trim() : ""
                    searchCurrent: root.searchShown && index === root.searchRow
                }
            }

            AgentGreeting {
                z: 2
                anchors.fill: parent
                shown: AgentService.messageIDs.length === 0 && !AgentService.missing
                windowName: root.focusedWindow()
                commandPrefix: root.commandPrefix
                onCompose: text => {
                    messageInputField.text = text;
                    messageInputField.cursorPosition = text.length;
                    messageInputField.forceActiveFocus();
                }
                onQuote: text => root.quoteToComposer(text)
            }

            PagePlaceholder { // Only when no agent CLI is installed
                z: 2
                icon: "auto_awesome"
                shape: MaterialShape.Shape.PixelCircle
                title: Translation.tr("No agent installed")

                rotateIconWithShape: true
                shown: AgentService.messageIDs.length === 0 && AgentService.missing
                description: Translation.tr("Install Claude Code, Codex or Antigravity and sign in\nto it, then reopen this tab. It runs on your own plan.")
                descriptionHorizontalAlignment: Text.AlignHCenter

                triggerAnimationOn: GlobalStates.policiesPanelOpen
                rotateToRight: GlobalStates.policiesOnLeft
            }

            ScrollToBottomButton {
                z: 3
                target: messageListView
            }

            AgentSelectionActions {
                z: 3
                anchorItem: transcriptItem
                // Scoped to this list so a selection made in a sibling tab's
                // transcript does not raise this toolbar over that tab's text.
                scopeItem: messageListView
                repositionTrigger: messageListView.contentY

                onQuoteRequested: text => root.quoteToComposer(text)
            }

            AgentHistoryPanel {
                id: historyPanel
                z: 4
                anchors.fill: parent

                // Enter decelerating on spatial, exit accelerating on fast effects at
                // about half the duration (DESIGN.md 2.5). Scale grows from the
                // bottom right, the corner nearest the composer-row button under the
                // sheet that opens it (2.6).
                property AnimSpec opacitySpec: Appearance.animation.elementMoveFast
                opacity: {
                    historyPanel.opacitySpec = root.historyShown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
                    return root.historyShown ? 1 : 0;
                }
                property AnimSpec scaleSpec: Appearance.animation.elementMoveEnter
                scale: {
                    historyPanel.scaleSpec = root.historyShown ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveExit;
                    return root.historyShown ? 1 : 0.96;
                }
                visible: opacity > 0
                transformOrigin: Item.BottomRight

                Behavior on opacity {
                    NumberAnimation {
                        duration: historyPanel.opacitySpec.duration
                        easing.type: historyPanel.opacitySpec.type
                        easing.bezierCurve: historyPanel.opacitySpec.bezierCurve
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: historyPanel.scaleSpec.duration
                        easing.type: historyPanel.scaleSpec.type
                        easing.bezierCurve: historyPanel.scaleSpec.bezierCurve
                    }
                }

                onRequestClose: root.historyShown = false
            }
        }

        AgentApprovalCard {
            Layout.fillWidth: true
            request: AgentService.pendingApproval
        }

        AgentClarifyCard {
            Layout.fillWidth: true
            request: AgentService.pendingClarify
        }

        Item { // Activity line
            id: activityLine
            Layout.fillWidth: true
            // Shown for the whole of a turn, not only while there is a caption:
            // it is now the only "working" indicator, so a gap in it would read as
            // the agent having stopped.
            // Also while the agent is getting ready to answer at all: a first-use
            // download, a sign-in it is waiting on.
            readonly property bool shown: (Config.options.agent?.showStatusLine ?? true)
                && (AgentService.busy || AgentService.dictating || AgentService.speakingMessageId.length > 0 || AgentService.setupText.length > 0)

            // This fires on every turn, which makes it the most frequent
            // transition on the page -- the one thing that must not snap. Same
            // pairing as the cards above: height spatial, opacity effects.
            property AnimSpec implicitHeightSpec: Appearance.animation.elementMoveEnter
            implicitHeight: {
                activityLine.implicitHeightSpec = activityLine.shown ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveExit;
                return activityLine.shown ? activityRow.implicitHeight : 0;
            }
            property AnimSpec opacitySpec: Appearance.animation.elementMoveFast
            opacity: {
                activityLine.opacitySpec = activityLine.shown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
                return activityLine.shown ? 1 : 0;
            }
            visible: implicitHeight > 0
            clip: true

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: activityLine.implicitHeightSpec.duration
                    easing.type: activityLine.implicitHeightSpec.type
                    easing.bezierCurve: activityLine.implicitHeightSpec.bezierCurve
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: activityLine.opacitySpec.duration
                    easing.type: activityLine.opacitySpec.type
                    easing.bezierCurve: activityLine.opacitySpec.bezierCurve
                }
            }

            RowLayout {
                id: activityRow
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
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
                    text: AgentService.voiceState === "listening" ? Translation.tr("Listening…") : AgentService.voiceState === "transcribing" ? Translation.tr("Transcribing…") : AgentService.speakingMessageId.length > 0 && !AgentService.busy ? Translation.tr("Reading aloud…") : AgentService.setupText.length > 0 ? AgentService.setupText : AgentService.statusText.length > 0 ? AgentService.statusText : Translation.tr("Working…")
                }

                InputIconButton { // Silence playback without hunting for the message
                    visible: AgentService.speakingMessageId.length > 0
                    symbol: "stop"
                    tooltip: Translation.tr("Stop reading")
                    releaseAction: () => AgentService.stopSpeaking()
                }
            }
        }

        DescriptionBox {
            text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""
            showArrows: root.suggestionList.length > 1
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

        AgentConsole { // A `!` command, while it runs and once it has
            Layout.fillWidth: true
            Layout.bottomMargin: visible ? 4 : 0
            maxOutputHeight: root.height / 3
        }

        Rectangle { // Input area
            id: inputWrapper
            property real spacing: 4
            Layout.fillWidth: true
            radius: Appearance.rounding.normal - root.padding
            color: Appearance.colors.colLayer2
            implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + inputWrapper.spacing, 45)
                + (composerAttachments.visible ? composerAttachments.height + composerAttachments.anchors.topMargin : 0)
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            AgentAttachmentStrip { // What is attached, above the text it sits in
                id: composerAttachments
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 8
                    leftMargin: 8
                    rightMargin: 8
                }
                height: implicitHeight
                removable: true
                attachments: Object.keys(AgentService.composerMarkers).map(token => Object.assign({ token: token }, AgentService.composerMarkers[token]))
                onRemoveRequested: attachment => AgentService.removeMarker(attachment.token)
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
                        placeholderText: Translation.tr('Message %1... "%2" for commands').arg(AgentService.agentName).arg(root.commandPrefix)

                        background: null

                        AgentAttachmentChips {
                            id: attachmentChips
                            target: messageInputField
                        }

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
                                } else {
                                    const inputText = messageInputField.text;
                                    messageInputField.clear();
                                    root.handleInput(inputText);
                                }
                                event.accepted = true;
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
                                root.openSearch();
                                event.accepted = true;
                            } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_Z && messageInputField.text.length === 0 && AgentService.can("undo")) {
                                // An empty box has nothing of its own to undo, so
                                // Ctrl+Z there means the conversation: back up a
                                // turn and put it in the composer to be reworded.
                                AgentService.undoTurns(1);
                                event.accepted = true;
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                if (event.modifiers & Qt.ShiftModifier)
                                    return; // Shift+Ctrl+V stays a plain text paste.
                                // Only divert when cliphist saw an image or files copied. The
                                // live clipboard can have moved on since (its cached
                                // list refreshes on a text change), so the service
                                // re-reads it and hands a text selection back here.
                                const entry = Cliphist.entries[0] ?? "";
                                // cliphist's line is cut short, so a file manager's copy
                                // of several files is read whole from the live selection
                                if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry) || StringUtils.cleanCliphistEntry(entry).startsWith("file://")) {
                                    AgentService.attachClipboardImage(() => messageInputField.paste());
                                    event.accepted = true;
                                    return;
                                }
                                event.accepted = false;
                            } else if (event.key === Qt.Key_Escape) {
                                if (AgentService.voiceState === "listening") {
                                    AgentService.cancelDictation();
                                    event.accepted = true;
                                } else if (AgentService.speakingMessageId.length > 0) {
                                    AgentService.stopSpeaking();
                                    event.accepted = true;
                                } else if (Object.keys(AgentService.composerMarkers).length > 0) {
                                    AgentService.detachAll();
                                    event.accepted = true;
                                } else if (root.searchShown) {
                                    root.closeSearch();
                                    event.accepted = true;
                                } else if (root.historyShown) {
                                    root.historyShown = false;
                                    event.accepted = true;
                                } else if (root.suggestionList.length > 0) {
                                    root.suggestionList = [];
                                    event.accepted = true;
                                } else if (AgentService.busy) {
                                    AgentService.interrupt();
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

                    // Offered whenever whisper.cpp is installed: the recorder fetches
                    // its model on first use and reports its own failure. Without the
                    // binary there is nothing it could do, so it is not offered.
                    visible: AgentService.dictationInstalled
                    toggled: AgentService.dictating

                    releaseAction: () => AgentService.toggleDictation()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        color: micButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2
                        text: AgentService.voiceState === "transcribing" ? "pending" : AgentService.voiceState === "listening" ? "graphic_eq" : "mic"
                    }

                    StyledToolTip {
                        text: AgentService.voiceState === "listening" ? Translation.tr("Listening — click to transcribe") : AgentService.voiceState === "transcribing" ? Translation.tr("Transcribing…") : Translation.tr("Dictate (Super+Shift+B)")
                    }
                }

                RippleButton { // Send / stop
                    id: sendButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.rightMargin: 4
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small

                    /*
                     * Stop only while there is nothing to send.
                     *
                     * This button used to become stop for the whole of a turn, so
                     * typing a follow-up while a reply streamed left the control
                     * under the cursor meaning the opposite of what it looked
                     * like it meant. Sending mid-run is defined anyway -- the
                     * agent takes the next request as the end of the last one.
                     */
                    readonly property bool stops: AgentService.busy && messageInputField.text.length === 0

                    enabled: sendButton.stops || messageInputField.text.length > 0
                    toggled: enabled

                    releaseAction: () => {
                        if (sendButton.stops) {
                            AgentService.interrupt();
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
                        text: sendButton.stops ? "stop" : "arrow_upward"
                    }

                    // The three ways to send are otherwise written down nowhere.
                    StyledToolTip {
                        text: sendButton.stops
                            ? Translation.tr("Stop this turn")
                            : Translation.tr("Send (Enter)\nShift+Enter for a new line")
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
                    id: modelChip
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: implicitWidth
                    icon: "auto_awesome"
                    text: AgentService.currentModel
                    tooltipText: modelPicker.shown ? "" : Translation.tr("Current model: %1\nProvider: %2\nClick to change it").arg(AgentService.currentModel).arg(AgentService.currentProvider)
                    clickAction: () => modelPicker.openFrom(modelChip)
                }

                AgentModelPicker {
                    id: modelPicker
                }

                ApiInputBoxIndicator {
                    id: effortChip
                    // Only for a model that takes an effort level at all.
                    visible: AgentService.effortOptions.length > 0
                    Layout.maximumWidth: implicitWidth
                    icon: "neurology"
                    text: AgentService.currentEffortLabel
                    tooltipText: effortPicker.shown ? "" : Translation.tr("Reasoning effort: %1\nClick to change it").arg(AgentService.currentEffortLabel)
                    clickAction: () => effortPicker.toggle(effortChip)
                }

                AgentEffortPicker {
                    id: effortPicker
                }

                AgentUsageMeter {}

                Item {
                    Layout.fillWidth: true
                }

                InputIconButton {
                    // The conversations themselves, not a clock: what the sheet holds.
                    symbol: "forum"
                    tooltip: Translation.tr("Chat history")
                    toggled: root.historyShown

                    releaseAction: () => {
                        root.historyShown = !root.historyShown;
                        if (root.historyShown) {
                            AgentService.refreshRecentSessions();
                            historyPanel.focusSearch();
                        }
                    }
                }

                InputIconButton {
                    // The pen on a blank page that chat apps use for a fresh chat.
                    symbol: "edit_square"
                    tooltip: Translation.tr("New conversation")
                    releaseAction: () => {
                        root.historyShown = false;
                        AgentService.newSession();
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
            fileDrop.localPaths(drop.urls).forEach(path => AgentService.attachImage(path));
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
