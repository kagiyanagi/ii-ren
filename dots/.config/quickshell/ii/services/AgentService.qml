pragma Singleton
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import qs.services.agent
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtMultimedia
import "speechMatch.js" as SpeechMatch
import "readingTimeline.js" as Timeline

/**
 * The left sidebar's agent: Claude Code, Codex or Antigravity, whichever the user has
 * signed in to.
 *
 * The agent is the vendor's own program, run unmodified under the user's own login --
 * the only way their plan's limits apply. For Antigravity that is Google's ACP
 * server, not the `agy` CLI: Google does not allow wrapping the CLI, and ships the
 * server for other apps to drive. scripts/agent/bridge.py starts it and
 * translates: one stdio process speaking line-delimited JSON-RPC, no port, and it
 * dies with the shell. Frames are a response (`id` set), an event
 * (`{method: "event", params: {type, payload}}`), or a question for the user
 * (`approval`, `clarify`) carrying an id the answer must echo.
 *
 * What a given agent can do arrives with its `ready` event as `capabilities`, and
 * the page only offers what is there (`can()`); nothing is faked for an agent that
 * lacks it.
 */
Singleton {
    id: root

    /**
     * Instantiates the singleton at shell start so the global shortcuts and the IPC
     * handler register without waiting for the page to be opened. Nothing else runs
     * then: the bridge, and even the look for which agents are installed, wait for
     * ensureStarted().
     */
    function load(): void {}

    readonly property string interfaceRole: "interface"
    readonly property string bridgeScript: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/agent/bridge.py"))

    readonly property bool enabled: Config.options?.agent?.enable ?? false

    // ── Connection ───────────────────────────────────────────────────────

    property bool starting: false
    property bool ready: false
    property string lastError: ""
    // Set when no agent CLI is installed: retrying cannot fix that, so the page
    // shows how to get one instead of a spinner.
    property bool missing: false

    property int consecutiveFailures: 0
    readonly property int maxRestarts: 3

    // ── Agent ────────────────────────────────────────────────────────────
    //
    // Which agent answers. Only those found here are offered, so the menu never
    // lists an agent that cannot start; the probe settles a moment after the first
    // open. Settings > Agent turns agents off, points at another program, and
    // signs them in (services/AgentSetup.qml, in the settings app's own process).
    // Antigravity is offered with the `agy` CLI installed even before Google's ACP
    // server is: the bridge downloads that on first use, and the row says so.
    readonly property var knownBackends: [
        { id: "claude", commands: ["claude"], label: "Claude Code", plan: Translation.tr("Uses your Claude plan") },
        { id: "codex", commands: ["codex"], label: "Codex", plan: Translation.tr("Uses your ChatGPT plan") },
        { id: "antigravity", commands: ["agy", "agy_acp_server", "@installed"], label: "Antigravity", plan: Translation.tr("Uses your Google AI plan"),
          firstUse: Translation.tr("Uses your Google AI plan. First use downloads Google's agent server (about 340 MB)") }
    ]
    property var backends: []
    property bool backendsProbed: false
    readonly property var backend: root.backends.find(b => b.id === (Persistent.states?.agent?.backend ?? "")) ?? root.backends[0] ?? null
    readonly property string agentName: root.backend?.label ?? Translation.tr("Agent")
    // Every agent turned off in Settings, as opposed to none installed.
    readonly property bool allDisabled: root.knownBackends.every(b => !(Config.options?.agent?.[b.id]?.enable ?? true))
    property bool _restarting: false
    property bool _startWhenProbed: false

    // What this agent can genuinely do, from its ready event.
    property var capabilities: ({})
    // The subscription the agent reports, when it does (Antigravity: "Google AI Pro").
    property string planName: ""
    // What the agent is doing before it can answer: a first-use download, a
    // sign-in it is waiting on. Shown in the activity line until cleared.
    property string setupText: ""
    function can(feature: string): bool {
        return root.capabilities?.[feature] === true;
    }

    function setBackend(id: string): void {
        // Before the first start nothing has looked for the agents: keep the
        // choice for when something does.
        if (!root.backendsProbed) {
            if (root.knownBackends.some(b => b.id === id))
                Persistent.states.agent.backend = id;
            return;
        }
        if (id === root.backend?.id || !root.backends.some(b => b.id === id))
            return;
        Persistent.states.agent.backend = id;
        if (root.busy)
            root.interrupt();
        root._forgetAgent();
        root._restart();
    }

    /** Everything that belonged to the agent that was answering. */
    function _forgetAgent(): void {
        root.clearMessages();
        root.sessionTitle = "";
        root.recentSessions = [];
        root.providers = [];
        root.slashCommands = [];
        root.currentModel = "";
        root.currentProvider = "";
        root.currentEffort = "";
        root.approvalMode = "";
        root.capabilities = ({});
        root.planName = "";
        root.setupText = "";
        root.usageLimits = null;
        root.lastError = "";
        root.consecutiveFailures = 0;
        restartTimer.stop();
    }

    /** A fresh bridge on the agent and settings now in force. */
    function _restart(): void {
        // The old process has to be gone before the new one starts; onExited
        // picks the restart up rather than counting it as a crash.
        if (bridgeProc.running) {
            root._restarting = true;
            bridgeProc.running = false;
        } else if (root.enabled) {
            root.ensureStarted();
        }
    }

    // ── Settings > Agent ─────────────────────────────────────────────────

    function _expandHome(path: string): string {
        return path.replace(/^~(?=\/|$)/, FileUtils.trimFileProtocol(Directories.home));
    }

    // What the probe looks for: each agent Settings has not turned off, as the
    // program Settings points at, else its usual names on PATH. "@installed" is a
    // server the bridge or Settings downloaded.
    readonly property var _probeTargets: {
        const out = [];
        for (const b of root.knownBackends) {
            const settings = Config.options.agent[b.id];
            if (!settings.enable)
                continue;
            const custom = root._expandHome(settings.binary.trim());
            (custom.length > 0 ? [custom] : b.commands).forEach(c => out.push(`${b.id}=${c}`));
        }
        return out;
    }

    // What the bridge reads as it starts: bridge.agent_binary, desktop_tools and
    // antigravity_backend.find_server. Null unsets, so an empty field means the
    // usual program again.
    readonly property var _bridgeEnv: {
        const agent = Config.options.agent;
        const path = id => root._expandHome(agent[id].binary.trim()) || null;
        return {
            "AGENT_CLAUDE_BIN": path("claude"),
            "AGENT_CODEX_BIN": path("codex"),
            "AGENT_ANTIGRAVITY_SERVER": path("antigravity"),
            "AGENT_DESKTOP_TOOLS": agent.desktopTools ? "1" : "0"
        };
    }
    readonly property string _bridgeEnvKey: JSON.stringify(root._bridgeEnv)
    // What the running bridge was started on, to tell a change from a re-read.
    property string _launchedId: ""
    property string _launchedEnv: ""
    // Settings' account changes for this agent: a restart even with nothing else new.
    property string _restartFor: ""
    property bool _restartWhenIdle: false
    // The chat to reopen once the restarted bridge is ready.
    property string _resumeAfterStart: ""

    // Before the first open nothing has been looked for, and a settings change
    // starts nothing either (tools/check-sidebar-boot.py). After it, look again.
    readonly property string _launchSettings: JSON.stringify(root._probeTargets) + root._bridgeEnvKey
    on_LaunchSettingsChanged: {
        if (root.backendsProbed)
            backendProbe.refresh();
    }

    /** Settings signed `id` in or out, installed or removed it (the `agent refresh` IPC). */
    function refreshFromSettings(id: string): void {
        if (!root.backendsProbed)
            return;
        root._restartFor = id;
        backendProbe.refresh();
    }

    /** The probe has answered again: bring the bridge in line with it. */
    function _applySettings(): void {
        const forced = root._restartFor.length > 0 && root._restartFor === root._launchedId;
        root._restartFor = "";
        if (!bridgeProc.running) {
            // Stopped for something a restart could not fix -- not installed,
            // signed out -- and the new settings may be the fix.
            if (root.enabled && !root.missing && !root.starting) {
                root.consecutiveFailures = 0;
                restartTimer.stop();
                root.ensureStarted();
            }
            return;
        }
        if (!forced && root.backend?.id === root._launchedId && root._bridgeEnvKey === root._launchedEnv)
            return;
        root._restartForSettings();
    }

    function _restartForSettings(): void {
        // Mid-reply, or waiting on the user: the new settings wait for it to end.
        if (root.busy || root.pendingApproval || root.pendingClarify) {
            root._restartWhenIdle = true;
            return;
        }
        root._restartWhenIdle = false;
        if (root.backend?.id === root._launchedId)
            root._resumeAfterStart = root.storedSessionId;
        else
            root._forgetAgent();
        root._restart();
    }
    onBusyChanged: {
        if (!root.busy && root._restartWhenIdle)
            Qt.callLater(root._restartForSettings);
    }

    RefreshProcess {
        id: backendProbe
        running: false // ensureStarted() runs it first; a settings change, again
        // Each target is `id=program`: printed as `id program` when it runs.
        command: ["sh", "-c", 'for a in "$@"; do id=${a%%=*}; c=${a#*=}; '
            + 'if [ "$c" = @installed ]; then '
            + 'for f in "${XDG_DATA_HOME:-$HOME/.local/share}"/quickshell/agent/antigravity-acp/*/.complete; do [ -f "$f" ] && echo "$id antigravity-server" && break; done; '
            + 'elif command -v "$c" >/dev/null 2>&1; then echo "$id $c"; fi; done',
            "sh", ...root._probeTargets]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                for (const line of this.text.split("\n").map(l => l.trim())) {
                    const cut = line.indexOf(" ");
                    if (cut <= 0)
                        continue;
                    const id = line.slice(0, cut);
                    found[id] = (found[id] ?? []).concat([line.slice(cut + 1)]);
                }
                const firstProbe = !root.backendsProbed;
                root.backends = root.knownBackends.filter(b => found[b.id]).map(b => {
                    // A server on PATH, one downloaded here ("antigravity-server") or
                    // one Settings points at: nothing left to download.
                    const serverHere = found[b.id].some(what => what !== "agy");
                    return Object.assign({}, b, { plan: b.firstUse && !serverHere ? b.firstUse : b.plan });
                });
                // The shell's start is the first probe: it starts on the default
                // agent, if Settings names one; the menu still switches after.
                const preferred = Config.options.agent.defaultBackend;
                if (firstProbe && root.backends.some(b => b.id === preferred))
                    Persistent.states.agent.backend = preferred;
                root.backendsProbed = true;
                root.missing = root.backends.length === 0;
                if (root._startWhenProbed) {
                    root._startWhenProbed = false;
                    root.ensureStarted();
                } else if (!firstProbe) {
                    root._applySettings();
                }
            }
        }
    }

    // ── Session ──────────────────────────────────────────────────────────

    property string sessionId: ""
    property string storedSessionId: ""
    property string sessionTitle: ""
    property string cwd: ""
    property bool busy: false
    // Transient one-liner from the agent ("(´･_･`) reasoning...", "Resuming…").
    property string statusText: ""

    // ── What the session is running with ─────────────────────────────────

    property string currentModel: ""
    property string currentProvider: ""
    // Reasoning effort, as the agent's own id ("high", "xhigh"...; "default" for
    // Claude Code's model default). Empty for a model that takes none.
    property string currentEffort: ""
    property string approvalMode: ""

    // ── Inventory ────────────────────────────────────────────────────────

    property var providers: []
    property bool providersLoading: false
    // The levels the current model takes, read off the same inventory as the model
    // picker; empty for a model with none, which hides the effort chip.
    readonly property var effortOptions: {
        const provider = root.providers.find(p => p.slug === root.currentProvider || p.name === root.currentProvider) ?? root.providers[0];
        return provider?.capabilities?.[root.currentModel]?.efforts ?? [];
    }
    readonly property string currentEffortLabel: root.effortOptions.find(option => option.id === root.currentEffort)?.label ?? ""
    property var slashCommands: []
    property var recentSessions: []

    // ── Plan limits ──────────────────────────────────────────────────────
    //
    // The plan's own windows (5-hour, weekly) as the agent reports them about
    // itself -- see bridge.py "Plan limits". Fetched once a chat is open and when
    // the usage button is opened; the bridge pushes changes as replies spend them.
    property var usageLimits: null
    property bool limitsLoading: false
    readonly property var limitWindows: root.usageLimits?.windows ?? []

    // ── Transcript ───────────────────────────────────────────────────────

    property var messageIDs: []
    property var messageByID: ({})
    property string streamingId: ""

    // ── Voice ──────────────────────────────────────────────────────
    //
    // Both ends are the shell's own: dictation records with pw-record and
    // transcribes with whisper.cpp (or, opted into, Groq's hosted Whisper),
    // read-aloud synthesizes with edge-tts. Neither is required -- each control
    // shows only when its engine is there.
    readonly property bool dictationAvailable: root.speech.available || root.speech.downloading
    // whisper.cpp is on this machine at all, or dictation is online; the mic is
    // offered only then.
    readonly property bool dictationInstalled: root.speech.online || root.speech.binary.length > 0
    readonly property string voiceState: root.speech.recording ? "listening" : root.speech.transcribing ? "transcribing" : "idle"
    readonly property bool dictating: root.voiceState !== "idle"

    // Emitted with a finished transcript so the page can put it in the input box.
    signal dictationTranscript(string text)

    // An undone turn's text, handed back to edit rather than send.
    signal composerPrefill(string text)

    // A staged file's `@file:` reference. Appended rather than prefilled: dropping
    // three files has to leave three refs in the box, and a prefill would keep
    // only the last one.
    signal composerAppend(string text)

    // An attachment's chip in the composer, placed where the caret was, and taken
    // back out if the attachment goes before sending.
    signal composerInsert(string text)
    signal composerRemove(string text)

    /*
     * Composer token -> { kind, name, send, paths, icon, thumb }. kind is image,
     * file or folder; paths are the images it staged on the session; thumb is the
     * picture a tile shows, empty for a file. A token is the name bracketed
     * with U+2063, led by figure spaces the chip's icon sits on, and made of
     * non-breaking characters so it never wraps; AgentAttachmentChips draws the
     * chip behind it. Sending swaps it for `send`, which is what the model reads.
     */
    property var composerMarkers: ({})

    function _addMarker(kind: string, name: string, send: string, paths: var): void {
        const shown = name.length > 28 ? name.slice(0, 27) + "…" : name;
        // Four figure spaces hold the icon and the gap after it; the one at the end is
        // the chip's right padding. Spaces are U+202F, not U+00A0: a plain TextArea
        // hands U+00A0 back as a plain space, which read as an edit inside the token
        // and deleted it, so a second paste of one name never stayed.
        const base = "\u2063\u2007\u2007\u2007\u2007" + shown.replace(/ /g, "\u202f").replace(/-/g, "\u2011");
        let token = base + "\u2007\u2063";
        for (let n = 2; root.composerMarkers[token]; n++)
            token = `${base}\u2007${n}\u2007\u2063`;
        root.composerMarkers = Object.assign({}, root.composerMarkers, { [token]: root._marker(kind, name, send, paths) });
        root.attachedImages = [...root.attachedImages, ...paths];
        root.composerInsert(token);
    }

    function _marker(kind: string, name: string, send: string, paths: var): var {
        const icon = kind === "folder" ? "folder" : FileUtils.iconForFile(name);
        const thumb = kind === "image" ? (paths[0] ?? "") : "";
        return { kind, name, send, paths, icon, thumb };
    }

    /**
     * A stored user turn, back as { text, attachments }: the text is what was sent,
     * which is each chip's `send` -- `[Image: name]`, `@file:path`, `@folder:path`
     * -- so the chips come back from the text alone. An image's pixels went to the
     * agent, not into the text, so a restored image chip has no thumbnail.
     * tools/check-agent-composer.py runs this.
     */
    function _restoredTurn(body: string): var {
        const text = body.trim();
        const attachments = [];
        // An exec loop: the shell's JS engine has no matchAll
        const refs = /\[Image: ([^\]\n]+)\]|@(file|folder):("[^"\n]+"|`[^`\n]+`|'[^'\n]+'|\S+)/g;
        for (let match = refs.exec(text); match !== null; match = refs.exec(text)) {
            if (attachments.some(item => item.send === match[0]))
                continue;
            if (match[1]) {
                attachments.push(root._marker("image", match[1], match[0], []));
            } else {
                const path = match[3].replace(/^["'`]|["'`]$/g, "");
                attachments.push(root._marker(match[2], match[2] === "folder" ? FileUtils.folderNameForPath(path) : FileUtils.fileNameForPath(path), match[0], []));
            }
        }
        return { text, attachments };
    }

    /** The chip's text is gone from the composer: unstage what it carried. */
    function dropMarker(token: string): void {
        const marker = root.composerMarkers[token];
        if (!marker)
            return;
        const next = Object.assign({}, root.composerMarkers);
        delete next[token];
        root.composerMarkers = next;
        // The bridge detaches every copy of a path, so one pasted twice stays
        // staged while the other chip holds it
        const kept = Object.values(next).reduce((all, item) => all.concat(item.paths), []);
        marker.paths.filter(path => !kept.includes(path))
            .forEach(path => root.call("image.detach", { session_id: root.sessionId, path: path }, null));
        root.attachedImages = root.attachedImages.filter(item => !marker.paths.includes(item) || kept.includes(item));
    }

    /** A tile's X: the chip leaves the composer, and what it carried the session. */
    function removeMarker(token: string): void {
        root.composerRemove(token);
        root.dropMarker(token);
    }

    /** `text` with each chip swapped for what the model reads. */
    function _expandMarkers(text: string): string {
        return text.replace(/\u2063[^\u2063]*\u2063/g, token => root.composerMarkers[token]?.send ?? "");
    }

    // ── Approvals ────────────────────────────────────────────────────────

    // Non-null while the agent is parked waiting for the user to allow a tool.
    property var pendingApproval: null

    // Non-null while the agent has stopped to ask a question.
    // Payload is either {question, choices, multi_select, request_id} or a batch
    // {questions: [{qid, question, choices, multi_select}], request_id}.
    property var pendingClarify: null

    property Component messageComponent: AgentMessageData {}

    signal transcriptCleared

    // ── JSON-RPC plumbing ────────────────────────────────────────────────

    property int _nextRequestId: 1
    // id -> callback(result, error). Plain object: nothing binds to it.
    property var _pendingCalls: ({})
    property var _queuedCalls: []

    function ensureStarted(): void {
        if (!root.backendsProbed) {
            root._startWhenProbed = true;
            backendProbe.running = true;
            return;
        }
        if (root.missing || !root.backend || bridgeProc.running || root.starting)
            return;
        root.starting = true;
        root.lastError = "";
        root._launchedId = root.backend.id;
        root._launchedEnv = root._bridgeEnvKey;
        bridgeProc.running = true;
    }

    /** Fire a JSON-RPC call; `callback(result, error)` runs when it answers. */
    function call(method: string, params: var, callback: var): void {
        const frame = {
            jsonrpc: "2.0",
            id: `ii-${root._nextRequestId++}`,
            method: method,
            params: params ?? {}
        };
        if (callback)
            root._pendingCalls[frame.id] = callback;

        // Before `ready` the bridge either is not up or has not finished starting
        // the agent; either way stdin writes would be lost.
        if (!root.ready) {
            root._queuedCalls.push(frame);
            root.ensureStarted();
            return;
        }
        bridgeProc.write(JSON.stringify(frame) + "\n");
    }

    function _drainQueue(): void {
        const queued = root._queuedCalls;
        root._queuedCalls = [];
        queued.forEach(frame => bridgeProc.write(JSON.stringify(frame) + "\n"));
    }

    // ── Transcript helpers ───────────────────────────────────────────────

    function _newMessage(role: string, content: string): string {
        const message = root.messageComponent.createObject(root, {
            role: role,
            content: content ?? "",
            model: root.currentModel,
            done: role !== "assistant",
            createdAt: Date.now()
        });
        const id = `agent-${root.messageIDs.length}-${Date.now()}`;
        root.messageByID[id] = message;
        root.messageIDs = [...root.messageIDs, id];
        return id;
    }

    // The attachments go with the turn that consumes them, so the bubble can show
    // them after the send has cleared the composer.
    function _newUserMessage(content: string): string {
        const id = root._newMessage("user", content);
        root.messageByID[id].attachments = Object.values(root.composerMarkers);
        return id;
    }

    function addMessage(content: string, role: string): void {
        root._newMessage(role ?? root.interfaceRole, content);
    }

    function clearMessages(): void {
        root.messageIDs.forEach(id => root.messageByID[id]?.destroy());
        root.messageByID = ({});
        root.messageIDs = [];
        root.streamingId = "";
        root._releaseRun();
        root.pendingApproval = null;
        root.pendingClarify = null;
        root.transcriptCleared();
    }

    property var streamingMessage: root.messageByID[root.streamingId] ?? null

    /*
     * A run is everything the agent does to answer one request, and it is what the
     * transcript shows as one card.
     *
     * The bridge's message.start/message.complete bracket a single *model* turn,
     * not a run: an agentic answer is turn (text, calls tools) -> tools run -> turn
     * (text) -> tools -> turn (final text). Opening a fresh bubble on every
     * message.start split one answer into three stacked cards, each with its own
     * header and its own copy/retry buttons, and left the reader to work out which
     * commands belonged to which paragraph.
     *
     * So the run's card is held here and later turns continue it. It is released
     * when the user speaks again, which is the only unambiguous end of a run --
     * the protocol has no run-level event.
     */
    property string _runMessageId: ""
    // Where the current model turn's text starts inside that card, so a
    // message.complete carrying the turn's full text replaces its own segment
    // instead of overwriting everything said before it.
    property int _runSegmentStart: 0
    // Whether this turn called anything. A turn that ends without tool calls is the
    // end of the agent loop; one that ends with them is going to continue.
    property bool _runSegmentUsedTools: false

    function _releaseRun(): void {
        root._runMessageId = "";
        root._runSegmentStart = 0;
        root._runSegmentUsedTools = false;
    }

    // ── Session lifecycle ────────────────────────────────────────────────

    function createSession(): void {
        // Settings > Agent's default model and instructions, for this chat on.
        const settings = { model: Config.options.agent[root._launchedId]?.model ?? "", instructions: Config.options.agent.instructions };
        root.call("session.create", settings, (result, error) => {
            if (error) {
                root.lastError = error.message ?? "session.create failed";
                return;
            }
            root._adoptSession(result);
            root.refreshProviders();
            root.refreshSlashCommands();
            root.refreshUsageLimits(false);
        });
    }

    function _adoptSession(result: var): void {
        root.sessionId = result.session_id ?? "";
        root.storedSessionId = result.stored_session_id ?? "";
        root._applyInfo(result.info ?? {});
        root.busy = false;
    }

    function _applyInfo(info: var): void {
        if (!info)
            return;
        if (info.model !== undefined)
            root.currentModel = info.model ?? "";
        if (info.plan !== undefined)
            root.planName = info.plan ?? "";
        if (info.provider !== undefined)
            root.currentProvider = info.provider ?? "";
        if (info.approval_mode !== undefined)
            root.approvalMode = info.approval_mode ?? "";
        if (info.effort !== undefined)
            root.currentEffort = info.effort ?? "";
        if (info.cwd !== undefined)
            root.cwd = info.cwd ?? "";
    }

    /** Fresh session, fresh transcript. */
    function newSession(): void {
        if (root.busy)
            root.interrupt();
        const previous = root.sessionId;
        root.sessionId = "";
        root.sessionTitle = "";
        root.clearMessages();
        if (previous.length > 0)
            root.call("session.close", { session_id: previous }, null);
        root.createSession();
    }

    function resumeSession(storedId: string): void {
        if (storedId.length === 0)
            return;
        if (root.busy)
            root.interrupt();
        root.clearMessages();
        root.call("session.resume", { session_id: storedId, instructions: Config.options.agent.instructions }, (result, error) => {
            if (error) {
                root.addMessage(Translation.tr("Could not resume: %1").arg(error.message ?? ""), root.interfaceRole);
                return;
            }
            root._adoptSession(result);
            root._restoreTranscript(result);
            root.refreshRecentSessions();
        });
    }

    /** Drop a stored session; the live one is rolled over to a fresh chat first. */
    function deleteSession(storedId: string): void {
        if ((storedId ?? "").length === 0)
            return;
        if (storedId === root.storedSessionId)
            root.newSession();
        root.call("session.delete", { session_id: storedId }, (result, error) => {
            if (error) {
                root.addMessage(error.message ?? Translation.tr("Could not delete that chat"), root.interfaceRole);
                return;
            }
            root.refreshRecentSessions();
        });
    }

    /**
     * Rebuild the transcript from a resumed session.
     *
     * Stored rows are NOT shaped like the live event stream: the body is `text`,
     * and a tool call is its own row with role "tool" rather than something hanging
     * off the assistant turn, so they are folded back into run cards here.
     */
    function _restoreTranscript(result: var): void {
        let lastAssistantId = "";

        const restored = (role, body) => {
            const id = root._newMessage(role, body);
            const message = root.messageByID[id];
            message.createdAt = 0;
            message.completedAt = 0;
            return id;
        };

        (result.messages ?? []).forEach(entry => {
            const role = entry.role ?? "";

            if (role === "tool") {
                // Attach to the turn that called it, so it renders in the same
                // ToolActivityRow the live stream produces.
                if (lastAssistantId.length === 0)
                    lastAssistantId = restored("assistant", "");
                const message = root.messageByID[lastAssistantId];
                if (!message)
                    return;
                message.toolCalls = [...message.toolCalls, {
                    // Stored rows arrive in order and attach to the turn they
                    // followed, so the end of that turn's text is where they ran.
                    contentMark: (message.content ?? "").length,
                    toolId: "",
                    toolName: entry.name ?? "tool",
                    toolInput: entry.context ?? "",
                    toolFullInput: root._formatToolArgs(entry.args ?? ({})),
                    // The arguments themselves, which the row lays out and highlights.
                    toolArgs: entry.args ?? null,
                    // session.resume returns a tool row as {role, name, context,
                    // args}: a resumed chat shows the call, not what it returned.
                    toolResult: "",
                    toolExitCode: null,
                    duration: 0,
                    toolRunning: false,
                    toolFailed: false
                }];
                message.done = true;
                return;
            }

            const body = (entry.text ?? entry.content ?? "").toString();
            if (body.trim().length === 0)
                return; // No empty bubbles for rows that carry no prose.

            if (role === "user") {
                const turn = root._restoredTurn(body);
                const userId = restored("user", turn.text);
                root.messageByID[userId].attachments = turn.attachments;
                root.messageByID[userId].done = true;
                lastAssistantId = ""; // A request starts a new run.
                return;
            }

            // Consecutive assistant rows are the turns of one run, so they rebuild
            // into the single card the live stream would have produced.
            const open = root.messageByID[lastAssistantId] ?? null;
            if (open) {
                open.content += open.content.length > 0 ? `\n\n${body}` : body;
                open.done = true;
                return;
            }
            const id = restored("assistant", body);
            root.messageByID[id].done = true;
            lastAssistantId = id;
        });

        // Say so rather than silently showing a conversation that starts mid-thought.
        const omitted = result.messages_omitted ?? 0;
        if (omitted > 0)
            root.addMessage(Translation.tr("%1 earlier messages are in the agent's context but not shown here.").arg(omitted), root.interfaceRole);
    }

    function refreshRecentSessions(): void {
        root.call("session.list", { limit: 30 }, (result, error) => {
            if (error)
                return;
            root.recentSessions = result.sessions ?? [];
        });
    }

    function refreshUsageLimits(force: bool): void {
        if (!root.can("limits") || root.limitsLoading)
            return;
        root.limitsLoading = true;
        root.call("usage.limits", { refresh: force }, (result, error) => {
            root.limitsLoading = false;
            if (!error)
                root.usageLimits = result;
        });
    }

    // ── Settings the agent owns ───────────────────────────────────────────

    function setConfig(key: string, value: var, callback: var): void {
        root.call("config.set", { key: key, value: value, session_id: root.sessionId }, (result, error) => {
            if (error)
                root.addMessage(error.message ?? Translation.tr("%1 would not take that setting.").arg(root.agentName), root.interfaceRole);
            if (callback)
                callback(error ? null : result);
        });
    }

    /** manual | smart | off. The session info event echoes the change back. */
    function setApprovalMode(mode: string): void {
        root.setConfig("approvals.mode", mode, null);
    }

    // ── Per-message actions ────────────────────────────────────────

    // Which turn we asked to be read out. There is no "speech finished" event on
    // the wire (tts_done_event stays inside the agent), so this is what we asked
    // for rather than what is provably still playing -- pressing stop after it has
    // already ended is harmless.
    property string speakingMessageId: ""

    /** Read one message out loud. */
    function speakMessage(id: string): void {
        const body = root.messageByID[id]?.content ?? "";
        if (body.trim().length === 0)
            return;
        root.speakingMessageId = id;
        root.speak(body);
    }

    // Marks a reading that belongs to no particular turn. `speakingMessageId`
    // doubles as the "a reading is still wanted" flag that `_onSpoken` checks
    // before it plays anything, so reading a selection has to set it too; a
    // sentinel that cannot collide with a real id keeps every per-message speak
    // button dark while a selection is the thing being read.
    readonly property string selectionSpeechId: "__selection__"

    /** Read an arbitrary passage out loud -- a selection rather than a whole turn. */
    function speakText(text: string): void {
        if ((text ?? "").trim().length === 0)
            return;
        root.speakingMessageId = root.selectionSpeechId;
        root.speak(text);
    }


    function removeMessagesFrom(index: int): void {
        if (index < 0 || index >= root.messageIDs.length)
            return;
        const dropped = root.messageIDs.slice(index);
        const kept = root.messageIDs.slice(0, index);
        const byID = Object.assign({}, root.messageByID);
        dropped.forEach(id => {
            byID[id]?.destroy();
            delete byID[id];
        });
        root.messageByID = byID;
        root.messageIDs = kept;
        if (dropped.includes(root.streamingId))
            root.streamingId = "";
        if (dropped.includes(root._runMessageId))
            root._releaseRun();
    }

    /**
     * Re-run the last turn. The agent rewinds its own history to before that
     * request and asks it again, so what gets replayed is what the agent holds
     * rather than a guess assembled from this transcript. The local trailing
     * replies are dropped first, otherwise the old answer would sit above the new one.
     */
    function regenerate(): void {
        if (root.busy || root.sessionId.length === 0 || !root.can("retry"))
            return;
        let index = root.messageIDs.length - 1;
        while (index >= 0 && root.messageByID[root.messageIDs[index]]?.role !== "user")
            index--;
        if (index < 0)
            return;
        root.removeMessagesFrom(index + 1);
        root._releaseRun();
        root.busy = true;
        root.call("session.retry", { session_id: root.sessionId }, (result, error) => {
            if (error) {
                root.busy = false;
                root.addMessage(error.message ?? Translation.tr("Could not retry"), root.interfaceRole);
            }
        });
    }

    /**
     * Rewind the transcript to the user turn `messageId` names, dropping it and
     * everything after it.
     *
     * The agent rewinds its own history (session.undo), so the model forgets
     * exactly what this transcript stops showing. It counts *user turns* rather
     * than messages, which is why the turns from `messageId` on are counted
     * instead of the index being sent. Files the agent changed stay changed.
     *
     * `prefill` hands the rewound turn back to the composer to be edited and sent
     * again -- the bridge returns its text for exactly that.
     */
    function rewindTo(messageId: string, prefill: bool): void {
        const index = root.messageIDs.indexOf(messageId);
        if (index < 0 || root.busy || root.sessionId.length === 0 || !root.can("undo"))
            return;
        const turns = root.messageIDs.slice(index).filter(id => root.messageByID[id]?.role === "user").length;
        if (turns === 0)
            return;
        root.call("session.undo", { session_id: root.sessionId, turns: turns }, (result, error) => {
            if (error) {
                root.addMessage(error.message ?? Translation.tr("Could not undo that far"), root.interfaceRole);
                return;
            }
            // Only now: the agent is the authority on whether the rewind happened,
            // and a transcript trimmed ahead of a refusal would be a lie.
            root.removeMessagesFrom(index);
            if (prefill)
                root.composerPrefill((result?.message ?? "").toString());
        });
    }

    /** Rewind `count` user turns back from the end, the way `/undo N` reads. */
    function undoTurns(count: int): void {
        const userTurns = root.messageIDs.filter(id => root.messageByID[id]?.role === "user");
        if (userTurns.length === 0)
            return;
        root.rewindTo(userTurns[Math.max(0, userTurns.length - Math.max(1, count))], true);
    }

    // ── Attachments ────────────────────────────────────────────────
    //
    // Images are staged with the bridge and go out with the next prompt.submit;
    // anything else (a PDF included) is referenced by path, and the agent reads it
    // with its own tools.

    property var attachedImages: []

    function attachImage(path: string): void {
        const clean = FileUtils.trimFileProtocol((path ?? "").trim());
        if (clean.length === 0)
            return;
        if (root.sessionId.length === 0) {
            root.addMessage(Translation.tr("Still connecting — try the attachment again in a moment."), root.interfaceRole);
            return;
        }
        root.call("image.attach", { session_id: root.sessionId, path: clean }, (result, error) => {
            if (error) {
                // A non-image goes to file.attach instead, which hands back an
                // @file: ref.
                root._attachAsFile(clean, error.message ?? "");
                return;
            }
            // A paste is written to a timestamped temp file, a name nobody chose
            const file = FileUtils.fileNameForPath(clean);
            const name = file.startsWith("agent-clip-") ? "image" + file.slice(file.lastIndexOf(".")) : file;
            root._addMarker("image", name, `[Image: ${name}]`, [result.path ?? clean]);
        });
    }

    function _attachAsFile(path: string, imageError: string): void {
        root.call("file.attach", { session_id: root.sessionId, path: path }, (result, error) => {
            // A folder fails both attaches. Asked here, it goes in as an @folder:
            // reference, which the agent lists with its own tools.
            if (error) {
                const probe = root._isFolderProbe.createObject(root, { command: ["test", "-d", path] });
                probe.exited.connect(code => {
                    probe.destroy();
                    if (code === 0) {
                        const quoted = /[\s`"']/.test(path) ? `"${path}"` : path;
                        root._addMarker("folder", FileUtils.folderNameForPath(path), `@folder:${quoted}`, []);
                    } else {
                        root.addMessage(imageError.length > 0 ? imageError : (error.message ?? Translation.tr("Could not attach that file")), root.interfaceRole);
                    }
                });
                probe.running = true;
                return;
            }
            // A staged file is referenced by text, not held as an attachment.
            root._addMarker("file", FileUtils.fileNameForPath(path), (result.ref_text ?? result.path ?? "").toString(), []);
        });
    }

    property Component _isFolderProbe: Process {}

    function detachAll(): void {
        Object.keys(root.composerMarkers).forEach(token => root.removeMarker(token));
    }

    /**
     * Attach the image on the clipboard; `onText` runs instead when it holds text.
     * scripts/agent/clipboard-image.sh says which source wins and why.
     */
    function attachClipboardImage(onText: var): void {
        if (clipboardImageProc.running)
            return;
        clipboardImageProc.onText = onText ?? null;
        clipboardImageProc.command = [root.clipboardImageScript, Directories.tempImages, Cliphist.cliphistBinary];
        clipboardImageProc.running = true;
    }

    readonly property string clipboardImageScript: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/agent/clipboard-image.sh"))

    Process {
        id: clipboardImageProc
        property var onText: null
        stdout: StdioCollector {
            onStreamFinished: {
                const result = this.text.trim();
                if (result === "text")
                    clipboardImageProc.onText?.();
                else if (result.length > 0)
                    result.split("\n").forEach(line => root.attachImage(line.startsWith("file://") ? decodeURIComponent(line) : line));
                else
                    root.addMessage(Translation.tr("No image found in clipboard"), root.interfaceRole);
            }
        }
    }

    // ── Sending ──────────────────────────────────────────────────────────

    function sendMessage(text: string): void {
        const trimmed = (text ?? "").trim();
        if (trimmed.length === 0)
            return;

        // Expanded here, while the composer's clear cannot yet have unstaged them
        const sent = root._expandMarkers(trimmed).trim();
        root._newUserMessage(sent);
        root.composerMarkers = ({});
        if (sent.length > 0)
            root._tryRoute(sent);
    }

    property string _deferredPrompt: ""

    // ── Local fast path ──────────────────────────────────────────────────
    //
    // A request the shell can already answer by itself resolves here, with no
    // model call: about 50ms against the seconds one agent step costs.
    // The catalogue lives in scripts/agent/desktop.py and is deliberately
    // timid -- a question, two actions in one, or anything long exits 2 and
    // falls through to the agent untouched, because a wrong instant answer is
    // worse than a slow right one.
    //
    // ponytail: a routed action never enters the agent's history, so a later
    // "undo that" has nothing to undo against. The catalogue is held to
    // self-evident, individually reversible toggles for exactly that reason;
    // widening it is what would make the missing history matter.

    readonly property string desktopScript: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/agent/desktop.py"))
    property string _routingText: ""

    function _tryRoute(text: string): void {
        // One at a time: a second message while the first is still routing goes
        // straight to the agent rather than queueing behind it.
        if (routeProc.running || root.desktopScript.length === 0) {
            root._sendOrDefer(text);
            return;
        }
        root._routingText = text;
        // `timeout` is the whole guard against a wedged helper: the process is
        // then certain to exit, and exit settles the message either way.
        routeProc.command = ["timeout", "5", root.desktopScript, "do", text];
        routeProc.running = true;
    }

    function _sendOrDefer(text: string): void {
        if (root.sessionId.length === 0) {
            // Session still being created: send once it lands.
            root._deferredPrompt = text;
            root.ensureStarted();
            return;
        }
        root._submit(text);
    }

    /**
     * Whichever of the two paths below arrives first decides; clearing
     * `_routingText` makes the other a no-op. Only a route the helper confirms
     * it both matched *and* ran replaces the agent's turn -- everything else,
     * including a helper that never started, goes to the agent unchanged.
     */
    function _finishRoute(output: string): void {
        const text = root._routingText;
        if (text.length === 0)
            return;
        root._routingText = "";
        let reply = null;
        try {
            reply = JSON.parse(output);
        } catch (e) {
            reply = null;
        }
        if (reply?.routed === true && reply?.ok === true) {
            root.addMessage(Translation.tr("Done · %1").arg(reply.action ?? ""), root.interfaceRole);
            return;
        }
        root._sendOrDefer(text);
    }

    Process {
        id: routeProc

        // The collector is what the rest of this repo reads from, and it is the
        // only point where the output is known to be complete.
        stdout: StdioCollector {
            onStreamFinished: root._finishRoute(this.text)
        }

        // Safety net. A helper that never starts produces no stream to finish,
        // and the message would sit here forever -- so exit always settles it
        // too. callLater lets a stream that *is* coming win the race.
        onExited: Qt.callLater(() => root._finishRoute(""))
    }

    function _submit(text: string): void {
        // The user's next request is the one unambiguous end of the previous run.
        root._releaseRun();
        root.busy = true;
        root.statusText = "";
        // The bridge sends whatever is staged with this turn, so the local list has
        // to clear with it or the indicator would keep showing spent images.
        root.attachedImages = [];
        root.composerMarkers = ({});
        root.speakingMessageId = "";
        root.call("prompt.submit", {
            session_id: root.sessionId,
            text: text
        }, (result, error) => {
            if (error) {
                root.busy = false;
                root._failStream(error.message ?? Translation.tr("prompt failed"));
                return;
            }
            // Sent while a reply was still running: say where it went, or it reads
            // as a message the agent ignored. Events carry the rest.
            if (result.status === "queued")
                root.statusText = Translation.tr("Queued: goes out when this reply ends");
            else if (result.status === "steered")
                root.statusText = Translation.tr("Added to the reply in progress");
        });
    }

    function interrupt(): void {
        if (root.sessionId.length === 0)
            return;
        root.call("session.interrupt", { session_id: root.sessionId }, null);
        root.statusText = Translation.tr("Interrupting…");
    }

    function _failStream(message: string): void {
        const streaming = root.streamingMessage;
        if (streaming) {
            streaming.error = message;
            streaming.done = true;
        } else {
            root.addMessage(message, root.interfaceRole);
        }
        root.streamingId = "";
        root._releaseRun();
        root.busy = false;
        root.statusText = "";
    }

    // ── Slash commands ───────────────────────────────────────────────────

    function refreshSlashCommands(): void {
        root.call("complete.slash", { text: "/" }, (result, error) => {
            if (error)
                return;
            root.slashCommands = (result.items ?? []).map(item => ({
                name: item.text,
                displayName: item.display ?? `/${item.text}`,
                description: item.meta ?? "",
                kind: item.kind ?? "command"
            }));
        });
    }

    /** Live completions for what is typed so far, ranked by the agent itself. */
    function completeSlash(text: string, callback: var): void {
        root.call("complete.slash", { text: text }, (result, error) => {
            if (error) {
                callback([]);
                return;
            }
            callback((result.items ?? []).map(item => ({
                name: item.text,
                displayName: item.display ?? `/${item.text}`,
                description: item.meta ?? "",
                kind: item.kind ?? "command"
            })));
        });
    }

    // Handled by the shell rather than the agent: these mean something different
    // in a sidebar than they do in a terminal.
    readonly property var localCommands: ["new", "reset", "clear"]

    function runSlashCommand(commandLine: string): void {
        const line = commandLine.trim();
        const base = line.replace(/^\//, "").split(/\s+/)[0].toLowerCase();
        const arg = line.replace(/^\/\S+\s*/, "");

        if (root.localCommands.includes(base)) {
            root.newSession();
            return;
        }

        // `/undo` goes through the same rewind the message buttons drive, so the
        // transcript and the agent's history drop the same turns.
        if (base === "undo" && root.can("undo")) {
            root.undoTurns(parseInt(arg, 10) || 1);
            return;
        }

        root.call("slash.exec", {
            command: line,
            session_id: root.sessionId
        }, (result, error) => {
            if (error) {
                root.addMessage(error.message ?? Translation.tr("Command failed"), root.interfaceRole);
                return;
            }
            // Most commands are the agent's own (its skills, its custom commands)
            // and run as an ordinary turn; the bridge says which.
            if (result?.send === true) {
                root._submitPrompt(line, line);
                return;
            }
            root._reportCommandOutput(result.output);
        });
    }

    /** Send `text` to the agent while the transcript shows `display`. */
    function _submitPrompt(text: string, display: string): void {
        root._newUserMessage(display.length > 0 ? display : text);
        root._submit(text);
    }

    function _reportCommandOutput(output: var): void {
        const text = (output ?? "").toString();
        if (text.trim().length > 0)
            root.addMessage(text.replace(/\s+$/, ""), root.interfaceRole);
        root.refreshSessionInfo();
    }

    function refreshSessionInfo(): void {
        if (root.sessionId.length === 0)
            return;
        root.call("session.status", { session_id: root.sessionId }, (result, error) => {
            if (error)
                return;
            root._applyInfo(result.info ?? result);
        });
    }

    // ── Models and providers ─────────────────────────────────────────────

    function refreshProviders(): void {
        if (root.providersLoading)
            return;
        root.providersLoading = true;
        root.call("model.options", { session_id: root.sessionId }, (result, error) => {
            root.providersLoading = false;
            if (error) {
                root.lastError = error.message ?? "";
                return;
            }
            root.providers = result.providers ?? [];
            if (result.model)
                root.currentModel = result.model;
            if (result.provider)
                root.currentProvider = result.provider;
        });
    }

    /**
     * Switch the reasoning effort. Like the model, the bridge applies it to the
     * running chat, remembers it per agent, and echoes it back as session.info.
     */
    function setEffort(effort: string): void {
        if ((effort ?? "").length === 0 || effort === root.currentEffort)
            return;
        root.call("effort.set", { session_id: root.sessionId, effort: effort }, (result, error) => {
            if (error)
                root.addMessage(error.message ?? Translation.tr("Could not change the effort"), root.interfaceRole);
        });
    }

    /**
     * Switch the model. The bridge remembers the pick per agent and starts the
     * next chat on it too, so nothing about it lives here.
     */
    function setModel(model: string, providerSlug: string): void {
        if ((model ?? "").length === 0)
            return;
        root.call("model.set", { session_id: root.sessionId, model: model }, (result, error) => {
            if (error)
                root.addMessage(error.message ?? Translation.tr("Could not switch model"), root.interfaceRole);
        });
    }

    // ── Voice ──────────────────────────────────────────────────────

    /*
     * Dictation runs on the shell's own recorder (pw-record) and transcribes with
     * whisper.cpp; nothing is sent anywhere unless the user chose online
     * dictation (Groq). A recorder subprocess this service
     * owns is also what makes stop genuinely close the device -- a held mic drags a
     * Bluetooth headset from A2DP down to HSP.
     */
    function startDictation(): void {
        root.speech.startRecording();
    }

    /** Stop the capture and transcribe what was said. */
    function stopDictation(): void {
        root.speech.stopRecording();
    }

    /** Drop what is being recorded without transcribing it. */
    function cancelDictation(): void {
        root.speech.cancelRecording();
    }

    function toggleDictation(): void {
        // Mid-transcription there is nothing useful to toggle; let it land.
        if (root.voiceState === "transcribing")
            return;
        if (root.voiceState === "listening")
            root.stopDictation();
        else
            root.startDictation();
    }

    // ── Approvals ────────────────────────────────────────────────────────

    function respondToApproval(choice: string, all = false): void {
        const request = root.pendingApproval;
        root.pendingApproval = null;
        if (!request)
            return;
        root._reply(request.srq, {
            choice: choice,
            all: all
        });
    }

    // Answer a server->client request: a response frame carrying its id.
    function _reply(id: string, result: var): void {
        bridgeProc.write(JSON.stringify({
            jsonrpc: "2.0",
            id: id,
            result: result
        }) + "\n");
    }

    /**
     * Answer the agent's question. A batch asks one call per `questionId`; the turn
     * unblocks once every question has been answered.
     */
    function respondToClarify(answer: string, questionId: string): void {
        const request = root.pendingClarify;
        if (!request)
            return;
        // A single question is answered by the response frame itself.
        if ((questionId ?? "").length === 0) {
            root.pendingClarify = null;
            root._reply(request.srq, {
                answer: answer
            });
            return;
        }
        // A batch locks one answer per call; the last lock resolves the request.
        root.call("clarify.lock", {
            request_id: request.srq,
            question_id: questionId,
            answer: answer
        }, (result, error) => {
            if (error) {
                root.addMessage(error.message ?? Translation.tr("Could not send that answer"), root.interfaceRole);
                return;
            }
            if ((result?.remaining ?? []).length === 0 && root.pendingClarify === request)
                root.pendingClarify = null;
        });
    }

    // ── Event handling ───────────────────────────────────────────────────

    function _handleFrame(frame: var): void {
        // The bridge asking the user something (approval, clarify): it has an id
        // like a reply, and a method like a call.
        if (frame.method && frame.method !== "event" && frame.id !== undefined && frame.id !== null) {
            root._handleServerRequest(frame);
            return;
        }
        if (frame.id !== undefined && frame.id !== null) {
            const callback = root._pendingCalls[frame.id];
            delete root._pendingCalls[frame.id];
            if (callback)
                callback(frame.result ?? {}, frame.error ?? null);
            return;
        }
        if (frame.method === "event")
            root._handleEvent(frame.params ?? {});
    }

    function _handleServerRequest(frame: var): void {
        // `srq` is the id the answer must carry; `request_id` is approval's own.
        const request = Object.assign({}, frame.params ?? {}, {
            srq: frame.id
        });
        switch (frame.method) {
        case "approval":
            root.pendingApproval = request;
            root.statusText = Translation.tr("Waiting for your approval");
            root.notifyWaiting(request, true);
            break;
        case "clarify":
            root.pendingClarify = request;
            root.statusText = Translation.tr("Waiting for your answer");
            root.notifyWaiting(request, false);
            break;
        default:
            // Anything else has no card here. Saying so ends the agent's wait now
            // instead of at its timeout.
            bridgeProc.write(JSON.stringify({
                jsonrpc: "2.0",
                id: frame.id,
                error: {
                    code: -32601,
                    message: `${frame.method} is not supported by the sidebar`
                }
            }) + "\n");
        }
    }

    function _handleEvent(params: var): void {
        const type = params.type ?? "";
        const payload = params.payload ?? {};

        switch (type) {
        case "ready":
            root.capabilities = payload.capabilities ?? ({});
            root.ready = true;
            root.starting = false;
            root.consecutiveFailures = 0;
            root._drainQueue();
            if (root._resumeAfterStart.length > 0) {
                // Restarted on new settings: the same chat, not a fresh one.
                const stored = root._resumeAfterStart;
                root._resumeAfterStart = "";
                root.resumeSession(stored);
            } else if (root.sessionId.length === 0) {
                root.createSession();
            }
            break;

        case "message.start":
            root.speakingMessageId = "";
            root.busy = true;
            root.statusText = "";
            root._runSegmentUsedTools = false;
            const continuing = root.messageByID[root._runMessageId] ?? null;
            if (continuing) {
                // Same answer, later turn: reopen the card rather than stacking a
                // new one. A blank line keeps the resumed prose off the end of the
                // sentence that preceded the tools.
                if (continuing.content.length > 0)
                    continuing.content += "\n\n";
                continuing.done = false;
                root._runSegmentStart = continuing.content.length;
                root.streamingId = root._runMessageId;
            } else {
                root.streamingId = root._newMessage("assistant", "");
                root._runMessageId = root.streamingId;
                root._runSegmentStart = 0;
            }
            break;

        case "message.delta":
            if (root.streamingId.length === 0)
                root.streamingId = root._newMessage("assistant", "");
            if (root.streamingMessage)
                root.streamingMessage.content += (payload.text ?? "");
            break;

        case "thinking.delta":
            // Not model reasoning — the agent's own activity line, which the TUI
            // shows as a spinner caption. Anything real arrives as message.delta.
            if ((payload.text ?? "").trim().length > 0)
                root.statusText = payload.text.trim();
            break;

        case "message.complete":
            // Held onto: streamingId is cleared just below, and the notification
            // needs the turn that actually finished. The id as well as the
            // message, because a spoken reply has to claim it -- see below.
            let finished = root.streamingMessage;
            let finishedId = root.streamingId;
            if (finished) {
                // Only this turn's slice: the payload is the turn's full text, and
                // assigning it whole would erase everything earlier turns in the
                // same run had already put in the card.
                if ((payload.text ?? "").length > 0)
                    finished.content = finished.content.slice(0, root._runSegmentStart) + payload.text;
                if (payload.status === "error")
                    finished.error = payload.text ?? "";
                finished.usage = payload.usage ?? null;
                finished.done = true;
            } else if ((payload.text ?? "").length > 0) {
                const id = root._newMessage("assistant", payload.text);
                root.messageByID[id].done = true;
                finished = root.messageByID[id];
                finishedId = id;
                root._runMessageId = id;
            }
            root.streamingId = "";
            root.busy = false;
            root.statusText = "";
            // A turn that called tools is mid-run, and the agent is about to speak
            // again -- notifying on it would fire once per step of one answer.
            if (!root._runSegmentUsedTools)
                root.notifyFinished(finished);
            break;

        case "tool.generating":
            root.statusText = Translation.tr("Preparing %1…").arg(payload.name ?? "tool");
            break;

        case "tool.start":
            root._addToolCall(payload);
            root.statusText = payload.context ?? payload.name ?? "";
            break;

        case "tool.complete":
            root._completeToolCall(payload);
            root.statusText = "";
            break;

        case "request.cancel":
            // A question timed out or the turn was interrupted: take its card down.
            if (root.pendingApproval?.srq === payload.id)
                root.pendingApproval = null;
            if (root.pendingClarify?.srq === payload.id)
                root.pendingClarify = null;
            break;

        case "session.info":
            root._applyInfo(payload);
            break;


        case "session.title":
            root.sessionTitle = payload.title ?? root.sessionTitle;
            break;

        case "status.update":
            root.statusText = (payload.text ?? "").trim();
            break;

        case "status.setup":
            root.setupText = (payload.text ?? "").trim();
            break;

        case "usage.limits":
            root.usageLimits = payload;
            break;

        case "notice":
            if ((payload.message ?? "").length > 0)
                root.addMessage(payload.message, root.interfaceRole);
            break;

        case "error":
            root._failStream(payload.message ?? Translation.tr("%1 reported an error").arg(root.agentName));
            break;

        case "sessions.changed":
            root.refreshRecentSessions();
            break;
        }
    }

    function _addToolCall(payload: var): void {
        root._runSegmentUsedTools = true;
        // A tool can fire before any assistant text, so the turn may not exist yet.
        // It still belongs to the run in progress, if there is one.
        if (root.streamingId.length === 0)
            root.streamingId = root.messageByID[root._runMessageId] ? root._runMessageId : root._newMessage("assistant", "");
        if (root._runMessageId.length === 0)
            root._runMessageId = root.streamingId;
        const message = root.streamingMessage;
        if (!message)
            return;
        // Duck-typed to what ToolActivityRow reads, so a tool call is narrated
        // by the shared row rather than a renderer of its own.
        const args = payload.args ?? {};
        // Where in the reply this fired. The transcript interleaves tool rows with
        // the prose by this offset, so "I'll check the package list" stays above the
        // command it was talking about instead of the whole run being hoisted into
        // one block at the top of the turn.
        message.toolCalls = [...message.toolCalls, {
            contentMark: (message.content ?? "").length,
            toolId: payload.tool_id ?? "",
            toolName: payload.name ?? "tool",
            toolInput: payload.context ?? payload.preview ?? "",
            toolFullInput: root._formatToolArgs(args),
            toolArgs: args,
            toolResult: "",
            toolExitCode: null,
            duration: 0,
            toolRunning: true,
            toolFailed: false
        }];
    }

    /** The full argument set, as the expanded tool row shows it. */
    function _formatToolArgs(args: var): string {
        if (!args || typeof args !== "object")
            return "";
        const keys = Object.keys(args);
        if (keys.length === 0)
            return "";
        // A lone `command`/`code` argument is the thing itself -- printing it as
        // JSON would bury a shell line in quotes and escapes.
        if (keys.length === 1 && ["command", "code", "query", "text"].includes(keys[0]))
            return (args[keys[0]] ?? "").toString();
        try {
            return JSON.stringify(args, null, 2);
        } catch (e) {
            return "";
        }
    }

    /**
     * What a tool handed back, as text for the expanded row.
     *
     * `result` is whatever the tool returned: a command answers {output,
     * exit_code}, a failure {error}, and most tools a bare string. Reading `output`
     * alone left the return box empty -- and so hidden -- for everything that is
     * not a shell command.
     */
    function _resultText(result: var): string {
        if (result === null || result === undefined)
            return "";
        if (typeof result !== "object")
            return `${result}`;
        if ((result.error ?? null) !== null)
            return `${result.error}`;
        if (typeof result.output === "string")
            return result.output;
        // read_file answers {content, total_lines, ...}; the content is what was read,
        // and as JSON it was one escaped string.
        if (typeof result.content === "string")
            return result.content;
        try {
            return JSON.stringify(result, null, 2);
        } catch (e) {
            return "";
        }
    }

    function _completeToolCall(payload: var): void {
        const message = root.streamingMessage;
        if (!message)
            return;
        const result = payload.result ?? {};
        const structured = result !== null && typeof result === "object";
        const failed = structured && ((result.error ?? null) !== null || (result.exit_code ?? 0) !== 0);
        message.toolCalls = message.toolCalls.map(call => {
            if (call.toolId !== (payload.tool_id ?? ""))
                return call;
            return Object.assign({}, call, {
                toolRunning: false,
                toolFailed: failed,
                toolResult: root._resultText(result),
                // null when the tool has no notion of one, so the row can tell
                // "exited 0" apart from "never reported a code".
                toolExitCode: structured && (result.exit_code ?? null) !== null ? result.exit_code : null,
                duration: payload.duration_s ?? 0
            });
        });
    }

    // ── Dictation ──────────────────────────────────────────────────
    //
    // The mic button and Super+Shift+B record with pw-record and transcribe with
    // whisper.cpp, or online with Groq; the settings below choose which, and the
    // local model.

    readonly property var sttPresets: ({
        "fast":     { "file": "ggml-tiny.en.bin" },              //  78MB, ~2s per 11s of audio
        "balanced": { "file": "ggml-base.en.bin" },              // 148MB, ~4s
        "accurate": { "file": "ggml-small.en-q5_1.bin" },        // 190MB, ~12s
        "best":     { "file": "ggml-large-v3-turbo-q5_0.bin" }   // 574MB, slow without a GPU backend
    })
    readonly property string sttQuality: {
        const stored = Config.options.agent.sttQuality;
        return root.sttPresets[stored] ? stored : "balanced";
    }
    readonly property string sttModelDir: FileUtils.trimFileProtocol(`${Directories.home}/.local/share/vynx-conduit/models`)

    // An explicit path always wins, so a hand-picked model is never overridden.
    readonly property string sttModel: {
        const stored = Config.options.agent.sttModel;
        if (stored.length > 0) return stored.replace(/^~/, FileUtils.trimFileProtocol(Directories.home));
        return `${root.sttModelDir}/${root.sttPresets[root.sttQuality].file}`;
    }
    readonly property string sttModelUrl: {
        const stored = Config.options.agent.sttModel;
        if (stored.length > 0) return ""; // Manual path: the user owns fetching it.
        return `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${root.sttPresets[root.sttQuality].file}`;
    }

    /**
     * Shell commands the user runs themselves -- `!` in the composer, Run on a
     * code block. Separate from the agent's own tools: this is the user's hand on
     * the keyboard, not the model's.
     */
    property CommandRunner runner: CommandRunner {
        // Same directory the agent is working in, so a `!git status` answers about
        // the project being discussed rather than about wherever the shell started.
        workingDirectory: root.cwd
    }

    /**
     * Hand a finished command's output to the agent.
     *
     * `prompt.submit` is the only route into the model's history and it answers,
     * so there is no way to quietly add context to a turn that has not happened
     * yet. The output goes to the composer instead: it rides along with whatever
     * is asked next, and a `!ls` run for the user's own eyes costs no context
     * until they decide it should.
     */
    function shareCommandOutput(command: string, output: string, exitCode: int): void {
        const body = (output ?? "").trim();
        const status = exitCode === 0 ? "" : `\n(exit ${exitCode})`;
        root.composerAppend("```console\n$ " + command + "\n" + (body.length > 0 ? body : "(no output)") + status + "\n```");
    }

    property SpeechToText speech: SpeechToText {
        engine: Config.options.agent.sttEngine
        modelPath: root.sttModel
        modelUrl: root.sttModelUrl
        language: Config.options.agent.sttLanguage
        prompt: Config.options.agent.sttPrompt
        source: Config.options.agent.sttSource

        onModelDownloaded: console.log("[Agent] dictation voice model ready:", root.sttQuality)

        onTranscribed: text => {
            // Handed to the composer to review rather than sent: STT mishears and a
            // send cannot be undone.
            root.dictationTranscript(text);
        }
        onFailed: reason => {
            root.addMessage(reason, root.interfaceRole);
        }
    }

    // ── Read-aloud ─────────────────────────────────────────────────
    //
    // scripts/agent/tts.py only *synthesizes* -- online with edge-tts, or on this
    // computer with Kokoro, both timing every word -- and the shell plays the
    // files itself. MediaPlayer.stop() drains the stream the same graceful way a
    // clip ends on its own, and the volume is faded to zero first; killing a
    // player mid-waveform into a Bluetooth A2DP sink is a loud buzz.

    readonly property string ttsScript: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/agent/tts.sh"))
    readonly property string ttsDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/quickshell/agent/tts`

    // Optimistic until the server says otherwise: it exits 127 without edge-tts,
    // and the read-aloud buttons go away rather than failing on every press.
    property bool ttsAvailable: true
    property bool ttsReady: false
    property int _ttsNextId: 1
    property var _ttsPending: ({})       // id -> callback(reply)
    property var _ttsQueuedRequests: []  // {id, frame}, written once the server says ready

    /** Start the synth server early so the first read-aloud does not pay the model load. */
    function prewarmTts(): void {
        if (!ttsProc.running)
            ttsProc.running = true;
    }

    /** Ask the server for `text` as a clip; `callback(reply)` when it is made. Returns its id. */
    function _ttsRequest(text: string, callback: var): string {
        const id = `tts-${root._ttsNextId++}`;
        const out = `${root.ttsDir}/${id}-${Date.now()}.mp3`;
        const local = Config.options.agent.ttsEngine === "kokoro";
        const frame = JSON.stringify({
            id: id,
            text: text,
            out: out,
            engine: local ? "kokoro" : "edge",
            voice: local ? Config.options.agent.ttsLocalVoice : Config.options.agent.ttsVoice,
            // Beside dictation's whisper models; Kokoro's are fetched here on first use.
            modelDir: root.sttModelDir
        }) + "\n";
        root._ttsPending[id] = callback;
        if (!root.ttsReady) {
            root._ttsQueuedRequests.push({ id: id, frame: frame });
            root.prewarmTts();
            return id;
        }
        ttsProc.write(frame);
        return id;
    }

    /**
     * Forget requests the server has not started on. Each is still answered,
     * `dropped`, so whoever asked hears back either way; one already being made
     * comes back made.
     */
    function _ttsDrop(ids: var): void {
        const unsent = root._ttsQueuedRequests.filter(request => ids.includes(request.id));
        root._ttsQueuedRequests = root._ttsQueuedRequests.filter(request => !ids.includes(request.id));
        for (const request of unsent) {
            const callback = root._ttsPending[request.id];
            delete root._ttsPending[request.id];
            if (callback)
                callback({ id: request.id, ok: false, dropped: true, paths: [] });
        }
        const sent = ids.filter(id => !unsent.some(request => request.id === id));
        if (sent.length > 0 && root.ttsReady)
            ttsProc.write(JSON.stringify({ drop: sent }) + "\n");
    }

    Process {
        id: ttsProc
        running: false
        stdinEnabled: true
        command: [root.ttsScript]

        stdout: SplitParser {
            onRead: line => {
                if (line.trim().length === 0)
                    return;
                let reply;
                try {
                    reply = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (reply.event === "status") {
                    root.addMessage(reply.text ?? "", root.interfaceRole);
                    return;
                }
                if (reply.event === "ready") {
                    root.ttsReady = true;
                    const queued = root._ttsQueuedRequests;
                    root._ttsQueuedRequests = [];
                    queued.forEach(request => ttsProc.write(request.frame));
                    return;
                }
                const callback = root._ttsPending[reply.id];
                delete root._ttsPending[reply.id];
                if (callback)
                    callback(reply);
            }
        }

        stderr: SplitParser {
            onRead: line => {
                if (line.trim().length > 0)
                    console.log("[Agent/tts]", line.trim());
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.ttsReady = false;
            root._ttsPending = ({});
            root._ttsQueuedRequests = [];
            if (exitCode === 127)
                root.ttsAvailable = false;
            root._serverGone();
        }
    }

    // The player is built on first use: instantiating MediaPlayer links QtMultimedia's
    // backend and starts an audio thread (see SoundService), none of it needed until
    // something is actually read out. It holds one part's clip at a time; which
    // part, and where in the reading that is, is the service's to say.
    Loader {
        id: readerLoader
        active: false
        sourceComponent: Item {
            id: reader
            readonly property alias player: readerPlayer
            readonly property alias markClock: readerMarks
            /** Which part's clip is in the player, or -1. */
            property int loadedIndex: -1
            // Where to put the clip once it has loaded, whether to play it then,
            // and whether from silence: a clip entered mid-sentence fades in.
            property real startAt: 0
            property bool playOnLoad: false
            property bool fadeIn: false
            // The clip being loaded. A seek before the load is dropped, so it
            // waits for LoadedMedia -- after LoadingMedia, because a source changed
            // mid-play first reports the old clip loaded (both measured, Qt 6.12).
            property bool loading: false

            MediaDevices {
                id: readerDevices
            }

            MarkClock {
                id: readerMarks
                player: readerPlayer
                marks: reader.loadedIndex >= 0 ? (root._speakClips[reader.loadedIndex]?.marks ?? []) : []
            }

            MediaPlayer {
                id: readerPlayer
                audioOutput: AudioOutput {
                    id: readerOutput
                    device: readerDevices.defaultAudioOutput
                    volume: 1
                }

                onMediaStatusChanged: {
                    const status = readerPlayer.mediaStatus;
                    if (status === MediaPlayer.LoadingMedia) {
                        reader.loading = true;
                    } else if (status === MediaPlayer.LoadedMedia && reader.loading) {
                        reader.loading = false;
                        readerPlayer.position = reader.startAt;
                        readerMarks.jump(reader.startAt);
                        if (!reader.playOnLoad) {
                            readerPlayer.pause();
                            return;
                        }
                        readerPlayer.play();
                        if (reader.fadeIn)
                            resumeFade.start();
                    } else if (status === MediaPlayer.EndOfMedia) {
                        root._partEnded(reader.loadedIndex);
                    }
                }

                onErrorOccurred: (error, message) => {
                    console.log("[Agent/tts] playback error:", message);
                    root._partEnded(reader.loadedIndex);
                }
            }

            /** Put part `index`'s clip in the player at `startMs`, playing or held there. */
            function load(index: int, path: string, startMs: real, play: bool): void {
                fadeOut.stop();
                pauseFade.stop();
                resumeFade.stop();
                reader.loadedIndex = index;
                reader.startAt = startMs;
                reader.playOnLoad = play;
                reader.fadeIn = startMs > 0;
                reader.loading = false;
                readerPlayer.stop();
                readerPlayer.source = "";
                readerOutput.volume = reader.fadeIn ? 0 : 1;
                readerPlayer.source = `file://${path}`;
            }

            /** Move within the clip in the player -- back as well as on. */
            function seekWithin(ms: real, play: bool): void {
                // A clip fading out to be let go -- the reading moved to a part not
                // made yet -- is wanted again: left running, the fade let it go
                // under the move back, and the reading sat silent until moved again.
                fadeOut.stop();
                if (reader.loading) {
                    reader.startAt = ms;
                    reader.playOnLoad = play;
                    return;
                }
                readerPlayer.position = ms;
                readerMarks.jump(ms);
                if (play)
                    reader.release();
                else
                    reader.hold();
            }

            /** Fade to silence, then hold where it is. */
            function hold(): void {
                resumeFade.stop();
                if (reader.loading)
                    reader.playOnLoad = false;
                else if (readerPlayer.playbackState === MediaPlayer.PlayingState)
                    pauseFade.start();
            }

            /** Go on from where it was held, fading back in. */
            function release(): void {
                pauseFade.stop();
                if (reader.loading) {
                    reader.playOnLoad = true;
                    return;
                }
                if (readerPlayer.playbackState !== MediaPlayer.PlayingState) {
                    readerOutput.volume = 0;
                    readerPlayer.play();
                }
                resumeFade.start();
            }

            /** Fade to silence, then let the clip go. */
            function fadeAndStop(): void {
                pauseFade.stop();
                resumeFade.stop();
                if (readerPlayer.playbackState !== MediaPlayer.PlayingState) {
                    reader.unload();
                    return;
                }
                if (!fadeOut.running)
                    fadeOut.start();
            }

            /** Nothing in the player any more. */
            function unload(): void {
                fadeOut.stop();
                pauseFade.stop();
                resumeFade.stop();
                reader.loadedIndex = -1;
                reader.loading = false;
                readerPlayer.stop();
                readerPlayer.source = "";
                readerOutput.volume = 1;
            }

            // Fade first, on an effects spec (opacity/volume must never overshoot),
            // then stop: the stream then drains with silence in it rather than being
            // cut mid-waveform.
            SequentialAnimation {
                id: fadeOut
                NumberAnimation {
                    target: readerOutput
                    property: "volume"
                    to: 0
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                }
                ScriptAction {
                    script: reader.unload()
                }
            }

            // A pause is the same exit as a stop -- silence first, never cut
            // mid-waveform -- on the fast-exit spec; going on is its enter, the
            // volume back up on the default effects spec.
            SequentialAnimation {
                id: pauseFade
                NumberAnimation {
                    target: readerOutput
                    property: "volume"
                    to: 0
                    duration: Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
                }
                ScriptAction {
                    script: readerPlayer.pause()
                }
            }
            NumberAnimation {
                id: resumeFade
                target: readerOutput
                property: "volume"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }

    /**
     * Sentence-boundary chunks, so speaking can begin before the whole reply has
     * been synthesized.
     *
     * Synthesis cost scales with length -- a 250-character reply takes about four
     * seconds -- and the reply is only handed over once it is finished, so a long
     * answer sat in silence for all four. Split, the first chunk lands in about a
     * second and the player's queue covers the rest while they render.
     *
     * Only real sentence ends are cut, and short ones are merged up to `minChunk`:
     * a pause the listener does not expect is worse than waiting a moment longer,
     * and every boundary here is one a person reading aloud would also pause at.
     * A line that ends where a new block starts -- a list item, a heading, a
     * paragraph -- is one too: a list's items seldom end in a full stop, and a
     * long one with none was a single part, the voice silent while all of it was
     * made.
     * Never inside a code block, inline code or a formula: each is read as one
     * thing (scripts/agent/tts_text.py), and a cut through a fence left the next
     * chunk opening on its closing ``` and reading the prose after it as code.
     *
     * The local voice is cut finer. Kokoro makes a part in about the time the one
     * before it takes to say (measured: 1.1x real time on battery, 1.6x on AC,
     * plus 0.2 s a part), so a part much longer than the last is silence while it
     * renders: at those rates a 60-character first part and a 150-character second
     * leave 4 s between them on battery. Each of its parts is a sentence, and a
     * long one is cut at a comma as well -- a pause there is one a reader makes too.
     */
    // The opening chunk is allowed to be short so speaking starts sooner; the rest
    // are kept long, since by then the player is busy and only the total matters.
    readonly property int _minFirstChunk: 60
    readonly property int _minChunk: 140
    readonly property int _minLocalChunk: 40
    readonly property int _maxLocalChunk: 120

    function _splitForSpeech(text: string, local: bool): var {
        const trimmed = (text ?? "").trim();
        const firstFloor = local ? root._minLocalChunk : root._minFirstChunk;
        if (trimmed.length <= firstFloor)
            return [trimmed];
        const units = [];
        const whole = /```[\s\S]*?(?:```|$)|<think>[\s\S]*?(?:<\/think>|$)/g;
        for (let m; (m = whole.exec(trimmed)) !== null;)
            units.push([m.index, whole.lastIndex]);
        const inline = SpeechMatch.formulaPattern();
        for (let m; (m = inline.exec(trimmed)) !== null;)
            units.push([m.index, inline.lastIndex]);
        const inUnit = at => units.some(([from, to]) => from < at && at < to);
        // Split *after* the punctuation, keeping it with the sentence it ends.
        // Chunks are slices of the text, whitespace and all: joined back with
        // spaces, a list item's `- ` stopped being at the start of a line, the
        // transcript could no longer tell it from a word, and the spoken-word
        // mark drifted a marker further ahead after every item.
        const spans = [];
        const ends = /[.!?]\s+|\n(?=[ \t]*(?:\n|[-*+][ \t]|\d{1,9}[.)][ \t]|[#>|]))\s*/g;
        let start = 0;
        let match;
        const add = end => {
            const floor = local ? root._minLocalChunk : spans.length === 1 ? root._minFirstChunk : root._minChunk;
            const last = spans[spans.length - 1];
            if (last && last.end - last.start < floor)
                last.end = end;
            else
                spans.push({ start: start, end: end });
        };
        while ((match = ends.exec(trimmed)) !== null) {
            if (inUnit(match.index + 1))
                continue;
            add(match.index + 1);
            start = ends.lastIndex;
        }
        add(trimmed.length);
        // No cap on how many: they are asked for as the reading reaches them, a
        // couple ahead (_askForParts). Capped at eight, the rest of a long reply
        // was one part, and the reading fell silent after the seventh while all
        // of it was made.
        if (local)
            return root._cutClauses(trimmed, spans, inUnit).map(span => trimmed.slice(span.start, span.end));
        return spans.map(span => trimmed.slice(span.start, span.end));
    }

    /**
     * Each span longer than `_maxLocalChunk` cut at commas, colons and semicolons:
     * at the last one that keeps the piece within it, else the first one past it,
     * never leaving a piece under 30 characters -- a clause that short said alone
     * loses the run of the sentence it belongs to.
     */
    function _cutClauses(text: string, spans: var, inUnit: var): var {
        const out = [];
        for (const span of spans) {
            let from = span.start;
            while (span.end - from > root._maxLocalChunk) {
                const pauses = [];
                const clause = /[,;:]\s+/g;
                clause.lastIndex = from;
                for (let m; (m = clause.exec(text)) !== null && m.index < span.end;) {
                    const cut = m.index + 1;
                    if (cut - from >= 30 && span.end - clause.lastIndex >= 30 && !inUnit(cut))
                        pauses.push([cut, clause.lastIndex]);
                }
                if (pauses.length === 0)
                    break;
                const within = pauses.filter(([cut]) => cut - from <= root._maxLocalChunk);
                const [cut, next] = within.length > 0 ? within[within.length - 1] : pauses[0];
                out.push({ start: from, end: cut });
                from = next;
            }
            out.push({ start: from, end: span.end });
        }
        return out;
    }

    // ── The reading ──
    //
    // A reading is its parts (sentences, above), each made into a clip when it is
    // asked for, a couple ahead of where the reading is. Every clip made is kept
    // until the reading ends, so it can be moved back as well as on, and the bar
    // under the transcript is the whole reply: parts not made yet are estimated
    // from their length (readingTimeline.js), and the estimate gives way to the
    // real length as their clips come.

    // Bumped by every reading, and when one ends, so replies meant for a reading
    // that is over are thrown away rather than played over the top of the next.
    property int _speakEpoch: 0
    /** The reading's parts, in order: slices of the message. */
    property var _speakParts: []
    // Per part: {path, marks, duration} once made, "failed", or undefined.
    property var _speakClips: []
    // Part index -> request id, for the parts being made.
    property var _speakAsked: ({})
    // Ids already dropped, so a drop is not sent twice.
    property var _speakDropped: ({})
    /** The part the reading is at: playing, held in, or waiting for. */
    property int _speakIndex: 0
    // Where in that part the reading is while its clip is not playing: ms, and,
    // for a part not made yet, the character whose word it starts on (else -1).
    property real _speakStartMs: 0
    property int _speakStartChar: -1
    // How far ahead of the reading parts are made: the one it is at and the two
    // after it, two in the making at a time. The server makes them one at a time,
    // in order, so two keep it busy; past that it waits for the reading to catch
    // up, as a video player's buffer does. Made as far as they would go, the
    // local voice went on making a long reply after it was stopped, or while it
    // sat paused -- by its measured rates, minutes of work for a few thousand
    // characters.
    readonly property int _speakAhead: 2

    readonly property var _speakDurations: Timeline.durations(root._speakParts, root._speakClips)
    /** The whole reading in ms, the parts not made yet estimated. 0 until one is made. */
    readonly property real readingDuration: Timeline.total(root._speakDurations)
    /** Whether the reading is coming out of the speakers right now. */
    readonly property bool readingPlaying: (readerLoader.item?.player.playbackState ?? MediaPlayer.StoppedState) === MediaPlayer.PlayingState
    /** While the bar is dragged, where it is in ms; -1 otherwise. */
    property real readingScrub: -1
    // Whether to play on when the drag lets go: it was playing, or about to.
    property bool _scrubResume: false

    /**
     * Whether the reading is held where it was. Its parts still being made keep
     * arriving, and wait until it goes on.
     */
    property bool speakingPaused: false

    /**
     * Where the reading is, in ms from its start: to the frame while it plays,
     * for the bar to be drawn from every frame (MarkClock.now()).
     */
    function readingPositionNow(): real {
        const start = Timeline.startOf(root._speakDurations, root._speakIndex);
        const reader = readerLoader.item;
        if (reader && reader.loadedIndex === root._speakIndex && !reader.loading)
            return start + reader.markClock.now();
        return start + root._speakStartMs;
    }

    /** The part being read, or dragged to: the passage the transcript marks in. */
    readonly property string speakingPassage: {
        const parts = root._speakParts;
        if (root.speakingMessageId.length === 0 || parts.length === 0)
            return "";
        const index = root.readingScrub >= 0 ? Timeline.locate(root._speakDurations, root.readingScrub).index : root._speakIndex;
        return parts[index] ?? "";
    }

    /**
     * Where in that passage the word being said starts, or the word the bar is
     * dragged to. Off the clip's own word timings, on time while it plays
     * (MarkClock); for a part not made yet, the same share of its characters as
     * of its estimated length -- the word the reading will start on once it is.
     */
    readonly property int speakingOffset: {
        if (root.speakingPassage.length === 0)
            return -1;
        const parts = root._speakParts;
        const durs = root._speakDurations;
        if (root.readingScrub >= 0) {
            const at = Timeline.locate(durs, root.readingScrub);
            return Timeline.charAt(parts[at.index], root._speakClips[at.index], at.offset, durs[at.index]);
        }
        const index = root._speakIndex;
        const clip = root._speakClips[index];
        const reader = readerLoader.item;
        if (reader && reader.loadedIndex === index && !reader.loading) {
            const offset = reader.markClock.offset;
            return offset >= 0 ? offset : Timeline.charAt(parts[index], clip, reader.markClock.position, durs[index]);
        }
        if (root._speakStartChar >= 0)
            return root._speakStartChar;
        return Timeline.charAt(parts[index], clip, root._speakStartMs, durs[index]);
    }

    /** Read `text` out loud through the shell's own player. */
    function speak(text: string): void {
        if ((text ?? "").trim().length === 0)
            return;
        // A new reading replaces one in progress, silently.
        root._clearReading();
        root._speakParts = root._splitForSpeech(text, Config.options.agent.ttsEngine === "kokoro");
        root._askForParts(root._speakEpoch);
    }

    /**
     * Ask for the parts the reading needs next: those not made from where it is
     * to `_speakAhead` parts after. Ones queued for parts it has moved away from
     * are dropped; the one being made finishes, and is kept.
     */
    function _askForParts(epoch: int): void {
        if (epoch !== root._speakEpoch || root.speakingMessageId.length === 0)
            return;
        const parts = root._speakParts;
        const clips = root._speakClips;
        const wanted = [];
        const last = Math.min(parts.length - 1, root._speakIndex + root._speakAhead);
        for (let k = root._speakIndex; k <= last && wanted.length < root._speakAhead; k++) {
            if (clips[k] === undefined)
                wanted.push(k);
        }
        const asked = Object.assign({}, root._speakAsked);
        const dropped = Object.assign({}, root._speakDropped);
        const drop = [];
        for (const k of Object.keys(asked)) {
            if (!wanted.includes(Number(k)) && !dropped[asked[k]]) {
                drop.push(asked[k]);
                dropped[asked[k]] = true;
            }
        }
        root._speakDropped = dropped;
        for (const k of wanted) {
            if (asked[k] === undefined)
                asked[k] = root._ttsRequest(parts[k], reply => root._onSpoken(reply, epoch, k));
        }
        root._speakAsked = asked;
        if (drop.length > 0)
            root._ttsDrop(drop);
    }

    function _onSpoken(reply: var, epoch: int, index: int): void {
        // A reading that is over: its clips have nowhere to go.
        if (epoch !== root._speakEpoch) {
            root._removeFiles(reply.paths ?? []);
            return;
        }
        const asked = Object.assign({}, root._speakAsked);
        delete asked[index];
        root._speakAsked = asked;
        if (reply.dropped ?? false)
            return;
        const clips = root._speakClips.slice();
        if (!(reply.ok ?? false) || (reply.paths ?? []).length === 0) {
            clips[index] = "failed";
            root._speakClips = clips;
            // Only the opening part reports: a failure later on is a gap in the
            // reading, not a reason to replace it with an error bubble.
            if (index === 0 && root._speakIndex === 0) {
                root.addMessage(reply.error?.length > 0 ? reply.error : Translation.tr("Could not synthesize speech"), root.interfaceRole);
                root._endReading();
            } else if (index === root._speakIndex) {
                root._goTo(index + 1, 0, -1, root._playing());
            } else {
                root._askForParts(epoch);
            }
            return;
        }
        clips[index] = { path: reply.paths[0], marks: reply.marks ?? [], duration: reply.duration ?? 0 };
        root._speakClips = clips;
        // The part the reading was waiting on: it starts now, where it was meant to.
        if (index === root._speakIndex && (readerLoader.item?.loadedIndex ?? -1) !== index)
            root._goTo(index, root._speakStartMs, root._speakStartChar, root._playing());
        else
            root._askForParts(epoch);
    }

    // Whether the reading should be coming out now: not held, not being dragged.
    function _playing(): bool {
        return !root.speakingPaused && root.readingScrub < 0;
    }

    /**
     * Put the reading at part `index`, `startMs` into it -- or, for a part not
     * made yet, at the word holding character `startChar` -- playing or held.
     * A part that could not be made is passed over.
     */
    function _goTo(index: int, startMs: real, startChar: int, play: bool): void {
        const parts = root._speakParts;
        while (index < parts.length && root._speakClips[index] === "failed") {
            index++;
            startMs = 0;
            startChar = -1;
        }
        if (index >= parts.length) {
            root._endReading();
            return;
        }
        root._speakIndex = index;
        root._speakStartMs = startMs;
        root._speakStartChar = startChar;
        const clip = root._speakClips[index];
        if (clip !== undefined) {
            const ms = startChar >= 0 ? Timeline.startForChar(clip, startChar) : startMs;
            root._speakStartMs = ms;
            root._speakStartChar = -1;
            readerLoader.active = true;
            const reader = readerLoader.item;
            if (reader.loadedIndex === index && reader.player.playbackState !== MediaPlayer.StoppedState)
                reader.seekWithin(ms, play);
            else
                reader.load(index, clip.path, ms, play);
        } else if (readerLoader.item && readerLoader.item.loadedIndex >= 0) {
            // Waiting on a part still being made: whatever is in the player is
            // not where the reading is.
            readerLoader.item.fadeAndStop();
        }
        root._askForParts(root._speakEpoch);
    }

    /** A clip played to its end: on to the next part, or the reading is done. */
    function _partEnded(index: int): void {
        if (index < 0 || index !== root._speakIndex)
            return;
        if (index + 1 >= root._speakParts.length) {
            root._endReading();
            return;
        }
        root._goTo(index + 1, 0, -1, root._playing());
    }

    /** Move the reading to `ms` from its start: the start of the word there. */
    function _seek(ms: real, play: bool): void {
        const durs = root._speakDurations;
        if (root._speakParts.length === 0 || Timeline.total(durs) <= 0)
            return;
        const at = Timeline.locate(durs, ms);
        const clip = root._speakClips[at.index];
        if (clip !== undefined && clip !== "failed")
            root._goTo(at.index, Timeline.wordStart(clip, at.offset), -1, play);
        else
            root._goTo(at.index, at.offset, Timeline.charAt(root._speakParts[at.index], null, at.offset, durs[at.index]), play);
    }

    /** The bar was pressed: the audio holds while it is dragged. */
    function beginScrub(ms: real): void {
        if (root.speakingMessageId.length === 0 || root.readingScrub >= 0)
            return;
        root._scrubResume = !root.speakingPaused;
        root.readingScrub = Math.max(0, Math.min(ms, root.readingDuration));
        readerLoader.item?.hold();
    }

    /** The bar is being dragged: the transcript marks the word it is at. */
    function scrubTo(ms: real): void {
        if (root.readingScrub >= 0)
            root.readingScrub = Math.max(0, Math.min(ms, root.readingDuration));
    }

    /** The bar was let go: the reading goes on from the word it was left at. */
    function endScrub(ms: real): void {
        if (root.readingScrub < 0)
            return;
        root.readingScrub = -1;
        root._seek(ms, root._scrubResume);
    }

    /** Move the reading without a drag -- the keyboard's arrows on the bar. */
    function seekReading(ms: real): void {
        if (root.speakingMessageId.length > 0)
            root._seek(ms, root._playing());
    }

    /** Hold a read-aloud at the word it is on: fade to zero, then pause. */
    function pauseSpeaking(): void {
        if (root.speakingMessageId.length === 0 || root.speakingPaused)
            return;
        root.speakingPaused = true;
        readerLoader.item?.hold();
    }

    /** Go on from where it was held, fading back in. */
    function resumeSpeaking(): void {
        if (!root.speakingPaused)
            return;
        root.speakingPaused = false;
        const reader = readerLoader.item;
        if (reader && reader.loadedIndex === root._speakIndex)
            reader.release();
        else if (root._speakClips[root._speakIndex] !== undefined)
            root._goTo(root._speakIndex, root._speakStartMs, root._speakStartChar, true);
        // Otherwise the part is still being made, and plays when it comes.
    }

    /** Silence a read-aloud: fade to zero, then a graceful stop. Nothing is killed. */
    function stopSpeaking(): void {
        root._endReading();
    }

    /** The reading is over: its clips go, and the UI is told. */
    function _endReading(): void {
        root._clearReading();
        root.speakingMessageId = "";
    }

    // Everything of the reading but which message it was, for a new one to start
    // on: what is playing fades out, what is being made is dropped.
    function _clearReading(): void {
        root._speakEpoch++;
        const asked = Object.values(root._speakAsked);
        const paths = root._speakClips.filter(clip => clip && clip.path).map(clip => clip.path);
        if (asked.length > 0)
            root._ttsDrop(asked);
        // A clip still fading out keeps playing from its open file.
        root._removeFiles(paths);
        root._speakParts = [];
        root._speakClips = [];
        root._speakAsked = ({});
        root._speakDropped = ({});
        root._speakIndex = 0;
        root._speakStartMs = 0;
        root._speakStartChar = -1;
        root.readingScrub = -1;
        root.speakingPaused = false;
        readerLoader.item?.fadeAndStop();
    }

    // The server died: nothing asked of it will come. The reading plays what was
    // made and ends there, rather than waiting on the rest.
    function _serverGone(): void {
        if (root._speakParts.length === 0)
            return;
        const clips = root._speakClips.slice();
        for (let k = 0; k < root._speakParts.length; k++) {
            if (clips[k] === undefined)
                clips[k] = "failed";
        }
        root._speakClips = clips;
        root._speakAsked = ({});
        const reader = readerLoader.item;
        if (!reader || reader.loadedIndex !== root._speakIndex)
            root._goTo(root._speakIndex, 0, -1, root._playing());
    }

    // Clip files to delete. A removal asked for while one runs waits its turn:
    // `running = true` on a running Process does nothing, and the files stayed.
    property var _filesToRemove: []

    function _removeFiles(paths: var): void {
        if (paths.length === 0)
            return;
        root._filesToRemove = [...root._filesToRemove, ...paths];
        if (!cleanupOrphan.running)
            cleanupOrphan.next();
    }

    Process {
        id: cleanupOrphan
        function next(): void {
            if (root._filesToRemove.length === 0)
                return;
            cleanupOrphan.command = ["rm", "-f", ...root._filesToRemove];
            root._filesToRemove = [];
            cleanupOrphan.running = true;
        }
        onExited: cleanupOrphan.next()
    }

    // ── Finished-turn notification ─────────────────────────────────
    //
    // Only worth sending when the answer is somewhere the user cannot see, which
    // means the panel is shut or it is showing a different tab. A popup for a reply
    // already on screen is pure noise.

    readonly property bool viewingAgent: GlobalStates.policiesPanelOpen
        && root.agentTabIndex >= 0
        && Persistent.states.sidebar.policies.tab === root.agentTabIndex

    /**
     * Goes in as the `image-path` hint rather than `-i`: the notification server
     * treats an app icon as a freedesktop theme name and draws `image-missing` when
     * it is not one -- which a Material Symbol name never is. The hint takes a file.
     */
    readonly property string notifyIconPath: FileUtils.trimFileProtocol(Qt.resolvedUrl("../assets/icons/ii-vynx.svg").toString())

    property Process notifier: Process {}

    function notifyFinished(message: var): void {
        if (!(Config.options.agent?.notifyWhenAway ?? true))
            return;
        // One line either way: "why didn't it notify" is otherwise invisible.
        if (root.viewingAgent) {
            console.log("[Agent] No notification: the tab is on screen.");
            return;
        }

        const failed = (message?.error ?? "").length > 0;
        const body = failed ? message.error : (message?.content ?? "");
        const summary = body.replace(/\s+/g, " ").trim().slice(0, 140);

        notifier.command = ["notify-send",
            "-a", root.agentName,
            "-u", failed ? "critical" : "normal",
            "-h", `string:image-path:${root.notifyIconPath}`,
            // Replaces the previous reply's popup rather than stacking, on servers
            // that honour the hint.
            "-h", "string:x-canonical-private-synchronous:ii-agent",
            failed ? Translation.tr("%1 — turn failed").arg(root.agentName) : Translation.tr("%1 replied").arg(root.currentModel.length > 0 ? root.currentModel : root.agentName),
            summary.length > 0 ? summary : Translation.tr("Finished.")];
        notifier.running = true;
        console.log("[Agent] Notification sent.");
    }

    // ── Waiting-on-you notification ────────────────────────────────
    //
    // A turn parked on an approval or a question goes nowhere until it is answered,
    // so it is worth a notification more than a reply is. It stays up until the
    // request is answered or its card comes on screen, then closes itself; its
    // Open action brings the panel up on the agent.

    property var _waitingNotices: []

    property Component waitingNotice: Component {
        Process {
            id: notice
            required property var srq
            property int serverId: -1
            property bool closed: false

            // `--print-id` writes the id first; a chosen action is written as its key.
            stdout: SplitParser {
                onRead: line => {
                    if (notice.serverId < 0) {
                        const id = parseInt(line);
                        if (isNaN(id))
                            return;
                        notice.serverId = id;
                        root._closeAnsweredNotices(); // Answered before the id came back
                    } else if (line.trim() === "open") {
                        GlobalStates.policiesPanelOpen = true;
                        root.focusAgentTab();
                    }
                }
            }
            onExited: {
                root._waitingNotices = root._waitingNotices.filter(other => other !== notice);
                notice.destroy();
            }
        }
    }

    function notifyWaiting(request: var, approval: bool): void {
        if (!(Config.options.agent?.notifyWhenAway ?? true))
            return;
        if (root.viewingAgent) {
            console.log("[Agent] No notification: the request is on screen.");
            return;
        }

        const question = request.questions?.[0]?.question ?? request.question ?? "";
        const body = (approval ? (request.command || request.description || "") : question).trim();
        const notice = root.waitingNotice.createObject(root, {
            srq: request.srq
        });
        notice.command = ["notify-send", "--print-id", "--wait",
            "-a", root.agentName,
            "-u", "critical",
            "-t", "0", // Up until answered, not until the popup timeout
            "-h", `string:image-path:${root.notifyIconPath}`,
            "-A", `open=${Translation.tr("Open")}`,
            "--", // A command can start with a dash
            approval ? Translation.tr("%1 needs your approval").arg(root.agentName) : Translation.tr("%1 has a question").arg(root.agentName),
            // The server renders markup, and a command is full of < > &
            body.length > 0 ? StringUtils.escapeHtml(body.slice(0, 300)) : (approval ? Translation.tr("Waiting for your approval") : Translation.tr("Waiting for your answer"))];
        root._waitingNotices = [...root._waitingNotices, notice];
        notice.running = true;
        console.log("[Agent] Waiting notification sent.");
    }

    function _closeAnsweredNotices(): void {
        const waiting = [root.pendingApproval?.srq, root.pendingClarify?.srq];
        for (const notice of root._waitingNotices) {
            if (notice.closed || notice.serverId < 0)
                continue;
            if (root.viewingAgent || !waiting.includes(notice.srq)) {
                notice.closed = true;
                Notifications.discardNotification(notice.serverId + Notifications.idOffset);
            }
        }
    }

    onPendingApprovalChanged: root._closeAnsweredNotices()
    onPendingClarifyChanged: root._closeAnsweredNotices()
    onViewingAgentChanged: root._closeAnsweredNotices()

    // ── Shell entry points ─────────────────────────────────────────

    /**
     * The agent is the panel's first page when enabled, so there is nothing to
     * count. -1 when it is switched off and has no tab at all.
     */
    readonly property int agentTabIndex: root.enabled && (Config.options?.policies?.agent ?? 1) !== 0 ? 0 : -1

    function focusAgentTab(): void {
        if (root.agentTabIndex < 0)
            return;
        Persistent.states.sidebar.policies.tab = root.agentTabIndex;
    }

    /** Open the panel on the agent and start dictating; press again to transcribe. */
    function dictateToggle(): void {
        if (root.voiceState === "transcribing")
            return; // Mid-transcription; let it finish.
        if (root.voiceState === "listening") {
            root.stopDictation();
            return;
        }
        GlobalStates.policiesPanelOpen = true;
        root.focusAgentTab();
        root.startDictation();
    }

    property GlobalShortcut dictateShortcut: GlobalShortcut {
        name: "agentDictate"
        description: "Agent: open and dictate, press again to send"
        onPressed: root.dictateToggle()
    }

    property GlobalShortcut stopShortcut: GlobalShortcut {
        name: "agentStop"
        description: "Agent: stop the current response"
        onPressed: root.interrupt()
    }

    property IpcHandler ipc: IpcHandler {
        target: "agent"

        function dictate(): void {
            root.dictateToggle();
        }
        function stop(): void {
            root.interrupt();
        }
        function open(): void {
            GlobalStates.policiesPanelOpen = true;
            root.focusAgentTab();
        }
        function newSession(): void {
            root.newSession();
        }
        /** claude | codex | antigravity -- only one that is installed. */
        function backend(id: string): void {
            root.setBackend(id);
        }
        /** Settings changed `id`'s sign-in or install: look again, and restart on it if it answers. */
        function refresh(id: string): void {
            root.refreshFromSettings(id);
        }
    }

    // ── Process ──────────────────────────────────────────────────────────

    Process {
        id: bridgeProc
        running: false
        stdinEnabled: true
        // Read at start, so a switch only lands on the next launch -- setBackend
        // and a settings change restart the process for exactly that.
        command: ["python3", root.bridgeScript, root.backend?.id ?? ""]
        environment: root._bridgeEnv

        stdout: SplitParser {
            onRead: line => {
                if (line.trim().length === 0)
                    return;
                let frame;
                try {
                    frame = JSON.parse(line);
                } catch (e) {
                    return;
                }
                root._handleFrame(frame);
            }
        }

        stderr: SplitParser {
            onRead: line => {
                const text = line.trim();
                if (text.length === 0)
                    return;
                // The bridge's own account of why it cannot start: not installed,
                // or signed out. Shown as is; neither is fixed by a restart.
                if (text.startsWith("[agent-missing]") || text.startsWith("[agent-error]"))
                    root.lastError = text.replace(/^\[agent-(missing|error)\]\s*/, "");
                console.log("[Agent]", text);
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.ready = false;
            root.starting = false;
            root.setupText = "";
            // Its pending callbacks are dropped below, so nothing else would clear it.
            root.limitsLoading = false;
            root.sessionId = "";
            root.streamingId = "";
            root._releaseRun();
            root.busy = false;
            root.statusText = "";
            root.pendingApproval = null;
            root.pendingClarify = null;
            root.speakingMessageId = "";
            root._pendingCalls = ({});
            root._queuedCalls = [];

            if (root._restarting) {
                root._restarting = false;
                if (root.enabled)
                    root.ensureStarted();
                return;
            }

            // 127: the CLI is not installed. 78: it needs the user (signed out).
            if (exitCode === 127 || exitCode === 78)
                return;

            root.consecutiveFailures++;
            if (root.consecutiveFailures <= root.maxRestarts && root.enabled) {
                restartTimer.start();
            } else if (root.lastError.length === 0) {
                root.lastError = Translation.tr("%1 stopped (exit %2)").arg(root.agentName).arg(exitCode);
            }
        }
    }

    Timer {
        id: restartTimer
        // Backs off so a bridge that dies on startup does not spin.
        interval: 1000 * root.consecutiveFailures
        onTriggered: {
            if (root.enabled && !bridgeProc.running)
                root.ensureStarted();
        }
    }

    // The prompt typed before the session existed goes out as soon as it does.
    onSessionIdChanged: {
        if (root.sessionId.length === 0 || root._deferredPrompt.length === 0)
            return;
        const prompt = root._deferredPrompt;
        root._deferredPrompt = "";
        root._submit(prompt);
    }

    onEnabledChanged: {
        if (!root.enabled && bridgeProc.running) {
            bridgeProc.running = false;
        }
    }
}
