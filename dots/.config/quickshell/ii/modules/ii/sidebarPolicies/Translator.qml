import qs.services
import qs.modules.common
import qs.modules.common.widgets
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
    property var inputField: inputCanvas.textArea

    property string translatedText: ""
    property string translateError: ""
    // The translation spelled out in Latin letters, when its script is not.
    property string transliteration: ""
    // Google's "did you mean", when it read the input as something else.
    property string correction: ""
    // Code of what "auto" resolved to; empty when the source is picked by hand.
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
        return root.sourceLanguage === "auto" && target.split(" ")[0] === root.detectedLanguage;
    }
    onRefiningChanged: translateTimer.restart()
    // LanguageTool codes, fetched once; `trans` codes are resolved against them.
    property list<string> ltLanguages: []
    // The text a check ran on, with its matches, so the offsets never meet other text.
    property var refineResult: ({ text: "", matches: [] })
    property string refineError: ""
    readonly property string refinedText: root.applyFixes(root.refineResult.text, root.refineResult.matches, Config.options.sidebar.translator.fixes)
    readonly property string outputError: root.refining ? root.refineError : root.translateError
    readonly property string outputText: (root.refining ? root.refinedText : root.translatedText).trim()
    // What auto resolved to, as the endonym the language list and the swap use.
    readonly property string detectedEndonym: Object.keys(root.languageAliases).find(k => root.languageAliases[k].split(" ")[0] === root.detectedLanguage) ?? ""
    readonly property string swapTarget: root.sourceLanguage === "auto" ? root.detectedEndonym : root.sourceLanguage

    // `-dump` prints Google's raw answer still in HTTP chunks, a size line before each
    // body line; the JSON escapes its own newlines, so every other line is body. Null
    // when it does not parse, so a format change shows as a failure, not as garbage.
    function parseDump(raw: string): var {
        const body = raw.trim();
        try {
            const d = JSON.parse(body.startsWith("[") ? body : body.split(/\r?\n/).filter((_, i) => i % 2).join(""));
            const translation = d[0].map(s => s[0] ?? "").join("").trim();
            // The romanisation rides on a segment of its own, with no translation in it.
            const roman = d[0].find(s => s[0] === null)?.[2] ?? "";
            return {
                translation: translation,
                transliteration: roman === translation ? "" : roman,
                // Google still says iw and jw where `trans` lists he and jv.
                detected: ({ iw: "he", jw: "jv" })[d[2]] ?? d[2] ?? "",
                correction: d[7]?.[1] ?? "",
            };
        } catch (e) {
            return null;
        }
    }

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

    property bool languageSelectorTarget: false // true for target language, false for source language

    function showLanguageSelectorDialog(isTargetLang: bool) {
        root.languageSelectorTarget = isTargetLang;
        languageDialog.active = true;
        languageDialog.item.show = true;
    }

    function setLanguage(isTarget: bool, language: string) {
        if (isTarget) {
            root.targetLanguage = language;
            Config.options.language.translator.targetLanguage = language;
        } else {
            root.sourceLanguage = language;
            Config.options.language.translator.sourceLanguage = language;
        }
        translateTimer.restart();
    }

    // Google's swap: the languages trade places and a translation that is
    // showing becomes the input.
    function swapLanguages() {
        const target = root.targetLanguage;
        const carried = root.refining || root.outputError ? "" : root.outputText;
        root.setLanguage(true, root.swapTarget);
        root.setLanguage(false, target);
        if (carried) root.inputField.text = carried;
    }

    onFocusChanged: (focus) => {
        if (focus) {
            root.inputField.forceActiveFocus()
        }
    }

    Connections {
        target: root.inputField
        function onTextChanged() {
            translateTimer.restart();
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
                }
                // On auto it runs while refining too: the detected language is in its answer.
                if (!root.refining || root.sourceLanguage === "auto") {
                    translateProc.buffer = "";
                    root.translateError = "";
                    translateProc.running = true;
                }
            } else {
                root.translatedText = "";
                root.transliteration = "";
                root.correction = "";
                root.translateError = "";
                root.refineResult = { text: "", matches: [] };
                root.refineError = "";
            }
            if (root.sourceLanguage !== "auto" || root.inputField.text.trim().length === 0)
                root.detectedLanguage = "";
        }
    }

    Process {
        id: translateProc
        // Through env, so a missing `trans` still exits 127 instead of failing to start.
        command: ["env", "trans", "-dump", "-no-bidi", "-source", root.sourceLanguage, "-target", root.targetLanguage,
            "--", root.inputField.text.trim()]
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => {
                translateProc.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            // A run that was killed for a newer keystroke says nothing.
            if (exitStatus !== 0) return;
            const out = root.parseDump(translateProc.buffer);
            if (exitCode === 127) root.translateError = Translation.tr("Translating needs `trans` (translate-shell)");
            else if (exitCode !== 0 || !out?.translation) root.translateError = Translation.tr("Couldn't translate. Check your connection");
            else {
                root.translatedText = out.translation;
                root.transliteration = out.transliteration;
                root.correction = out.correction === root.inputField.text.trim() ? "" : out.correction;
                if (root.sourceLanguage === "auto") root.detectedLanguage = out.detected;
            }
        }
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
        id: speakProc
        // Killing `trans` would orphan its player, so a reading plays out; the button waits.
        // Voice wants a code: given "English" it says it has none, and exits 0.
        command: ["trans", "-speak", "-no-translate", "-source", root.languageAliases[root.targetLanguage]?.split(" ")[0] ?? "auto",
            "--", root.outputText]
        onStarted: console.warn("[Translator] speak start", JSON.stringify(command))
        onExited: (code, status) => console.warn("[Translator] speak exit", code, status)
        stdout: SplitParser { onRead: data => console.warn("[Translator] speak out:", data) }
        stderr: SplitParser { onRead: data => console.warn("[Translator] speak err:", data) }
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

    // The language bar, then the two cards sharing the rest of the height, as
    // Google Translate lays out a tall screen. Each card scrolls its own text.
    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 8

        // From, swap, to. The pills share the row equally, so the detected
        // hint growing in never moves the swap button.
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            LanguageSelectorButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                displayText: root.sourceLanguage === "auto" ? Translation.tr("Auto") : root.sourceLanguage
                hintText: root.sourceLanguage === "auto" ? root.detectedEndonym : ""
                onClicked: root.showLanguageSelectorDialog(false)
            }
            RippleButton {
                id: swapButton
                property int turns: 0
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                enabled: root.swapTarget.length > 0
                onClicked: {
                    swapButton.turns++;
                    root.swapLanguages();
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.hugeass
                    text: "swap_horiz"
                    color: Appearance.colors.colOnLayer1
                    rotation: swapButton.turns * 180
                    Behavior on rotation {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Swap languages (Ctrl+Enter)")
                }
            }
            LanguageSelectorButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                displayText: root.targetLanguage
                onClicked: root.showLanguageSelectorDialog(true)
            }
        }

        TextCanvas { // Content input
            id: inputCanvas
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1
            isInput: true
            placeholderText: Translation.tr("Enter text to translate")
            onCtrlReturnPressed: if (swapButton.enabled) swapButton.clicked()
            leading: root.correction ? correctionChip : characterCount
            CardButton {
                symbol: "content_paste"
                onClicked: root.inputField.text = Quickshell.clipboardText
            }
            CardButton {
                symbol: "close"
                enabled: root.inputField.text.length > 0
                onClicked: root.inputField.text = ""
            }
        }

        TextCanvas { // Content translation
            id: outputCanvas
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1
            isInput: false
            // No card: the translation sits straight on the page, under the input's.
            color: "transparent"
            emptyIcon: "translate"
            emptyTitle: Translation.tr("Translation")
            emptyDescription: Translation.tr("Appears here as you type\nPick the same language on both sides to fix spelling and grammar instead")
            text: root.outputError || root.outputText
            error: root.outputError.length > 0
            busy: translateProc.running || refineProc.running
            leading: root.refining ? fixSelector : root.transliteration && !outputCanvas.error ? transliterationText : null
            CardButton {
                id: copyButton
                property bool copied: false
                symbol: copied ? "check" : "content_copy"
                enabled: !outputCanvas.error && root.outputText.length > 0
                onClicked: {
                    Quickshell.clipboardText = root.outputText;
                    copyButton.copied = true;
                    copiedTimer.restart();
                }
                Timer {
                    id: copiedTimer
                    interval: 1500
                    onTriggered: copyButton.copied = false
                }
            }
            CardButton {
                symbol: speakProc.running ? "graphic_eq" : "volume_up"
                enabled: copyButton.enabled && !speakProc.running
                onClicked: speakProc.running = true
            }
            CardButton {
                symbol: "travel_explore"
                enabled: copyButton.enabled
                onClicked: {
                    let url = Config.options.search.engineBaseUrl + root.outputText;
                    for (let site of Config.options.search.excludedSites) {
                        url += ` -site:${site}`;
                    }
                    Qt.openUrlExternally(url);
                }
            }
        }
    }

    // The card actions: an M3 button group on the layer-2 cards.
    component CardButton: GroupButton {
        id: cardButton
        property string symbol
        baseWidth: 40
        baseHeight: 40
        // Round at rest, so no pressed morph (DESIGN.md 4.3); the group's
        // bounce is the press.
        buttonRadius: Appearance.rounding.full
        buttonRadiusPressed: Appearance.rounding.full
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            iconSize: Appearance.font.pixelSize.larger
            text: cardButton.symbol
            color: Appearance.colors.colOnLayer2
        }
    }

    Component {
        id: fixSelector
        FixSelectorButton {}
    }

    Component {
        id: characterCount
        StyledText {
            leftPadding: 8
            verticalAlignment: Text.AlignVCenter
            text: Translation.tr("%1 characters").arg(root.inputField.text.length)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    Component {
        id: transliterationText
        StyledText {
            leftPadding: 8
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: root.transliteration
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    // Takes Google's reading as the input, as its "Did you mean" link does.
    Component {
        id: correctionChip
        RippleButton {
            horizontalPadding: 12
            implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: root.inputField.text = root.correction
            contentItem: StyledText {
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: Translation.tr("Did you mean: %1").arg(root.correction)
                color: Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    // Latched: it stays loaded until the dialog's exit has played.
    Loader {
        id: languageDialog
        anchors.fill: parent
        active: false
        z: 9999
        sourceComponent: SelectionDialog {
            titleText: Translation.tr("Select language")
            items: root.languages
            searchAliases: root.languageAliases
            defaultChoice: root.languageSelectorTarget ? root.targetLanguage : root.sourceLanguage
            onCanceled: show = false
            onSelected: result => {
                show = false;
                if (result?.length > 0) root.setLanguage(root.languageSelectorTarget, result);
            }
            onVisibleChanged: if (!visible && !show) languageDialog.active = false
        }
    }
}
