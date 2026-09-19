pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * One shell command at a time, run the way a terminal runs it.
 *
 * The agent's own `shell.exec` is captured-only -- stdin is /dev/null, there is a
 * 30s cap, and nothing arrives until the process exits. A command you can answer
 * a prompt in, watch, and stop needs the opposite of all three, so the shell runs
 * it here rather than delegating.
 *
 * Everything runs under `script`, which allocates a pty. That is load-bearing,
 * not decoration:
 *   - Without a terminal on the far end, libc switches stdout to full buffering,
 *     so a long-running command would show nothing at all until it exited.
 *   - A prompt is written without a trailing newline ("Password: "), and a
 *     line-splitting reader never emits it. The collector here takes whatever has
 *     arrived, so a half-line prompt shows up.
 *   - ^C is not a signal you send to a process. It is a byte the line discipline
 *     turns into SIGINT for the whole foreground group -- which is why children
 *     of the command die too. Writing \x03 is a real Ctrl+C; signalling `script`
 *     would only kill the wrapper.
 *
 * One at a time is deliberate. A sidebar with a job table is a terminal
 * emulator, and there is already one of those on this machine.
 */
QtObject {
    id: root

    // Where staged code blocks land. /tmp/quickshell is the convention the rest
    // of the shell already uses for throwaway files.
    readonly property string workDir: "/tmp/quickshell/hermes/run"

    readonly property bool running: process.running
    // True once a run has finished and its output is still worth showing.
    property bool finished: false
    property string command: ""
    property string output: ""
    property int exitCode: 0
    // Set when the user stopped it, so the result line can say so rather than
    // reporting the 130 that a SIGINT leaves behind as a plain failure.
    property bool interrupted: false

    property string workingDirectory: ""

    signal completed(string command, string output, int exitCode)

    /**
     * Interpreters this can drive, by fenced-language name.
     *
     * Interpreters only. A compiled language needs a toolchain, a target
     * directory and a link step that a sidebar has no business guessing at --
     * `go run` is here because it is genuinely one command, and nothing else is.
     */
    readonly property var runners: ({
        "sh": ["sh"], "shell": ["bash"], "bash": ["bash"], "console": ["bash"], "zsh": ["zsh"], "fish": ["fish"],
        "python": ["python3"], "py": ["python3"], "python3": ["python3"],
        "javascript": ["node"], "js": ["node"], "node": ["node"], "mjs": ["node"],
        "typescript": ["bun", "run"], "ts": ["bun", "run"],
        "ruby": ["ruby"], "rb": ["ruby"],
        "perl": ["perl"], "pl": ["perl"],
        "lua": ["lua"], "php": ["php"], "r": ["Rscript"],
        "go": ["go", "run"]
    })

    readonly property var extensions: ({
        "shell": "sh", "console": "sh", "python": "py", "python3": "py", "javascript": "js",
        "node": "js", "typescript": "ts", "ruby": "rb", "perl": "pl", "r": "R"
    })

    // Binaries found on this machine. Empty until the probe answers, which is
    // why a Run button is hidden rather than disabled until then -- a control
    // that appears a moment later reads better than one that was dead and woke up.
    property var available: []

    /** The argv that runs `lang`, or null when nothing here can. */
    function runnerFor(lang: string): var {
        const argv = root.runners[(lang ?? "").toLowerCase()] ?? null;
        if (argv === null || !root.available.includes(argv[0]))
            return null;
        return argv;
    }

    function canRun(lang: string): bool {
        return root.runnerFor(lang) !== null;
    }

    function extensionFor(lang: string): string {
        const key = (lang ?? "").toLowerCase();
        return root.extensions[key] ?? (/^[a-z0-9]+$/.test(key) ? key : "txt");
    }

    /** Stage `code` as a file and run it under its interpreter. */
    function runCode(code: string, lang: string): void {
        const argv = root.runnerFor(lang);
        if (argv === null)
            return;
        // Staging is a subprocess of its own, so the interpreter can only be
        // started from its callback -- running straight after the call would race
        // the file into existence.
        const path = root._stagePath(lang);
        root._stage(code, path, () => root.run(`${argv.join(" ")} '${path}'`, root.workingDirectory));
    }

    /** Write `code` to a file and open it in whatever handles that file type. */
    function openInEditor(code: string, lang: string): void {
        const path = root._stagePath(lang);
        root._stage(code, path, () => Quickshell.execDetached(["xdg-open", path]));
    }

    /** Save `code` next to the user's other downloads, without clobbering the last one. */
    function saveToFile(code: string, lang: string, directory: string): void {
        const stamp = new Date().toISOString().replace(/[-:]/g, "").slice(0, 15);
        const path = `${directory}/code-${stamp}.${root.extensionFor(lang)}`;
        root._stage(code, path, () => Quickshell.execDetached(["notify-send",
            Translation.tr("Code saved"), path, "-a", "Shell"]));
        root.lastSavedPath = path;
    }

    property string lastSavedPath: ""

    function run(command: string, cwd: string): void {
        if (root.running || (command ?? "").trim().length === 0)
            return;
        root.command = command;
        root.output = "";
        root.exitCode = 0;
        root.interrupted = false;
        root.finished = false;
        process.workingDirectory = (cwd ?? "").length > 0 ? cwd : root.workingDirectory;
        // -q no start/stop banner, -f flush after every write (without it the pty
        // output arrives in blocks), -e exit with the command's own status,
        // -c the command. /dev/null discards the typescript file it insists on.
        process.command = ["script", "-qfec", command, "/dev/null"];
        process.running = true;
    }

    /** Answer a prompt the running command is sitting on. */
    function send(text: string): void {
        if (!root.running)
            return;
        process.write(`${text}\n`);
    }

    /** Ctrl+C, as the terminal means it. */
    function interrupt(): void {
        if (!root.running)
            return;
        root.interrupted = true;
        process.write("\u0003");
        // A command that ignores SIGINT would otherwise leave the console stuck
        // with a stop button that does nothing.
        forceQuit.restart();
    }

    function clear(): void {
        root.finished = false;
        root.output = "";
        root.command = "";
    }

    property Timer forceQuit: Timer {
        interval: 3000
        onTriggered: if (root.running) process.signal(9)
    }

    /**
     * Strip the terminal control codes a pty makes programs emit.
     *
     * The pty is what gets us streaming, prompts and a working Ctrl+C -- and the
     * price is that programs now think they are talking to a terminal, so they
     * send colour, cursor moves, erase-line and window-title sequences. None of
     * that is text. Rendered raw it shows up as "[0;37m" runs and a box for every
     * ESC byte, which no font has a glyph for.
     *
     * OSC goes first: its payload can contain "[", so the CSI rule would eat half
     * of a title or shell-integration sequence and leave the rest as visible junk.
     */
    function _strip(raw: string): string {
        return raw
            .replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?/g, "")
            .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
            .replace(/\x1b[()*+][0-9A-Za-z]/g, "")
            .replace(/\x1b[=>78MDEHcZ]/g, "")
            // Whatever control bytes are left, minus tab, newline, and the
            // carriage returns _render still needs.
            .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "");
    }

    /**
     * Collapse carriage returns the way a terminal would.
     *
     * Two different things arrive as \r and they need opposite treatment. A pty
     * ends every line with \r\n, so a \r in last position is punctuation and is
     * simply dropped. A progress bar rewrites its line by returning to the start
     * of it, so a \r anywhere else means "forget what came before on this line".
     * Doing only the second -- treating a line ending as an overwrite -- discards
     * every line in the buffer.
     */
    function _render(raw: string): string {
        return root._strip(raw).split("\n").map(line => {
            const body = line.endsWith("\r") ? line.slice(0, -1) : line;
            const at = body.lastIndexOf("\r");
            return at === -1 ? body : body.slice(at + 1);
        }).join("\n");
    }

    // ponytail: the whole tail is re-rendered on each pump, so cost is
    // O(outputLimit) every 60ms rather than O(total output). If a command that
    // prints for minutes ever feels heavy, render incrementally from a cursor.
    readonly property int outputLimit: 20000

    function _drain(): void {
        root.output = root._render(outputCollector.text.slice(-root.outputLimit));
    }

    // Every stage gets its own file. Two blocks staged in the same breath would
    // otherwise share a path, and the first callback would run the second's code.
    property int _stageSeq: 0

    function _stagePath(lang: string): string {
        return `${root.workDir}/block-${++root._stageSeq}.${root.extensionFor(lang)}`;
    }

    function _stage(code: string, path: string, then: var): void {
        // A quoted heredoc delimiter passes the code through verbatim: no
        // expansion, no escaping pass of ours to get wrong. The only way to break
        // it is for the code to contain the delimiter, so it is moved out of reach.
        let mark = "QSBLOCK";
        while (code.includes(mark))
            mark += "X";
        stager.command = ["bash", "-c",
            `mkdir -p "$(dirname "$1")" && cat > "$1" <<'${mark}'\n${code}\n${mark}\n`, "bash", path];
        stager.done = then;
        stager.running = true;
    }

    property Process stager: Process {
        property var done: null
        onExited: exitCode => {
            const then = stager.done;
            stager.done = null;
            if (exitCode === 0 && then !== null)
                then();
        }
    }

    property Process binaryProbe: Process {
        // One process for the whole table rather than one per interpreter.
        command: ["bash", "-c",
            "for b in sh bash zsh fish python3 node bun ruby perl lua php Rscript go; do command -v $b >/dev/null 2>&1 && echo $b; done"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.available = this.text.trim().split("\n").filter(line => line.length > 0)
        }
    }

    property Process process: Process {
        id: process
        stdinEnabled: true
        // `script` runs the command through $SHELL, which is whatever the user
        // happens to use interactively. Pinning bash keeps a code block the model
        // wrote from meeting fish syntax rules.
        environment: ({ "SHELL": "/bin/bash" })

        // The pty is the command's stdout AND its stderr, so one collector gets
        // both, interleaved in the order they were actually written.
        stdout: StdioCollector {
            id: outputCollector
            waitForEnd: false
        }

        onExited: exitCode => {
            root.forceQuit.stop();
            root._drain();
            root.exitCode = exitCode;
            root.finished = true;
            root.completed(root.command, root.output, exitCode);
        }
    }

    // Streaming output at whatever rate the command writes would rebind the view
    // per byte. 60ms is the same throttle the transcript uses for streamed text.
    property Timer pump: Timer {
        interval: 60
        repeat: true
        running: root.running
        onTriggered: root._drain()
    }
}
