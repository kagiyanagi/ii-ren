import QtQuick
import Quickshell.Io

/**
 * One file from the user, through kdialog or zenity, whichever is installed.
 * `missing` turns true when neither is, so the caller can say why nothing opened.
 * The label and patterns go in as arguments, never spliced into the script.
 * It was copied by hand into four settings pages before this.
 */
Process {
    id: root
    property string label
    property list<string> patterns
    property bool missing: false
    signal picked(string path)

    function pick() {
        root.running = false;
        root.running = true;
    }

    command: ["bash", "-c", 'p="${*:2}"; if command -v kdialog >/dev/null; then kdialog --getopenfilename "$HOME" "$p"; elif command -v zenity >/dev/null; then zenity --file-selection --file-filter="$1 | $p"; else exit 127; fi',
        "picker", root.label, ...root.patterns]
    stdout: StdioCollector {
        onStreamFinished: {
            const path = this.text.trim();
            if (path.length > 0)
                root.picked(path);
        }
    }
    onExited: exitCode => root.missing = exitCode === 127
}
