import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * One agent as Settings > Agent sees it: where its program is, who is signed in,
 * and the sign-in, sign-out, install or removal under way.
 *
 * Every answer comes from scripts/agent/setup.py running the agent's own program
 * -- this never reads a login either. A finished job tells the shell over IPC
 * (`agent refresh`), so a sidebar on that agent restarts on the new account; the
 * shell ignores it until the sidebar has been opened once.
 */
QtObject {
    id: root

    required property string agentId
    required property string label

    readonly property string setupScript: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/agent/setup.py"))
    readonly property var settings: Config.options.agent[root.agentId]
    readonly property string customPath: (root.settings?.binary ?? "").trim().replace(/^~(?=\/|$)/, FileUtils.trimFileProtocol(Directories.home))
    readonly property var binArgs: root.customPath.length > 0 ? ["--bin", root.customPath] : []

    // setup.py status, as it last answered; null until it has.
    property var status: null
    readonly property bool checked: root.status !== null
    readonly property bool checking: statusProc.running
    readonly property bool installed: root.status?.installed ?? false
    // true, false, or null when the program could not say (status.error).
    readonly property var signedIn: root.status?.signed_in ?? null

    // "" | "login" | "logout" | "install" | "remove", while setup.py runs it.
    property string job: ""
    // The browser link a sign-in waits on, opened once as it arrives.
    property string link: ""
    // The program wants the code the browser shows (its manual flow).
    property bool needsCode: false
    // An install's share done, 0..1; -1 before the size is known.
    property real progress: -1
    // The last job's failure, until the next one starts.
    property string jobError: ""
    // Antigravity: the server version the ACP registry offers now ("" unknown).
    property string latest: ""

    // The models the picker offered the last time the sidebar ran this agent
    // (scripts/agent/bridge.py writes them): Settings cannot ask an agent that is
    // not running.
    readonly property var models: root._catalog?.models ?? []
    property var _catalog: null

    function refresh(): void {
        statusProc.refresh();
    }
    // A program typed into Settings is the one asked from then on.
    onCustomPathChanged: {
        if (root.checked)
            root.refresh();
    }

    function signIn(): void {
        root._start("login");
    }

    function signOut(): void {
        root._start("logout");
    }

    function install(): void {
        root._start("install");
    }

    function remove(): void {
        root._start("remove");
    }

    function cancel(): void {
        if (jobProc.running)
            jobProc.signal(15); // setup.py stops the program it started, and cleans up a download
    }

    function sendCode(code: string): void {
        const clean = code.trim();
        if (clean.length === 0 || !jobProc.running)
            return;
        jobProc.write(clean + "\n");
        root.needsCode = false;
    }

    function checkLatest(): void {
        if (root.agentId === "antigravity" && !latestProc.running)
            latestProc.running = true;
    }

    function _start(kind: string): void {
        if (jobProc.running)
            return;
        root.jobError = "";
        root.link = "";
        root.needsCode = false;
        root.progress = -1;
        root.job = kind;
        jobProc.command = ["python3", root.setupScript, kind, root.agentId].concat(root.binArgs);
        jobProc.running = true;
    }

    function _read(line: string): void {
        let reply;
        try {
            reply = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (reply.url !== undefined) {
            const first = root.link.length === 0;
            root.link = reply.url;
            root.needsCode = reply.code === true;
            // Opened once, as T3 Code does; the page keeps it to open again or copy.
            if (first)
                Qt.openUrlExternally(reply.url);
        }
        if (reply.progress !== undefined) {
            const done = reply.progress[0] ?? 0;
            const total = reply.progress[1] ?? 0;
            root.progress = total > 0 ? Math.min(1, done / total) : -1;
        }
        if (reply.error !== undefined)
            root.jobError = reply.error;
    }

    property Process statusProc: RefreshProcess {
        command: ["python3", root.setupScript, "status", root.agentId].concat(root.binArgs)
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.status = JSON.parse(this.text);
                } catch (e) {
                    root.status = { installed: false, error: Translation.tr("Could not check %1").arg(root.label) };
                }
            }
        }
    }

    property Process jobProc: Process {
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root._read(line)
        }
        onExited: (exitCode, exitStatus) => {
            const kind = root.job;
            root.job = "";
            root.link = "";
            root.needsCode = false;
            root.progress = -1;
            // Cancelled is not a failure worth a red line.
            if (exitCode === 143 || exitCode === 129)
                root.jobError = "";
            root.refresh();
            if (kind === "install" || kind === "remove")
                root.checkLatest();
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "agent", "refresh", root.agentId]);
        }
    }

    property Process latestProc: Process {
        command: ["python3", root.setupScript, "latest", "antigravity"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.latest = JSON.parse(this.text).version ?? "";
                } catch (e) {
                    root.latest = "";
                }
            }
        }
    }

    // Where the bridge keeps it (bridge.STATE_DIR), named the way it does: this
    // app's own state directory is not the shell's.
    property FileView catalogView: FileView {
        path: `${Quickshell.env("XDG_STATE_HOME") || FileUtils.trimFileProtocol(Directories.home) + "/.local/state"}/quickshell/agent/catalog-${root.agentId}.json`
        watchChanges: true
        printErrors: false // absent until the sidebar first runs this agent
        onFileChanged: catalogView.reload()
        onLoaded: {
            try {
                root._catalog = JSON.parse(catalogView.text());
            } catch (e) {
                root._catalog = null;
            }
        }
        onLoadFailed: root._catalog = null
    }
}
