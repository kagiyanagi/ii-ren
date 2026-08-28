pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common.functions
import qs.modules.common.utils
import qs.services

/**
 * Batch text translator backed by the `trans` (translate-shell) CLI.
 * No API key, no billing: same tool the sidebar translator already uses.
 * Exposes `translations`, aligned index-for-index with the input strings.
 */
AsyncTask {
    id: root

    property list<string> pendingStrings: []
    property list<string> translations: []

    // `trans` wants BCP-47 (zh-CN), Translation hands out POSIX-ish (zh_CN).
    readonly property string targetLanguage: Translation.languageCode.replace("_", "-")

    function translateStrings(strings: list<string>) {
        resetState();
        root.pendingStrings = strings;
        root.translations = [];
        if (strings.length === 0) {
            root.succeed();
            return;
        }
        root.state = AsyncTask.State.Processing;

        // `trans` emits exactly one line per argument, so any newline in the source
        // would desync the input/output mapping.
        const args = strings.map(s => `'${StringUtils.shellSingleQuoteEscape(s.replace(/\s+/g, " ").trim())}'`).join(" ");
        proc.runSequence([
            ["bash", "-c", `trans -brief -no-bidi -target '${StringUtils.shellSingleQuoteEscape(root.targetLanguage)}' -- ${args}`],
            (out) => root.handleTransOutput(out)
        ]);
    }

    function handleTransOutput(out: string) {
        const lines = (out ?? "").split("\n");
        if (lines.length > 0 && lines[lines.length - 1] === "")
            lines.pop();
        if (lines.length !== root.pendingStrings.length) {
            root.fail(Translation.tr("Translation failed. Check your internet connection."));
            return;
        }
        root.translations = lines;
        root.succeed();
    }

    MultiTurnProcess {
        id: proc
    }
}
