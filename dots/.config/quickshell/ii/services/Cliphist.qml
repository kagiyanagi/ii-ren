pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // property string cliphistBinary: FileUtils.trimFileProtocol(`${Directories.home}/.cargo/bin/stash`)
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property string pressPasteCommand: "ydotool key -d 1 29:1 47:1 47:0 29:0"
    property list<string> entries: []
    readonly property var preparedEntries: entries.map(a => ({
        name: Fuzzy.prepare(`${a.replace(/^\s*\S+\s+/, "")}`),
        entry: a
    }))
    function fuzzyQuery(search: string): var {
        if (search.trim() === "") {
            return entries;
        }
        return Fuzzy.queryEntries(search, preparedEntries);
    }

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    function refresh() {
        readProc.running = true
    }

    // Shell that writes the entry's full content to stdout. Clipboard text is
    // always an argument, and printf's format is fixed, even for % and backslashes.
    function decodeCommand() {
        if (root.cliphistBinary.includes("cliphist")) // Classic cliphist
            return 'printf "%s" "$1" | "$2" decode';
        return '"$2" decode "$3"'; // Stash
    }

    function decodeArguments(entry) {
        return ["sh", entry, root.cliphistBinary, entry.split("\t")[0]];
    }

    function copy(entry) {
        Quickshell.execDetached(["bash", "-c", `${root.decodeCommand()} | wl-copy`, ...root.decodeArguments(entry)]);
    }

    // Same folder the screenshot preview's Save goes to.
    function saveImage(entry) {
        const dir = Config.options.screenSnip.savePath !== "" ? Config.options.screenSnip.savePath
            : `${FileUtils.trimFileProtocol(Directories.pictures)}/Screenshots`;
        const ext = entry.match(/binary data.*?\b(png|jpe?g|gif|webp|bmp)\b/i)?.[1] ?? "png";
        Quickshell.execDetached(["bash", "-c",
            `mkdir -p "$4" && ${root.decodeCommand()} > "$4"/clipboard-"$(date '+%Y-%m-%d_%H.%M.%S')"."$5"`,
            ...root.decodeArguments(entry), dir, ext]);
    }

    // Decoded rather than taken from the list, which cliphist cuts at 100 characters.
    function openLink(entry) {
        Quickshell.execDetached(["bash", "-c", `xdg-open "$(${root.decodeCommand()})"`, ...root.decodeArguments(entry)]);
    }

    function paste(entry) {
        const pasteCommand = root.cliphistBinary.includes("cliphist") ? "wl-paste" : root.pressPasteCommand;
        Quickshell.execDetached(["bash", "-c", `${root.decodeCommand()} | wl-copy && ${pasteCommand}`, ...root.decodeArguments(entry)]);
    }

    function superpaste(count, isImage = false) {
        // Find entries
        const targetEntries = entries.filter(entry => {
            if (!isImage) return true;
            return entryIsImage(entry);
        }).slice(0, count)
        Quickshell.execDetached(["bash", "-c",
            `binary=$1; delay=$2; shift 2; for entry; do `
            + `(set -- "$entry" "$binary" "\${entry%%\t*}"; ${root.decodeCommand()} | wl-copy)`
            + ` && sleep "$delay" && ${root.pressPasteCommand} && sleep "$delay" || exit; done`,
            "sh", root.cliphistBinary, String(root.pasteDelay), ...[...targetEntries].reverse()]);
    }

    Process {
        id: deleteProc
        property string entry: ""
        property list<string> pending: []
        command: ["sh", "-c", 'printf "%s\\n" "$1" | "$2" delete', "sh", deleteProc.entry, root.cliphistBinary]
        function deleteEntry(entry) {
            if (!entry) return;
            deleteProc.pending = deleteProc.pending.concat([entry]);
            deleteProc.next();
        }
        function next() {
            if (deleteProc.running || deleteProc.pending.length === 0) return;
            deleteProc.entry = deleteProc.pending[0];
            deleteProc.pending = deleteProc.pending.slice(1);
            deleteProc.running = true;
        }
        onExited: (exitCode, exitStatus) => {
            root.refresh();
            Qt.callLater(deleteProc.next);
        }
    }

    function deleteEntry(entry) {
        deleteProc.deleteEntry(entry);
    }

    Process {
        id: wipeProc
        command: [root.cliphistBinary, "wipe"]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    function wipe() {
        wipeProc.running = true;
    }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            delayedUpdateTimer.restart()
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        repeat: false
        onTriggered: {
            root.refresh()
        }
    }

    Process {
        id: readProc
        command: [root.cliphistBinary, "list"]
        // One split at the end: a push per line onto a list property copied the
        // whole list each time, quadratic in the history's 750 entries.
        stdout: StdioCollector { id: readOut }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.entries = readOut.text.split("\n").filter(line => line.length > 0)
            } else {
                console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
            }
        }
    }

    IpcHandler {
        target: "cliphistService"

        function update(): void {
            root.refresh()
        }
    }
}
