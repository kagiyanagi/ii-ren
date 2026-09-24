import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarPolicies.translator
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Translator widget with the `trans` commandline tool.
 */
Item {
    id: root

    property real padding: 4
    property var inputField: inputCanvas.inputTextArea

    property string translatedText: ""
    // English name of what "auto" resolved to; empty when the source is picked by hand.
    property string detectedLanguage: ""
    property list<string> languages: []
    // Endonym -> "code English name", which the language picker also searches.
    property var languageAliases: ({})

    property string targetLanguage: Config.options.language.translator.targetLanguage
    property string sourceLanguage: Config.options.language.translator.sourceLanguage

    // Same language on both sides: the output is the input with LanguageTool's fixes applied.
    readonly property bool refining: {
        const target = root.languageAliases[root.targetLanguage];
        if (!target) return false;
        if (root.sourceLanguage === root.targetLanguage) return true;
        return root.sourceLanguage === "auto" && target.slice(target.indexOf(" ") + 1) === root.detectedLanguage;
    }
    onRefiningChanged: translateTimer.restart()
    // LanguageTool codes, fetched once; `trans` codes are resolved against them.
    property list<string> ltLanguages: []
    // The text a check ran on, with its matches, so the offsets never meet other text.
    property var refineResult: ({ text: "", matches: [] })
    property string refineError: ""
    readonly property string refinedText: root.refineError || root.applyFixes(root.refineResult.text, root.refineResult.matches, Config.options.sidebar.translator.fixes)

    function ltCode(code: string): string {
        const L = root.ltLanguages;
        // Bare "en"/"de" skip spell checking, so prefer a regional variant.
        const picks = code.includes("-") ? [code] : [`${code}-${code.toUpperCase()}`, L.find(x => x.startsWith(code + "-")), code];
        return picks.find(x => L.includes(x)) ?? "";
    }

    function fixKind(category: string): string {
        if (category === "TYPOS") return "spelling";
        if (["PUNCTUATION", "TYPOGRAPHY"].includes(category)) return "punctuation";
        if (["STYLE", "REDUNDANCY", "PLAIN_ENGLISH", "REPETITIONS_STYLE", "COLLOQUIALISMS"].includes(category)) return "style";
        return "grammar";
    }

    function applyFixes(text: string, matches: var, fixes: var): string {
        let out = text;
        let end = Infinity;
        // Back to front, so each splice leaves the earlier offsets valid.
        for (const m of [...matches].sort((a, b) => b.offset - a.offset)) {
            if (m.offset + m.length > end || !m.replacements.length || !fixes.includes(root.fixKind(m.rule.category.id))) continue;
            out = out.slice(0, m.offset) + m.replacements[0].value + out.slice(m.offset + m.length);
            end = m.offset;
        }
        return out;
    }

    property bool showLanguageSelector: false
    property bool languageSelectorTarget: false // true for target language, false for source language

    function showLanguageSelectorDialog(isTargetLang: bool) {
        root.languageSelectorTarget = isTargetLang;
        root.showLanguageSelector = true
    }

    onFocusChanged: (focus) => {
        if (focus) {
            root.inputField.forceActiveFocus()
        }
    }

    Timer {
        id: translateTimer
        interval: Config.options.sidebar.translator.delay
        repeat: false
        onTriggered: () => {
            if (root.inputField.text.trim().length > 0) {
                // Restarted rather than started: a keystroke during a run has to
                // replace it, and the buffer belongs to the run that is ending.
                translateProc.running = false;
                refineProc.running = false;
                if (root.refining) {
                    const code = root.ltCode(root.languageAliases[root.targetLanguage].split(" ")[0]);
                    root.refineError = code ? "" : Translation.tr("LanguageTool can't check %1").arg(root.targetLanguage);
                    refineProc.language = code;
                    refineProc.text = root.inputField.text;
                    refineProc.running = code.length > 0;
                } else {
                    translateProc.buffer = "";
                    translateProc.running = true;
                }
                detectProc.running = false;
                detectProc.running = root.sourceLanguage === "auto";
            } else {
                root.translatedText = "";
                root.refineResult = { text: "", matches: [] };
                root.refineError = "";
            }
            if (root.sourceLanguage !== "auto" || root.inputField.text.trim().length === 0)
                root.detectedLanguage = "";
        }
    }

    Process {
        id: translateProc
        command: ["bash", "-c", `trans -brief -no-bidi`
            + ` -source '${StringUtils.shellSingleQuoteEscape(root.sourceLanguage)}'`
            + ` -target '${StringUtils.shellSingleQuoteEscape(root.targetLanguage)}'`
            + ` '${StringUtils.shellSingleQuoteEscape(root.inputField.text.trim())}'`]
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                translateProc.buffer += data + "\n";
            }
        }
        onExited: () => root.translatedText = translateProc.buffer.trim()
    }

    Process {
        id: refineProc
        property string language
        property string text
        command: ["curl", "-sS", "--max-time", "10", "https://api.languagetool.org/v2/check",
            "--data-urlencode", `language=${language}`, "--data-urlencode", `text=${text}`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.refineResult = { text: refineProc.text, matches: JSON.parse(this.text).matches };
                    root.refineError = "";
                } catch (e) {
                    // Rate limits and outages answer in plain text.
                    root.refineError = this.text.trim() || Translation.tr("LanguageTool is unreachable");
                }
            }
        }
    }

    Process {
        id: ltLanguagesProc
        command: ["curl", "-sS", "--max-time", "10", "https://api.languagetool.org/v2/languages"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.ltLanguages = JSON.parse(this.text).map(l => l.longCode);
                } catch (e) {}
            }
        }
    }

    Process {
        id: detectProc
        // `-brief` drops the source language, so identify it on a call of its own.
        command: ["trans", "-id", "-no-ansi", "-no-bidi", root.inputField.text.trim()]
        stdout: SplitParser {
            onRead: data => {
                const m = data.match(/^Name\s+(.+)$/);
                if (m) root.detectedLanguage = m[1].trim();
            }
        }
    }

    Process {
        id: getLanguagesProc
        // One language a line: code, English name, endonym, in columns.
        command: ["trans", "-list-all", "-no-bidi"]
        property var buffer: []
        running: true
        stdout: SplitParser {
            onRead: data => {
                const cols = data.trim().split(/\s{2,}/);
                if (cols.length === 3) getLanguagesProc.buffer.push(cols);
            }
        }
        onExited: () => {
            const aliases = {};
            for (const [code, english, endonym] of getLanguagesProc.buffer) aliases[endonym] = `${code} ${english}`;
            // "auto" first, then the rest alphabetically.
            root.languages = ["auto", ...Object.keys(aliases).sort((a, b) => a.localeCompare(b))];
            root.languageAliases = aliases;
            getLanguagesProc.buffer = [];
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: contentColumn.implicitHeight

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent

                TextCanvas { // Content translation
                    id: outputCanvas
                    isInput: false
                    language: root.targetLanguage
                    onLanguageClicked: root.showLanguageSelectorDialog(true)
                    placeholderText: Translation.tr("Translation goes here...")
                    readonly property string result: root.refining ? root.refinedText : root.translatedText
                    text: result.trim().length > 0 ? result : ""
                    statusComponent: root.refining ? fixSelector : null
                    GroupButton {
                        id: copyButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "content_copy"
                            color: copyButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        }
                        onClicked: {
                            Quickshell.clipboardText = outputCanvas.displayedText
                        }
                    }
                    GroupButton {
                        id: searchButton
                        baseWidth: height
                        buttonRadius: Appearance.rounding.small
                        enabled: outputCanvas.displayedText.trim().length > 0
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.larger
                            text: "travel_explore"
                            color: searchButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        }
                        onClicked: {
                            let url = Config.options.search.engineBaseUrl + outputCanvas.displayedText;
                            for (let site of Config.options.search.excludedSites) {
                                url += ` -site:${site}`;
                            }
                            Qt.openUrlExternally(url);
                        }
                    }
                }

            }
        }

        TextCanvas { // Content input
            id: inputCanvas
            isInput: true
            language: root.sourceLanguage
            languageHint: root.detectedLanguage
            onLanguageClicked: root.showLanguageSelectorDialog(false)
            placeholderText: Translation.tr("Enter text to translate...")
            onInputTextChanged: {
                translateTimer.restart();
            }
            GroupButton {
                id: pasteButton
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: "content_paste"
                    color: pasteButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                onClicked: {
                    root.inputField.text = Quickshell.clipboardText
                }
            }
            GroupButton {
                id: deleteButton
                baseWidth: height
                buttonRadius: Appearance.rounding.small
                enabled: inputCanvas.inputTextArea.text.length > 0
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    text: "close"
                    color: deleteButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                onClicked: {
                    root.inputField.text = ""
                }
            }
        }
    }

    Component {
        id: fixSelector
        FixSelectorButton {}
    }

    Loader {
        anchors.fill: parent
        active: root.showLanguageSelector
        visible: root.showLanguageSelector
        z: 9999
        sourceComponent: SelectionDialog {
            id: languageSelectorDialog
            titleText: Translation.tr("Select Language")
            items: root.languages
            searchAliases: root.languageAliases
            defaultChoice: root.languageSelectorTarget ? root.targetLanguage : root.sourceLanguage
            onCanceled: () => {
                root.showLanguageSelector = false;
            }
            onSelected: (result) => {
                root.showLanguageSelector = false;
                if (!result || result.length === 0) return;

                if (root.languageSelectorTarget) {
                    root.targetLanguage = result;
                    Config.options.language.translator.targetLanguage = result;
                } else {
                    root.sourceLanguage = result;
                    Config.options.language.translator.sourceLanguage = result;
                }

                translateTimer.restart();
            }
        }
    }
}
