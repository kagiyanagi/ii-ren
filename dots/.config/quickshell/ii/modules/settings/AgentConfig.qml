pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.agent
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Settings > Agent: the left sidebar's agents, set up from one place.
 *
 * Each agent gets its account card first -- installed, signed in as whom, and the
 * one thing to do about it -- then whether the sidebar offers it, the model new
 * chats start on, and the program it runs. Signing in is the agent's own: its CLI
 * (or Google's server) opens the browser and finishes on its own callback, as in
 * T3 Code; services/AgentSetup.qml only watches. The chat and voice options the
 * sidebar already read close the page.
 */
ContentPage {
    id: page
    readonly property int index: 10
    forceWidth: true

    // Checked again on every visit: a sign-in in a terminal, or a CLI updated,
    // changes the answer from outside.
    Component.onCompleted: {
        AgentSetup.refresh();
        if (page.sttOnline) groqKeyProbe.running = true;
    }

    // Signing out and removing the server ask first, in a WindowDialog as the
    // Profiles page's does. Copied on open, so the exit plays over the same text.
    property AgentSetupAgent confirmAgent: null
    property string confirmJob: ""
    property bool dialogOpen: false
    property bool dialogActive: false

    function confirm(agent: AgentSetupAgent, job: string): void {
        page.confirmAgent = agent;
        page.confirmJob = job;
        page.dialogActive = true;
        page.dialogOpen = true;
    }

    function sizeText(bytes: real): string {
        return bytes >= 1e9 ? Translation.tr("%1 GB").arg((bytes / 1e9).toFixed(1)) : Translation.tr("%1 MB").arg(Math.round(bytes / 1e6));
    }

    function newer(latest: string, current: string): bool {
        const a = latest.split(".").map(n => parseInt(n) || 0);
        const b = current.split(".").map(n => parseInt(n) || 0);
        for (let i = 0; i < Math.max(a.length, b.length); i++) {
            if ((a[i] ?? 0) !== (b[i] ?? 0))
                return (a[i] ?? 0) > (b[i] ?? 0);
        }
        return false;
    }

    // ── The account card ───────────────────────────────────────────────
    //
    // A card of its section's run, as the fingerprint reader's is: what the agent
    // is, then the actions that change it. One tonal action is the way forward
    // (install, sign in); the rest sit on the card's own layer.
    component AccountCard: Item {
        id: card

        required property AgentSetupAgent agent
        required property string icon
        // The vendor's own installer, for a terminal: Claude Code and Codex are
        // not installed from here.
        property string installCommand: ""
        property bool copied: false
        // Inline components cannot reach the page: it confirms, then signs out.
        signal signOutRequested

        readonly property bool wantsCard: true
        readonly property var status: card.agent.status ?? ({})
        readonly property bool busy: card.agent.job.length > 0

        Layout.fillWidth: true
        implicitHeight: cardLayout.implicitHeight + 28

        Connections {
            target: card.agent
            function onLinkChanged() {
                card.copied = false;
            }
        }

        readonly property string headline: {
            const a = card.agent;
            switch (a.job) {
            case "login":
                return Translation.tr("Waiting for you in the browser");
            case "logout":
                return Translation.tr("Signing out…");
            case "install":
                return Translation.tr("Downloading Google's agent server…");
            case "remove":
                return Translation.tr("Removing Google's agent server…");
            }
            if (!a.checked)
                return Translation.tr("Checking…");
            if (!a.installed)
                return a.customPath.length > 0 ? Translation.tr("Not found") : Translation.tr("Not installed");
            if (a.signedIn === true)
                return card.status.account || Translation.tr("Signed in");
            if (a.signedIn === false)
                return Translation.tr("Signed out");
            return Translation.tr("Couldn't tell who is signed in");
        }

        readonly property string detail: {
            const a = card.agent;
            if (a.job === "login")
                return a.needsCode ? Translation.tr("Paste the code the browser shows to finish")
                    : a.link.length > 0 ? Translation.tr("Finish on the page that opened. This carries on by itself")
                    : Translation.tr("Opening the sign-in page…");
            if (a.job === "install")
                return a.progress >= 0 ? Translation.tr("%1% of about 340 MB").arg(Math.round(a.progress * 100)) : Translation.tr("Asking Google for the latest version…");
            if (a.job.length > 0 || !a.checked)
                return "";
            if (!a.installed) {
                if (a.customPath.length > 0)
                    return Translation.tr("Nothing to run at %1").arg(a.customPath);
                return a.agentId === "antigravity" ? Translation.tr("Google's agent server for apps like this one, about 340 MB from Google")
                    : Translation.tr("Install it in a terminal, then sign in here");
            }
            if (a.signedIn === true) {
                const parts = [card.status.plan, card.status.org, card.status.method].filter(p => (p ?? "").length > 0);
                if ((card.status.version ?? "").length > 0)
                    parts.push(Translation.tr("version %1").arg(card.status.version));
                return parts.join(" · ");
            }
            if (a.signedIn === false)
                return Translation.tr("Sign in to use it from the sidebar, on your own plan");
            return card.status.error ?? "";
        }

        ColumnLayout {
            id: cardLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialSymbol {
                    text: card.icon
                    iconSize: 34
                    fill: card.agent.signedIn === true ? 1 : 0
                    color: card.agent.signedIn === true ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: card.headline
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        wrapMode: Text.Wrap
                        text: card.detail
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // The actions first, where the pointer is: what a job adds -- its
            // progress, a code to paste, a failure -- goes under them, so Cancel
            // takes Install's place rather than landing below it (TASTE 4.1).
            Flow {
                Layout.fillWidth: true
                visible: actions.count > 0
                spacing: 8

                Repeater {
                    id: actions
                    model: {
                        const a = card.agent;
                        // All three from the start, so Cancel never moves: the link's
                        // two are disabled until there is one.
                        if (a.job === "login")
                            return ["open", "copyLink", "cancel"];
                        if (a.job === "install")
                            return ["cancel"];
                        if (a.job.length > 0 || !a.checked)
                            return [];
                        if (!a.installed) {
                            if (a.agentId === "antigravity" && a.customPath.length === 0)
                                return ["install"];
                            return card.installCommand.length > 0 && a.customPath.length === 0 ? ["copyInstall"] : [];
                        }
                        if (a.signedIn === true)
                            return ["switch", "signOut"];
                        return ["signIn"];
                    }
                    delegate: RippleButtonWithIcon {
                        id: action
                        required property string modelData
                        readonly property bool forward: ["install", "signIn"].includes(action.modelData)
                        readonly property var spec: ({
                            "open": ["open_in_new", Translation.tr("Open it again")],
                            "copyLink": ["content_copy", card.copied ? Translation.tr("Copied") : Translation.tr("Copy link")],
                            "cancel": ["close", Translation.tr("Cancel")],
                            "install": ["download", Translation.tr("Install")],
                            "copyInstall": ["content_copy", card.copied ? Translation.tr("Copied") : Translation.tr("Copy install command")],
                            "signIn": ["login", Translation.tr("Sign in")],
                            "switch": ["switch_account", Translation.tr("Switch account")],
                            "signOut": ["logout", Translation.tr("Sign out")]
                        })[action.modelData]
                        materialIcon: action.spec[0]
                        mainText: action.spec[1]
                        enabled: !["open", "copyLink"].includes(action.modelData) || card.agent.link.length > 0
                        // Tonal, not an accent: with every agent signed out there is
                        // one on each card (TASTE 2.3).
                        colBackground: action.forward ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                        colBackgroundHover: action.forward ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                        colRipple: action.forward ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer2Active
                        colText: action.forward ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                        onClicked: {
                            const a = card.agent;
                            switch (action.modelData) {
                            case "open":
                                Qt.openUrlExternally(a.link);
                                break;
                            case "copyLink":
                                Quickshell.clipboardText = a.link;
                                card.copied = true;
                                break;
                            case "copyInstall":
                                Quickshell.clipboardText = card.installCommand;
                                card.copied = true;
                                break;
                            case "cancel":
                                a.cancel();
                                break;
                            case "install":
                                a.install();
                                break;
                            case "signIn":
                            case "switch":
                                a.signIn();
                                break;
                            case "signOut":
                                card.signOutRequested();
                                break;
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: action.modelData === "copyInstall"
                            text: card.installCommand
                        }
                    }
                }
            }

            // Known size: the bar fills; before the registry answers, it runs.
            StyledProgressBar {
                Layout.fillWidth: true
                visible: card.agent.job === "install" && card.agent.progress >= 0
                value: Math.max(0, card.agent.progress)
            }
            StyledIndeterminateProgressBar {
                Layout.fillWidth: true
                visible: card.agent.job === "install" && card.agent.progress < 0
            }

            // Claude Code's manual flow: the browser shows a code, and the CLI is
            // waiting for it on its input.
            RowLayout {
                Layout.fillWidth: true
                visible: card.agent.needsCode
                spacing: 8

                MaterialTextField {
                    id: codeField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Code from the browser")
                    onAccepted: card.agent.sendCode(codeField.text)
                }
                RippleButtonWithIcon {
                    materialIcon: "check"
                    mainText: Translation.tr("Continue")
                    enabled: codeField.text.trim().length > 0
                    onClicked: card.agent.sendCode(codeField.text)
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0 && !card.busy
                wrapMode: Text.Wrap
                text: card.agent.jobError
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
            }
        }
    }

    // ── The rows under it ──────────────────────────────────────────────

    component OfferSwitch: ConfigSwitch {
        id: offerSwitch
        required property AgentSetupAgent agent
        buttonIcon: "menu_open"
        text: Translation.tr("Offer in the sidebar")
        summary: offerSwitch.checked ? Translation.tr("In the agent menu, when it is installed") : Translation.tr("Off: the sidebar never starts it")
        toggles: false
        checked: offerSwitch.agent.settings.enable
        onClicked: offerSwitch.agent.settings.enable = !offerSwitch.checked
    }

    component ModelRow: ConfigSelectionRow {
        id: modelRow
        required property AgentSetupAgent agent
        readonly property string chosen: modelRow.agent.settings.model
        buttonIcon: "neurology"
        text: Translation.tr("New chats start on")
        summary: modelRow.agent.models.length > 0 ? Translation.tr("The picker in the sidebar still changes the chat you are in")
            : Translation.tr("Its models show here once it has run in the sidebar")
        currentValue: modelRow.chosen
        onSelected: newValue => modelRow.agent.settings.model = newValue
        // A default the agent stopped offering still shows, so the choice in force
        // is never invisible.
        options: [{ displayName: Translation.tr("Last picked"), value: "" }]
            .concat(modelRow.agent.models.map(m => ({ displayName: m.label, value: m.id })))
            .concat(modelRow.chosen.length > 0 && !modelRow.agent.models.some(m => m.id === modelRow.chosen)
                ? [{ displayName: Translation.tr("%1 (not offered now)").arg(modelRow.chosen), value: modelRow.chosen }] : [])
    }

    component ProgramRow: ConfigTextField {
        id: programRow
        required property AgentSetupAgent agent
        property string usual
        icon: "terminal"
        text: Translation.tr("Program")
        inputText: programRow.agent.settings.binary
        placeholderText: programRow.agent.customPath.length === 0 && programRow.agent.installed && (programRow.agent.status?.path ?? "").length > 0
            ? programRow.agent.status.path : programRow.usual
        onEditingFinished: {
            if (programRow.agent.settings.binary !== programRow.inputText.trim())
                programRow.agent.settings.binary = programRow.inputText.trim();
        }
    }

    // ── Sidebar ────────────────────────────────────────────────────────

    ContentSection {
        icon: "view_sidebar"
        title: Translation.tr("Sidebar")

        ConfigSwitch {
            buttonIcon: "auto_awesome"
            text: Translation.tr("Agent in the left sidebar")
            summary: Translation.tr("Claude Code, Codex or Antigravity, on your own plan")
            toggles: false
            checked: Config.options.agent.enable
            onClicked: Config.options.agent.enable = !checked
        }

        ConfigSelectionRow {
            buttonIcon: "start"
            text: Translation.tr("Starts with")
            summary: Translation.tr("Each time the shell starts. The sidebar's menu switches in between")
            currentValue: Config.options.agent.defaultBackend
            onSelected: newValue => Config.options.agent.defaultBackend = newValue
            options: [{ displayName: Translation.tr("Last used"), value: "" }].concat(AgentSetup.agents.map(agent => ({
                displayName: agent.label,
                value: agent.agentId,
                enabled: agent.settings.enable && (!agent.checked || agent.installed)
            })))
        }
    }

    // ── The agents ─────────────────────────────────────────────────────

    ContentSection {
        icon: "auto_awesome"
        title: "Claude Code"

        AccountCard {
            agent: AgentSetup.claude
            onSignOutRequested: page.confirm(AgentSetup.claude, "logout")
            icon: "auto_awesome"
            installCommand: "curl -fsSL https://claude.ai/install.sh | bash"
        }
        OfferSwitch {
            agent: AgentSetup.claude
        }
        ModelRow {
            agent: AgentSetup.claude
        }
        ProgramRow {
            agent: AgentSetup.claude
            usual: Translation.tr("claude, from your PATH")
        }
    }

    ContentSection {
        icon: "code"
        title: "Codex"

        AccountCard {
            agent: AgentSetup.codex
            onSignOutRequested: page.confirm(AgentSetup.codex, "logout")
            icon: "code"
            installCommand: "npm install -g @openai/codex"
        }
        OfferSwitch {
            agent: AgentSetup.codex
        }
        ModelRow {
            agent: AgentSetup.codex
        }
        ProgramRow {
            agent: AgentSetup.codex
            usual: Translation.tr("codex, from your PATH")
        }
    }

    ContentSection {
        icon: "rocket_launch"
        title: "Antigravity"

        AccountCard {
            agent: AgentSetup.antigravity
            onSignOutRequested: page.confirm(AgentSetup.antigravity, "logout")
            icon: "rocket_launch"
        }

        // The server this page downloaded: what it costs here, and the newer one.
        // One the user pointed at, or on PATH, is theirs to update.
        Item {
            id: serverCard
            readonly property bool wantsCard: true
            readonly property var agent: AgentSetup.antigravity
            readonly property var status: serverCard.agent.status ?? ({})
            readonly property bool update: serverCard.agent.latest.length > 0 && page.newer(serverCard.agent.latest, serverCard.status.version ?? "")
            visible: (serverCard.status.managed ?? false) && serverCard.agent.job.length === 0
            Layout.fillWidth: true
            implicitHeight: serverLayout.implicitHeight + 24

            RowLayout {
                id: serverLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 10

                MaterialSymbol {
                    text: "deployed_code"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSecondaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Translation.tr("Google's agent server")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: serverCard.update ? Translation.tr("Version %1 · %2 · %3 is out").arg(serverCard.status.version).arg(page.sizeText(serverCard.status.size ?? 0)).arg(serverCard.agent.latest)
                            : Translation.tr("Version %1 · %2").arg(serverCard.status.version ?? "").arg(page.sizeText(serverCard.status.size ?? 0))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButtonWithIcon {
                    visible: serverCard.update
                    materialIcon: "upgrade"
                    mainText: Translation.tr("Update")
                    onClicked: serverCard.agent.install()
                    StyledToolTip {
                        text: Translation.tr("The sidebar keeps the version it is running until it next starts")
                    }
                }
                RippleButtonWithIcon {
                    materialIcon: "delete"
                    mainText: Translation.tr("Remove")
                    colText: Appearance.colors.colError
                    onClicked: page.confirm(serverCard.agent, "remove")
                }
            }
        }

        OfferSwitch {
            agent: AgentSetup.antigravity
        }
        ModelRow {
            agent: AgentSetup.antigravity
        }
        ProgramRow {
            agent: AgentSetup.antigravity
            usual: Translation.tr("The server installed here")
        }
    }

    // ── Chat ───────────────────────────────────────────────────────────

    ContentSection {
        icon: "forum"
        title: Translation.tr("Chat")

        ConfigSwitch {
            buttonIcon: "construction"
            text: Translation.tr("Show each tool it uses")
            summary: Translation.tr("Commands, edits and searches, as rows in its reply")
            checked: Config.options.agent.showToolCalls
            onCheckedChanged: Config.options.agent.showToolCalls = checked
        }

        ConfigSwitch {
            buttonIcon: "pending"
            text: Translation.tr("Show what it is doing")
            summary: Translation.tr("A line over the reply box while it works, listens or reads aloud")
            checked: Config.options.agent.showStatusLine
            onCheckedChanged: Config.options.agent.showStatusLine = checked
        }

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Notify when it replies or needs you")
            summary: Translation.tr("Only while its tab is not on screen")
            checked: Config.options.agent.notifyWhenAway
            onCheckedChanged: Config.options.agent.notifyWhenAway = checked
        }

        ConfigSwitch {
            buttonIcon: "desktop_windows"
            text: Translation.tr("Let it see and use the desktop")
            summary: Translation.tr("Screenshots, windows, clicks and the shell's own controls. Clicking still asks first")
            checked: Config.options.agent.desktopTools
            onCheckedChanged: Config.options.agent.desktopTools = checked
        }

        ConfigSpinBox {
            icon: "format_list_bulleted"
            text: Translation.tr("Slash command suggestions")
            value: Config.options.agent.maxSuggestions
            from: 4
            to: 40
            stepSize: 1
            onValueChanged: Config.options.agent.maxSuggestions = value
        }

        ConfigLabeledRow {
            buttonIcon: "edit_note"
            text: Translation.tr("Your instructions")
            summary: Translation.tr("Every agent gets these, from its next chat on")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("What every agent should know about you")
                text: Config.options.agent.instructions
                wrapMode: TextEdit.Wrap
                onEditingFinished: {
                    if (Config.options.agent.instructions !== text.trim())
                        Config.options.agent.instructions = text.trim();
                }
            }
        }
    }

    // ── Voice ──────────────────────────────────────────────────────────

    readonly property bool sttOnline: Config.options.agent.sttEngine === "groq"

    /*
     * Online dictation's Groq key: a keyring entry of its own, which
     * scripts/agent/stt_groq.py reads at every use (its docstring says why not
     * KeyringStorage's shared JSON). The page only ever learns whether one is
     * saved; the key itself is written to secret-tool's input and never read back.
     */
    readonly property var groqKeyAttrs: ["application", "ii-ren", "secret", "groq-api-key"]
    property bool groqKeySaved: false
    property string groqKeyError: ""

    // Looked up only once online is picked (and on open, above): on a locked
    // keyring a lookup asks to unlock.
    onSttOnlineChanged: if (page.sttOnline) groqKeyProbe.running = true

    function saveGroqKey(key: string): void {
        const trimmed = key.trim();
        if (trimmed.length === 0 || groqKeyStore.running) return;
        page.groqKeyError = "";
        groqKeyStore.pending = trimmed;
        groqKeyStore.running = true;
    }

    Process {
        id: groqKeyProbe
        command: ["secret-tool", "lookup", ...page.groqKeyAttrs]
        onExited: exitCode => page.groqKeySaved = exitCode === 0
    }
    Process {
        id: groqKeyStore
        property string pending: ""
        command: ["secret-tool", "store", "--label=ii-ren Groq API key", ...page.groqKeyAttrs]
        stdinEnabled: true
        onRunningChanged: {
            if (!running) return;
            groqKeyStore.write(groqKeyStore.pending);
            groqKeyStore.pending = "";
            groqKeyStore.stdinEnabled = false; // EOF: secret-tool stores what it read
        }
        onExited: exitCode => {
            groqKeyStore.stdinEnabled = true;
            if (exitCode === 0) {
                page.groqKeySaved = true;
                groqKeyField.text = "";
            } else {
                page.groqKeyError = Translation.tr("Couldn't save the key to the keyring. Is a keyring (gnome-keyring or KWallet) running?");
            }
        }
    }
    Process {
        id: groqKeyClear
        command: ["secret-tool", "clear", ...page.groqKeyAttrs]
        onExited: groqKeyProbe.running = true
    }

    ContentSection {
        icon: "graphic_eq"
        title: Translation.tr("Voice")

        ConfigSelectionRow {
            buttonIcon: "cloud"
            text: Translation.tr("Dictation runs")
            summary: Translation.tr("On this computer stays private; online sends your recordings to Groq. Hover one to compare")
            currentValue: Config.options.agent.sttEngine
            onSelected: newValue => Config.options.agent.sttEngine = newValue
            options: [
                {
                    displayName: Translation.tr("On this computer"),
                    value: "local",
                    tooltip: Translation.tr("+ Your voice never leaves this computer\n+ Free and offline, no account\n– Slower, most of all the bigger models without a GPU\n– Needs whisper.cpp and a one-time model download")
                },
                {
                    displayName: Translation.tr("Online · Groq"),
                    value: "groq",
                    tooltip: Translation.tr("+ About a second per clip, on any computer\n+ As accurate as Best, in any language\n– Your recordings are sent to Groq\n– Needs internet and a free Groq key, with hourly limits")
                }
            ]
        }

        ConfigLabeledRow {
            visible: page.sttOnline
            buttonIcon: "key"
            text: Translation.tr("Groq API key")
            summary: page.groqKeySaved ? Translation.tr("Saved in your keyring. Paste a new one to replace it")
                : Translation.tr("Free from console.groq.com. Kept in your keyring, not in the config file")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialTextField {
                    id: groqKeyField
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: page.groqKeySaved ? Translation.tr("Paste a new key") : Translation.tr("Paste your key")
                    onAccepted: page.saveGroqKey(groqKeyField.text)
                }
                RippleButtonWithIcon {
                    visible: groqKeyField.text.trim().length > 0
                    materialIcon: "check"
                    mainText: Translation.tr("Save")
                    onClicked: page.saveGroqKey(groqKeyField.text)
                }
                RippleButtonWithIcon {
                    visible: groqKeyField.text.trim().length === 0 && !page.groqKeySaved
                    materialIcon: "open_in_new"
                    mainText: Translation.tr("Get a key")
                    onClicked: Qt.openUrlExternally("https://console.groq.com/keys")
                }
                RippleButtonWithIcon {
                    visible: groqKeyField.text.trim().length === 0 && page.groqKeySaved
                    materialIcon: "delete"
                    mainText: Translation.tr("Remove")
                    colText: Appearance.colors.colError
                    onClicked: groqKeyClear.running = true
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                wrapMode: Text.Wrap
                text: page.groqKeyError
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: !page.sttOnline && !AgentSetup.whisperInstalled
            materialIcon: "mic_off"
            text: Translation.tr("Dictation needs whisper.cpp: sudo pacman -S whisper-cpp")
        }

        ConfigSelectionRow {
            visible: !page.sttOnline
            enabled: AgentSetup.whisperInstalled
            buttonIcon: "mic"
            text: Translation.tr("Dictation model")
            summary: Translation.tr("A bigger one hears better and takes longer. Downloaded on first use")
            currentValue: Config.options.agent.sttQuality
            onSelected: newValue => Config.options.agent.sttQuality = newValue
            options: [
                { displayName: Translation.tr("Fast · 78 MB"), value: "fast" },
                { displayName: Translation.tr("Balanced · 148 MB"), value: "balanced" },
                { displayName: Translation.tr("Accurate · 190 MB"), value: "accurate" },
                { displayName: Translation.tr("Best · 574 MB"), value: "best" }
            ]
        }

        ConfigSelectionRow {
            enabled: page.sttOnline || AgentSetup.whisperInstalled
            buttonIcon: "translate"
            text: Translation.tr("Dictation language")
            summary: page.sttOnline ? Translation.tr("Online hears any language")
                : Translation.tr("Languages other than English need the Best model")
            currentValue: Config.options.agent.sttLanguage
            onSelected: newValue => Config.options.agent.sttLanguage = newValue
            options: [
                { displayName: Translation.tr("English"), value: "en" },
                { displayName: Translation.tr("Detect"), value: "auto" }
            ]
        }

        ConfigLabeledRow {
            enabled: page.sttOnline || AgentSetup.whisperInstalled
            buttonIcon: "spellcheck"
            text: Translation.tr("Words it should know")
            summary: Translation.tr("Names and terms to spell the way you do")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Names and terms, comma separated")
                text: Config.options.agent.sttPrompt
                wrapMode: TextEdit.Wrap
                onEditingFinished: {
                    if (Config.options.agent.sttPrompt !== text.trim())
                        Config.options.agent.sttPrompt = text.trim();
                }
            }
        }

        ConfigSelectionRow {
            buttonIcon: "cloud"
            text: Translation.tr("Read-aloud runs")
            summary: AgentSetup.kokoroInstalled ? Translation.tr("On this computer stays private; online sends each reply to Microsoft. Hover one to compare")
                : Translation.tr("On this computer needs the shell's Python packages updated first: iiren update")
            currentValue: Config.options.agent.ttsEngine
            onSelected: newValue => Config.options.agent.ttsEngine = newValue
            options: [
                {
                    displayName: Translation.tr("On this computer"),
                    value: "kokoro",
                    enabled: AgentSetup.kokoroInstalled,
                    tooltip: Translation.tr("+ Nothing read aloud leaves this computer\n+ Free and offline, no account\n– A one-time 205 MB download, and about 450 MB of memory once used\n– Slower to start, more so on battery")
                },
                {
                    displayName: Translation.tr("Online · Microsoft"),
                    value: "edge",
                    tooltip: Translation.tr("+ Starts quickly, on any computer\n+ Nothing to download, little memory\n– The text of each reply is sent to Microsoft\n– Needs internet")
                }
            ]
        }

        // Each engine keeps its own pick, so switching back finds the voice it had.
        ConfigSelectionRow {
            id: ttsVoiceRow
            readonly property bool local: Config.options.agent.ttsEngine === "kokoro"
            buttonIcon: "record_voice_over"
            text: Translation.tr("Read-aloud voice")
            currentValue: ttsVoiceRow.local ? (Config.options.agent.ttsLocalVoice || "af_heart") : (Config.options.agent.ttsVoice || "en-US-AriaNeural")
            onSelected: newValue => {
                if (ttsVoiceRow.local)
                    Config.options.agent.ttsLocalVoice = newValue;
                else
                    Config.options.agent.ttsVoice = newValue;
            }
            options: ttsVoiceRow.local ? [
                { displayName: "Heart · US", value: "af_heart" },
                { displayName: "Bella · US", value: "af_bella" },
                { displayName: "Michael · US", value: "am_michael" },
                { displayName: "Emma · UK", value: "bf_emma" },
                { displayName: "George · UK", value: "bm_george" }
            ] : [
                { displayName: "Aria · US", value: "en-US-AriaNeural" },
                { displayName: "Guy · US", value: "en-US-GuyNeural" },
                { displayName: "Sonia · UK", value: "en-GB-SoniaNeural" },
                { displayName: "Ryan · UK", value: "en-GB-RyanNeural" }
            ]
        }
    }

    // ── Confirmation ───────────────────────────────────────────────────

    Loader {
        parent: page
        anchors.fill: parent
        z: 100
        active: page.dialogActive

        sourceComponent: WindowDialog {
            id: dialog
            property AgentSetupAgent agent
            property string job

            function accept(): void {
                if (dialog.job === "logout")
                    dialog.agent.signOut();
                else
                    dialog.agent.remove();
                page.dialogOpen = false;
            }

            // Created shut and opened a turn later, so onShowChanged runs and it enters.
            show: false
            Component.onCompleted: {
                dialog.agent = page.confirmAgent;
                dialog.job = page.confirmJob;
                dialog.show = Qt.binding(() => page.dialogOpen);
                // Focus inside, so WindowDialog's Escape and Tab reach it.
                cancelButton.forceActiveFocus();
            }
            onVisibleChanged: if (!visible && !show) page.dialogActive = false
            onDismiss: page.dialogOpen = false

            WindowDialogTitle {
                text: dialog.job === "logout" ? Translation.tr("Sign out of %1?").arg(dialog.agent?.label ?? "")
                    : Translation.tr("Remove Google's agent server?")
            }
            WindowDialogParagraph {
                text: dialog.job === "logout"
                    ? Translation.tr("This signs %1 out on this computer, in a terminal too. Your chats are kept.").arg(dialog.agent?.label ?? "")
                    : Translation.tr("Frees %1. Your Google sign-in and your chats are kept, and it downloads again from here.").arg(page.sizeText(dialog.agent?.status?.size ?? 0))
            }
            WindowDialogButtonRow {
                Item {
                    Layout.fillWidth: true
                }
                DialogButton {
                    id: cancelButton
                    buttonText: Translation.tr("Cancel")
                    onClicked: page.dialogOpen = false
                }
                DialogButton {
                    buttonText: dialog.job === "logout" ? Translation.tr("Sign out") : Translation.tr("Remove")
                    colEnabled: Appearance.colors.colError
                    onClicked: dialog.accept()
                }
            }
        }
    }
}
