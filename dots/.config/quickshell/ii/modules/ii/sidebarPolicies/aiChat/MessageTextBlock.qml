pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

ColumnLayout {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    // On by default: no call site ever set this, so reply text could not be
    // selected at all and copying meant taking the whole message.
    property bool enableMouseSelection: true
    property var segmentContent: ({})
    // `{}` here is an empty block, not an empty object, so this was undefined --
    // which is what logged a TypeError per chunk on every message rendered.
    property var messageData: null
    property bool done: false
    property bool forceDisableChunkSplitting: false
    property bool isHistorical: false
    /** Passage a read-aloud is speaking right now, marked live. Empty when silent. */
    property string speakingPhrase: ""
    /** How far into it the voice is, 0..1, or -1 when unknown. */
    property real speakingProgress: -1
    /** Where the word being spoken starts in it, or -1 without word timings. */
    property int speakingOffset: -1
    /** What a transcript search is looking for. Every occurrence here is marked. */
    property string searchQuery: ""
    /** Whether this block's turn is the one the search has stepped to. */
    property bool searchCurrent: false

    /**
     * The fill of an inline `code` pill. A neutral step up with an outline-variant
     * border and primary text, as a chat sets a path apart: the fill alone (layer 3
     * or 4) was measured barely visible on a card, and the border is what makes the
     * box read, on the turn's card and inside a thought alike.
     */
    property color codeSpanColor: Appearance.colors.colLayer4Base

    // The formulas this block has asked for, as a set
    property var latexHashes: ({})
    property string renderedSegmentContent: ""
    property string shownText: ""
    property bool fadeChunkSplitting: false
    property string targetText: ""
    property int revealedWordCount: 0
    property int totalWordCount: 0
    property int settleCounter: 10

    Timer {
        id: streamTimer
        interval: 35 // design-ok: token streaming cadence, 28 words/sec
        repeat: true
        running: false
        onTriggered: root.advanceStream()
    }

    Layout.fillWidth: true


    /**
     * Inline `code` set apart from the prose around it, as a chat sets a path or
     * a command.
     *
     * Qt's markdown import gives a code span a fixed-pitch font and nothing else. So
     * each span becomes an HTML span in the code face and colour, which the import
     * keeps, bracketed with U+2063 for InlineCode to find and draw its pill behind,
     * and with `gap` px of letter-spacing on its last character and on the plain
     * character before it, which is the room the pill's padding sits in. Qt's rich
     * text has no padding, border or radius to give a span.
     *
     * The import goes on parsing markdown *inside* the tags, so the text has its
     * punctuation backslash-escaped, then `& < >` as entities (in that order, or the
     * entities' own `;` is escaped): unescaped, `a_b_c` came out as "abc". The
     * character before is only spaced when it is plain text, since a `*` or `)`
     * there is closing emphasis or a link. Fences are left alone. With the brackets
     * removed the plain text is the same as the unstyled markdown's, so copying,
     * selection, search marks and read-aloud all still line up.
     * tools/check-hermes-thread.py runs this under node.
     */
    function styleCodeSpans(md: string, foreground: string, family: string, gap: real): string {
        const mark = "\u2063";
        const escape = text => text.replace(/([!"#$%'()*+,\-./:;=?@\[\\\]^_`{|}~])/g, "\\$1")
            .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const spaced = text => `<span style="letter-spacing:${gap}px;">${escape(text)}</span>`;
        return (md ?? "").split(/(```[\s\S]*?(?:```|$))/).map((part, i) => {
            if (i % 2 === 1)
                return part;
            const span = /(`+)(?!`)([\s\S]*?[^`])\1(?!`)/g;
            let out = "";
            let last = 0;
            let match;
            while ((match = span.exec(part)) !== null) {
                if (match.index > 0 && "\\`".includes(part[match.index - 1])) {
                    span.lastIndex = match.index + 1;
                    continue;
                }
                let text = match[2].replace(/\n/g, " ");
                if (/^ [\s\S]* $/.test(text) && text.trim().length > 0)
                    text = text.slice(1, -1);
                let lead = part.slice(last, match.index);
                const tail = /([A-Za-z0-9\u00C0-\uFFFF.,;:!?'"])(\s*)$/.exec(lead);
                if (tail)
                    lead = lead.slice(0, tail.index) + spaced(tail[1]) + tail[2];
                out += `${lead}<span style="color:${foreground}; font-family:'${family}';">${mark}${escape(text.slice(0, -1))}${spaced(text.slice(-1))}${mark}</span>`;
                last = span.lastIndex;
            }
            return out + part.slice(last);
        }).join("");
    }

    /**
     * Prepares markdown text with proper paragraph spacing and line breaks for Qt's
     * Markdown importer.
     *
     * Qt's CommonMark parser collapses single newlines into spaces (soft breaks) and
     * imports paragraphs with zero top/bottom margins, rendering markdown without
     * line breaks or paragraph gaps. This:
     * 1. Preserves fenced code blocks untouched.
     * 2. Promotes single newlines around headings to paragraph breaks.
     * 3. Preserves single line breaks within paragraphs as hard breaks by adding two
     *    trailing spaces (GFM style).
     * 4. Inserts a non-breaking space paragraph (&nbsp;) between paragraphs to create
     *    a natural vertical paragraph gap.
     */
    function formatMarkdown(md: string): string {
        if (!md)
            return "";
        const text = md.replace(/\r\n/g, "\n");
        // Qt reads a leading `---` as YAML front matter and drops everything up to
        // the next one: a block opening on a rule lost its first section, formulas
        // and all, and LatexFormulas then put every later formula in the wrong place.
        if (text.startsWith("---"))
            return root.formatMarkdown(`\n${text}`);
        return text.split(/(```[\s\S]*?(?:```|$))/).map((part, idx) => {
            if (idx % 2 === 1)
                return part;

            let p = part.replace(/([^\n])\n(#{1,6}\s+)/g, "$1\n\n$2");
            p = p.replace(/(^#{1,6}\s+[^\n]+)\n([^\n#])/gm, "$1\n\n$2");

            const paragraphs = p.split(/\n{2,}/);
            const formatted = [];
            for (let i = 0; i < paragraphs.length; i++) {
                const para = paragraphs[i];
                if (para.trim().length === 0)
                    continue;

                const lines = para.split("\n");
                for (let j = 0; j < lines.length - 1; j++) {
                    const line = lines[j];
                    if (line.endsWith("  ") || line.endsWith("\\") || (/^\s*\|/.test(line) && /\|\s*$/.test(line)))
                        continue;
                    lines[j] = line + "  ";
                }
                formatted.push(lines.join("\n"));
            }
            return formatted.join("\n\n&nbsp;\n\n");
        }).join("");
    }

    // $...$, $$...$$, \[...\] and \(...\); the whole match, delimiters and all, is
    // what gets rendered and what its image replaces
    function latexPattern(): var {
        return /(\$\$([\s\S]+?)\$\$)|(\$([^\$]+?)\$)|(\\\[((?:.|\n)+?)\\\])|(\\\(([\s\S]+?)\\\))/g;
    }

    /**
     * The text each view of this block is given, formatted.
     *
     * While the reply is still arriving: settled runs of it, and the run coming in.
     * Qt re-parses a view's markdown whole on every change, so one view re-read the
     * entire reply on every tick of the reveal -- ~8ms at 16k characters, before
     * laying it out -- and a long answer streamed at a crawl, dropping frames. Cut,
     * a tick re-reads only the last run.
     *
     * One cut per 2000 characters, at the last paragraph break in them, so a run
     * once settled never changes and is never parsed again. Only before a block that
     * means the same wherever it starts, never a list item, which continues the
     * list above, or an indented line. Each run but the last keeps the blank
     * paragraph formatMarkdown() puts between paragraphs and the views meet with no
     * padding, so they lay out exactly as the one view they become once the reveal
     * settles, which is when a selection can run across the whole reply again.
     * tools/check-hermes-stream.py runs this.
     */
    function viewTexts(): var {
        const text = root.shownText;
        if (!root.renderMarkdown || root.editing)
            return [text];
        // Split by either double newlines or single newlines in a list
        if (root.fadeChunkSplitting)
            return text.split(/\n\n(?= {0,2})|\n(?= {0,2}(?:[-\*]|\d+\.))/g).filter(line => line.trim() !== "").map(line => root.formatMarkdown(line));
        if (root.done && !streamTimer.running)
            return [root.formatMarkdown(text)];
        // A step back from the end: a cut reads the line after it, and the word fade
        // restyles the last few words, so only a run with all of that behind it is
        // settled.
        const arrived = text.length - text.length % 2000 - 2000;
        const boundary = /\n\n+(?![ \t\n<`]|[*+-](?:\s|[*+-]{2})|\d+[.)](?:\s|$)|\[[^\]\n]*\]:)/g;
        const cuts = [];
        for (let match; (match = boundary.exec(text)) !== null && match.index < arrived;) {
            const last = cuts[cuts.length - 1];
            if (last && Math.floor(last.index / 2000) === Math.floor(match.index / 2000))
                cuts[cuts.length - 1] = match;
            else
                cuts.push(match);
        }
        const runs = [];
        let from = 0;
        for (const cut of cuts) {
            const run = text.slice(from, cut.index);
            if (run.trim().length === 0)
                continue;
            runs.push(root.formatMarkdown(run) + "\n\n&nbsp;");
            from = cut.index + cut[0].length;
        }
        return runs.concat([root.formatMarkdown(text.slice(from))]);
    }

    function renderLatex() {
        const regex = root.latexPattern();
        let match;
        while ((match = regex.exec(segmentContent)) !== null) {
            const [renderHash] = LatexRenderer.requestRender(match[0].trim());
            root.latexHashes[renderHash] = true;
        }
    }

    /**
     * The text with every formula rendered so far swapped for its image, in one
     * pass from the source. Patched in one formula per render, a reply of 234 was
     * re-laid 234 times, and again on every streamed chunk.
     */
    function applyLatex(): void {
        root.renderedSegmentContent = (segmentContent || "").toString().replace(root.latexPattern(), whole => {
            const hash = LatexRenderer.hashOf(whole.trim());
            const [width, height] = LatexRenderer.renderedSizes[hash] ?? [];
            // Not rendered yet, or failed: the source stays, not a broken image
            if (!width)
                return whole;
            // A blank of the formula's size, centred on the text, not sat on its
            // baseline; LatexFormulas draws the formula (the alt) over it, scrolling
            // on its own when wider than its line, which Qt's rich text cannot do to
            // an image. The hair space is for Qt: an image that opens a list item is
            // drawn above its own line, over the heading before it; any visible
            // character first stops that, a zero-width one does not. Self-closed, or
            // the importer swallows the rest of the text waiting for </img>.
            const imagePath = LatexRenderer.renderedImagePaths[hash];
            const markdownImage = `\u200A<img src="${LatexRenderer.placeholder}" alt="${imagePath}" width="${width}" height="${height}" align="middle" />`;
            return markdownImage;
        });
    }

    // Formulas finish one process at a time and every pass re-lays the whole text,
    // so they go in together once the last of this block's is back: one reflow,
    // not one per formula. Later in the loop, so renders landing together are
    // one pass.
    function handleRenderedLatex(hash) {
        if (!root.editing && root.latexHashes[hash]
                && Object.keys(root.latexHashes).every(h => LatexRenderer.renderedImagePaths[h] !== undefined))
            Qt.callLater(root.applyLatex);
    }

    /**
     * Applies an intense, creative trailing word-by-word fade-in to newly revealed words.
     * The newest words enter with a luminous primary accent glow and low opacity (5%),
     * smoothly transitioning into standard reading color and full opacity across a 10-step
     * gradient wave. Tags and inline code spans are preserved untouched.
     */
    function applyWordFade(text: string, fadeCount: int, textColor: color, primaryColor: color): string {
        if (!text || fadeCount <= 0)
            return text;

        const cText = Qt.color(textColor);
        const tr = Math.round(cText.r * 255);
        const tg = Math.round(cText.g * 255);
        const tb = Math.round(cText.b * 255);

        const cPrim = Qt.color(primaryColor);
        const pr = Math.round(cPrim.r * 255);
        const pg = Math.round(cPrim.g * 255);
        const pb = Math.round(cPrim.b * 255);

        // 10-step ladder: oldest word (0.98, neutral) to newest word (0.05, primary tint)
        const FADE_LADDER = [
            { alpha: 0.98, tint: 0.00 },
            { alpha: 0.94, tint: 0.06 },
            { alpha: 0.88, tint: 0.14 },
            { alpha: 0.80, tint: 0.24 },
            { alpha: 0.70, tint: 0.36 },
            { alpha: 0.58, tint: 0.50 },
            { alpha: 0.44, tint: 0.65 },
            { alpha: 0.30, tint: 0.80 },
            { alpha: 0.16, tint: 0.92 },
            { alpha: 0.05, tint: 1.00 }
        ];

        const activeLadder = FADE_LADDER.slice(0, Math.min(fadeCount, FADE_LADDER.length));
        if (activeLadder.length === 0)
            return text;

        const parts = text.split(/(<[^>]+>|`[^`]+`)/);
        const wordsToFade = [];
        for (let pIdx = parts.length - 1; pIdx >= 0; pIdx--) {
            const p = parts[pIdx];
            if (p.startsWith("<") || p.startsWith("`"))
                continue;

            const regex = /\b[\w'-]+(?:\.[\w'-]+)*\b/gu;
            let match;
            const matches = [];
            while ((match = regex.exec(p)) !== null) {
                matches.push({ start: match.index, end: regex.lastIndex });
            }
            for (let i = matches.length - 1; i >= 0; i--) {
                wordsToFade.push({ pIdx: pIdx, start: matches[i].start, end: matches[i].end });
                if (wordsToFade.length >= activeLadder.length)
                    break;
            }
            if (wordsToFade.length >= activeLadder.length)
                break;
        }

        if (wordsToFade.length === 0)
            return text;

        wordsToFade.reverse();
        const num = wordsToFade.length;
        const ladderSlice = activeLadder.slice(activeLadder.length - num);

        const partMods = {};
        for (let i = 0; i < wordsToFade.length; i++) {
            const item = wordsToFade[i];
            if (!partMods[item.pIdx])
                partMods[item.pIdx] = [];
            const step = ladderSlice[i];
            partMods[item.pIdx].push({ start: item.start, end: item.end, alpha: step.alpha, tint: step.tint });
        }

        const newParts = [...parts];
        for (const pIdxStr in partMods) {
            const pIdx = parseInt(pIdxStr);
            let p = parts[pIdx];
            const mods = partMods[pIdx];
            mods.sort((x, y) => y.start - x.start);
            for (let m = 0; m < mods.length; m++) {
                const mod = mods[m];
                const word = p.slice(mod.start, mod.end);
                const r = Math.round(tr + (pr - tr) * mod.tint);
                const g = Math.round(tg + (pg - tg) * mod.tint);
                const b = Math.round(tb + (pb - tb) * mod.tint);
                const span = `<span style="color:rgba(${r},${g},${b},${mod.alpha.toFixed(2)});">` + word + `</span>`;
                p = p.slice(0, mod.start) + span + p.slice(mod.end);
            }
            newParts[pIdx] = p;
        }

        return newParts.join("");
    }

    function updateStreamedText(): void {
        if (!root.targetText) {
            root.shownText = "";
            return;
        }

        if (root.revealedWordCount >= root.totalWordCount && root.settleCounter <= 0) {
            root.shownText = root.targetText;
            return;
        }

        // Never between a tag's attributes: a LaTeX <img> cut there shows as raw text.
        // A tag is a token of its own rather than a lookahead from every space for a
        // `>` ahead, which read to the end of a reply with none: 26ms a split at 16k
        // characters, run on every tick of the reveal.
        const tokens = root.targetText.split(/(<[^<>]*>|\s+)/);
        const wordIndices = [];
        for (let i = 0; i < tokens.length; i++) {
            if (!/^\s*$/.test(tokens[i]))
                wordIndices.push(i);
        }

        let slice = "";
        if (root.revealedWordCount >= wordIndices.length) {
            slice = root.targetText;
        } else if (root.revealedWordCount > 0) {
            const lastTokenIdx = wordIndices[root.revealedWordCount - 1];
            slice = tokens.slice(0, lastTokenIdx + 1).join("");
        } else {
            slice = "";
        }

        const textColor = root.messageData?.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer2;
        const primaryColor = Appearance.m3colors.m3primary;
        root.shownText = root.applyWordFade(slice, root.settleCounter, textColor, primaryColor);
    }

    function advanceStream(): void {
        const remaining = root.totalWordCount - root.revealedWordCount;
        if (remaining > 0) {
            let step = 1;
            if (remaining > 80) {
                step = 3;
            } else if (remaining > 40) {
                step = 2;
            }
            root.revealedWordCount = Math.min(root.totalWordCount, root.revealedWordCount + step);
            root.settleCounter = 10;
            root.updateStreamedText();
        } else {
            if (root.settleCounter > 0) {
                root.settleCounter--;
                root.updateStreamedText();
            } else {
                streamTimer.stop();
                root.shownText = root.targetText;
            }
        }
    }

    function syncContent(): void {
        const text = renderedSegmentContent ? renderedSegmentContent : (segmentContent ? segmentContent : "");
        if (!text) {
            root.targetText = "";
            root.shownText = "";
            if (streamTimer.running)
                streamTimer.stop();
            return;
        }

        root.targetText = text;

        const fadeEnabled = Config.options.sidebar?.ai?.textFadeIn ?? true;
        if (root.isHistorical || root.editing || !fadeEnabled) {
            if (streamTimer.running)
                streamTimer.stop();
            root.revealedWordCount = 0;
            root.settleCounter = 0;
            root.shownText = text;
            return;
        }

        const tokens = text.split(/(<[^<>]*>|\s+)/);
        let count = 0;
        for (let i = 0; i < tokens.length; i++) {
            if (!/^\s*$/.test(tokens[i]))
                count++;
        }
        root.totalWordCount = count;

        if (root.revealedWordCount >= root.totalWordCount && root.settleCounter <= 0) {
            root.shownText = text;
            if (streamTimer.running)
                streamTimer.stop();
            return;
        }

        if (!streamTimer.running) {
            streamTimer.start();
            root.advanceStream();
        }
    }

    onDoneChanged: {
        if (root.done) {
            if (root.revealedWordCount >= root.totalWordCount && root.settleCounter <= 0) {
                if (streamTimer.running)
                    streamTimer.stop();
                root.shownText = root.targetText ? root.targetText : (root.renderedSegmentContent ? root.renderedSegmentContent : "");
            } else if (!streamTimer.running && !root.isHistorical) {
                streamTimer.start();
            }
        }
    }
    onEditingChanged: {
        if (!editing) {
            root.renderLatex();
            root.applyLatex();
            root.syncContent();
        } else {
            if (streamTimer.running)
                streamTimer.stop();
            root.shownText = segmentContent;
        }
    }

    // Through renderedSegmentContent's own handler: syncing here as well laid the
    // text out twice per streamed chunk.
    onSegmentContentChanged: {
        if (root.editing) {
            renderedSegmentContent = segmentContent;
            return;
        }
        root.renderLatex();
        root.applyLatex();
    }

    onRenderedSegmentContentChanged: {
        root.syncContent();
    }

    Component.onCompleted: {
        // A turn rebuilt on scroll, or reopened from history, finds its formulas
        // already rendered and shows them from its first layout.
        if (!root.editing) {
            root.renderLatex();
            root.applyLatex();
        }
        const text = renderedSegmentContent ? renderedSegmentContent : (segmentContent ? segmentContent : "");
        if (root.done || (root.messageData && root.messageData.done)) {
            root.isHistorical = true;
            root.targetText = text;
            root.shownText = text;
            root.revealedWordCount = 999999;
            root.settleCounter = 0;
        } else {
            root.syncContent();
        }
    }

    Connections {
        target: LatexRenderer
        function onRenderFinished(hash) {
            handleRenderedLatex(hash);
        }
    }

    spacing: root.fadeChunkSplitting ? Appearance.font.pixelSize.small : 0
    Repeater {
        id: textLinesRepeater
        property list<real> textLineOpacities: []
        model: ScriptModel {
            // Keyed by position: the last line grows with every streamed token, and
            // a bare string model rebuilds its whole delegate each time -- retyping
            // the text, and destroying the MouseArea under the pointer, which is
            // what made the cursor flicker while a reply came in.
            objectProp: "key"
            values: root.viewTexts().map((line, i) => ({ key: i, text: line }))
            onValuesChanged: {
                while (textLinesRepeater.textLineOpacities.length < values.length) {
                    textLinesRepeater.textLineOpacities.push(root.messageData?.done ? 1 : 0);
                }
            }
        }
        delegate: TextArea {
            id: textArea
            required property int index
            required property var modelData

            // Fade in animation
            visible: opacity > 0
            opacity: fadeChunkSplitting ? (textLinesRepeater.textLineOpacities[index] ?? (root.messageData?.done ? 1 : 0)) : 1
            Connections {
                target: root.messageData ?? null
                function onDoneChanged() {
                    if (root.messageData?.done) {
                        textLinesRepeater.textLineOpacities[textArea.index] = 1
                    }
                }
            }
            Connections {
                target: textLinesRepeater.model
                function onValuesChanged() {
                    if (textLinesRepeater.model.values.length > textArea.index + 1) {
                        textLinesRepeater.textLineOpacities[textArea.index] = 1
                    }
                }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Layout.fillWidth: true
            // Where a streaming reply's two views meet, as one view's lines would
            topPadding: textArea.index > 0 ? 0 : textArea.padding
            bottomPadding: textArea.index < textLinesRepeater.count - 1 ? 0 : textArea.padding
            readOnly: !editing
            selectByMouse: enableMouseSelection || editing
            renderType: Text.NativeRendering
            font.family: Appearance.font.family.reading
            font.hintingPreference: Font.PreferNoHinting // Prevent weird bold text
            font.pixelSize: Appearance.font.pixelSize.small
            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
            selectionColor: Appearance.colors.colSecondaryContainer
            wrapMode: TextEdit.Wrap
            color: root.messageData?.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer2
            textFormat: renderMarkdown ? TextEdit.MarkdownText : TextEdit.PlainText
            text: root.renderMarkdown && !root.editing
                ? root.styleCodeSpans(modelData.text, Appearance.m3colors.m3primary, Appearance.font.family.monospace, codePills.gap)
                : modelData.text

            onTextChanged: {
                if (!root.editing) return
                segmentContent = text
            }

            // Reported upward so the transcript can offer actions on a selection:
            // the highlight itself is confined to this one delegate, and a reply is
            // split across many of them.
            onSelectedTextChanged: TextSelectionService.report(textArea)
            Component.onDestruction: TextSelectionService.release(textArea)

            InlineCode {
                id: codePills
                target: textArea
                fill: root.codeSpanColor
            }

            LatexFormulas {
                target: textArea
                markup: textArea.modelData.text
            }

            SpeechHighlight {
                target: textArea
                phrase: root.speakingPhrase
                progress: root.speakingProgress
                wordOffset: root.speakingOffset
            }

            SpeechHighlight { // Search hits, marked alongside a read-aloud rather than instead of it
                target: textArea
                query: root.searchQuery
                // The turn the search has stepped to is the one being looked at;
                // the rest are marked only enough to say "also here".
                // Both translucent: the stepped-to hit is stronger, not solid.
                markColor: ColorUtils.applyAlpha(Appearance.colors.colPrimaryContainer, root.searchCurrent ? 0.4 : 0.18)
            }

            onLinkActivated: (link) => {
                Qt.openUrlExternally(link)
                GlobalStates.sidebarLeftOpen = false
            }

            MouseArea { // Pointing hand for links; also eats the stock context menu
                anchors.fill: parent
                // Qt 6.9+ gives every TextArea a built-in editing menu. Over a
                // read-only transcript it opens with Cut/Paste/Delete greyed out
                // and in a style that is not this shell's, so the right button is
                // taken here. While editing that menu is useful, so it is left.
                acceptedButtons: root.editing ? Qt.NoButton : Qt.RightButton
                hoverEnabled: true
                cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor :
                    (enableMouseSelection || editing) ? Qt.IBeamCursor : Qt.ArrowCursor
            }
        }
    }
}
