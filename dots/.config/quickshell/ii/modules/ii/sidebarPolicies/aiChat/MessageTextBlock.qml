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
    property bool done: true
    property bool forceDisableChunkSplitting: false
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

    property list<string> renderedLatexHashes: []
    property string renderedSegmentContent: ""
    property string shownText: ""
    property bool fadeChunkSplitting: !forceDisableChunkSplitting && !editing && !/\n\|/.test(shownText) && Config.options.sidebar.ai.textFadeIn

    Layout.fillWidth: true

    Timer {
        id: renderTimer
        interval: 1000
        repeat: false
        onTriggered: {
            renderLatex()
            for (const hash of renderedLatexHashes) {
                handleRenderedLatex(hash, true);
            }
        }
    }

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

    function renderLatex() {
        // $...$, $$...$$, \[...\] and \(...\)
        let regex = /(\$\$([\s\S]+?)\$\$)|(\$([^\$]+?)\$)|(\\\[((?:.|\n)+?)\\\])|(\\\(([\s\S]+?)\\\))/g;
        let match;
        while ((match = regex.exec(segmentContent)) !== null) {
            let expression = match[1] || match[2] || match[3] || match[4] || match[5] || match[6] || match[7] || match[8];
            if (expression) {
                Qt.callLater(() => {
                    const [renderHash, isNew] = LatexRenderer.requestRender(expression.trim());
                    if (!renderedLatexHashes.includes(renderHash)) {
                        renderedLatexHashes.push(renderHash);
                    }
                });
            }
        }
    }

    function handleRenderedLatex(hash, force = false) {
        if (renderedLatexHashes.includes(hash) || force) {
            const imagePath = LatexRenderer.renderedImagePaths[hash];
            const markdownImage = `![latex](${imagePath})`;

            const expression = LatexRenderer.processedExpressions[hash];
            renderedSegmentContent = renderedSegmentContent.replace(expression, markdownImage);
        }
    }

    onDoneChanged: {
        renderTimer.restart();
    }
    onEditingChanged: {
        if (!editing) {
            renderLatex()
        } else {
            root.shownText = segmentContent
        }
    }

    onSegmentContentChanged: {
        renderedSegmentContent = segmentContent;
        if (!root.editing && segmentContent) {
            root.renderLatex();
        }
    }

    onRenderedSegmentContentChanged: {
        if (renderedSegmentContent) {
            root.shownText = renderedSegmentContent;
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
            // Split by either double newlines or single newlines in a list
            values: (root.fadeChunkSplitting ? root.shownText.split(/\n\n(?= {0,2})|\n(?= {0,2}(?:[-\*]|\d+\.))/g).filter(line => line.trim() !== "") : [root.shownText])
                .map((line, i) => ({ key: i, text: root.renderMarkdown && !root.editing ? root.formatMarkdown(line) : line }))
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
