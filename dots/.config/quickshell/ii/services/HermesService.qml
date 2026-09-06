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
     * Instantiates the singleton at shell start so the global shortcuts, the IPC
     * handler and the wake-word listener register without waiting for the page to
     * be opened. The gateway process itself stays lazy -- see ensureStarted().
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

    // ── Transcript ───────────────────────────────────────────────────────

    property var messageIDs: []
    property var messageByID: ({})
    property string streamingId: ""

    // ── Voice ──────────────────────────────────────────────────────
    //
    // Hermes brings its own capture and STT (local faster-whisper by default), so
    // dictation goes through the agent rather than a second recorder in the shell.
    // `voice.record` is VAD-bounded -- it stops on silence and answers with
    // `voice.transcript` -- so the mic button is a toggle, not a hold.


    // Dictation readiness is the shell's own recorder, which is what actually runs
    // when the mic button is pressed.
    readonly property bool dictationAvailable: root.speech.modelReady || root.speech.downloading
    readonly property string voiceState: root.speech.recording ? "listening" : root.speech.transcribing ? "transcribing" : "idle"
    readonly property bool dictating: root.voiceState !== "idle"

    // Emitted with a finished transcript so the page can put it in the input box.
    signal dictationTranscript(string text)

    // A `prefill` directive (e.g. /undo) hands text back to edit rather than send.
    signal composerPrefill(string text)

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
            done: role !== "assistant"
        });
        const id = `hermes-${root.messageIDs.length}-${Date.now()}`;
        root.messageByID[id] = message;
        root.messageIDs = [...root.messageIDs, id];
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
        root.pendingApproval = null;
        root.pendingClarify = null;
        root.transcriptCleared();
    }

    property var streamingMessage: root.messageByID[root.streamingId] ?? null

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

    function renameSession(storedId: string, title: string): void {
        root.call("session.title", { session_id: storedId, title: title }, (result, error) => {
            if (!error)
                root.refreshRecentSessions();
        });
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

        (result.messages ?? []).forEach(entry => {
            const role = entry.role ?? "";

            if (role === "tool") {
                // Attach to the turn that called it, so it renders in the same
                // ToolActivityRow the live stream produces.
                if (lastAssistantId.length === 0)
                    lastAssistantId = root._newMessage("assistant", "");
                const message = root.messageByID[lastAssistantId];
                if (!message)
                    return;
                message.toolCalls = [...message.toolCalls, {
                    toolId: "",
                    toolName: entry.name ?? "tool",
                    toolInput: entry.context ?? "",
                    toolFullInput: root._formatToolArgs(entry.args ?? ({})),
                    toolResult: "",
                    toolRunning: false,
                    toolFailed: false
                }];
                message.done = true;
                return;
            }

            const body = (entry.text ?? entry.content ?? "").toString();
            if (body.trim().length === 0)
                return; // No empty bubbles for rows that carry no prose.

            const id = root._newMessage(role === "user" ? "user" : "assistant", body);
            root.messageByID[id].done = true;
            if (role !== "user")
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
        root.call("image.attach", { session_id: root.sessionId, path: clean }, (result, error) => {
            if (error) {
                // A non-image goes to file.attach instead, which stages it into the
                // workspace and hands back an @file: ref.
                root._attachAsFile(clean, error.message ?? "");
                return;
            }
            root.attachedImages = [...root.attachedImages, result.path ?? clean];
        });
    }

    function _attachAsFile(path: string, imageError: string): void {
        root.call("file.attach", { session_id: root.sessionId, path: path }, (result, error) => {
            if (error) {
                root.addMessage(imageError.length > 0 ? imageError : (error.message ?? Translation.tr("Could not attach that file")), root.interfaceRole);
                return;
            }
            // A staged file is referenced by text, not held as an attachment.
            root.composerPrefill((result.ref ?? result.path ?? "").toString());
        });
    }

    function detachImage(path: string): void {
        root.call("image.detach", { session_id: root.sessionId, path: path }, (result, error) => {
            if (error)
                return;
            root.attachedImages = root.attachedImages.filter(item => item !== path);
        });
    }

    function detachAll(): void {
        root.attachedImages.forEach(path => root.call("image.detach", { session_id: root.sessionId, path: path }, null));
        root.attachedImages = [];
    }

    /** Attach whatever image is on the clipboard, through the agent's own reader. */
    function attachClipboardImage(): void {
        root.call("clipboard.paste", { session_id: root.sessionId }, (result, error) => {
            if (error || !(result?.attached ?? false)) {
                const note = result?.message ?? error?.message ?? "";
                if (note.length > 0)
                    root.addMessage(note, root.interfaceRole);
                return;
            }
            root.attachedImages = [...root.attachedImages, result.path ?? ""];
        });
    }

    // ── Sending ──────────────────────────────────────────────────────────

    function sendMessage(text: string): void {
        const trimmed = (text ?? "").trim();
        if (trimmed.length === 0)
            return;

        if (root.sessionId.length === 0) {
            // Session still being created: send once it lands.
            root._newMessage("user", trimmed);
            root._deferredPrompt = trimmed;
            root.ensureStarted();
            return;
        }

        root._newMessage("user", trimmed);
        root._submit(trimmed);
    }

    property string _deferredPrompt: ""

    function _submit(text: string): void {
        root.busy = true;
        root.statusText = "";
        // The gateway consumes whatever is staged on this turn, so the local list
        // has to clear with it or the indicator would keep showing spent images.
        root.attachedImages = [];
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
        root._newMessage("user", display.length > 0 ? display : text);
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
        Persistent.states.hermes.model = model;
        Persistent.states.hermes.provider = providerSlug ?? "";

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
        if (model.length === 0 || model === root.currentModel)
            return;
        root.setModel(model, Persistent.states.hermes.provider ?? "", false);
    }

    function saveApiKey(slug: string, apiKey: string): void {
        root.call("model.save_key", { slug: slug, api_key: apiKey }, (result, error) => {
            if (error) {
                root.addMessage(error.message ?? Translation.tr("Could not save key"), root.interfaceRole);
                return;
            }
            root.addMessage(Translation.tr("Saved API key for %1").arg(result.provider?.name ?? slug), root.interfaceRole);
            root.refreshProviders(true);
        });
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
        root.speech.autoSend = false;
        root.speech.startRecording();
    }

    /** Stop the capture and transcribe what was said. */
    function stopDictation(): void {
        root.speech.stopRecording();
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
        root.call("approval.respond", {
            session_id: root.sessionId,
            choice: choice,
            all: all,
            request_id: request.request_id ?? request.id ?? undefined
        }, null);
    }

    /**
     * Answer the agent's question. A batch asks one call per `questionId`; the turn
     * unblocks once every question has been answered.
     */
    function respondToClarify(answer: string, questionId: string): void {
        const request = root.pendingClarify;
        if (!request)
            return;
        const params = {
            session_id: root.sessionId,
            request_id: request.request_id ?? "",
            answer: answer
        };
        if ((questionId ?? "").length > 0)
            params.question_id = questionId;

        root.call("clarify.respond", params, (result, error) => {
            if (error) {
                root.addMessage(error.message ?? Translation.tr("Could not send that answer"), root.interfaceRole);
                return;
            }
            // A batch stays open until nothing is left unanswered.
            const remaining = result?.remaining ?? [];
            if (remaining.length === 0)
                root.pendingClarify = null;
        });
    }

    // ── Event handling ───────────────────────────────────────────────────

    function _handleFrame(frame: var): void {
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
            root.streamingId = root._newMessage("assistant", "");
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
            // needs the turn that actually finished.
            let finished = root.streamingMessage;
            if (finished) {
                if ((payload.text ?? "").length > 0)
                    finished.content = payload.text;
                if (payload.status === "error")
                    finished.error = payload.text ?? "";
                finished.usage = payload.usage ?? null;
                finished.done = true;
            } else if ((payload.text ?? "").length > 0) {
                const id = root._newMessage("assistant", payload.text);
                root.messageByID[id].done = true;
                finished = root.messageByID[id];
            }
            root.streamingId = "";
            root.busy = false;
            root.statusText = "";
            if (payload.usage)
                root.usage = payload.usage;
            if (root.speakReply) {
                root.speakReply = false;
                root.speak(payload.text ?? "");
            }
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

        case "approval.request":
            root.pendingApproval = payload;
            root.statusText = Translation.tr("Waiting for your approval");
            break;

        case "clarify.request":
            // The agent has stopped mid-turn to ask something. Without this the
            // turn simply hangs until the clarify timeout expires.
            root.pendingClarify = payload;
            root.statusText = Translation.tr("Waiting for your answer");
            break;

        case "clarify.expire":
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

        case "sessions.changed":
            root.refreshRecentSessions();
            break;
        }
    }

    function _addToolCall(payload: var): void {
        // A tool can fire before any assistant text, so the turn may not exist yet.
        if (root.streamingId.length === 0)
            root.streamingId = root._newMessage("assistant", "");
        const message = root.streamingMessage;
        if (!message)
            return;
        // Duck-typed to what ToolActivityRow reads, so a tool call is narrated
        // by the shared row rather than a renderer of its own.
        const args = payload.args ?? {};
        message.toolCalls = [...message.toolCalls, {
            toolId: payload.tool_id ?? "",
            toolName: payload.name ?? "tool",
            toolInput: payload.context ?? payload.preview ?? "",
            toolFullInput: root._formatToolArgs(args),
            toolResult: "",
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

    function _completeToolCall(payload: var): void {
        const message = root.streamingMessage;
        if (!message)
            return;
        const result = payload.result ?? {};
        const failed = (result.error ?? null) !== null || (result.exit_code ?? 0) !== 0;
        message.toolCalls = message.toolCalls.map(call => {
            if (call.toolId !== (payload.tool_id ?? ""))
                return call;
            return Object.assign({}, call, {
                toolRunning: false,
                toolFailed: failed,
                toolResult: (result.error ?? result.output ?? "").toString(),
                duration: payload.duration_s ?? 0
            });
        });
    }

    // ── Wake word ──────────────────────────────────────────────────
    //
    // Detection is local ONNX (scripts/wakeword/wakeword.py) and the script owns the
    // microphone for the whole cycle -- listen, detect, then keep recording the
    // request and endpoint it on silence -- handing back a finished WAV. That is why
    // this path uses whisper.cpp rather than the agent's own capture: `voice.record`
    // opens its own stream and cannot transcribe a file, and waking QML *then*
    // starting a recorder loses the first word of every request.

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

    property SpeechToText speech: SpeechToText {
        modelPath: root.sttModel
        modelUrl: root.sttModelUrl
        language: Config.options.hermes.sttLanguage
        prompt: Config.options.hermes.sttPrompt
        source: Config.options.hermes.sttSource

        onModelDownloaded: {
            root.wakeError = "";
            console.log("[Hermes] wake-word voice model ready:", root.sttQuality);
        }

        onTranscribed: text => {
            const wasWake = root.wakeTurn;
            const spoken = wasWake ? root.stripWakePhrase(text) : text;
            root.wakeTurn = false;

            if (root.speech.autoSend) {
                root.speech.autoSend = false;
                // Voice in, voice out: a turn started hands-free is read back the same way.
                root.speakReply = Config.options.hermes.speakReplies;
                root.sendMessage(spoken);
                return;
            }
            // Typed-by-voice: hand it to the composer to review, the same as any
            // other dictation -- local STT mishears and a send cannot be undone.
            root.dictationTranscript(spoken);
        }
        onFailed: reason => {
            // Cleared here too, else a failed hands-free turn leaves the next one
            // being treated as one.
            root.wakeTurn = false;
            root.addMessage(reason, root.interfaceRole);
        }
    }

    /*
     * Which classifier files to load for each setting. "any" runs all three at
     * once: the expensive part of detection is the shared frontend, which runs
     * once no matter how many phrases are watched, so a second and third phrase
     * cost about a megabyte each and no measurable CPU.
     *
     * hey_jarvis is openWakeWord's own pretrained model. It is deliberately *not*
     * offered in settings and stays here only as a way to exercise the pipeline
     * before a trained Scout model exists, by setting hermes.wakeWord.phrase to
     * "hey_jarvis" in config.json by hand. Nothing in the UI leads here.
     */
    readonly property var wakePhrasePresets: ({
        "hey_scout":  [{ "name": "hey_scout",  "file": "hey_scout.onnx",  "bare": false }],
        "okay_scout": [{ "name": "okay_scout", "file": "okay_scout.onnx", "bare": false }],
        "scout":      [{ "name": "scout",      "file": "scout.onnx",      "bare": true  }],
        "any_scout":  [{ "name": "hey_scout",  "file": "hey_scout.onnx",  "bare": false },
                       { "name": "okay_scout", "file": "okay_scout.onnx", "bare": false },
                       { "name": "scout",      "file": "scout.onnx",      "bare": true  }],

        // openWakeWord's own pretrained phrases. No training, no Colab - they are
        // fetched straight from the release and work immediately, which is what
        // makes the feature usable without a GPU anywhere in the picture.
        // Not "bare" despite having no prefix: that flag exists for single-syllable
        // triggers, and "Alexa" is three distinctive ones.
        "alexa":       [{ "name": "alexa",       "file": "alexa_v0.1.onnx",       "bare": false }],
        "hey_mycroft": [{ "name": "hey_mycroft", "file": "hey_mycroft_v0.1.onnx", "bare": false }],
        "hey_rhasspy": [{ "name": "hey_rhasspy", "file": "hey_rhasspy_v0.1.onnx", "bare": false }],
        "hey_jarvis":  [{ "name": "hey_jarvis",  "file": "hey_jarvis_v0.1.onnx",  "bare": false }]
    })

    readonly property var wakePhrases: {
        const preset = root.wakePhrasePresets[Config.options.hermes.wakeWord.phrase]
            ?? root.wakePhrasePresets["hey_scout"];
        const wake = Config.options.hermes.wakeWord;
        return preset.map(phrase => ({
            "name": phrase.name,
            "file": phrase.file,
            "threshold": phrase.bare ? wake.bareThreshold : wake.threshold
        }));
    }

    // Why the wake word is not listening, if it is not. Surfaced in settings rather
    // than the transcript; empty once it arms.
    property string wakeError: ""

    // Marks the turn as hands-free, so the transcript gets the wake phrase trimmed
    // off it and the reply is spoken.
    property bool wakeTurn: false
    property bool speakReply: false

    /**
     * Capture starts a fraction before the phrase is detected, so whatever the user
     * said arrives with the tail of "hey scout" stuck to the front of it. Trimmed
     * only when it is really there -- and never down to nothing, so a bare "Scout"
     * with no request survives as something to answer.
     */
    function stripWakePhrase(text: string): string {
        const stripped = text
            .replace(/^[\s,.!?-]*(?:(?:hey|okay|ok)\s+)?(?:s?cout|jarvis)\b[\s,.!?-]*/i, "")
            .trim();
        return stripped.length > 0 ? stripped : text;
    }

    property WakeWord wake: WakeWord {
        // Config.ready gates this: before the user's config loads, `phrase` still
        // reads the schema default (hey_scout), whose models are custom-trained and
        // genuinely absent -- so an ungated probe tries to fetch them, fails, and
        // reports a problem about a phrase the user never selected. That race is
        // what produced the wake-word complaint on every single start.
        enabled: Config.ready && root.enabled && Config.options.hermes.wakeWord.enable
        phrases: root.wakePhrases
        source: Config.options.hermes.wakeWord.source

        /*
         * Deaf while the shell is talking, thinking, or locked. The first of those is
         * not optional: TTS output reaches the microphone, so a reply containing the
         * wake phrase would wake the shell with its own voice.
         */
        suspended: root.busy || root.dictating
            || root.speech.recording || root.speech.transcribing
            || (Config.options.hermes.wakeWord.pauseWhenLocked && GlobalStates.screenLocked)

        // A phrase whose models are already on disk downloads nothing, so there is
        // no completion event to clear a stale complaint -- it has to come off the
        // moment the detector is armed, and go back on only if arming fails again.
        onModelsReadyChanged: if (wake.modelsReady) root.wakeError = ""
        onPhrasesChanged: root.wakeError = ""

        onWoke: (phrase, score) => {
            root.wakeError = "";
            console.log(`[Hermes] Wake word "${phrase}" at ${score}`);
            GlobalStates.policiesPanelOpen = true;
            root.focusHermesTab();
        }

        onUtterance: path => {
            root.wakeTurn = true;
            root.speech.autoSend = true;
            root.speech.transcribeFile(path);
        }

        // Not addMessage(): this fires at startup, every startup, whenever the
        // configured phrase has no model on disk. Greeting an empty chat with a
        // setup problem is noise -- it belongs beside the setting that caused it,
        // so it is published here and rendered in Settings > Hermes > Wake word.
        onFailed: reason => {
            root.wakeError = reason;
            console.log("[Hermes] wake word:", reason);
        }
    }

    Binding { target: GlobalStates; property: "wakeListening"; value: root.wake.listening }
    Binding { target: GlobalStates; property: "wakeCapturing"; value: root.wake.capturing }
    Binding { target: GlobalStates; property: "wakeLevel"; value: root.wake.level }

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
            // Files still to play after the current one: long-form replies come back as
            // several clips.
            property var queue: []
            // Everything played this turn, deleted once it is over.
            property var produced: []

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
                        readerPlayer.source = `file://${next}`;
                        readerPlayer.play();
                        return;
                    }
                    reader.finish();
                }

                onErrorOccurred: (error, message) => {
                    console.log("[Hermes/tts] playback error:", message);
                    reader.finish();
                }
            }

            function start(paths: var): void {
                reader.produced = [...reader.produced, ...paths];
                reader.queue = paths.slice(1);
                readerPlayer.source = `file://${paths[0]}`;
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
                readerOutput.volume = 1;
                if (reader.produced.length > 0) {
                    cleanup.command = ["rm", "-f", ...reader.produced];
                    cleanup.running = true;
                    reader.produced = [];
                }
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

    /** Read `text` out loud through the shell's own player. */
    function speak(text: string): void {
        if ((text ?? "").trim().length === 0)
            return;
        // A new reading replaces one in progress, silently: fade what is playing.
        if (readerLoader.item?.player.playing)
            readerLoader.item.fadeAndStop();
        root._ttsRequest(text, reply => {
            if (!(reply.ok ?? false) || (reply.paths ?? []).length === 0) {
                root.speakingMessageId = "";
                root.addMessage(reply.error?.length > 0 ? reply.error : Translation.tr("Could not synthesize speech"), root.interfaceRole);
                return;
            }
            // Stopped while synthesis was still running: do not start playing now.
            if (root.speakingMessageId.length === 0) {
                cleanupOrphan.command = ["rm", "-f", ...reply.paths];
                cleanupOrphan.running = true;
                return;
            }
            readerLoader.active = true;
            readerLoader.item.start(reply.paths);
        });
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
                if (text.startsWith("[gateway-crash]"))
                    root.lastError = text;
                console.log("[Hermes]", text);
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.ready = false;
            root.starting = false;
            root.sessionId = "";
            root.streamingId = "";
            root.busy = false;
            root.statusText = "";
            root.pendingApproval = null;
            root.pendingClarify = null;
            root.speakingMessageId = "";
            root._pendingCalls = ({});

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
