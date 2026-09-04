pragma Singleton
import qs
import qs.modules.common
import qs.modules.common.functions as CF
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs.services.conduit

/**
 * Conduit — chat backend for AI providers the built-in AI Chat doesn't cover.
 *
 * The built-in `Ai` service hardcodes its provider map, and the extension system has no
 * contribution point for registering a new one, so Conduit runs its own request loop
 * rather than trying to plug into it. Wire formats live in ./conduit/*Strategy.qml.
 */
Singleton {
    id: root

    // A singleton is only built when something reads it, and the dictation shortcut and
    // IPC target have to exist before the tab has ever been opened.
    function load(): void {}

    readonly property string interfaceRole: "interface"

    // Emitted for dictation that should be reviewed before sending. Auto-send dictation
    // never reaches here; the service sends it directly, so it works even when the tab
    // has never been opened and no UI exists to listen.
    signal dictationReady(string text)

    property Component messageComponent: ConduitMessage {}
    property Component partComponent: ConduitPart {}
    property Component claudeCliStrategy: ClaudeCliStrategy {}
    property Component antigravityStrategy: AntigravityStrategy {}

    /* ---------- Providers ---------------------------------------------------
     * To add a provider: write ./conduit/<Name>Strategy.qml extending ProviderStrategy,
     * add a Component property above, register it in `strategies`, and add an entry here.
     *
     * Both providers drive a CLI that is already logged in, so neither takes an
     * API key. `capabilities` records what that CLI can actually do, so the UI can
     * hide a control rather than offer one that silently does nothing.
     */
    readonly property var providers: ({
        "claude-cli": {
            "name": "Claude Code",
            "command": "claude",
            "icon": "terminal",
            "blurb": "Runs on your local Claude Code login. No API key.",
            "capabilities": {
                "slashCommands": true,
                "sessions": true,
                "cost": true,
                "toolsOffSwitch": true,
                "customModels": false,
                "persistentProcess": false,
                // The CLI takes reasoning effort as its own `--effort` flag rather than
                // baking it into the model name the way Antigravity's list does.
                "effortLevels": true
            },
            "models": [
                { "value": "claude-sonnet-5", "title": "Claude Sonnet 5", "description": "Balanced default." },
                { "value": "claude-opus-5", "title": "Claude Opus 5", "description": "Most capable, slowest." },
                { "value": "claude-fable-5", "title": "Claude Fable 5", "description": "Tuned for writing and long-form prose." },
                { "value": "claude-haiku-4-5-20251001", "title": "Claude Haiku 4.5", "description": "Fastest." }
            ]
        },
        "antigravity": {
            "name": "Antigravity",
            "command": "agy",
            "icon": "auto_awesome",
            "blurb": "Runs on your local Antigravity login. No API key.",
            "capabilities": {
                "slashCommands": true,
                "sessions": true,
                // The result frame reports tokens, not a price.
                "cost": false,
                // No flag that removes the toolset.
                "toolsOffSwitch": false,
                // `agy models` moves independently of the list below.
                "customModels": true,
                // One process serves the whole conversation; see supportsPersistentProcess.
                "persistentProcess": true,
                // Effort is a model variant here (gemini-3.1-pro-high vs -low), not a flag.
                "effortLevels": false
            },
            "models": [
                { "value": "gemini-3.7-flash-high", "title": "Gemini 3.7 Flash (High)", "description": "Balanced default: newest Flash, full reasoning." },
                { "value": "gemini-3.1-pro-high", "title": "Gemini 3.1 Pro (High)", "description": "Most capable, deepest reasoning." },
                { "value": "gemini-3.1-pro-low", "title": "Gemini 3.1 Pro (Low)", "description": "Pro quality, lighter reasoning." },
                { "value": "gemini-3.7-flash-medium", "title": "Gemini 3.7 Flash (Medium)", "description": "Less reasoning, quicker replies." },
                { "value": "gemini-3.7-flash-low", "title": "Gemini 3.7 Flash (Low)", "description": "Fastest." },
                { "value": "claude-sonnet-4-6", "title": "Claude Sonnet 4.6", "description": "Anthropic model with thinking, billed to Antigravity." },
                { "value": "claude-opus-4-6-thinking", "title": "Claude Opus 4.6", "description": "Anthropic's most capable, billed to Antigravity." },
                { "value": "gpt-oss-120b-medium", "title": "GPT-OSS 120B", "description": "Open-weights model." },
                { "value": "gemini-3.6-flash-high", "title": "Gemini 3.6 Flash (High)", "description": "Previous Flash generation." },
                { "value": "gemini-3.6-flash-medium", "title": "Gemini 3.6 Flash (Medium)", "description": "Previous Flash generation." },
                { "value": "gemini-3.6-flash-low", "title": "Gemini 3.6 Flash (Low)", "description": "Previous Flash generation." },
                { "value": "gemini-3.5-flash-high", "title": "Gemini 3.5 Flash (High)", "description": "Older Flash generation." },
                { "value": "gemini-3.5-flash-medium", "title": "Gemini 3.5 Flash (Medium)", "description": "Older Flash generation." },
                { "value": "gemini-3.5-flash-low", "title": "Gemini 3.5 Flash (Low)", "description": "Older Flash generation." }
            ]
        }
    })

    readonly property var strategies: ({
        "claude-cli": root.claudeCliStrategy.createObject(root),
        "antigravity": root.antigravityStrategy.createObject(root)
    })

    readonly property var providerIds: Object.keys(root.providers)

    /* ---------- Provider capabilities -------------------------------------- */

    readonly property var capabilities: root.currentProvider.capabilities ?? ({})
    // The CLI can run the user's own slash commands and skills.
    readonly property bool supportsSlashPassthrough: root.capabilities.slashCommands === true
    // Later turns resume a session instead of replaying the transcript.
    readonly property bool supportsSessions: root.capabilities.sessions === true
    readonly property bool supportsCost: root.capabilities.cost === true
    // False when the CLI has no flag that takes the toolset away, in which case
    // /tools off can only be enforced by instruction.
    readonly property bool hasToolsOffSwitch: root.capabilities.toolsOffSwitch === true
    readonly property bool supportsCustomModels: root.capabilities.customModels === true
    /**
     * The CLI can take one turn per line on stdin, so a single process serves the whole
     * conversation. That matters a lot: for agy roughly ten of the twelve seconds a turn
     * takes is the CLI reaching its first `init`, and only the first turn of a process
     * pays it. Follow-ups land in under two seconds.
     */
    readonly property bool supportsPersistentProcess: root.capabilities.persistentProcess === true
    readonly property bool supportsEffortLevels: root.capabilities.effortLevels === true

    // Reasoning effort for providers whose CLI takes it as its own flag (claude-cli's
    // `--effort`) rather than baking it into the model name (Antigravity's `-high`/`-low`
    // model suffixes already do that, so it has no use for this).
    readonly property var effortLevels: [
        { "value": "low", "title": "Low", "description": "Fastest, least reasoning." },
        { "value": "medium", "title": "Medium", "description": "Balanced." },
        { "value": "high", "title": "High", "description": "Deeper reasoning." },
        { "value": "xhigh", "title": "Extra high", "description": "More thorough than high." },
        { "value": "max", "title": "Max", "description": "Most thorough, slowest." }
    ]
    readonly property string effort: Config.options.conduit.effort

    // A live process was launched with these baked in, so any change replaces it.
    readonly property string requestKey: JSON.stringify([root.currentProviderId, root.currentModelId,
        root.workingDir, root.enableTools, root.permissionMode, root.disallowedTools, root.effort])

    /* ---------- Config-backed state ---------------------------------------- */

    readonly property string currentProviderId: {
        const stored = Config.options.conduit.provider;
        return root.providers[stored] ? stored : "claude-cli";
    }
    readonly property var currentProvider: root.providers[root.currentProviderId]

    readonly property string currentModelId: {
        const stored = Config.options.conduit.model;
        const models = root.currentProvider.models;
        if (models.some(model => model.value === stored)) return stored;
        // A provider whose model list moves independently keeps whatever was set,
        // unless the id plainly belongs to one of the other providers.
        const claimedElsewhere = root.providerIds.some(id => id !== root.currentProviderId
            && root.providers[id].models.some(model => model.value === stored));
        if (stored.length > 0 && !claimedElsewhere && root.supportsCustomModels) return stored;
        return models[0].value;
    }
    readonly property string systemPrompt: Config.options.conduit.systemPrompt
    /**
     * Whether a restart picks the last conversation back up. Off: a restart is a clean
     * slate, and the previous chat is one click away in the history.
     *
     * Closing and reopening the tab is unaffected either way — the service outlives the
     * page, so the conversation is still there whatever this says.
     *
     * Deliberately not the old `restoreLastSession` key: that one already has `true`
     * stored from every existing install, and a stored value wins over a default, so
     * flipping the default alone would have changed nothing for anyone.
     */
    readonly property bool restoreOnRestart: Config.options.conduit.restoreOnRestart

    /* ---------- Tool access ------------------------------------------------ *
     * Print mode cannot show an approval prompt, so whatever is allowed here runs
     * unattended. `workingDir` is the blast radius and is surfaced in the UI.
     */
    readonly property bool enableTools: Config.options.conduit.enableTools

    // Desktop control is MCP, not a built-in tool: the server in scripts/mcp is what
    // gives the agent the screen, the pointer and the shell's own IPC.
    readonly property bool desktopControl: Config.options.conduit.desktopControl
    readonly property string desktopMcpPath: CF.FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/scripts/mcp/desktop.py`)
    readonly property string permissionMode: Config.options.conduit.permissionMode
    readonly property string disallowedTools: Config.options.conduit.disallowedTools
    readonly property string workingDir: {
        const stored = Config.options.conduit.workingDir;
        return stored.length > 0 ? stored : CF.FileUtils.trimFileProtocol(Directories.home);
    }

    /**
     * Drop the conversation. Clearing the id is not enough for a persistent provider:
     * the context lives inside the running process, so it has to go too, or the model
     * keeps answering from history the transcript no longer shows.
     */
    function resetSession() {
        root.cliSessionId = "";
        root.sessionPrimed = false;
        if (root.supportsPersistentProcess && requester.running && !root.responding) {
            // Between asking it to stop and it actually going, `running` is still true.
            // Clearing the key stops the next turn reusing a process that is on its way
            // out, which would post the turn into a closing stdin and hang.
            requester.turnKey = "";
            requester.running = false;
        }
        // Whatever invalidated the conversation — model, directory, tools, a new chat —
        // the next question should not also pay for the CLI starting up.
        warmTimer.restart();
    }

    function setWorkingDir(path) {
        const trimmed = (path ?? "").trim();
        if (trimmed.length === 0) {
            root.addInterfaceMessage(`Working directory: \`${root.workingDir}\`\n\nChange with /cwd PATH. Tools can only reach files under it.`);
            return;
        }
        const expanded = trimmed.replace(/^~/, CF.FileUtils.trimFileProtocol(Directories.home)).replace(/\/+$/, "");
        Config.options.conduit.workingDir = expanded;
        root.resetSession(); // CLI sessions are per-directory
        root.addInterfaceMessage(`Working directory set to \`${expanded}\`.`);
    }

    function setToolsEnabled(enabled) {
        Config.options.conduit.enableTools = enabled;
        root.resetSession();
        if (enabled) {
            root.addInterfaceMessage(`Tools **enabled** (\`${root.permissionMode}\`) in \`${root.workingDir}\`.\n\nNothing will ask before it edits files or runs commands. Disable with \`/tools off\`.`);
        } else if (root.hasToolsOffSwitch) {
            root.addInterfaceMessage("Tools **disabled**. Replies are plain chat.");
        } else {
            root.addInterfaceMessage(`Tools **disabled**. \`${root.currentProvider.command}\` has no flag that removes them, so the model is told not to use them — a call that still needs approval will end the turn with an error.`);
        }
    }

    /* ---------- Attachments ------------------------------------------------ *
     * Attachments are passed to the model as file paths, which the Read tool then
     * opens. That is why they work for images, PDFs, notebooks and plain text alike
     * rather than only for formats a chat API happens to inline — but it also means
     * they need tools switched on.
     */

    readonly property string attachDir: `${root.scriptDir}/attachments`
    property var pendingAttachments: []

    function attachFile(path) {
        let clean = (path ?? "").trim();
        if (clean.length === 0) return;
        // Drops arrive percent-encoded as file:// URLs.
        clean = CF.FileUtils.trimFileProtocol(decodeURIComponent(clean));
        clean = clean.replace(/^~/, CF.FileUtils.trimFileProtocol(Directories.home));
        if (root.pendingAttachments.indexOf(clean) !== -1) return;
        root.pendingAttachments = [...root.pendingAttachments, clean];
        if (!root.enableTools) {
            root.addInterfaceMessage("Attached, but **tools are off** so it can't be opened. Click \"Tools off\" in the status pill, or run `/tools on`.");
        }
    }

    function detachFile(path) {
        root.pendingAttachments = root.pendingAttachments.filter(entry => entry !== path);
    }

    function detachLast() {
        if (root.pendingAttachments.length === 0) return false;
        root.pendingAttachments = root.pendingAttachments.slice(0, -1);
        return true;
    }

    function clearAttachments() {
        root.pendingAttachments = [];
    }

    // Pasted images live only inside cliphist, so they have to be decoded to a real
    // file before anything can read them.
    property Process clipboardDecodeProc: Process {
        id: clipboardDecodeProc
        property string outPath: ""

        function decodeEntry(entry) {
            const id = entry.match(/^(\d+)\t/)?.[1];
            if (!id) return;
            clipboardDecodeProc.outPath = `${root.attachDir}/clipboard-${id}.png`;
            const escaped = CF.StringUtils.shellSingleQuoteEscape(entry);
            clipboardDecodeProc.command = ["bash", "-c",
                `mkdir -p '${root.attachDir}' && { [ -s '${clipboardDecodeProc.outPath}' ] || printf '%s' '${escaped}' | ${Cliphist.cliphistBinary} decode > '${clipboardDecodeProc.outPath}'; }`];
            clipboardDecodeProc.running = true;
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                root.attachFile(clipboardDecodeProc.outPath);
            } else {
                console.log("[Conduit] Failed to decode clipboard image, exit", exitCode);
                root.addInterfaceMessage("Could not decode the image on the clipboard.");
            }
        }
    }

    /**
     * Attaches whatever is currently on the clipboard: a copied image, or a copied
     * file path. Returns true if it took responsibility for the paste.
     */
    function attachFromClipboard() {
        const entry = Cliphist.entries[0] ?? "";
        if (entry.length === 0) return false;
        if (Cliphist.entryIsImage(entry)) {
            clipboardDecodeProc.decodeEntry(entry);
            return true;
        }
        const text = CF.StringUtils.cleanCliphistEntry(entry);
        if (text.startsWith("file://")) {
            root.attachFile(text);
            return true;
        }
        return false;
    }

    /* ---------- Voice input ------------------------------------------------ */

    /* ---------- Dictation accuracy -----------------------------------------
     * Presets rather than a file path, so the choice is "how accurate" instead of "go
     * find a model". Times are measured on an 8-core TigerLake CPU for 11s of audio; a
     * GPU backend (ggml-vulkan) changes them substantially.
     */
    readonly property var sttPresets: ({
        "fast":     { "file": "ggml-tiny.en.bin" },              //  78MB, ~2s per 11s of audio
        "balanced": { "file": "ggml-base.en.bin" },              // 148MB, ~4s
        "accurate": { "file": "ggml-small.en-q5_1.bin" },        // 190MB, ~12s
        "best":     { "file": "ggml-large-v3-turbo-q5_0.bin" }   // 574MB, slow without a GPU backend
    })
    readonly property string sttQuality: {
        const stored = Config.options.conduit.sttQuality;
        return root.sttPresets[stored] ? stored : "balanced";
    }
    readonly property string sttModelDir: CF.FileUtils.trimFileProtocol(`${Directories.home}/.local/share/vynx-conduit/models`)

    // An explicit path always wins, so a hand-picked model is never overridden.
    readonly property string sttModel: {
        const stored = Config.options.conduit.sttModel;
        if (stored.length > 0) return stored.replace(/^~/, CF.FileUtils.trimFileProtocol(Directories.home));
        return `${root.sttModelDir}/${root.sttPresets[root.sttQuality].file}`;
    }
    readonly property string sttModelUrl: {
        const stored = Config.options.conduit.sttModel;
        if (stored.length > 0) return ""; // Manual path: the user owns fetching it.
        return `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${root.sttPresets[root.sttQuality].file}`;
    }
    readonly property string sttLanguage: Config.options.conduit.sttLanguage
    readonly property string sttPrompt: Config.options.conduit.sttPrompt
    readonly property string sttSource: Config.options.conduit.sttSource

    property SpeechToText speech: SpeechToText {
        modelPath: root.sttModel
        modelUrl: root.sttModelUrl
        language: root.sttLanguage
        prompt: root.sttPrompt
        source: root.sttSource

        onModelDownloaded: root.addInterfaceMessage(`Voice model ready (**${root.sttQuality}**). Press the mic or your dictation key.`)

        onTranscribed: text => {
            if (root.speech.autoSend) {
                root.speech.autoSend = false;
                // Voice in, voice out: a turn dictated with the keybinding is read
                // back the same way, so the whole exchange works without looking.
                root.speakReply = true;
                root.sendUserMessage(text);
                return;
            }
            root.dictationReady(text);
        }
        onFailed: reason => root.addInterfaceMessage(reason)
    }

    /* ---------- Voice output ----------------------------------------------- */

    // piper: a path to a .onnx voice. espeak-ng: a voice name such as "en-gb".
    // A leading ~ is expanded here: the value reaches bash single-quoted, so the
    // shell would never expand it and piper would look for a literal "~" directory.
    readonly property string ttsVoice: {
        const stored = Config.options.conduit.ttsVoice;
        return stored.replace(/^~/, CF.FileUtils.trimFileProtocol(Directories.home));
    }
    // Where a piper voice is looked for when none is configured — the same
    // convention as the Whisper models next door.
    readonly property string ttsVoiceDir: CF.FileUtils.trimFileProtocol(`${Directories.home}/.local/share/vynx-conduit/voices`)

    // Which memo owns the speakers. Held here rather than in the players so they do
    // not have to know about each other.
    property int activeMemo: -1
    // Armed by the dictation keybinding, consumed by the next reply that finishes.
    property bool speakReply: false

    // Which memo may start on its own. Taken by calling takeAutoPlay, never bound
    // to by the players: more than one copy of the page can be alive and every copy
    // renders the same message, so the claim has to be consumed synchronously.
    property int autoPlayFor: -1

    property string autoPlayPath: ""

    /**
     * Takes the claim for `messageId`. Returns where to start from in ms, or -1 if
     * this memo may not start.
     *
     * Non-zero when a memo is already being played out of band and a real player has
     * just appeared: it picks up where the sound actually is, so opening the panel
     * mid-memo shows the waveform in the right place instead of starting over.
     */
    function takeAutoPlay(messageId) {
        if (root.autoPlayFor !== messageId) return -1;
        root.autoPlayFor = -1;
        if (root.memoPlayer.forMessage !== messageId) return 0;
        return Math.max(0, Date.now() - root.memoPlayer.startedAt);
    }

    /*
     * Nobody on screen took it. With the sidebar closed, on another tab, or scrolled
     * away there is no player at all — and a dictated exchange has to be audible
     * without looking at anything, so it is played straight out.
     *
     * 700ms: an on-screen player claims in about 75ms, measured, so this only fires
     * when there really is none. The claim keeps the two from ever both playing.
     */
    property Timer autoPlayWindow: Timer {
        interval: 700
        onTriggered: {
            if (root.autoPlayFor < 0) return;
            console.log(`[Conduit] Nothing on screen took the memo for message ${root.autoPlayFor}; playing it directly.`);
            root.playOutOfBand(root.autoPlayFor, root.autoPlayPath);
        }
    }

    /**
     * No pausing and no scrubbing here — this is the path for when there is nothing
     * to press anyway. The claim is deliberately left open: a player that appears
     * while this is running takes over from wherever the sound has got to.
     */
    property Process memoPlayer: Process {
        property int forMessage: -1
        property double startedAt: 0

        onExited: {
            // The handover window closes with the sound. Guarded, because a newer
            // memo's claim may already be waiting by now.
            if (root.autoPlayFor === memoPlayer.forMessage) root.autoPlayFor = -1;
            memoPlayer.forMessage = -1;
        }
    }

    function playOutOfBand(messageId, path) {
        if (path.length === 0) return;
        memoPlayer.forMessage = messageId;
        memoPlayer.startedAt = Date.now();
        memoPlayer.command = ["pw-play", path];
        memoPlayer.running = true;
    }

    // A real player is taking over, so whatever is coming out of pw-play stops.
    function claimSpeakers(messageId) {
        memoPlayer.running = false;
        root.activeMemo = messageId;
    }
    readonly property int ttsSpeakingFor: root.reader.speakingFor

    property TextToSpeech reader: TextToSpeech {
        voice: root.ttsVoice
        voiceDir: root.ttsVoiceDir

        onReady: (messageId, path, bytes, bars) => {
            const message = root.messageByID[messageId];
            if (!message) return;
            if (message.audioPath === undefined) {
                root.addInterfaceMessage("The memo was made, but playing it needs a shell restart (`Super+Ctrl+R`) — the message type is cached from an older reload.");
                return;
            }
            message.audioBytes = bytes;
            message.audioBars = bars;
            // Before the path: assigning that is what starts playback.
            root.autoPlayFor = messageId;
            root.autoPlayPath = path;
            root.autoPlayWindow.restart();
            // Assigned last: this is the property the player watches, and it starts
            // playing the moment it changes.
            message.audioPath = path;
        }
        onFailed: reason => root.addInterfaceMessage(reason)
    }

    function speakMessage(messageId) {
        const message = root.messageByID[messageId];
        if (!message) return;
        root.reader.speak(messageId, message.content);
    }

    /**
     * One-key dictation: open the tab and record, then stop and send on the next press.
     */
    function dictateToggle() {
        if (root.speech.transcribing) return; // Mid-transcription; let it finish.

        if (root.speech.recording) {
            root.speech.stopRecording(); // autoSend is already armed
            return;
        }

        GlobalStates.policiesPanelOpen = true;
        root.focusConduitTab();
        root.speech.autoSend = true;
        root.speech.startRecording();
    }

    /**
     * Conduit is the sidebar's first page when enabled, so there is nothing to count.
     * -1 when it is switched off and has no tab at all.
     */
    readonly property int conduitTabIndex: Config.options.conduit.enable ? 0 : -1

    function focusConduitTab() {
        if (root.conduitTabIndex < 0) return; // Disabled, leave the tab alone.
        Persistent.states.sidebar.policies.tab = root.conduitTabIndex;
    }

    /* ---------- Finished-turn notification ---------------------------------- *
     * Only worth sending when the answer is somewhere the user cannot see, which
     * means the sidebar is shut or it is showing a different tab. A popup for a
     * reply already on screen is pure noise.
     */

    readonly property bool viewingConduit: GlobalStates.policiesPanelOpen
        && root.conduitTabIndex >= 0
        && Persistent.states.sidebar.policies.tab === root.conduitTabIndex

    readonly property bool notifyWhenAway: Config.options.conduit.notifyWhenAway

    /**
     * The extension's own icon, resolved relative to this file so it works wherever the
     * extension happens to be installed.
     *
     * It goes in as the `image-path` hint, not as `-i`: the shell treats an app icon as a
     * freedesktop theme name and draws `image-missing` when it is not one — which a
     * Material Symbol name such as "chat" never is. The image hint takes a real file.
     */
    readonly property string notifyIconPath: {
        return CF.FileUtils.trimFileProtocol(Qt.resolvedUrl("../assets/icons/conduit.svg").toString());
    }

    property Process notifier: Process {}

    function notifyFinished(message) {
        if (!root.notifyWhenAway) return;
        // One line either way: "why didn't it notify" is otherwise invisible.
        if (root.viewingConduit) {
            console.log("[Conduit] No notification: the tab is on screen.");
            return;
        }

        const failed = (message?.error ?? "").length > 0;
        const body = failed ? message.error : (message?.content ?? "");
        const summary = body.replace(/\s+/g, " ").trim().slice(0, 140);

        notifier.command = ["notify-send",
            "-a", "Conduit",
            "-u", failed ? "critical" : "normal",
            "-h", `string:image-path:${root.notifyIconPath}`,
            // Replaces Conduit's own previous popup rather than stacking, on servers
            // that honour the hint.
            "-h", "string:x-canonical-private-synchronous:vynx-conduit",
            failed ? "Conduit — turn failed" : `Conduit — ${root.currentProvider.name} replied`,
            summary.length > 0 ? summary : "Finished."];
        notifier.running = true;
        console.log("[Conduit] Notification sent.");
    }

    property GlobalShortcut stopShortcut: GlobalShortcut {
        name: "conduitStop"
        description: "Conduit: stop the current response"
        onPressed: root.stop()
    }

    property GlobalShortcut dictateShortcut: GlobalShortcut {
        name: "conduitDictate"
        description: "Conduit: open and dictate, press again to send"
        onPressed: root.dictateToggle()
    }

    property IpcHandler ipc: IpcHandler {
        target: "conduit"

        function dictate(): void {
            root.dictateToggle();
        }
        function stop(): void {
            root.stop();
        }
        function open(): void {
            GlobalStates.policiesPanelOpen = true;
            root.focusConduitTab();
        }
    }

    /* ---------- Conversation state ---------------------------------------- */

    property var messageIDs: []
    property var messageByID: ({})
    property int nextMessageID: 0
    property bool responding: false
    property var tokenCount: ({ input: -1, output: -1 })
    property real lastCostUsd: -1
    property var rateLimit: ({ status: "", resetsAt: 0, kind: "" })

    /* ---------- Account limits ---------------------------------------------- *
     * Both CLIs can say how much of the subscription is left, and neither says it
     * the same way, so each strategy normalises its own report to percent
     * remaining. Asking costs a CLI invocation, so it is not done per turn: when
     * the tab opens, when asked, and after a turn only once what we have is stale.
     */

    property var limits: []              // [{ label, remaining, resets }]
    property real limitsCheckedAt: 0
    property bool limitsChecking: false
    property bool limitsReportPending: false

    readonly property int limitsStaleMinutes: 10

    // The binding constraint is whichever window has least left.
    readonly property var tightestLimit: root.limits.reduce((worst, entry) =>
        !worst || entry.remaining < worst.remaining ? entry : worst, null)

    function refreshLimits(force) {
        if (root.limitsChecking) return;

        const command = root.strategies[root.currentProviderId].usageCommand();
        if (command.length === 0) return;

        const age = Date.now() - root.limitsCheckedAt;
        if (force !== true && root.limitsCheckedAt > 0 && age < root.limitsStaleMinutes * 60000) return;

        root.limitsChecking = true;
        limitChecker.providerId = root.currentProviderId;
        limitChecker.command = ["bash", "-c", command];
        limitChecker.running = true;
    }

    function requestLimitsReport() {
        if (root.strategies[root.currentProviderId].usageCommand().length === 0) {
            root.addInterfaceMessage(`${root.currentProvider.name} cannot report account limits.`);
            return;
        }
        root.limitsReportPending = true;
        root.refreshLimits(true);
    }

    function reportLimits() {
        if (root.limits.length === 0) {
            root.addInterfaceMessage(`No limit information came back from \`${root.currentProvider.command}\`.`);
            return;
        }
        const rows = root.limits
            .map(entry => `| ${entry.label} | ${entry.remaining}% | ${entry.resets.length > 0 ? entry.resets : "—"} |`)
            .join("\n");
        root.addInterfaceMessage(`**${root.currentProvider.name}** account limits:\n\n| Window | Left | Resets |\n|---|---|---|\n${rows}`);
    }

    property Process limitChecker: Process {
        id: limitChecker
        property string providerId: ""

        stdout: StdioCollector {
            id: limitOutput
            onStreamFinished: {
                root.limitsChecking = false;

                // The provider may have been switched while this was in flight; its
                // numbers would belong to a different account.
                if (limitChecker.providerId === root.currentProviderId) {
                    let parsed = [];
                    try {
                        parsed = root.strategies[limitChecker.providerId].parseUsage(limitOutput.text) ?? [];
                    } catch (e) {
                        console.log("[Conduit] Could not read the usage report:", e);
                    }
                    if (parsed.length > 0) {
                        root.limits = parsed;
                        root.limitsCheckedAt = Date.now();
                    }
                }

                if (root.limitsReportPending) {
                    root.limitsReportPending = false;
                    root.reportLimits();
                }
            }
        }

        // Backstop: a process that dies without ever opening its stream must not leave
        // the check latched on.
        onExited: root.limitsChecking = false
    }

    function addMessage(content, role, visibleToUser = true) {
        const message = root.messageComponent.createObject(root, {
            "role": role,
            "content": content,
            "rawContent": content,
            "done": true,
            "visibleToUser": visibleToUser
        });
        return root.appendMessage(message);
    }

    function addInterfaceMessage(content) {
        return root.addMessage(content, root.interfaceRole);
    }

    function appendMessage(message) {
        const id = root.nextMessageID++;
        root.messageByID[id] = message;
        root.messageIDs = [...root.messageIDs, id];
        return id;
    }

    /* ---------- Assistant turn assembly ----------------------------------- *
     * A turn is an ordered list of parts, because the CLI interleaves text with
     * tool calls. Parts are QObjects so streaming mutates them in place; the
     * array is only reassigned when a part is added, which is what notifies the UI.
     */

    function appendPart(message, properties) {
        const part = root.partComponent.createObject(message, properties);
        message.parts = [...message.parts, part];
        return part;
    }

    function currentTextPart(message) {
        const parts = message.parts;
        const last = parts.length > 0 ? parts[parts.length - 1] : null;
        if (last && last.kind === "text") return last;
        return root.appendPart(message, { "kind": "text", "text": "" });
    }

    /**
     * Collapses a turn's parts into one string for request history and saved chats.
     * Tool calls become a one-line note: replaying full tool output into the next
     * prompt would balloon the context for no benefit.
     */
    function flattenParts(message) {
        let out = [];
        for (const part of message.parts) {
            if (part.kind === "text") {
                if (part.text.trim().length > 0) out.push(part.text);
            } else if (part.kind === "tool") {
                out.push(`_[${part.toolName}${part.toolInput ? " " + part.toolInput : ""}]_`);
            }
        }
        return out.join("\n\n");
    }

    function findToolPart(message, toolId) {
        return message.parts.find(part => part.kind === "tool" && part.toolId === toolId) ?? null;
    }

    function removeMessagesFrom(index) {
        if (index < 0 || index >= root.messageIDs.length) return;
        const removed = root.messageIDs.slice(index);
        root.messageIDs = root.messageIDs.slice(0, index);
        const remaining = Object.assign({}, root.messageByID);
        for (const id of removed) {
            remaining[id]?.destroy();
            delete remaining[id];
        }
        root.messageByID = remaining;
    }

    function sendUserMessage(text) {
        const trimmed = (text ?? "").trim();
        if (trimmed.length === 0) return;
        if (root.responding) {
            root.addInterfaceMessage("Still waiting on the previous response. Press stop first.");
            return;
        }
        const id = root.addMessage(trimmed, "user");
        const message = root.messageByID[id];

        if (root.pendingAttachments.length > 0) {
            const files = root.pendingAttachments;
            // What gets sent lives in rawContent; `content` stays clean for display.
            //
            // Sending deliberately avoids depending on a recently added property: types
            // reached through `import qs.services.conduit` are cached by the QML engine, so a
            // Reload can pair a new service with a stale message type.
            const list = files.map(path => `- ${path}`).join("\n");
            message.rawContent = `Attached files (read them before answering):\n${list}\n\n${trimmed}`;

            // Previews are a nicety, so they are allowed to be unavailable on a stale type.
            if ("attachments" in message) {
                message.attachments = files;
            } else {
                root.addInterfaceMessage("Files were sent, but showing them needs a shell restart (`Super+Ctrl+R`) — the message type is cached from an older reload.");
            }
            root.clearAttachments();
        }
        root.saveCurrentChat(); // listed straight away, even if the reply fails
        requester.makeRequest();
    }

    function regenerate() {
        // Walk back past the trailing assistant/interface turns to the last user message.
        let index = root.messageIDs.length - 1;
        while (index >= 0 && root.messageByID[root.messageIDs[index]].role !== "user") index--;
        if (index < 0) return;
        root.removeMessagesFrom(index + 1);
        // Replay from scratch: a resumed session would already contain the turn we dropped.
        root.resetSession();
        requester.makeRequest();
    }

    function stop() {
        if (!root.responding) return;
        requester.stopped = true;

        const pid = requester.processId;
        requester.signal(15); // Ask the process itself to wind down first.

        if (pid && pid > 1) {
            killer.command = ["bash", root.killerPath, String(pid)];
            killer.running = true;
        }
        killTimer.restart();
    }

    // If SIGTERM was ignored or the process wedged, don't leave an agent running.
    property Timer killTimer: Timer {
        id: killTimer
        interval: 3000
        onTriggered: {
            if (!root.responding) return;
            console.log("[Conduit] Response did not stop on SIGTERM; sending SIGKILL");
            requester.signal(9);
        }
    }

    function setProvider(providerId) {
        if (!root.providers[providerId]) {
            root.addInterfaceMessage(`Unknown provider "${providerId}". Available: ${root.providerIds.join(", ")}`);
            return;
        }
        Config.options.conduit.provider = providerId;
        Config.options.conduit.model = root.providers[providerId].models[0].value;
        root.limits = [];               // a different account's quota
        root.limitsCheckedAt = 0;
        root.resetSession(); // Sessions don't carry across providers
        root.addInterfaceMessage(`Provider set to ${root.providers[providerId].name}.`);
    }

    function setModel(modelId) {
        const listed = root.currentProvider.models.some(model => model.value === modelId);
        if (!listed && !root.supportsCustomModels) {
            root.addInterfaceMessage(`Unknown model "${modelId}" for ${root.currentProvider.name}.`);
            return;
        }
        Config.options.conduit.model = modelId;
        root.resetSession(); // A resumed CLI session keeps its original model
        root.addInterfaceMessage(listed
            ? `Model set to ${modelId}.`
            : `Model set to ${modelId}, which the picker does not list. Run \`${root.currentProvider.command} models\` to see the current names — a wrong one fails on the next message.`);
    }

    function setEffort(level) {
        if (!root.supportsEffortLevels) {
            root.addInterfaceMessage(`\`${root.currentProvider.command}\` has no effort flag — pick a model variant instead (see \`/model\`).`);
            return;
        }
        const value = (level ?? "").trim().toLowerCase();
        if (!root.effortLevels.some(entry => entry.value === value)) {
            root.addInterfaceMessage(`Unknown effort level "${level}". Try: ${root.effortLevels.map(entry => entry.value).join(", ")}.`);
            return;
        }
        Config.options.conduit.effort = value;
        root.resetSession(); // A resumed CLI session keeps its original effort
        root.addInterfaceMessage(`Effort set to **${value}**.`);
    }

    function setSystemPrompt(prompt) {
        const trimmed = (prompt ?? "").trim();
        if (trimmed.length === 0) {
            root.addInterfaceMessage(`Current system prompt:\n\n---\n\n${root.systemPrompt}`);
            return;
        }
        Config.options.conduit.systemPrompt = trimmed;
        root.addInterfaceMessage("System prompt updated.");
    }

    /* ---------- Request loop ---------------------------------------------- */

    readonly property string scriptDir: "/tmp/quickshell/vynx-conduit"
    readonly property string scriptPath: `${root.scriptDir}/request.sh`
    // The request body (or CLI prompt) is written here and read by the script, so
    // user-authored text is never escaped into a shell command line.
    readonly property string payloadPath: `${root.scriptDir}/payload`
    readonly property string killerPath: `${root.scriptDir}/stop.sh`

    // Session id for CLI-backed providers, so follow-up turns resume instead of replaying.
    property string cliSessionId: ""
    /**
     * Whether the CLI's current conversation already contains this transcript. A session
     * id alone does not answer that: a warmed-up process announces the id of an *empty*
     * conversation before a word has been sent, and trusting it would drop the history
     * of a restored chat on the floor.
     */
    property bool sessionPrimed: false

    property Process scriptDirProc: Process {
        command: ["mkdir", "-p", root.scriptDir]
        running: true
    }

    property FileView requesterScriptFile: FileView {}
    property FileView requesterPayloadFile: FileView {}
    property FileView killerScriptFile: FileView {}

    /**
     * Stop has to be absolute, because an agent with unattended tools may have spawned
     * long-running children of its own (a Bash tool running an install, say). Killing only
     * the process we spawned leaves those orphaned and still working.
     *
     * So: walk the whole descendant tree, SIGTERM it, then SIGKILL whatever survives. The
     * tree is collected BEFORE any signal is sent — once the parent dies its children are
     * reparented and can no longer be found by walking down from the root.
     *
     * Scoped strictly to descendants of the process we started, so unrelated `claude`
     * sessions elsewhere on the machine are never touched.
     */
    readonly property string killerScript: `#!/usr/bin/env bash
ROOT="$1"
[ -n "$ROOT" ] || exit 0
case "$ROOT" in ''|0|1) exit 0 ;; esac

collect() {
    local p="$1" c
    for c in $(pgrep -P "$p" 2>/dev/null); do collect "$c"; done
    printf '%s\n' "$p"
}

PIDS="$(collect "$ROOT")"
[ -n "$PIDS" ] || exit 0

kill -TERM $PIDS 2>/dev/null
sleep 1.5
for p in $PIDS; do
    kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null
done
exit 0
`

    property Process killer: Process {
        id: killer
        onExited: {
            // Never leave the UI stuck in a responding state, whatever the kill did.
            if (root.responding && requester.message) requester.markDone();
            root.responding = false;
        }
    }

    /** Everything a strategy needs, minus the turn itself. */
    function requestContext(history, cliHasHistory) {
        // Only widen the CLI's workspace when there is something in there to read.
        // Handing it a scratch directory it has no use for is an invitation to poke
        // at it, and a tool call against a temp path can fail the whole turn.
        const usesAttachments = history.some(message => (message.rawContent ?? "").indexOf(root.attachDir) >= 0);
        return {
            "provider": root.currentProvider,
            "modelId": root.currentModelId,
            "messages": history,
            "systemPrompt": root.systemPrompt,
            "payloadPath": root.payloadPath,
            "workingDir": root.workingDir,
            "attachDir": usesAttachments ? root.attachDir : "",
            "sessionId": root.cliSessionId,
            "effort": root.supportsEffortLevels ? root.effort : "",
            "enableTools": root.enableTools,
            "desktopMcp": (root.enableTools && root.desktopControl) ? root.desktopMcpPath : "",
            "permissionMode": root.permissionMode,
            "disallowedTools": root.disallowedTools,
            "continuing": cliHasHistory === true
        };
    }

    /**
     * Start the CLI before there is anything to ask it. Only the first turn of a process
     * pays the startup, so paying it when the tab is opened rather than when the user
     * presses Enter is most of the wait gone.
     */
    function warmUp() {
        if (!root.supportsPersistentProcess) return;
        if (requester.running || root.responding) return;

        const strategy = root.strategies[root.currentProviderId];
        const built = strategy.buildProcessScript(root.requestContext([], false));
        if (!built.script) return;

        requester.strategy = strategy;
        requester.turnKey = root.requestKey;
        requester.pendingLine = "";
        root.requesterScriptFile.path = Qt.resolvedUrl(root.scriptPath);
        root.requesterScriptFile.setText(built.script);
        requester.command = ["bash", root.scriptPath];
        requester.running = true;
    }

    property Process requester: Process {
        id: requester

        property var message: null
        property int messageId: -1
        property var strategy: null
        property bool stopped: false // Set by root.stop() so a cancel isn't reported as a failure

        // A persistent CLI takes its turns on stdin instead of from a file.
        stdinEnabled: root.supportsPersistentProcess
        // The settings the running process was launched with.
        property string turnKey: ""
        // Written once the process is up, since nothing can be sent before then.
        property string pendingLine: ""
        // Set while a process is being replaced, so its exit is not read as a failed turn.
        property bool restartPending: false
        // `running` goes true the moment it is asked for; this goes true only once the
        // process exists. Writing in between is writing into nothing.
        property bool processUp: false

        function makeRequest() {
            requester.strategy = root.strategies[root.currentProviderId];
            requester.strategy.reset();

            // Build the request from history BEFORE adding the placeholder, so the
            // empty assistant turn isn't sent along.
            const history = root.messageIDs
                .map(id => root.messageByID[id])
                .filter(message => message.role !== root.interfaceRole && !message.error);

            // A process launched with the current settings is still holding the
            // conversation, so the turn is one line on its stdin rather than a restart.
            const reusable = root.supportsPersistentProcess && requester.running
                && requester.turnKey === root.requestKey;
            // The CLI only has the earlier turns if we are talking to the same process
            // it primed, or if the conversation can still be resumed by id. Without that
            // second half, a process that failed to launch would leave the flag set and
            // the next attempt would send a follow-up with no conversation behind it.
            const cliHasHistory = root.sessionPrimed && (reusable || root.cliSessionId.length > 0);
            const context = root.requestContext(history, cliHasHistory);

            let built;
            if (reusable) {
                built = requester.strategy.buildTurnPayload(context);
            } else {
                built = requester.strategy.buildScript(context);
                if (!built.error && !built.script) built = { "error": "Could not build the request." };
            }

            if (built.error) {
                root.addInterfaceMessage(built.error);
                return;
            }
            // Whatever was just built carries everything the CLI still needed.
            root.sessionPrimed = true;

            requester.message = root.messageComponent.createObject(root, {
                "role": "assistant",
                "model": root.currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false
            });
            requester.messageId = root.appendMessage(requester.message);
            root.responding = true;
            requester.stopped = false;
            root.tokenCount = ({ input: -1, output: -1 });
            // Providers disagree on whether they report a price at all, so don't leave
            // one provider's figure sitting next to another's turn.
            root.lastCostUsd = -1;

            if (reusable) {
                // A warm process reports `running` long before the CLI is up — it takes
                // about ten seconds to reach its first init. Sending during that window
                // would drop the turn and leave the UI waiting on a reply that was never
                // delivered, so hand it to onStarted instead.
                if (requester.processUp) requester.write(built.payload ?? "");
                else requester.pendingLine = built.payload ?? "";
                return;
            }

            if (root.supportsPersistentProcess) {
                // Handed over once the process reports it has started.
                requester.pendingLine = built.payload ?? "";
            } else {
                root.requesterPayloadFile.path = Qt.resolvedUrl(root.payloadPath);
                root.requesterPayloadFile.setText(built.payload ?? "");
            }
            root.requesterScriptFile.path = Qt.resolvedUrl(root.scriptPath);
            root.requesterScriptFile.setText(built.script);
            requester.turnKey = root.requestKey;

            if (requester.running) {
                // Settings changed under a live process: replace it, and let onExited
                // start the replacement once this one is actually gone.
                requester.restartPending = true;
                requester.running = false;
                return;
            }
            requester.command = ["bash", root.scriptPath];
            requester.running = true;
        }

        onStarted: {
            requester.processUp = true;
            if (requester.pendingLine.length === 0) return;
            requester.write(requester.pendingLine);
            requester.pendingLine = "";
        }

        function markDone() {
            if (!requester.message) return;
            if (requester.reasoningOpen) {
                requester.reasoningOpen = false;
                root.currentTextPart(requester.message).text += "\n\n</think>\n\n";
            }
            requester.message.thinking = false;
            requester.message.done = true;
            // Flatten parts into `content` for request history and persistence.
            requester.message.content = root.flattenParts(requester.message);
            requester.message.rawContent = requester.message.content;
            root.responding = false;
            root.saveCurrentChat();
            // A turn the user cancelled is not something to tell them about.
            if (!requester.stopped) root.notifyFinished(requester.message);

            // Dictated turns get read back. Consumed either way: a stopped or empty
            // turn must not leave it armed for whatever is typed next.
            if (root.speakReply) {
                root.speakReply = false;
                if (!requester.stopped && requester.message.content.length > 0) {
                    root.speakMessage(requester.messageId);
                }
            }
            root.refreshLimits(false); // no-op unless what we have has aged out
        }

        // Tracks whether streamed reasoning is currently open, so it can be wrapped
        // in the <think></think> markers splitMarkdownBlocks() understands.
        property bool reasoningOpen: false

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0 || !requester.strategy) return;

                let result = {};
                try {
                    result = requester.strategy.parseLine(data, requester.message) ?? {};
                } catch (e) {
                    console.log("[Conduit] Failed to parse response line:", e);
                    return;
                }

                // Caught before the guard below: a warmed-up process announces its
                // conversation id long before there is a turn to attach it to.
                if (result.sessionId) root.cliSessionId = result.sessionId;

                const message = requester.message;
                if (!message) return;

                if (result.textDelta || result.thinkingDelta || result.toolStart || result.toolCalls) {
                    message.thinking = false;
                }

                if (result.newBlock === "text" && requester.reasoningOpen) {
                    requester.reasoningOpen = false;
                    root.currentTextPart(message).text += "\n\n</think>\n\n";
                }

                if (result.thinkingDelta) {
                    let part = root.currentTextPart(message);
                    if (!requester.reasoningOpen) {
                        requester.reasoningOpen = true;
                        part.text += "\n\n<think>\n\n";
                    }
                    part.text += result.thinkingDelta;
                }

                if (result.textDelta) {
                    if (requester.reasoningOpen) {
                        requester.reasoningOpen = false;
                        root.currentTextPart(message).text += "\n\n</think>\n\n";
                    }
                    root.currentTextPart(message).text += result.textDelta;
                }

                // A tool call ends reasoning just as plainly as text does — without this,
                // every thinking block that leads into a tool call (rather than straight
                // into the reply) is left with its <think> tag never closed, so
                // splitMarkdownBlocks() treats it as still-streaming and it never becomes
                // expandable in the UI.
                if ((result.toolStart || (result.toolCalls ?? []).length > 0) && requester.reasoningOpen) {
                    requester.reasoningOpen = false;
                    root.currentTextPart(message).text += "\n\n</think>\n\n";
                }

                // Announced with an empty input; arguments arrive in the assistant frame.
                if (result.toolStart) {
                    if (!root.findToolPart(message, result.toolStart.id)) {
                        root.appendPart(message, {
                            "kind": "tool",
                            "toolId": result.toolStart.id,
                            "toolName": result.toolStart.name,
                            "toolRunning": true
                        });
                    }
                }

                for (const call of result.toolCalls ?? []) {
                    let part = root.findToolPart(message, call.id);
                    if (!part) {
                        part = root.appendPart(message, { "kind": "tool", "toolId": call.id, "toolName": call.name, "toolRunning": true });
                    }
                    part.toolName = call.name;
                    part.toolInput = call.input;
                    if (call.fullInput !== undefined) part.toolFullInput = call.fullInput;
                }

                for (const toolResult of result.toolResults ?? []) {
                    const part = root.findToolPart(message, toolResult.id);
                    if (!part) continue;
                    part.toolResult = toolResult.content;
                    part.toolFailed = toolResult.failed;
                    part.toolRunning = false;
                }

                if (result.cost !== undefined) root.lastCostUsd = result.cost;
                if (result.rateLimit) root.rateLimit = result.rateLimit;
                if (result.error) message.error = result.error;

                if (result.tokenUsage) {
                    const usage = result.tokenUsage;
                    root.tokenCount = ({
                        input: usage.input !== undefined && usage.input >= 0 ? usage.input : root.tokenCount.input,
                        output: usage.output !== undefined && usage.output >= 0 ? usage.output : root.tokenCount.output
                    });
                }
                if (result.finished) requester.markDone();
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (data.trim().length === 0) return;
                console.log("[Conduit] stderr:", data);
                if (requester.message && !requester.message.error) {
                    requester.message.error = data.trim();
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            requester.processUp = false;
            if (requester.restartPending) {
                // Replaced on purpose; the new process carries the turn already built.
                requester.restartPending = false;
                requester.command = ["bash", root.scriptPath];
                requester.running = true;
                return;
            }
            if (!requester.message) {
                root.responding = false;
                return;
            }
            requester.strategy?.onFinished(requester.message);
            if (requester.message.done) return;

            if (requester.stopped) {
                // Cancelled on purpose: keep whatever streamed in, don't flag it as an error.
                requester.markDone();
                return;
            }
            if (exitCode !== 0 && !requester.message.error) {
                requester.message.error = `Request failed (exit ${exitCode}).`;
            }
            if (requester.message.content.length === 0 && !requester.message.error) {
                requester.message.error = `Empty response from \`${root.currentProvider.command}\`. Check that the model id is still valid; \`qs -c ii log\` has the detail.`;
            }
            requester.markDone();
        }
    }

    /* ---------- Chat history ------------------------------------------------ *
     * Each conversation is <id>.json in chatDir. index.json carries just enough
     * metadata to draw the list — title, timestamp, provider, model, preview — so
     * showing the history never has to open every conversation on disk.
     */

    readonly property string chatDir: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/conduit`)
    readonly property string chatIndexPath: `${root.chatDir}/index.json`

    // Metadata for every saved conversation, newest first.
    property var chats: []
    property string currentChatId: ""

    property Process chatDirProc: Process {
        command: ["mkdir", "-p", root.chatDir]
        running: true
    }

    property Process chatRemover: Process {}
    property FileView chatFile: FileView { printErrors: false }
    property FileView chatIndexFile: FileView { printErrors: false }

    function chatById(id) {
        return root.chats.find(chat => chat.id === id) ?? null;
    }

    /** First line of the opening question, which is what people actually recognise. */
    function deriveTitle() {
        for (const id of root.messageIDs) {
            const message = root.messageByID[id];
            if (!message || message.role !== "user") continue;
            const line = (message.content ?? "").trim().split("\n").find(part => part.trim().length > 0);
            if (!line) continue;
            const clean = line.trim();
            return clean.length > 60 ? `${clean.slice(0, 57)}…` : clean;
        }
        return "New conversation";
    }

    /** Tail of the conversation, so the list shows where it got to rather than where it began. */
    function derivePreview() {
        for (let i = root.messageIDs.length - 1; i >= 0; i--) {
            const message = root.messageByID[root.messageIDs[i]];
            if (!message || message.role === root.interfaceRole) continue;
            const text = (message.content ?? "").replace(/\s+/g, " ").trim();
            if (text.length === 0) continue;
            return text.length > 120 ? `${text.slice(0, 117)}…` : text;
        }
        return "";
    }

    function serializeChat() {
        return root.messageIDs.map(id => {
            const message = root.messageByID[id];
            return {
                "role": message.role,
                "content": message.content,
                "rawContent": message.rawContent,
                "attachments": message.attachments,
                "model": message.model,
                "error": message.error,
                "visibleToUser": message.visibleToUser,
                // An assistant turn renders from its parts, so the ordered text and tool
                // rows have to be stored too. `content` alone is only the flattened form
                // kept for request history, and restoring from it loses the tool rows.
                "parts": message.parts.map(part => ({
                    "kind": part.kind,
                    "text": part.text,
                    "toolId": part.toolId,
                    "toolName": part.toolName,
                    "toolInput": part.toolInput,
                    "toolFullInput": part.toolFullInput,
                    "toolResult": part.toolResult,
                    "toolFailed": part.toolFailed
                }))
            };
        });
    }

    function writeChatIndex() {
        root.chatIndexFile.path = Qt.resolvedUrl(root.chatIndexPath);
        root.chatIndexFile.setText(JSON.stringify(root.chats, null, 2));
    }

    function upsertChat(entry) {
        let out = root.chats.filter(chat => chat.id !== entry.id);
        out.push(entry);
        out.sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0));
        root.chats = out;
        root.writeChatIndex();
    }

    /**
     * Writes the conversation on screen. An id is minted on first save rather than when
     * the chat is opened, so an empty chat nobody typed into never reaches the list.
     */
    function saveCurrentChat() {
        const real = root.messageIDs.filter(id => root.messageByID[id]?.role !== root.interfaceRole);
        if (real.length === 0) return;

        if (root.currentChatId.length === 0) {
            root.currentChatId = `chat-${Date.now()}`;
            Config.options.conduit.currentChatId = root.currentChatId;
        }

        const existing = root.chatById(root.currentChatId);
        const entry = {
            "id": root.currentChatId,
            // A title the user typed themselves outranks anything derived from the text.
            "title": existing?.renamed === true ? existing.title : root.deriveTitle(),
            "renamed": existing?.renamed === true,
            "createdAt": existing?.createdAt ?? Date.now(),
            "updatedAt": Date.now(),
            "provider": root.currentProviderId,
            "model": root.currentModelId,
            "count": real.length,
            "preview": root.derivePreview()
        };

        root.chatFile.path = Qt.resolvedUrl(`${root.chatDir}/${root.currentChatId}.json`);
        root.chatFile.setText(JSON.stringify(Object.assign({}, entry, {
            "version": 2,
            "messages": root.serializeChat()
        }), null, 2));
        root.upsertChat(entry);
    }

    /** Wipe what is on screen without touching what is on disk. */
    function discardMessages() {
        for (const id of root.messageIDs) root.messageByID[id]?.destroy();
        root.messageIDs = [];
        root.messageByID = ({});
        root.resetSession();
        root.tokenCount = ({ input: -1, output: -1 });
        root.lastCostUsd = -1;
    }

    /**
     * Rebuilds an assistant turn's parts. Without this the turn carries its text in
     * `content`, which only user and interface turns are rendered from, so a restored
     * conversation shows the questions and nothing that answered them.
     */
    function restoreParts(message, entry) {
        if (message.role === "user" || message.role === root.interfaceRole) return;

        for (const part of (Array.isArray(entry.parts) ? entry.parts : [])) {
            root.appendPart(message, {
                "kind": part.kind ?? "text",
                "text": part.text ?? "",
                "toolId": part.toolId ?? "",
                "toolName": part.toolName ?? "",
                "toolInput": part.toolInput ?? "",
                "toolFullInput": part.toolFullInput ?? part.toolInput ?? "",
                "toolResult": part.toolResult ?? "",
                "toolFailed": part.toolFailed === true,
                "toolRunning": false // whatever it was doing finished long ago
            });
        }
    }

    function newChat() {
        root.saveCurrentChat(); // never lose the one being left behind
        root.currentChatId = "";
        Config.options.conduit.currentChatId = "";
        root.discardMessages();
    }

    function openChat(id) {
        if (id === root.currentChatId) return;
        if (!root.chatById(id)) return;
        root.saveCurrentChat();
        root.discardMessages();
        root.currentChatId = id;
        Config.options.conduit.currentChatId = id;
        root.chatLoader.path = Qt.resolvedUrl(`${root.chatDir}/${id}.json`);
        root.chatLoader.reload();
    }

    function renameChat(id, title) {
        const clean = (title ?? "").trim();
        if (clean.length === 0 || !root.chatById(id)) return;
        root.chats = root.chats.map(chat => chat.id === id
            ? Object.assign({}, chat, { "title": clean, "renamed": true })
            : chat);
        root.writeChatIndex();
    }

    function deleteChat(id) {
        if (!root.chatById(id)) return;
        root.chats = root.chats.filter(chat => chat.id !== id);
        root.writeChatIndex();
        chatRemover.command = ["rm", "-f", `${root.chatDir}/${id}.json`];
        chatRemover.running = true;
        if (id === root.currentChatId) {
            root.currentChatId = "";
            Config.options.conduit.currentChatId = "";
            root.discardMessages();
            }
    }

    // resetSession() kills the warm process, so put one back after the conversation
    // changes. Deferred because the old process takes a moment to actually go.
    property Timer warmTimer: Timer {
        id: warmTimer
        interval: 600
        onTriggered: root.warmUp()
    }

    /** Restores messages saved by saveCurrentChat. */
    property FileView chatLoader: FileView {
        onLoaded: {
            let saved;
            try {
                saved = JSON.parse(chatLoader.text());
            } catch (e) {
                console.log("[Conduit] Could not parse saved chat:", e);
                return;
            }

            const messages = saved.messages ?? [];
            if (!Array.isArray(messages)) return;

            for (const id of root.messageIDs) root.messageByID[id]?.destroy();
            root.messageIDs = [];
            root.messageByID = ({});
            root.resetSession(); // any CLI session from the saved run is stale

            for (const entry of messages) {
                const message = root.messageComponent.createObject(root, {
                    "role": entry.role ?? "user",
                    "content": entry.content ?? "",
                    "rawContent": entry.rawContent ?? entry.content ?? "",
                    "attachments": entry.attachments ?? [],
                    "model": entry.model ?? "",
                    "error": entry.error ?? "",
                    "visibleToUser": entry.visibleToUser ?? true,
                    "done": true
                });
                root.appendMessage(message);
                root.restoreParts(message, entry);
            }
        }
        onLoadFailed: error => {
            // A chat listed in the index but missing on disk: drop it rather than leave
            // a row that cannot be opened.
            if (root.currentChatId.length === 0) return;
            root.chats = root.chats.filter(chat => chat.id !== root.currentChatId);
            root.writeChatIndex();
            root.currentChatId = "";
        }
    }

    property FileView chatIndexLoader: FileView {
        printErrors: false // No index yet on a first run
        onLoaded: {
            try {
                const parsed = JSON.parse(chatIndexLoader.text());
                if (Array.isArray(parsed)) root.chats = parsed;
            } catch (e) {
                console.log("[Conduit] Could not parse the chat index:", e);
            }
            root.restoreChat();
        }
    }

    function restoreChat() {
        if (!root.restoreOnRestart || root.chats.length === 0) return;
        const stored = Config.options.conduit.currentChatId;
        const wanted = root.chatById(stored) ? stored : root.chats[0].id;
        root.currentChatId = wanted;
        root.chatLoader.path = Qt.resolvedUrl(`${root.chatDir}/${wanted}.json`);
        root.chatLoader.reload();
    }

    property Timer restoreTimer: Timer {
        interval: 250
        running: true
        onTriggered: {
            root.chatIndexLoader.path = Qt.resolvedUrl(root.chatIndexPath);
            root.chatIndexLoader.reload();
        }
    }

    Component.onCompleted: {
        // Written once, and takes the pid as an argument, so nothing is ever interpolated
        // into it at stop time.
        root.killerScriptFile.path = Qt.resolvedUrl(root.killerPath);
        root.killerScriptFile.setText(root.killerScript);
    }
}
