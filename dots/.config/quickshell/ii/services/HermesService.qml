pragma Singleton
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services.hermes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtMultimedia

/**
 * Hermes — the Nous Research agent, driven from the sidebar.
 *
 * Hermes' desktop app spawns `hermes serve` and talks to it over a websocket.
 * That needs a port, a session token and a server lifecycle to babysit, so this
 * takes the other transport the same backend offers: `tui_gateway.entry` speaking
 * line-delimited JSON-RPC 2.0 on stdio, which is what hermes' own
 * scripts/probe_active_session_exclusivity.py drives. One process, no port, and it
 * dies with the shell.
 *
 * Frames are either a response (`id` set) or an event
 * (`{method: "event", params: {type, session_id, payload}}`).
 *
 * The model picked here is applied with `--session`, never `--global`: the sidebar
 * gets its own model without rewriting the model the user's `hermes` CLI starts on.
 * The choice is remembered in Persistent and re-applied to each new session.
 */
Singleton {
    id: root

    /**
     * Instantiates the singleton at shell start so the global shortcuts and the IPC
     * handler register without waiting for the page to be opened. The gateway
     * process itself stays lazy -- see ensureStarted().
     */
    function load(): void {}

    readonly property string interfaceRole: "interface"
    readonly property string gatewayScript: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/hermes/gateway.sh"))

    readonly property bool enabled: Config.options?.hermes?.enable ?? false

    // ── Connection ───────────────────────────────────────────────────────

    property bool starting: false
    property bool ready: false
    property string lastError: ""
    // Set once the launcher reports no hermes-agent checkout: retrying cannot fix
    // a missing install, so the page shows how to get one instead of a spinner.
    property bool missing: false

    property int consecutiveFailures: 0
    readonly property int maxRestarts: 3

    // ── Gateway ──────────────────────────────────────────────────────────
    //
    // Which Hermes install the sidebar drives. The list is the desktop app's own,
    // so a host added there shows up here. Only local and ssh gateways: the stdio
    // transport this uses goes over ssh as-is, and the remote's HERMES_HOME brings
    // its own sessions, memory and personality with it.
    property var gateways: [{ id: "local", kind: "local", label: Translation.tr("This device") }]
    readonly property var gateway: root.gateways.find(g => g.id === (Persistent.states?.hermes?.gateway ?? "local")) ?? root.gateways[0]
    readonly property bool remote: root.gateway.kind === "ssh"
    property bool _switchingGateway: false

    function setGateway(id: string): void {
        if (id === root.gateway.id)
            return;
        Persistent.states.hermes.gateway = id;
        if (root.busy)
            root.interrupt();
        root.clearMessages();
        root.sessionTitle = "";
        root.usage = null;
        root.recentSessions = [];
        root.sideTasks = [];
        root.subagents = [];
        root.currentModel = "";
        root.currentProvider = "";
        root.approvalMode = "";
        root.missing = false;
        root.lastError = "";
        root.consecutiveFailures = 0;
        restartTimer.stop();
        // The old process has to be gone before the new one starts; onExited
        // picks the switch up rather than counting it as a crash.
        if (gatewayProc.running) {
            root._switchingGateway = true;
            gatewayProc.running = false;
        } else if (root.enabled) {
            root.ensureStarted();
        }
    }

    FileView {
        path: FileUtils.trimFileProtocol(`${Directories.config}/Hermes/connections.json`)
        watchChanges: true
        onFileChanged: reload()
        // Read before the lazy start can pick a gateway off the fallback list.
        blockLoading: true
        onLoaded: {
            try {
                const listed = (JSON.parse(text()).connections ?? []).filter(c => c.kind === "ssh" && c.host).map(c => ({
                    id: c.id,
                    kind: "ssh",
                    label: c.label || c.host,
                    host: c.host,
                    user: c.user ?? "",
                    keyPath: c.keyPath ?? ""
                }));
                root.gateways = [root.gateways[0], ...listed];
            } catch (e) {
                console.log("[Hermes] could not read the desktop app's gateways:", e);
            }
        }
    }

    // ── Session ──────────────────────────────────────────────────────────

    property string sessionId: ""
    property string storedSessionId: ""
    property string sessionTitle: ""
    property string cwd: ""
    property string branch: ""
    property bool busy: false
    // Transient one-liner from the agent ("(´･_･`) reasoning...", "Resuming…").
    property string statusText: ""

    // ── What the session is running with ─────────────────────────────────

    property string currentModel: ""
    property string currentProvider: ""
    property string approvalMode: ""
    property bool yolo: false
    // { group: [toolName, ...] }
    property var sessionTools: ({})
    property var sessionSkills: ({})
    property var usage: null

    // ── Inventory ────────────────────────────────────────────────────────

    property var providers: []
    property bool providersLoading: false
    property var slashCommands: []
    property var recentSessions: []

    // ── Side work ────────────────────────────────────────────────────────
    //
    // A background turn or a `btw` question runs on its own agent thread and
    // reports back as an event, so the composer stays free while it does. Both
    // land in the same list; `kind` is what the card renders as.
    // [{ taskId, kind: "bg"|"btw", text, startedAt, done, result, failed }]
    property var sideTasks: []
    readonly property int runningSideTasks: root.sideTasks.filter(task => !task.done).length

    // Delegated children of the current turn, from subagent.list.
    property var subagents: []
    property bool spawnPaused: false

    // ── Context ──────────────────────────────────────────────────────────
    //
    // The live percentage rides along on every usage payload, so the meter costs
    // nothing; the breakdown is only fetched when the meter is actually opened.
    readonly property int contextPercent: root.usage?.context_percent ?? 0
    readonly property int contextUsed: root.usage?.context_used ?? 0
    readonly property int contextMax: root.usage?.context_max ?? 0
    property bool compressing: false
    property var contextBreakdown: null

    // ── Processes ────────────────────────────────────────────────────────

    property var agentProcesses: []
    property var spawnTrees: []

    // ── Transcript ───────────────────────────────────────────────────────

    property var messageIDs: []
    property var messageByID: ({})
    property string streamingId: ""

    // ── Voice ──────────────────────────────────────────────────────
    //
    // The shell records (pw-record), Hermes transcribes with whatever `stt.provider`
    // it is configured with. See the Dictation section below for why the capture is
    // not the agent's own.

    // Dictation readiness is the shell's own recorder, which is what actually runs
    // when the mic button is pressed.
    readonly property bool dictationAvailable: root.speech.available || root.speech.downloading
    readonly property string voiceState: root.speech.recording ? "listening" : root.speech.transcribing ? "transcribing" : "idle"
    readonly property bool dictating: root.voiceState !== "idle"

    // Emitted with a finished transcript so the page can put it in the input box.
    signal dictationTranscript(string text)

    // A `prefill` directive (e.g. /undo) hands text back to edit rather than send.
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
     * Composer token -> { kind, name, send, paths, icon, thumb }. kind is image, pdf,
     * file or folder; paths are the images it staged on the session; thumb is the
     * picture a tile shows, empty for a file. A token is the name bracketed
     * with U+2063, led by figure spaces the chip's icon sits on, and made of
     * non-breaking characters so it never wraps; HermesAttachmentChips draws the
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
        const thumb = kind === "image" || kind === "pdf" ? (paths[0] ?? "") : "";
        return { kind, name, send, paths, icon, thumb };
    }

    /**
     * A stored user turn, back as { text, attachments }. The gateway stores the text
     * the model read: the references each chip was sent as, then its own context
     * warnings, then one `@image:<path>` line per staged image, a PDF's pages named
     * pdf_p*. tools/check-hermes-composer.py runs this.
     */
    function _restoredTurn(body: string): var {
        const lines = body.split("\n");
        const images = [];
        while (lines.length > 0 && lines[lines.length - 1].startsWith("@image:"))
            images.unshift(lines.pop().slice(7));
        const text = lines.join("\n").replace(/\s*--- Context Warnings ---[\s\S]*$/, "").trim();
        const pages = images.filter(path => FileUtils.fileNameForPath(path).startsWith("pdf_p"));
        const photos = images.filter(path => !pages.includes(path));
        const attachments = [];
        // An exec loop: the shell's JS engine has no matchAll
        const refs = /\[(Image|PDF): ([^\]\n]+)\]|@(file|folder):("[^"\n]+"|`[^`\n]+`|'[^'\n]+'|\S+)/g;
        for (let match = refs.exec(text); match !== null; match = refs.exec(text)) {
            if (attachments.some(item => item.send === match[0]))
                continue;
            if (match[1]) {
                const image = match[1] === "Image";
                attachments.push(root._marker(image ? "image" : "pdf", match[2], match[0], image ? photos.splice(0, 1) : pages.slice(0, 1)));
            } else {
                const path = match[4].replace(/^["'`]|["'`]$/g, "");
                attachments.push(root._marker(match[3], match[3] === "folder" ? FileUtils.folderNameForPath(path) : FileUtils.fileNameForPath(path), match[0], []));
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
        // The gateway detaches every copy of a path, so one pasted twice stays
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

    // Non-null while the agent has stopped to ask a question (the `clarify` tool).
    // Payload is either {question, choices, multi_select, request_id} or a batch
    // {questions: [{qid, question, choices, multi_select}], request_id}.
    property var pendingClarify: null

    property Component messageComponent: HermesMessageData {}

    signal transcriptCleared

    // ── JSON-RPC plumbing ────────────────────────────────────────────────

    property int _nextRequestId: 1
    // id -> callback(result, error). Plain object: nothing binds to it.
    property var _pendingCalls: ({})
    property var _queuedCalls: []

    function ensureStarted(): void {
        if (root.missing || gatewayProc.running || root.starting)
            return;
        root.starting = true;
        root.lastError = "";
        gatewayProc.running = true;
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

        // Before gateway.ready the process either is not up or has not finished
        // importing the agent; either way stdin writes would be lost.
        if (!root.ready) {
            root._queuedCalls.push(frame);
            root.ensureStarted();
            return;
        }
        gatewayProc.write(JSON.stringify(frame) + "\n");
    }

    function _drainQueue(): void {
        const queued = root._queuedCalls;
        root._queuedCalls = [];
        queued.forEach(frame => gatewayProc.write(JSON.stringify(frame) + "\n"));
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
        const id = `hermes-${root.messageIDs.length}-${Date.now()}`;
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
     * The gateway's message.start/message.complete bracket a single *model* turn,
     * not a run: an agentic answer is turn (text, calls tools) -> tools run -> turn
     * (text) -> tools -> turn (final text). Opening a fresh bubble on every
     * message.start split one answer into three stacked cards, each with its own
     * header and its own copy/retry buttons, and left the reader to work out which
     * commands belonged to which paragraph.
     *
     * So the run's card is held here and later turns continue it. It is released
     * when the user speaks again, which is the only unambiguous end of a run --
     * the gateway has no run-level event.
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
        root.call("session.create", {}, (result, error) => {
            if (error) {
                root.lastError = error.message ?? "session.create failed";
                return;
            }
            root._adoptSession(result);
            root.applyPreferredModel();
            root.refreshProviders();
            root.refreshSlashCommands();
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
        if (info.provider !== undefined)
            root.currentProvider = info.provider ?? "";
        if (info.approval_mode !== undefined)
            root.approvalMode = info.approval_mode ?? "";
        if (info.yolo !== undefined)
            root.yolo = info.yolo ?? false;
        if (info.tools !== undefined)
            root.sessionTools = info.tools ?? ({});
        if (info.skills !== undefined)
            root.sessionSkills = info.skills ?? ({});
        if (info.cwd !== undefined)
            root.cwd = info.cwd ?? "";
        if (info.branch !== undefined)
            root.branch = info.branch ?? "";
    }

    /** Fresh session, fresh transcript. */
    function newSession(): void {
        if (root.busy)
            root.interrupt();
        const previous = root.sessionId;
        root.sessionId = "";
        root.sessionTitle = "";
        root.usage = null;
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
        root.call("session.resume", { session_id: storedId }, (result, error) => {
            if (error) {
                root.addMessage(Translation.tr("Could not resume: %1").arg(error.message ?? ""), root.interfaceRole);
                return;
            }
            root._adoptSession(result);
            root._restoreTranscript(result);
            root.refreshRecentSessions();
        });
    }

    /**
     * Drop a stored session. The gateway refuses to delete one that is live (its
     * agent would trip a foreign key on the next flush), so the current chat is
     * rolled over to a fresh one first and then removed.
     */
    function deleteSession(storedId: string): void {
        if ((storedId ?? "").length === 0)
            return;
        if (storedId === root.storedSessionId) {
            root.newSession();
            // The close is asynchronous; give it the turn to land before deleting.
            deleteRetry.pendingId = storedId;
            deleteRetry.restart();
            return;
        }
        root._deleteStored(storedId);
    }

    function _deleteStored(storedId: string): void {
        root.call("session.delete", { session_id: storedId }, (result, error) => {
            if (error) {
                root.addMessage(error.message ?? Translation.tr("Could not delete that chat"), root.interfaceRole);
                return;
            }
            root.refreshRecentSessions();
        });
    }

    Timer {
        id: deleteRetry
        property string pendingId: ""
        interval: 400
        onTriggered: {
            if (deleteRetry.pendingId.length > 0)
                root._deleteStored(deleteRetry.pendingId);
            deleteRetry.pendingId = "";
        }
    }

    /**
     * Rebuild the transcript from a resumed session.
     *
     * Stored rows are NOT shaped like the live event stream: the body is `text`
     * (not `content`), and a tool call is its own row with role "tool" rather than
     * something hanging off the assistant turn. Reading them as live messages gave
     * a column of empty bubbles -- one per tool row, plus one per assistant turn
     * whose text was being looked for under the wrong key.
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
                    // args} -- the gateway does not persist what the tool returned,
                    // so a resumed chat can only ever show the call, not its output.
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

    // ── Side work: background turns and `btw` questions ───────────────────

    function _startSideTask(method: string, kind: string, text: string): void {
        const clean = (text ?? "").trim();
        if (clean.length === 0 || root.sessionId.length === 0)
            return;
        root.call(method, { session_id: root.sessionId, text: clean }, (result, error) => {
            if (error) {
                root.addMessage(error.message ?? Translation.tr("Could not start that task."), root.interfaceRole);
                return;
            }
            root.sideTasks = [...root.sideTasks, {
                taskId: result.task_id ?? "",
                kind: kind,
                text: clean,
                startedAt: Date.now(),
                done: false,
                failed: false,
                result: ""
            }];
        });
    }

    /**
     * Runs a whole turn on its own agent, leaving this conversation free to carry
     * on. The answer arrives as `background.complete`, never in the transcript.
     */
    function runInBackground(text: string): void {
        root._startSideTask("prompt.background", "bg", text);
    }

    function _finishSideTask(taskId: string, text: string, question: string): void {
        const answer = text ?? "";
        const failed = answer.startsWith("error: ");
        // `/bg` and `/btw` are gateway slash commands too, so a task can finish that
        // this never started. Adopting it here is what keeps a slash-typed question
        // from answering into nothing, which is what used to happen.
        if (!root.sideTasks.some(task => task.taskId === taskId)) {
            root.sideTasks = [...root.sideTasks, {
                taskId: taskId,
                kind: taskId.startsWith("btw_") ? "btw" : "bg",
                text: question ?? "",
                startedAt: Date.now(),
                done: true,
                failed: failed,
                result: answer
            }];
            return;
        }
        root.sideTasks = root.sideTasks.map(task => task.taskId !== taskId ? task : Object.assign({}, task, {
            done: true,
            failed: failed,
            result: answer
        }));
    }

    function dismissSideTask(taskId: string): void {
        root.sideTasks = root.sideTasks.filter(task => task.taskId !== taskId);
    }

    function clearFinishedSideTasks(): void {
        root.sideTasks = root.sideTasks.filter(task => !task.done);
    }

    // ── Delegated children ────────────────────────────────────────────────

    // Children seen so far in this run, keyed by id. A child that has already
    // finished drops out of subagent.list, so the snapshot has to be built up
    // as the run goes rather than read off the end of it.
    property var _runSubagents: ({})
    property real _runSubagentsStartedAt: 0

    function refreshSubagents(): void {
        if (root.sessionId.length === 0)
            return;
        root.call("subagent.list", { session_id: root.sessionId }, (result, error) => {
            const live = error ? [] : (result.subagents ?? []);
            root.subagents = live;
            if (live.length === 0)
                return;
            if (root._runSubagentsStartedAt === 0)
                root._runSubagentsStartedAt = Date.now() / 1000;
            const seen = Object.assign({}, root._runSubagents);
            live.forEach(subagent => {
                const id = subagent.subagent_id ?? "";
                if (id.length > 0)
                    seen[id] = subagent;
            });
            root._runSubagents = seen;
        });
    }

    /**
     * Nothing in the backend writes spawn trees -- spawn_tree.save takes the
     * subagent list from whoever was watching. So a run only ends up in the
     * history if this saves it as the turn finishes.
     */
    function _saveSpawnTree(): void {
        const collected = Object.values(root._runSubagents);
        root._runSubagents = ({});
        const startedAt = root._runSubagentsStartedAt;
        root._runSubagentsStartedAt = 0;
        if (collected.length === 0)
            return;
        root.call("spawn_tree.save", {
            session_id: root.sessionId,
            subagents: collected,
            started_at: startedAt,
            finished_at: Date.now() / 1000,
            label: root.sessionTitle
        }, (result, error) => {
            if (!error)
                root.refreshSpawnTrees();
        });
    }

    onBusyChanged: {
        if (!root.busy)
            root._saveSpawnTree();
    }

    function refreshDelegation(): void {
        root.call("delegation.status", {}, (result, error) => {
            if (!error)
                root.spawnPaused = result.paused ?? false;
        });
    }

    function setSpawnPaused(paused: bool): void {
        root.call("delegation.pause", { paused: paused }, (result, error) => {
            if (!error)
                root.spawnPaused = result.paused ?? paused;
        });
    }

    /** Queues text into a live child. The tool call it is inside is never cut. */
    function steerSubagent(subagentId: string, text: string): void {
        const clean = (text ?? "").trim();
        if (clean.length === 0)
            return;
        root.call("subagent.steer", { session_id: root.sessionId, subagent_id: subagentId, text: clean }, (result, error) => {
            if (error || (result.status ?? "") === "rejected")
                root.addMessage(Translation.tr("That task would not take the steer."), root.interfaceRole);
        });
    }

    function interruptSubagent(subagentId: string): void {
        root.call("subagent.interrupt", { session_id: root.sessionId, subagent_id: subagentId }, () => root.refreshSubagents());
    }

    function tailSubagent(subagentId: string, callback: var): void {
        root.call("subagent.tail", { session_id: root.sessionId, subagent_id: subagentId }, (result, error) => {
            if (callback)
                callback(error ? "" : (result.text ?? ""), error ? false : (result.available ?? false));
        });
    }

    function refreshSpawnTrees(): void {
        root.call("spawn_tree.list", { session_id: root.sessionId, limit: 20 }, (result, error) => {
            root.spawnTrees = error ? [] : (result.entries ?? []);
        });
    }

    function loadSpawnTree(path: string, callback: var): void {
        root.call("spawn_tree.load", { path: path }, (result, error) => {
            if (callback)
                callback(error ? null : result);
        });
    }

    // ── Context ───────────────────────────────────────────────────────────

    /** Folds the conversation down so a long session can keep going. */
    function compressSession(focusTopic: string): void {
        if (root.compressing || root.busy || root.sessionId.length === 0)
            return;
        root.compressing = true;
        const params = { session_id: root.sessionId };
        if ((focusTopic ?? "").trim().length > 0)
            params.focus_topic = focusTopic.trim();
        root.call("session.compress", params, (result, error) => {
            root.compressing = false;
            if (error) {
                root.addMessage(error.message ?? Translation.tr("Could not compress this conversation."), root.interfaceRole);
                return;
            }
            root.addMessage(result.message ?? Translation.tr("Compressed this conversation."), root.interfaceRole);
            root.refreshContextBreakdown();
        });
    }

    function refreshContextBreakdown(): void {
        if (root.sessionId.length === 0)
            return;
        root.call("session.context_breakdown", { session_id: root.sessionId }, (result, error) => {
            root.contextBreakdown = error ? null : result;
        });
    }

    // ── Settings the gateway owns ─────────────────────────────────────────

    function setConfig(key: string, value: var, callback: var): void {
        root.call("config.set", { key: key, value: value, session_id: root.sessionId }, (result, error) => {
            if (error)
                root.addMessage(error.message ?? Translation.tr("Hermes would not take that setting."), root.interfaceRole);
            if (callback)
                callback(error ? null : result);
        });
    }

    /** manual | smart | off. The session info event echoes the change back. */
    function setApprovalMode(mode: string): void {
        root.setConfig("approvals.mode", mode, null);
    }

    function setYolo(on: bool): void {
        root.setConfig("yolo", on ? "on" : "off", null);
    }

    // ── Attachments ───────────────────────────────────────────────────────

    function attachPdf(path: string, firstPage: int, lastPage: int): void {
        const clean = FileUtils.trimFileProtocol((path ?? "").trim());
        if (clean.length === 0 || root.sessionId.length === 0)
            return;
        const params = { session_id: root.sessionId, path: clean };
        if (firstPage > 0)
            params.first_page = firstPage;
        if (lastPage > 0)
            params.last_page = lastPage;
        root.call("pdf.attach", params, (result, error) => {
            if (error) {
                root.addMessage(error.message ?? Translation.tr("Could not read that PDF."), root.interfaceRole);
                return;
            }
            const name = FileUtils.fileNameForPath(clean);
            root._addMarker("pdf", name, `[PDF: ${name}]`, (result.pages ?? []).map(page => page.path ?? ""));
        });
    }

    // ── Processes ─────────────────────────────────────────────────────────

    function refreshAgentProcesses(): void {
        root.call("agents.list", {}, (result, error) => {
            root.agentProcesses = error ? [] : (result.processes ?? []);
        });
    }

    // ── Per-message actions ────────────────────────────────────────

    // Which turn we asked to be read out. There is no "speech finished" event on
    // the wire (tts_done_event stays inside the agent), so this is what we asked
    // for rather than what is provably still playing -- pressing stop after it has
    // already ended is harmless.
    property string speakingMessageId: ""

    /** Read one message out loud through the agent's TTS. */
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
     * Re-run the last turn. `/retry` is the agent's own command for it, so what gets
     * replayed is the history the agent actually holds rather than a guess assembled
     * from this transcript. The local trailing replies are dropped first, otherwise
     * the old answer would sit above the new one.
     */
    function regenerate(): void {
        if (root.busy || root.sessionId.length === 0)
            return;
        let index = root.messageIDs.length - 1;
        while (index >= 0 && root.messageByID[root.messageIDs[index]]?.role !== "user")
            index--;
        if (index < 0)
            return;
        root.removeMessagesFrom(index + 1);
        root.busy = true;
        root.call("slash.exec", { command: "/retry", session_id: root.sessionId }, (result, error) => {
            if (error) {
                root.busy = false;
                root.addMessage(error.message ?? Translation.tr("Could not retry"), root.interfaceRole);
                return;
            }
            // A retry that streams answers through the usual message events; one that
            // only prints (nothing to retry) has to release `busy` itself.
            const output = (result.output ?? "").trim();
            if (output.length > 0) {
                root.busy = false;
                root._reportCommandOutput(output);
            }
        });
    }

    /**
     * Rewind the transcript to the user turn `messageId` names, dropping it and
     * everything after it.
     *
     * `/undo` is the agent's own rewind: it soft-deletes the truncated rows on
     * disk and rewinds the live history, so the model forgets exactly what this
     * transcript stops showing. Reimplementing it here would only desync the two.
     * It counts *user turns* rather than messages, which is why the turns from
     * `messageId` on are counted instead of the index being sent.
     *
     * `prefill` hands the rewound turn back to the composer to be edited and sent
     * again -- the gateway returns its text for exactly that.
     */
    function rewindTo(messageId: string, prefill: bool): void {
        const index = root.messageIDs.indexOf(messageId);
        if (index < 0 || root.busy || root.sessionId.length === 0)
            return;
        const turns = root.messageIDs.slice(index).filter(id => root.messageByID[id]?.role === "user").length;
        if (turns === 0)
            return;
        root.call("command.dispatch", {
            name: "undo",
            arg: `${turns}`,
            session_id: root.sessionId
        }, (result, error) => {
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
    // Images are staged on the agent's session and consumed by the next
    // prompt.submit, so nothing has to be re-sent with the message itself.

    property var attachedImages: []

    function attachImage(path: string): void {
        const clean = FileUtils.trimFileProtocol((path ?? "").trim());
        if (clean.length === 0)
            return;
        if (root.sessionId.length === 0) {
            root.addMessage(Translation.tr("Still connecting — try the attachment again in a moment."), root.interfaceRole);
            return;
        }
        // Every attachment route lands here, so PDFs are picked off once rather
        // than in each caller. They go to the renderer instead of image.attach,
        // which would only fail and fall through to a file the agent cannot read.
        if (clean.toLowerCase().endsWith(".pdf")) {
            root.attachPdf(clean, 0, 0);
            return;
        }
        root.call("image.attach", { session_id: root.sessionId, path: clean }, (result, error) => {
            if (error) {
                // A non-image goes to file.attach instead, which stages it into the
                // workspace and hands back an @file: ref.
                root._attachAsFile(clean, error.message ?? "");
                return;
            }
            // A paste is written to a timestamped temp file, a name nobody chose
            const file = FileUtils.fileNameForPath(clean);
            const name = file.startsWith("hermes-clip-") ? "image" + file.slice(file.lastIndexOf(".")) : file;
            root._addMarker("image", name, `[Image: ${name}]`, [result.path ?? clean]);
        });
    }

    function _attachAsFile(path: string, imageError: string): void {
        root.call("file.attach", { session_id: root.sessionId, path: path }, (result, error) => {
            // The gateway resolves attachments as files, so a folder fails both
            // attaches as "not found". Asked here, it goes in as an @folder:
            // reference, which the agent expands into a listing.
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

    /** Attach whatever image is on the clipboard, through the agent's own reader. */
    /**
     * Attach the image on the clipboard; `onText` runs instead when it holds text.
     *
     * Read in the shell, not through the gateway's clipboard.paste, which only
     * asks the live selection: the composer decides from cliphist that an image
     * was copied, the selection dies with the app that offered it, and the paste
     * answered "No image found in clipboard" for an image cliphist still held.
     * scripts/hermes/clipboard-image.sh says which source wins and why.
     */
    function attachClipboardImage(onText: var): void {
        if (clipboardImageProc.running)
            return;
        clipboardImageProc.onText = onText ?? null;
        clipboardImageProc.command = [root.clipboardImageScript, Directories.tempImages, Cliphist.cliphistBinary];
        clipboardImageProc.running = true;
    }

    readonly property string clipboardImageScript: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/hermes/clipboard-image.sh"))

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
    // model call: about 50ms against the ~6s one agent step cost on 2026-09-21.
    // The catalogue lives in scripts/hermes/desktop.py and is deliberately
    // timid -- a question, two actions in one, or anything long exits 2 and
    // falls through to the agent untouched, because a wrong instant answer is
    // worse than a slow right one.
    //
    // ponytail: a routed action never enters the agent's history, so a later
    // "undo that" has nothing to undo against. The catalogue is held to
    // self-evident, individually reversible toggles for exactly that reason;
    // widening it is what would make the missing history matter.

    readonly property string desktopScript: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/hermes/desktop.py"))
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
        // The gateway consumes whatever is staged on this turn, so the local list
        // has to clear with it or the indicator would keep showing spent images.
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
            // "streaming" | "queued" | "busy" — events carry the rest.
            if (result.status === "queued")
                root.statusText = Translation.tr("Queued");
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

        // `/undo` goes through the same rewind the message buttons drive. The
        // generic dispatch path prefills the composer but leaves the transcript
        // showing turns the agent has already forgotten, which reads as the
        // command having done nothing.
        if (base === "undo") {
            root.undoTurns(parseInt(arg, 10) || 1);
            return;
        }

        root._execSlash(line, base, arg);
    }

    function _execSlash(line: string, base: string, arg: string): void {
        root.call("slash.exec", {
            command: line,
            session_id: root.sessionId
        }, (result, error) => {
            if (error) {
                // Skill / bundle / pending-input commands refuse slash.exec by
                // design and name command.dispatch as the route (error 4018).
                if (error.code === 4018) {
                    root._dispatchCommand(base, arg);
                    return;
                }
                root.addMessage(error.message ?? Translation.tr("Command failed"), root.interfaceRole);
                return;
            }
            // slash.exec forwards pending-input commands to command.dispatch itself,
            // so a typed directive can come back through this path too.
            if ((result?.type ?? "").length > 0) {
                root._handleDispatch(base, arg, result);
                return;
            }
            root._reportCommandOutput(result.output);
        });
    }

    function _dispatchCommand(name: string, arg: string): void {
        root.call("command.dispatch", {
            name: name,
            arg: arg,
            session_id: root.sessionId
        }, (result, error) => {
            if (error) {
                root.addMessage(error.message ?? Translation.tr("Command failed"), root.interfaceRole);
                return;
            }
            root._handleDispatch(name, arg, result ?? ({}));
        });
    }

    /**
     * command.dispatch answers with a *directive*, not just text. A skill or a
     * `/goal`-style command comes back as something to SEND -- printing its
     * `output` (which is empty) is why `/learn ...` looked like it did nothing.
     */
    function _handleDispatch(name: string, arg: string, dispatch: var): void {
        const type = dispatch.type ?? "";
        const notice = (dispatch.notice ?? "").trim();
        const message = (dispatch.message ?? "").trim();

        if (type === "alias") {
            const target = (dispatch.target ?? "").trim();
            if (target.length > 0)
                root.runSlashCommand(`/${target}${arg.length > 0 ? " " + arg : ""}`);
            return;
        }

        if (type === "exec" || type === "plugin") {
            root._reportCommandOutput(dispatch.output);
            return;
        }

        // A notice ("⊙ Goal set …") is meant to be shown before the message is acted on.
        if (notice.length > 0)
            root.addMessage(notice, root.interfaceRole);

        if (type === "prefill") {
            // /undo hands back the backed-up message to edit, not to send.
            if (message.length > 0)
                root.composerPrefill(message);
            return;
        }

        if (type === "skill" || type === "send") {
            if (message.length === 0) {
                root.addMessage(Translation.tr("/%1: the command returned nothing to send").arg(name), root.interfaceRole);
                return;
            }
            // A skill's `message` is the expanded body -- model-facing scaffolding.
            // Never show it: the bubble gets the gateway's projection, or failing
            // that the command as it was typed.
            const shown = (dispatch.display ?? "").trim();
            root._submitPrompt(message, shown.length > 0 ? shown : `/${name}${arg.length > 0 ? " " + arg : ""}`);
            return;
        }

        root._reportCommandOutput(dispatch.output ?? dispatch.text);
    }

    /** Send `text` to the agent while the transcript shows `display`. */
    function _submitPrompt(text: string, display: string): void {
        root._newUserMessage(display.length > 0 ? display : text);
        root._submit(text);
    }

    function _reportCommandOutput(output: var): void {
        const text = (output ?? "").toString();
        if (text.trim().length > 0) {
            // Gateway output is terminal art (box rules, fixed columns); a code
            // fence keeps its alignment instead of letting markdown reflow it.
            root.addMessage("```\n" + text.replace(/\s+$/, "") + "\n```", root.interfaceRole);
        }
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

    function refreshProviders(refresh = false): void {
        if (root.providersLoading)
            return;
        root.providersLoading = true;
        root.call("model.options", {
            session_id: root.sessionId,
            include_unconfigured: true,
            refresh: refresh
        }, (result, error) => {
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
     * Switch the model for this session only. `--global` is deliberately never
     * sent: the sidebar remembers the pick itself (see applyPreferredModel) so a
     * choice made here cannot change what `hermes` in a terminal starts with.
     */
    function setModel(model: string, providerSlug: string, feedback = true): void {
        if ((model ?? "").length === 0)
            return;
        // A remote gateway keeps its own default: the remembered pick is this
        // machine's, and the remote may not even have the provider.
        if (!root.remote) {
            Persistent.states.hermes.model = model;
            Persistent.states.hermes.provider = providerSlug ?? "";
        }

        const parts = [`/model ${model}`];
        if ((providerSlug ?? "").length > 0)
            parts.push(`--provider ${providerSlug}`);
        parts.push("--session");

        root.call("slash.exec", {
            command: parts.join(" "),
            session_id: root.sessionId
        }, (result, error) => {
            if (error) {
                root.addMessage(error.message ?? Translation.tr("Could not switch model"), root.interfaceRole);
                return;
            }
            if (feedback)
                root._reportCommandOutput(result.output);
            else
                root.refreshSessionInfo();
        });
    }

    /** Re-apply the remembered pick to a newly created session. */
    function applyPreferredModel(): void {
        const model = Persistent.states?.hermes?.model ?? "";
        if (root.remote || model.length === 0 || model === root.currentModel)
            return;
        root.setModel(model, Persistent.states.hermes.provider ?? "", false);
    }

    // ── Voice ──────────────────────────────────────────────────────

    /*
     * Dictation runs on the shell's own recorder, NOT the agent's `voice.record`.
     *
     * Measured: `voice.record start` opens a PipeWire capture that neither
     * `voice.record stop` nor `voice.toggle off` ever releases -- it stays
     * `state=running, Corked: no` for the life of the gateway process. A held mic
     * also drags a Bluetooth headset from A2DP down to HSP, which is what the
     * "loud low-quality buzzing" was. The recorder below is a pw-record subprocess
     * this service owns, so stopping it genuinely closes the device.
     *
     * The agent's TTS (`voice.tts`) is unaffected and still used for reading out.
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
        gatewayProc.write(JSON.stringify({
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
        // The gateway asking us something (clarify, approval, ...): it has an id
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
            break;
        case "clarify":
            root.pendingClarify = request;
            root.statusText = Translation.tr("Waiting for your answer");
            break;
        default:
            // sudo, secret, vault and desktop bridges have no card here. Saying so
            // ends the agent's wait now instead of at its timeout.
            gatewayProc.write(JSON.stringify({
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
        case "gateway.ready":
            root.ready = true;
            root.starting = false;
            root.consecutiveFailures = 0;
            root._drainQueue();
            if (root.sessionId.length === 0)
                root.createSession();
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
            if (payload.usage)
                root.usage = payload.usage;
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

        case "session.usage":
            root.usage = payload.usage ?? root.usage;
            break;

        case "session.title":
            root.sessionTitle = payload.title ?? root.sessionTitle;
            break;

        case "status.update":
            root.statusText = (payload.text ?? "").trim();
            break;

        case "notice":
            if ((payload.message ?? "").length > 0)
                root.addMessage(payload.message, root.interfaceRole);
            break;

        case "error":
            root._failStream(payload.message ?? Translation.tr("Hermes reported an error"));
            break;

        case "background.complete":
        case "btw.complete":
            // btw.complete carries the question it answered; background.complete does not.
            root._finishSideTask(payload.task_id ?? "", payload.text ?? "", payload.question ?? "");
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
     * `result` is whatever the tool returned, JSON-parsed by the gateway when it
     * could be: the terminal answers {output, exit_code, error}, but a search
     * answers its own shape and a tool whose result would not parse arrives as a
     * bare string. Reading `output` alone left the return box empty -- and so
     * hidden -- for everything that is not a shell command.
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
    // The mic button and Super+Shift+B record with pw-record, then hand the file to
    // Hermes' own STT provider through scripts/hermes/stt.sh -- so `stt.provider` in
    // ~/.hermes/config.yaml decides what transcribes, for the agent and for dictation
    // alike. whisper.cpp is the fallback, and the settings below configure it.
    //
    // The capture is deliberately not the agent's `voice.record`: that opens its own
    // stream, which on a Bluetooth headset drags the card from A2DP down to HSP and
    // stops whatever is playing.

    readonly property string sttScript: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/hermes/stt.sh"))

    readonly property var sttPresets: ({
        "fast":     { "file": "ggml-tiny.en.bin" },              //  78MB, ~2s per 11s of audio
        "balanced": { "file": "ggml-base.en.bin" },              // 148MB, ~4s
        "accurate": { "file": "ggml-small.en-q5_1.bin" },        // 190MB, ~12s
        "best":     { "file": "ggml-large-v3-turbo-q5_0.bin" }   // 574MB, slow without a GPU backend
    })
    readonly property string sttQuality: {
        const stored = Config.options.hermes.sttQuality;
        return root.sttPresets[stored] ? stored : "balanced";
    }
    readonly property string sttModelDir: FileUtils.trimFileProtocol(`${Directories.home}/.local/share/vynx-conduit/models`)

    // An explicit path always wins, so a hand-picked model is never overridden.
    readonly property string sttModel: {
        const stored = Config.options.hermes.sttModel;
        if (stored.length > 0) return stored.replace(/^~/, FileUtils.trimFileProtocol(Directories.home));
        return `${root.sttModelDir}/${root.sttPresets[root.sttQuality].file}`;
    }
    readonly property string sttModelUrl: {
        const stored = Config.options.hermes.sttModel;
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
        engine: Config.options.hermes.sttEngine
        bridgeScript: root.sttScript
        modelPath: root.sttModel
        modelUrl: root.sttModelUrl
        language: Config.options.hermes.sttLanguage
        prompt: Config.options.hermes.sttPrompt
        source: Config.options.hermes.sttSource

        onModelDownloaded: console.log("[Hermes] dictation voice model ready:", root.sttQuality)

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
    // The agent's `voice.tts` synthesizes AND plays, through an `ffplay` child it
    // gives no way to stop: `voice.record`/`voice.toggle`/`session.interrupt` all act
    // on a different pipeline, the only thing that cuts this one is the barge-in
    // listener, and killing the player -- SIGTERM or SIGKILL -- ends the stream
    // mid-waveform, which into a Bluetooth A2DP sink is a loud low-quality buzz.
    // Muting or re-routing the stream is no better: WirePlumber persists both per
    // application name, so every later read-aloud would inherit them.
    //
    // So the agent only *synthesizes* (scripts/hermes/tts.py, same voice, same
    // normalizer) and the shell plays the file itself. MediaPlayer.stop() drains
    // the stream the same graceful way a clip ends on its own, and the volume is
    // faded to zero first so there is no discontinuity at all.

    readonly property string ttsScript: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/hermes/tts.sh"))
    readonly property string ttsDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/quickshell/hermes/tts`

    property bool ttsReady: false
    property int _ttsNextId: 1
    property var _ttsPending: ({})       // id -> callback(reply)
    property var _ttsQueuedRequests: []  // written once the server says ready

    /** Start the synth server early so the first read-aloud does not pay the model load. */
    function prewarmTts(): void {
        if (!ttsProc.running)
            ttsProc.running = true;
    }

    function _ttsRequest(text: string, callback: var): void {
        const id = `tts-${root._ttsNextId++}`;
        const out = `${root.ttsDir}/${id}-${Date.now()}.mp3`;
        const frame = JSON.stringify({ id: id, text: text, out: out }) + "\n";
        root._ttsPending[id] = callback;
        if (!root.ttsReady) {
            root._ttsQueuedRequests.push(frame);
            root.prewarmTts();
            return;
        }
        ttsProc.write(frame);
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
                if (reply.event === "ready") {
                    root.ttsReady = true;
                    const queued = root._ttsQueuedRequests;
                    root._ttsQueuedRequests = [];
                    queued.forEach(frame => ttsProc.write(frame));
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
                    console.log("[Hermes/tts]", line.trim());
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.ttsReady = false;
            root._ttsPending = ({});
            if (root.speakingMessageId.length > 0 && !readerLoader.item?.player.playing)
                root.speakingMessageId = "";
        }
    }

    // The player is built on first use: instantiating MediaPlayer links QtMultimedia's
    // backend and starts an audio thread (see SoundService), none of it needed until
    // something is actually read out.
    Loader {
        id: readerLoader
        active: false
        sourceComponent: Item {
            id: reader
            readonly property alias player: readerPlayer
            readonly property alias output: readerOutput
            // Clips still to play after the current one, as {path, chunk, share, span, marks}:
            // long-form replies come back as several of them, and each one carries
            // the text it says, and which slice of it, so the transcript can mark
            // the word being spoken while it plays.
            property var queue: []
            // Everything played this turn, deleted once it is over.
            property var produced: []
            // Which reading these clips belong to, so a fade finishing after the
            // next reading has begun tidies up without cancelling it.
            property int epoch: 0

            MediaDevices {
                id: readerDevices
            }

            MediaPlayer {
                id: readerPlayer
                audioOutput: AudioOutput {
                    id: readerOutput
                    device: readerDevices.defaultAudioOutput
                    volume: 1
                }

                onMediaStatusChanged: {
                    if (readerPlayer.mediaStatus !== MediaPlayer.EndOfMedia)
                        return;
                    if (reader.queue.length > 0) {
                        const next = reader.queue[0];
                        reader.queue = reader.queue.slice(1);
                        reader.playEntry(next);
                        return;
                    }
                    reader.finish();
                }

                onErrorOccurred: (error, message) => {
                    console.log("[Hermes/tts] playback error:", message);
                    reader.finish();
                }
            }

            /**
             * Add clips to the reading. Starts playing if nothing is, appends if
             * something is -- a reply is spoken as several chunks that arrive while
             * the earlier ones are still playing, so this must never restart.
             */
            function enqueue(paths: var, chunk: string, marks: var): void {
                if (paths.length === 0)
                    return;
                // A chunk long enough to come back as several clips is assumed to
                // divide evenly between them, so the mark keeps moving through it.
                const entries = paths.map((path, index) => ({
                    path: path,
                    chunk: chunk,
                    share: index / paths.length,
                    span: 1 / paths.length,
                    // Word timings belong to a single clip; a chunk that came back
                    // as several has none, and falls back to the estimate.
                    marks: paths.length === 1 ? marks : []
                }));
                // A new reading arriving mid-fade takes over immediately. The fade
                // was the old reading's exit; letting it land afterwards would empty
                // the queue this is filling and delete the clips with it.
                if (fadeOut.running) {
                    fadeOut.stop();
                    readerPlayer.stop();
                    reader.finish();
                }
                reader.produced = [...reader.produced, ...paths];
                if (readerPlayer.playbackState === MediaPlayer.PlayingState || reader.queue.length > 0) {
                    reader.queue = [...reader.queue, ...entries];
                    return;
                }
                reader.epoch = root._speakEpoch;
                reader.queue = entries.slice(1);
                reader.playEntry(entries[0]);
            }

            /** Play one clip and say, for the highlight, what it is saying. */
            function playEntry(entry: var): void {
                root._speakingChunk = entry.chunk ?? "";
                root._speakingShare = entry.share ?? 0;
                root._speakingSpan = entry.span ?? 1;
                root._speakingMarks = entry.marks ?? [];
                readerPlayer.source = `file://${entry.path}`;
                readerPlayer.play();
            }

            /**
             * Fade to silence, then stop. Exposed as a function because `fadeOut` is
             * an id inside this component: reachable from in here, not through the
             * Loader's `item` from outside.
             */
            function fadeAndStop(): void {
                if (fadeOut.running)
                    return;
                fadeOut.start();
            }

            /** Playback is over -- naturally or stopped -- tidy up and let the UI know. */
            function finish(): void {
                readerPlayer.source = "";
                reader.queue = [];
                root._speakingChunk = "";
                root._speakingMarks = [];
                readerOutput.volume = 1;
                if (reader.produced.length > 0) {
                    cleanup.command = ["rm", "-f", ...reader.produced];
                    cleanup.running = true;
                    reader.produced = [];
                }
                // Only if this is still the current reading: a later one has already
                // claimed the id, and clearing it would stop it before it is heard.
                if (reader.epoch === root._speakEpoch)
                    root.speakingMessageId = "";
            }

            Process {
                id: cleanup
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
                    script: {
                        readerPlayer.stop();
                        reader.finish();
                    }
                }
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
     */
    // The opening chunk is allowed to be short so speaking starts sooner; the rest
    // are kept long, since by then the player is busy and only the total matters.
    readonly property int _minFirstChunk: 60
    readonly property int _minChunk: 140
    readonly property int _maxChunks: 8

    function _splitForSpeech(text: string): var {
        const trimmed = (text ?? "").trim();
        if (trimmed.length <= root._minFirstChunk)
            return [trimmed];
        // Split *after* the punctuation, keeping it with the sentence it ends.
        // Chunks are slices of the text, whitespace and all: joined back with
        // spaces, a list item's `- ` stopped being at the start of a line, the
        // transcript could no longer tell it from a word, and the spoken-word
        // mark drifted a marker further ahead after every item.
        const spans = [];
        const ends = /[.!?]\s+/g;
        let start = 0;
        let match;
        const add = end => {
            const floor = spans.length === 1 ? root._minFirstChunk : root._minChunk;
            const last = spans[spans.length - 1];
            if (last && last.end - last.start < floor)
                last.end = end;
            else
                spans.push({ start: start, end: end });
        };
        while ((match = ends.exec(trimmed)) !== null) {
            add(match.index + 1);
            start = ends.lastIndex;
        }
        add(trimmed.length);
        // Past the cap the tail is spoken as one piece: more requests would not
        // start the audio any sooner, and each one costs a round trip.
        if (spans.length > root._maxChunks)
            spans.splice(root._maxChunks - 1, spans.length, { start: spans[root._maxChunks - 1].start, end: trimmed.length });
        return spans.map(span => trimmed.slice(span.start, span.end));
    }

    // What the clip now playing is saying, and which slice of that text it covers
    // -- set by the player, read by `speakingPassage` and `speakingProgress`.
    property string _speakingChunk: ""
    property real _speakingShare: 0
    property real _speakingSpan: 1
    // [[start_ms, offset into the chunk], …] for the clip playing, when the
    // provider reports word boundaries. Empty when it does not.
    property var _speakingMarks: []

    /** The chunk being read right now: the passage the transcript marks in. */
    readonly property string speakingPassage: root._speakingChunk

    /**
     * Where in the chunk the word now being spoken starts, or -1 when the voice
     * came back without timings and `speakingProgress` has to stand in.
     *
     * Exact: edge reports a boundary per word off the synthesis stream, aligned
     * to this text before it was ever played (scripts/hermes/tts_marks.py). The
     * only slack left is how often the player reports its position.
     */
    readonly property int speakingOffset: {
        const marks = root._speakingMarks;
        if (marks.length === 0 || root._speakingChunk.length === 0)
            return -1;
        const position = readerLoader.item?.player.position ?? 0;
        let offset = marks[0][1];
        for (let i = 0; i < marks.length && marks[i][0] <= position; i++)
            offset = marks[i][1];
        return offset;
    }

    /**
     * How far into that chunk the voice is, 0..1, or -1 when nothing is read.
     * The fallback for a provider that reports no word boundaries.
     *
     * The synth gives no word timings, so this is the clip's own playback
     * position: speech runs at a near constant rate, so a character-proportional
     * split of it lands on the right word. A duration is not known for the first
     * moments of a clip, which reads as the start of the clip's own slice.
     * ponytail: proportional estimate, swap in word timestamps if a provider offers them.
     */
    readonly property real speakingProgress: {
        if (root._speakingChunk.length === 0)
            return -1;
        const player = readerLoader.item?.player ?? null;
        const duration = player?.duration ?? 0;
        const played = duration > 0 ? Math.max(0, Math.min(0.999, (player?.position ?? 0) / duration)) : 0;
        return root._speakingShare + root._speakingSpan * played;
    }

    // Bumped by every new reading, so replies to a superseded one are discarded
    // rather than played over the top of it.
    property int _speakEpoch: 0

    /** Read `text` out loud through the shell's own player. */
    function speak(text: string): void {
        if ((text ?? "").trim().length === 0)
            return;
        // A new reading replaces one in progress, silently: fade what is playing.
        if (readerLoader.item?.player.playing)
            readerLoader.item.fadeAndStop();
        const epoch = ++root._speakEpoch;
        const chunks = root._splitForSpeech(text);
        // Requested up front: the server answers them in order, so the clips queue
        // up in order too, and chunk two is already rendering while chunk one plays.
        chunks.forEach((chunk, index) => root._ttsRequest(chunk, reply => root._onSpoken(reply, epoch, index, chunk)));
    }

    function _onSpoken(reply: var, epoch: int, index: int, chunk: string): void {
        const stale = epoch !== root._speakEpoch || root.speakingMessageId.length === 0;
        if (!(reply.ok ?? false) || (reply.paths ?? []).length === 0) {
            // Only the opening chunk reports: a failure halfway through is a gap in
            // the reading, not a reason to replace it with an error bubble.
            if (!stale && index === 0) {
                root.speakingMessageId = "";
                root.addMessage(reply.error?.length > 0 ? reply.error : Translation.tr("Could not synthesize speech"), root.interfaceRole);
            }
            return;
        }
        // Stopped or superseded while synthesis was still running: do not play now.
        if (stale) {
            cleanupOrphan.command = ["rm", "-f", ...reply.paths];
            cleanupOrphan.running = true;
            return;
        }
        readerLoader.active = true;
        readerLoader.item.enqueue(reply.paths, chunk, reply.marks ?? []);
    }

    Process {
        id: cleanupOrphan
    }

    /** Silence a read-aloud: fade to zero, then a graceful stop. Nothing is killed. */
    function stopSpeaking(): void {
        root.speakingMessageId = "";
        const reader = readerLoader.item;
        if (!reader)
            return;
        if (reader.player.playing)
            reader.fadeAndStop();
        else
            reader.finish();
    }

    // ── Finished-turn notification ─────────────────────────────────
    //
    // Only worth sending when the answer is somewhere the user cannot see, which
    // means the panel is shut or it is showing a different tab. A popup for a reply
    // already on screen is pure noise.

    readonly property bool viewingHermes: GlobalStates.policiesPanelOpen
        && root.hermesTabIndex >= 0
        && Persistent.states.sidebar.policies.tab === root.hermesTabIndex

    /**
     * Goes in as the `image-path` hint rather than `-i`: the notification server
     * treats an app icon as a freedesktop theme name and draws `image-missing` when
     * it is not one -- which a Material Symbol name never is. The hint takes a file.
     */
    readonly property string notifyIconPath: FileUtils.trimFileProtocol(Qt.resolvedUrl("../assets/icons/hermes.svg").toString())

    property Process notifier: Process {}

    function notifyFinished(message: var): void {
        if (!(Config.options.hermes?.notifyWhenAway ?? true))
            return;
        // One line either way: "why didn't it notify" is otherwise invisible.
        if (root.viewingHermes) {
            console.log("[Hermes] No notification: the tab is on screen.");
            return;
        }

        const failed = (message?.error ?? "").length > 0;
        const body = failed ? message.error : (message?.content ?? "");
        const summary = body.replace(/\s+/g, " ").trim().slice(0, 140);

        notifier.command = ["notify-send",
            "-a", "Hermes",
            "-u", failed ? "critical" : "normal",
            "-h", `string:image-path:${root.notifyIconPath}`,
            // Replaces Hermes' own previous popup rather than stacking, on servers
            // that honour the hint.
            "-h", "string:x-canonical-private-synchronous:ii-hermes",
            failed ? Translation.tr("Hermes — turn failed") : Translation.tr("Hermes — %1 replied").arg(root.currentModel),
            summary.length > 0 ? summary : Translation.tr("Finished.")];
        notifier.running = true;
        console.log("[Hermes] Notification sent.");
    }

    // ── Shell entry points ─────────────────────────────────────────

    /**
     * Hermes is the panel's first page when enabled, so there is nothing to count.
     * -1 when it is switched off and has no tab at all.
     */
    readonly property int hermesTabIndex: root.enabled ? 0 : -1

    function focusHermesTab(): void {
        if (root.hermesTabIndex < 0)
            return;
        Persistent.states.sidebar.policies.tab = root.hermesTabIndex;
    }

    /** Open the panel on Hermes and start dictating; press again to transcribe. */
    function dictateToggle(): void {
        if (root.voiceState === "transcribing")
            return; // Mid-transcription; let it finish.
        if (root.voiceState === "listening") {
            root.stopDictation();
            return;
        }
        GlobalStates.policiesPanelOpen = true;
        root.focusHermesTab();
        root.startDictation();
    }

    property GlobalShortcut dictateShortcut: GlobalShortcut {
        name: "hermesDictate"
        description: "Hermes: open and dictate, press again to send"
        onPressed: root.dictateToggle()
    }

    property GlobalShortcut stopShortcut: GlobalShortcut {
        name: "hermesStop"
        description: "Hermes: stop the current response"
        onPressed: root.interrupt()
    }

    property IpcHandler ipc: IpcHandler {
        target: "hermes"

        function dictate(): void {
            root.dictateToggle();
        }
        function stop(): void {
            root.interrupt();
        }
        function open(): void {
            GlobalStates.policiesPanelOpen = true;
            root.focusHermesTab();
        }
        function newSession(): void {
            root.newSession();
        }
    }

    // ── Process ──────────────────────────────────────────────────────────

    Process {
        id: gatewayProc
        running: false
        stdinEnabled: true
        command: [root.gatewayScript]
        // Read at start, so a switch only lands on the next launch -- setGateway
        // restarts the process for exactly that.
        environment: ({
            HERMES_GATEWAY_SSH: root.remote ? (root.gateway.user ? `${root.gateway.user}@` : "") + root.gateway.host : null,
            HERMES_GATEWAY_SSH_KEY: root.remote ? root.gateway.keyPath : null
        })

        stdout: SplitParser {
            onRead: line => {
                if (line.trim().length === 0)
                    return;
                let frame;
                try {
                    frame = JSON.parse(line);
                } catch (e) {
                    // The agent prints the odd non-JSON banner line; ignore it
                    // rather than tearing the connection down.
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
                if (text.includes("hermes-agent not found")) {
                    root.missing = true;
                    root.lastError = text;
                    return;
                }
                // ssh's own complaints (unreachable host, refused key) are the only
                // account of why a remote gateway never came up.
                if (text.startsWith("[gateway-crash]") || text.startsWith("ssh:") || text.includes("Permission denied"))
                    root.lastError = text;
                console.log("[Hermes]", text);
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.ready = false;
            root.starting = false;
            root.sessionId = "";
            root.streamingId = "";
            root._releaseRun();
            root.busy = false;
            root.statusText = "";
            root.pendingApproval = null;
            root.pendingClarify = null;
            root.speakingMessageId = "";
            root._pendingCalls = ({});

            if (root._switchingGateway) {
                root._switchingGateway = false;
                if (root.enabled)
                    root.ensureStarted();
                return;
            }

            if (root.missing || exitCode === 127) {
                root.missing = true;
                return;
            }

            root.consecutiveFailures++;
            if (root.consecutiveFailures <= root.maxRestarts && root.enabled) {
                restartTimer.start();
            } else if (root.lastError.length === 0) {
                root.lastError = Translation.tr("Hermes gateway stopped (exit %1)").arg(exitCode);
            }
        }
    }

    // Children are watched here, not in the panel that shows them: a delegated
    // run has to be recorded whether or not anyone happened to have the panel
    // open, or it is missing from the live list AND from the saved history.
    Timer {
        interval: 2000
        repeat: true
        running: root.ready && root.busy && root.sessionId.length > 0
        onTriggered: root.refreshSubagents()
    }

    Timer {
        id: restartTimer
        // Backs off so a gateway that dies on startup does not spin.
        interval: 1000 * root.consecutiveFailures
        onTriggered: {
            if (root.enabled && !gatewayProc.running)
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
        if (!root.enabled && gatewayProc.running) {
            gatewayProc.running = false;
        }
    }
}
