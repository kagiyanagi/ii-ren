pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services.conduit

/**
 * Conduit's left-sidebar page, laid out to match the built-in Intelligence tab:
 * a floating status pill over the transcript, provider chips and a model dropdown
 * while empty, then the input row and a command bar along the bottom.
 */
Item {
    // No anchors: SwipeView sizes its pages itself and refuses to lay out an anchored
    // one. The extension build got away with it because it sat inside a Loader.
    id: root

    property real padding: 4
    property string commandPrefix: "/"

    readonly property var service: ConduitService

    // Opening the tab is the earliest honest signal that a question is coming. For a CLI
    // that serves the whole conversation from one process, starting it now means the
    // first question does not wait on it.
    //
    // Keyed off the tab being on screen, NOT page construction: the sidebar builds every
    // page at shell startup, and a `claude` launch there is a Node process' worth of
    // startup lag before anything is even asked for.
    // Both calls launch a Node process, and measured on this machine that costs the GUI
    // thread ~1.3 CPU-seconds: fired on open it lands on the opening animation and eats
    // it (first open 171 ticks vs 40 for later ones). Held until well clear of the
    // animation. Closing the tab before then cancels: nothing was asked.
    readonly property bool onScreen: root.service?.viewingConduit ?? false
    onOnScreenChanged: root.onScreen ? warmUpTimer.restart() : warmUpTimer.stop()
    Timer {
        id: warmUpTimer
        interval: 2500
        onTriggered: {
            root.service?.warmUp();
            root.service?.refreshLimits(false);
        }
    }
    readonly property var messageIDs: (root.service?.messageIDs ?? []).filter(id => root.service?.messageByID[id]?.visibleToUser ?? true)
    readonly property bool responding: root.service?.responding ?? false
    readonly property bool toolsOn: root.service?.enableTools ?? false

    property var suggestionList: []
    property bool historyShown: false

    onFocusChanged: focus => {
        if (focus) messageInputField.forceActiveFocus();
    }

    Connections {
        target: root.service ?? null
        // Insert rather than send: whisper mishears names and technical words, and
        // fixing that before it reaches the model is cheaper than a wrong reply.
        function onDictationReady(text) {
            const existing = messageInputField.text;
            const joiner = (existing.length > 0 && !existing.endsWith(" ")) ? " " : "";
            messageInputField.text = existing + joiner + text;
            messageInputField.cursorPosition = messageInputField.text.length;
            messageInputField.forceActiveFocus();
        }
    }

    readonly property var commands: [
        { name: "attach", description: "Attach a file by path (or paste / drag one in)" },
        { name: "detach", description: "Remove all pending attachments" },
        { name: "tools", description: "Enable or disable tools: /tools on|off", args: "tools" },
        { name: "cwd", description: "Set the directory tools may touch" },
        { name: "provider", description: "Switch provider", args: "providers" },
        { name: "model", description: "Switch model", args: "models" },
        { name: "prompt", description: "Set the system prompt" },
        { name: "retry", description: "Regenerate the last response" },
        { name: "new", description: "Start a new conversation" },
        { name: "chats", description: "Show saved conversations" },
        { name: "limits", description: "How much of the account's limit is left" },
        { name: "rename", description: "Rename this conversation" },
        { name: "clear", description: "Start fresh, keeping the old chat in history" },
        { name: "help", description: "List commands" }
    ]

    /** The values a command accepts, for the ones whose values are knowable. */
    function argumentsFor(commandName) {
        const command = root.commands.find(cmd => cmd.name === commandName);
        switch (command?.args ?? "") {
        case "tools":
            return [
                { value: "on", description: "Files, shell and web search — unattended" },
                { value: "off", description: "Plain chat, no tools" }
            ];
        case "providers":
            return (root.service?.providerIds ?? []).map(id => ({
                value: id,
                description: `${root.service.providers[id].name} — ${root.service.providers[id].blurb ?? ""}`
            }));
        case "models":
            return (root.service?.currentProvider.models ?? []).map(model => ({
                value: model.value,
                description: `${model.title} — ${model.description}`
            }));
        }
        return [];
    }

    /**
     * What to offer for the text typed so far: command names while the command itself is
     * still being written, then that command's own values once there is a space after it.
     * Each entry carries the whole line it expands to, because completing an argument has
     * to replace only the last word rather than the input.
     */
    function completionsFor(text) {
        if (!text.startsWith(root.commandPrefix)) return [];

        const body = text.slice(root.commandPrefix.length);
        const split = body.indexOf(" ");

        if (split < 0) {
            return root.commands
                .filter(cmd => cmd.name.startsWith(body))
                .map(cmd => ({
                    name: `${root.commandPrefix}${cmd.name}`,
                    description: cmd.description,
                    replacement: `${root.commandPrefix}${cmd.name}`
                }));
        }

        const name = body.slice(0, split);
        const partial = body.slice(split + 1);
        // Only ever completing the last word; anything with a space in it is settled text.
        if (partial.includes(" ")) return [];

        const needle = partial.toLowerCase();
        return root.argumentsFor(name)
            .filter(option => option.value.toLowerCase().includes(needle))
            .map(option => ({
                name: option.value,
                description: option.description,
                replacement: `${root.commandPrefix}${name} ${option.value}`
            }));
    }

    function handleInput(text) {
        const trimmed = (text ?? "").trim();
        if (trimmed.length === 0 || !root.service) return;

        // The user just acted, so they want to see the result regardless of where
        // they had scrolled to.
        messageListView.jumpToBottom();

        if (!trimmed.startsWith(root.commandPrefix)) {
            root.service.sendUserMessage(trimmed);
            return;
        }

        const parts = trimmed.slice(root.commandPrefix.length).split(/\s+/);
        const command = parts[0];
        const args = parts.slice(1);

        switch (command) {
        case "attach":
            if (args.length === 0) {
                root.service.addInterfaceMessage("Usage: `/attach PATH`. You can also paste an image, paste a copied file, or drag files onto the input.");
            } else {
                root.service.attachFile(args.join(" "));
            }
            break;
        case "detach":
            root.service.clearAttachments();
            break;
        case "tools":
            if (args.length === 0) {
                root.service.addInterfaceMessage(`Tools are **${root.toolsOn ? "on" : "off"}**. Usage: /tools on|off`);
            } else {
                root.service.setToolsEnabled(args[0] === "on");
            }
            break;
        case "cwd":
            root.service.setWorkingDir(args.join(" "));
            break;
        case "provider":
            if (args.length === 0) {
                root.service.addInterfaceMessage(`Available providers: ${root.service.providerIds.join(", ")}`);
            } else {
                root.service.setProvider(args[0]);
            }
            break;
        case "model":
            if (args.length === 0) {
                const models = root.service.currentProvider.models.map(model => `- \`${model.value}\` — ${model.description}`).join("\n");
                const extra = root.service.supportsCustomModels
                    ? `\n\nAny id from \`${root.service.currentProvider.command} models\` also works.`
                    : "";
                root.service.addInterfaceMessage(`Models for ${root.service.currentProvider.name}:\n\n${models}${extra}`);
            } else {
                root.service.setModel(args[0]);
            }
            break;
        case "prompt":
            root.service.setSystemPrompt(args.join(" "));
            break;
        case "retry":
            root.service.regenerate();
            break;
        case "clear":
        case "new":
            root.service.newChat();
            root.historyShown = false;
            break;
        case "chats":
            root.historyShown = true;
            historyPanel.focusSearch();
            break;
        case "limits":
            root.service.requestLimitsReport();
            break;
        case "rename":
            if (args.length === 0) {
                root.service.addInterfaceMessage("Usage: `/rename NEW TITLE`.");
            } else if ((root.service.currentChatId ?? "").length === 0) {
                root.service.addInterfaceMessage("Nothing to rename yet — send a message first.");
            } else {
                root.service.renameChat(root.service.currentChatId, args.join(" "));
                root.service.addInterfaceMessage(`Renamed to **${args.join(" ")}**.`);
            }
            break;
        case "help":
            root.service.addInterfaceMessage(root.commands.map(cmd => `- \`${root.commandPrefix}${cmd.name}\` — ${cmd.description}`).join("\n")
                + (root.service.supportsSlashPassthrough
                    ? `\n\nAnything else starting with \`/\` is passed through to ${root.service.currentProvider.name}, so your own skills and slash commands work here.`
                    : ""));
            break;
        default:
            // Not one of ours: hand it to the CLI, which owns its own commands,
            // custom commands and skills.
            if (root.service.supportsSlashPassthrough) {
                root.service.sendUserMessage(trimmed);
            } else {
                root.service.addInterfaceMessage(`Unknown command \`${root.commandPrefix}${command}\`. Try \`${root.commandPrefix}help\`.`);
            }
            break;
        }
    }

    component StatusItem: MouseArea {
        id: statusItem
        property string icon
        property string statusText
        property string description
        property color accent: Appearance.colors.colSubtext
        property var clickAction: null

        hoverEnabled: true
        cursorShape: statusItem.clickAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        implicitHeight: statusItemRow.implicitHeight
        implicitWidth: statusItemRow.implicitWidth
        onClicked: if (statusItem.clickAction) statusItem.clickAction()

        RowLayout {
            id: statusItemRow
            spacing: 2
            MaterialSymbol {
                text: statusItem.icon
                iconSize: Appearance.font.pixelSize.large
                color: statusItem.containsMouse && statusItem.clickAction ? Appearance.colors.colOnLayer1 : statusItem.accent
            }
            StyledText {
                visible: statusItem.statusText.length > 0
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: statusItem.statusText
                color: statusItem.containsMouse && statusItem.clickAction ? Appearance.colors.colOnLayer1 : statusItem.accent
                animateChange: true
            }
        }

        StyledToolTip {
            text: statusItem.description
            extraVisibleCondition: false
            alternativeVisibleCondition: statusItem.containsMouse
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
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.padding

        Item { // Transcript
            Layout.fillWidth: true
            Layout.fillHeight: true

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: columnLayout.width
                    height: columnLayout.height
                    radius: Appearance.rounding.small
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

                spacing: 12
                popin: false
                clip: true
                // Keeps turns instantiated while off-screen. Recreating a delegate loses
                // its rendered LaTeX: the re-request hits LatexRenderer's cache, which
                // emits renderFinished synchronously before MessageTextBlock has recorded
                // the hash, so the substitution is dropped.
                cacheBuffer: 8000

                // Deliberately not derived from contentHeight. Feeding the content size
                // back into the view's own geometry breaks in two ways: sizing `height`
                // from it collapses the bottom-most scroll position onto the top-most
                // one, and deriving topMargin from it is a binding loop, since the
                // padding changes which delegates are instantiated.
                topMargin: statusBg.implicitHeight + 12

                touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
                mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

                add: null // Keeps streaming updates from looking janky

                /* ---- Sticky bottom -------------------------------------------
                 * Follow new content only while the user is already at the bottom;
                 * if they have scrolled up to read something, leave them alone.
                 *
                 * StyledListView animates every contentY change, and re-targeting that
                 * animation on each streamed token makes it chase a moving target. The
                 * inherited Behavior is therefore replaced here and disabled while
                 * pinning: user scrolling stays smooth, following is instant.
                 */
                property bool followBottom: true
                property bool pinning: false
                // The bottom as it was before the latest change. Scrolling up makes
                // ListView instantiate delegates and refine contentHeight, so
                // onContentHeightChanged can fire BEFORE onContentYChanged has noticed
                // the scroll. Judging against the old bottom makes the decision
                // independent of which signal arrives first.
                property real lastBottomY: 0
                readonly property real followThreshold: 60
                // Derived from contentHeight rather than item geometry: while text is
                // streaming, positionViewAtEnd() reads item positions that have not
                // re-laid out yet and lands short by the amount the turn just grew.
                readonly property real bottomY: Math.max(originY - topMargin, originY + contentHeight + bottomMargin - height)
                // When the content fits, the bottom-most and top-most scroll positions are
                // the same value, so "pin to the bottom" would jump the view to the top.
                // Async LaTeX images make contentHeight dip transiently, which turned that
                // into a visible top/bottom oscillation.
                readonly property bool scrollable: contentHeight + topMargin + bottomMargin > height + 1

                Behavior on contentY {
                    id: scrollBehavior
                    NumberAnimation {
                        duration: Appearance.animation.scroll.duration
                        easing.type: Appearance.animation.scroll.type
                        easing.bezierCurve: Appearance.animation.scroll.bezierCurve
                    }
                }

                function distanceFromBottom() {
                    return Math.max(0, messageListView.bottomY - messageListView.contentY);
                }

                function pinToBottom() {
                    if (!messageListView.scrollable) {
                        messageListView.lastBottomY = messageListView.contentY;
                        return;
                    }
                    const target = messageListView.bottomY;
                    if (Math.abs(messageListView.contentY - target) >= 1) {
                        messageListView.pinning = true;
                        scrollBehavior.enabled = false; // Instant, so it never chases a moving target
                        messageListView.contentY = target;
                        scrollBehavior.enabled = true;
                        messageListView.pinning = false;
                    }
                    // Record where we actually landed, not where we aimed: Flickable
                    // clamps the assignment while contentHeight is still catching up,
                    // and the leftover gap would otherwise look like a user scroll.
                    messageListView.lastBottomY = messageListView.contentY;
                }

                function jumpToBottom() {
                    messageListView.followBottom = true;
                    messageListView.pinToBottom();
                    Qt.callLater(messageListView.followAgain); // Again once layout settles
                }

                // Content grew (or the viewport changed). Follow only if the view was
                // sitting at the *previous* bottom.
                function follow() {
                    // Sitting at the bottom *is* following, so the two are never allowed
                    // to disagree. Keeping that invariant makes the state self-healing
                    // rather than dependent on bookkeeping surviving every clamp and
                    // relayout along the way.
                    const wasAtBottom = ((messageListView.lastBottomY - messageListView.contentY) <= messageListView.followThreshold)
                        || (messageListView.distanceFromBottom() <= messageListView.followThreshold);
                    messageListView.lastBottomY = messageListView.bottomY;
                    messageListView.followBottom = wasAtBottom;
                    if (!wasAtBottom) return;
                    messageListView.pinToBottom();
                    Qt.callLater(messageListView.followAgain);
                }
                function followAgain() {
                    if (messageListView.distanceFromBottom() <= messageListView.followThreshold) {
                        messageListView.followBottom = true;
                    }
                    if (messageListView.followBottom) messageListView.pinToBottom();
                }

                // Follow state changes only on a real gesture. A bare "contentY moved"
                // test cannot distinguish the user from ListView re-laying itself out.
                property bool wheelActive: false
                readonly property bool userDriven: wheelActive || dragging || flicking

                function markWheel() {
                    messageListView.wheelActive = true;
                    Qt.callLater(messageListView.clearWheel);
                }
                function clearWheel() {
                    messageListView.wheelActive = false;
                }

                MouseArea { // Observes the wheel; the list still does the scrolling.
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: wheel => {
                        messageListView.markWheel();
                        wheel.accepted = false;
                    }
                }

                onContentYChanged: {
                    if (messageListView.pinning || !messageListView.userDriven) return;
                    messageListView.followBottom = messageListView.distanceFromBottom() <= messageListView.followThreshold;
                    messageListView.lastBottomY = messageListView.bottomY;
                }
                onMovementEnded: messageListView.followBottom = messageListView.distanceFromBottom() <= messageListView.followThreshold

                onContentHeightChanged: messageListView.follow()
                onCountChanged: messageListView.follow()
                onHeightChanged: messageListView.follow()

                model: root.messageIDs
                delegate: ConduitTurn {
                    required property var modelData
                    width: messageListView.width
                    messageData: root.service?.messageByID[modelData] ?? null
                    messageId: modelData
                    service: root.service
                }
            }

            StyledRectangularShadow {
                z: 1
                target: statusBg
                opacity: messageListView.atYBeginning ? 0 : 1
                visible: opacity > 0
            }

            Rectangle { // Floating status pill
                id: statusBg
                z: 2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 4

                implicitWidth: statusRow.implicitWidth + 12 * 2
                implicitHeight: Math.max(statusRow.implicitHeight, 38)
                radius: Appearance.rounding.normal - root.padding
                color: messageListView.atYBeginning ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Base

                RowLayout {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 8

                    StatusItem { // Stop — only while something is actually running
                        visible: root.responding
                        icon: "stop_circle"
                        statusText: "Stop"
                        accent: Appearance.colors.colError
                        clickAction: () => root.service?.stop()
                        description: "Stop the current response (also Esc, or your stop keybinding)"
                    }

                    StatusSeparator { visible: root.responding }

                    StatusItem { // Tool access — the most consequential state, so it leads
                        // Spelled out, not just an icon: with tools off the model will
                        // describe tool calls it cannot make, and a bare glyph is far too
                        // quiet an explanation for that. Click to toggle.
                        icon: root.toolsOn ? "construction" : "lock"
                        statusText: root.toolsOn ? "Tools" : "Tools off"
                        accent: root.toolsOn ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        clickAction: () => root.service?.setToolsEnabled(!root.toolsOn)
                        description: root.toolsOn
                            ? `Tools ON (${root.service?.permissionMode ?? ""}) in:\n${root.service?.workingDir ?? ""}\n\nNothing asks before editing files or running commands.\n\nClick to disable.`
                            : (root.service?.hasToolsOffSwitch ?? true)
                                ? "Tools OFF — no file access, no web search.\nThe model may still describe tool calls it cannot make.\n\nClick to enable."
                                : `Tools OFF — ${root.service?.currentProvider.command ?? "this CLI"} cannot remove them, so the model is\nonly instructed not to use them.\n\nClick to enable.`
                    }

                    StatusSeparator { visible: root.service?.supportsSessions ?? false }

                    StatusItem { // Session continuity
                        visible: root.service?.supportsSessions ?? false
                        icon: (root.service?.cliSessionId ?? "").length > 0 ? "link" : "link_off"
                        statusText: ""
                        description: (root.service?.cliSessionId ?? "").length > 0
                            ? `Resuming session ${(root.service?.cliSessionId ?? "").slice(0, 8)}\nContext is kept by ${root.service?.currentProvider.name ?? "the CLI"} between turns.`
                            : "New session on next message."
                    }

                    StatusSeparator { visible: (root.service?.supportsCost ?? false) && (root.service?.lastCostUsd ?? -1) >= 0 }

                    StatusItem { // Cost of the last turn, where the CLI reports one
                        visible: (root.service?.supportsCost ?? false) && (root.service?.lastCostUsd ?? -1) >= 0
                        icon: "payments"
                        statusText: `$${(root.service?.lastCostUsd ?? 0).toFixed(3)}`
                        description: "Cost of the last turn, as reported by the CLI."
                    }

                    StatusSeparator { visible: (root.service?.limits.length ?? 0) > 0 }

                    StatusItem { // Subscription left, worst window first
                        visible: (root.service?.limits.length ?? 0) > 0
                        icon: "data_usage"
                        statusText: `${root.service?.tightestLimit?.remaining ?? 0}%`
                        accent: {
                            const left = root.service?.tightestLimit?.remaining ?? 100;
                            if (left <= 10) return Appearance.colors.colError;
                            if (left <= 25) return Appearance.m3colors.m3tertiary;
                            return Appearance.colors.colSubtext;
                        }
                        clickAction: () => root.service?.requestLimitsReport()
                        description: {
                            const entries = root.service?.limits ?? [];
                            const lines = entries.map(entry =>
                                `${entry.label}: ${entry.remaining}% left${entry.resets.length > 0 ? `, resets ${entry.resets}` : ""}`);
                            return `${root.service?.currentProvider.name ?? ""} — least remaining shown\n\n${lines.join("\n")}\n\nClick for the full breakdown.`;
                        }
                    }

                    StatusSeparator { visible: (root.service?.tokenCount.output ?? -1) >= 0 }

                    StatusItem { // Tokens
                        visible: (root.service?.tokenCount.output ?? -1) >= 0
                        icon: "token"
                        statusText: `${root.service?.tokenCount.output ?? 0}`
                        description: `Input: ${root.service?.tokenCount.input ?? 0}\nOutput: ${root.service?.tokenCount.output ?? 0}`
                    }

                    StatusSeparator { visible: (root.service?.rateLimit.status ?? "") === "rejected" }

                    StatusItem { // Rate limit, only when it actually bites
                        visible: (root.service?.rateLimit.status ?? "") === "rejected"
                        icon: "hourglass_disabled"
                        statusText: "Limit"
                        description: `Rate limited (${root.service?.rateLimit.kind ?? ""}).`
                    }
                }
            }

            PagePlaceholder { // Anchors itself to fill the parent
                z: 0
                icon: "neurology"
                shape: MaterialShape.Shape.PixelCircle
                title: "Conduit"
                rotateIconWithShape: true
                shown: root.messageIDs.length === 0
                description: `${root.service?.currentProvider.blurb ?? ""}\n${root.commandPrefix}tools on for files, shell and web search\n${root.commandPrefix}help for all commands`

                triggerAnimationOn: GlobalStates.policiesPanelOpen
                rotateToRight: GlobalStates.policiesOnLeft
            }

            ScrollToBottomButton {
                z: 3
                target: messageListView
            }

            ChatHistoryPanel { // Covers the transcript, not the whole page
                id: historyPanel
                z: 20
                anchors.fill: parent
                visible: opacity > 0
                opacity: root.historyShown ? 1 : 0
                service: root.service
                onRequestClose: root.historyShown = false

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                    }
                }
            }
        }

        DescriptionBox {
            text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""
            showArrows: root.suggestionList.length > 1
        }

        Loader { // Provider and model pickers, shown only on an empty chat
            active: root.messageIDs.length === 0 && root.service
            visible: active
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: item?.implicitWidth ?? 0
            Layout.preferredHeight: item?.implicitHeight ?? 0

            sourceComponent: ColumnLayout {
                width: 330
                spacing: 4

                ConfigSelectionArray {
                    id: providerSelector
                    Layout.alignment: Qt.AlignHCenter
                    currentValue: root.service?.currentProviderId ?? "claude-cli"
                    onSelected: newValue => root.service?.setProvider(newValue)
                    options: [
                        { displayName: "Claude Code", icon: "terminal", value: "claude-cli" },
                        { displayName: "Antigravity", icon: "auto_awesome", value: "antigravity" }
                    ]
                }

                StyledComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "wand_stars"
                    textRole: "title"
                    model: root.service?.currentProvider.models ?? []
                    currentIndex: Math.max(0, (root.service?.currentProvider.models ?? [])
                        .findIndex(model => model.value === root.service?.currentModelId))
                    onActivated: index => {
                        const models = root.service?.currentProvider.models ?? [];
                        if (models[index]) root.service?.setModel(models[index].value);
                    }
                }
            }
        }

        FlowButtonGroup { // Command suggestions
            id: suggestions
            visible: root.suggestionList.length > 0 && messageInputField.text.length > 0
            property int selectedIndex: 0
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                model: {
                    suggestions.selectedIndex = 0;
                    return root.suggestionList.slice(0, 10);
                }
                delegate: ApiCommandButton {
                    id: suggestionButton
                    required property var modelData
                    required property int index

                    colBackground: suggestions.selectedIndex === suggestionButton.index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                    bounce: false
                    contentItem: StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                        text: suggestionButton.modelData.name
                    }
                    onHoveredChanged: if (suggestionButton.hovered) suggestions.selectedIndex = suggestionButton.index
                    onClicked: suggestions.accept(suggestionButton.modelData.replacement)
                }
            }

            function accept(replacement) {
                messageInputField.text = replacement + " ";
                messageInputField.cursorPosition = messageInputField.text.length;
                messageInputField.forceActiveFocus();
                root.suggestionList = [];
            }

            function acceptSelected() {
                if (root.suggestionList.length === 0) return;
                suggestions.accept(root.suggestionList[suggestions.selectedIndex].replacement);
            }
        }

        Rectangle { // Input area
            Layout.fillWidth: true
            implicitHeight: inputColumn.implicitHeight + 8
            radius: Appearance.rounding.small
            color: dropArea.containsDrag ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2

            DropArea { // Drag files in from anywhere
                id: dropArea
                anchors.fill: parent
                onDropped: drop => {
                    if (!drop.hasUrls) return;
                    for (const url of drop.urls) root.service?.attachFile(url);
                    drop.accept(Qt.CopyAction);
                }
            }

            ColumnLayout {
                id: inputColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 4
                spacing: 2

                Repeater { // Pending attachments
                    model: root.service?.pendingAttachments ?? []

                    delegate: AttachedFileIndicator {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.margins: 2
                        filePath: modelData
                        highlight: false
                        canRemove: true
                        onRemove: root.service?.detachFile(modelData)
                    }
                }

                StyledText {
                    visible: dropArea.containsDrag
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSecondaryContainer
                    text: "Drop to attach"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(root.height * 2 / 5, messageInputField.implicitHeight)
                        clip: true
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                        StyledTextArea {
                            id: messageInputField
                            anchors.fill: parent
                            wrapMode: TextArea.Wrap
                            padding: 8
                            background: null
                            color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                            placeholderText: `Message ${root.service?.currentProvider.name ?? "the model"}… "${root.commandPrefix}" for commands`

                            onTextChanged: root.suggestionList = root.completionsFor(messageInputField.text)

                            Keys.onPressed: event => {
                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                    // Shift+Ctrl+V forces a plain text paste.
                                    if (event.modifiers & Qt.ShiftModifier) {
                                        messageInputField.insert(messageInputField.cursorPosition, Quickshell.clipboardText);
                                        event.accepted = true;
                                        return;
                                    }
                                    // An image or file on the clipboard becomes an attachment;
                                    // anything else falls through to a normal paste.
                                    event.accepted = root.service?.attachFromClipboard() ?? false;
                                    return;
                                }
                                if (event.key === Qt.Key_Escape) {
                                    if (root.historyShown) {
                                        root.historyShown = false;
                                        event.accepted = true;
                                        return;
                                    }
                                    // Stopping a running agent is the more urgent meaning of Esc.
                                    if (root.responding) {
                                        root.service?.stop();
                                        event.accepted = true;
                                        return;
                                    }
                                    event.accepted = root.service?.detachLast() ?? false;
                                    return;
                                }
                                if (event.key === Qt.Key_Tab) {
                                    suggestions.acceptSelected();
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
                                        const text = messageInputField.text;
                                        messageInputField.clear();
                                        root.suggestionList = [];
                                        root.handleInput(text);
                                    }
                                    event.accepted = true;
                                }
                            }
                        }
                    }

                    RippleButton { // Voice input
                        id: micButton
                        Layout.alignment: Qt.AlignBottom
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full ?? 18
                        enabled: !root.responding && !(root.service?.speech.transcribing ?? false)
                        toggled: root.service?.speech.recording ?? false

                        onClicked: root.service?.speech.toggle()

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: {
                                if (root.service?.speech.transcribing) return "hourglass_bottom";
                                if (root.service?.speech.recording) return "stop_circle";
                                return "mic";
                            }
                            iconSize: Appearance.font.pixelSize.larger
                            color: {
                                if (micButton.toggled) return Appearance.colors.colOnPrimary;
                                if (!(root.service?.speech.available ?? false)) return Appearance.colors.colSubtext;
                                return Appearance.colors.colOnLayer1;
                            }

                            // A quiet pulse while the mic is live, so it is obvious it is on.
                            SequentialAnimation on opacity {
                                running: root.service?.speech.recording ?? false
                                loops: Animation.Infinite
                                alwaysRunToEnd: true
                                NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                            }
                        }

                        StyledToolTip {
                            text: {
                                if (root.service?.speech.transcribing) return "Transcribing…";
                                if (root.service?.speech.recording) return "Stop and transcribe";
                                if (!(root.service?.speech.available ?? false)) return "Voice input unavailable — click for setup steps";
                                return "Dictate a message";
                            }
                        }
                    }

                    RippleButton { // Send / stop
                        id: sendButton
                        Layout.alignment: Qt.AlignBottom
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full ?? 18
                        enabled: root.responding || messageInputField.text.trim().length > 0
                        toggled: enabled

                        onClicked: {
                            if (root.responding) {
                                root.service?.stop();
                                return;
                            }
                            const text = messageInputField.text;
                            messageInputField.clear();
                            root.suggestionList = [];
                            root.handleInput(text);
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: root.responding ? "stop" : "arrow_upward"
                            iconSize: Appearance.font.pixelSize.larger
                            color: sendButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                        }

                        StyledToolTip {
                            text: root.responding ? "Stop generating" : "Send message"
                        }
                    }
                }

                RowLayout { // Command bar
                    Layout.fillWidth: true
                    spacing: 2

                    ApiInputBoxIndicator { // Model
                        icon: root.service?.currentProvider.icon ?? "terminal"
                        text: root.service?.currentModelId ?? ""
                        tooltipText: `${root.service?.currentProvider.name ?? ""}\nChange with ${root.commandPrefix}model MODEL`
                    }

                    ApiInputBoxIndicator { // Working directory, only meaningful with tools on
                        visible: root.toolsOn
                        icon: "folder_open"
                        text: {
                            const dir = root.service?.workingDir ?? "";
                            return dir.split("/").filter(Boolean).pop() ?? "/";
                        }
                        tooltipText: `Tools may touch:\n${root.service?.workingDir ?? ""}\n\nChange with ${root.commandPrefix}cwd PATH`
                    }

                    Item { Layout.fillWidth: true }

                    ButtonGroup {
                        padding: 0

                        ApiCommandButton {
                            buttonText: root.commandPrefix
                            downAction: () => {
                                messageInputField.text = root.commandPrefix;
                                messageInputField.cursorPosition = messageInputField.text.length;
                                messageInputField.forceActiveFocus();
                            }
                        }

                        ApiCommandButton {
                            buttonText: `${root.commandPrefix}clear`
                            downAction: () => {
                                messageInputField.text = "";
                                root.handleInput(`${root.commandPrefix}clear`);
                            }
                        }
                    }
                }
            }
        }
    }
}
