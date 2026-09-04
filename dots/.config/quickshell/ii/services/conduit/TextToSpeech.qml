import qs.modules.common.functions as CF
import Quickshell.Io
import QtQuick

/**
 * Local text-to-speech, so a reply can be listened to instead of read.
 *
 * Nothing is uploaded — same as the dictation side. Engines are tried in quality
 * order: piper is a neural voice that sounds like a person but wants a model
 * file, espeak-ng is a 2MB formant synth that needs no model and sounds like
 * 1995. Whichever is installed is used.
 *
 * Synthesis and waveform extraction share one process launch: the player needs a
 * peak envelope to draw, the WAV is already on disk by then, and a second launch
 * just to read it back would add latency for nothing.
 */
QtObject {
    id: root

    // piper: path to a .onnx voice model. espeak-ng: a voice name such as "en-gb".
    // Left empty, piper picks up whatever voice is sitting in voiceDir.
    property string voice: ""
    property string voiceDir: ""

    readonly property string workDir: "/tmp/quickshell/vynx-conduit/tts"
    readonly property string helper: {
        // A reloaded extension carries a ?_t= cache-buster that must not reach the path.
        const resolved = Qt.resolvedUrl("waveform.py").toString().split("?")[0];
        return CF.FileUtils.trimFileProtocol(resolved);
    }

    property string binary: ""
    property string engine: "" // "piper" | "espeak-ng"
    readonly property bool available: root.binary.length > 0

    property int speakingFor: -1 // Message id being synthesised, -1 when idle
    readonly property bool busy: root.speakingFor >= 0
    property int sequence: 0

    signal ready(int messageId, string path, int bytes, var bars)
    signal failed(string reason)

    /**
     * Markdown read aloud is unlistenable: fences become punctuation soup and a
     * table becomes a minute of pipes. Only the prose survives.
     *
     * Maths is worse than unlistenable. The system prompts ask for LaTeX in `$$`,
     * so a chemistry answer arrives full of `$[Cu(NH_3)_4]^{2+}$`, and an engine
     * handed that says "dollar bracket Cu open brace" — the delimiters get spoken
     * and the content does not. So maths is translated into the words a person
     * reading the page aloud would use, before the markdown pass runs.
     */
    function speakable(markdown) {
        let text = (markdown ?? "")
            .replace(/<think>[\s\S]*?<\/think>/g, " ")
            .replace(/_\[[^\]]*\]_/g, " ")               // Tool-call notes from flattenParts
            .replace(/```[\s\S]*?```/g, " code block. ") // Named, not spelled out
            .replace(/`([^`]*)`/g, "$1");

        text = root.spokenMath(text);

        text = root.spokenAbbreviations(text)
            .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")   // Link text, never the URL
            .replace(/\bhttps?:\/\/\S+/g, " a link ");   // A spelled-out URL is 20 seconds of noise

        return root.spokenBlocks(text)
            .replace(/[*_~>#]/g, "")
            // The prompts ask headings to open with an emoji, which an engine
            // either skips or reads out as its CLDR name.
            .replace(/[\uD83C-\uDBFF][\uDC00-\uDFFF]/g, " ")
            .replace(/[\u2600-\u27BF\u2B00-\u2BFF\uFE0F\u20E3]/g, " ")
            .replace(/\s+/g, " ")
            // Substitution leaves gaps in front of punctuation, and a gap there is
            // a pause the engine takes literally.
            .replace(/\s+([,.;:!?])/g, "$1")
            .trim();
    }

    /**
     * Markdown carries its phrasing in the layout, and stripping the markers
     * throws that away: a heading runs straight into the paragraph beneath it and
     * every bullet joins the last, so the engine is handed one enormous sentence
     * and reads the whole reply in one breathless monotone. Intonation resets on a
     * terminator, so each block ends with one.
     *
     * Per block and not per line, which is why the markers have to still be here:
     * a wrapped paragraph is one sentence continued, and a full stop at the wrap
     * would chop it in half.
     */
    function spokenBlocks(text) {
        const opensBlock = line => /^(?:#{1,6}\s|[-*+]\s|\d+[.)]\s|\|)/.test(line);
        const lines = text.split("\n").map(line => line.trim());
        const spoken = [];

        for (let i = 0; i < lines.length; ++i) {
            let line = lines[i];
            if (line.length === 0) continue;
            if (/^\|.*\|$/.test(line)) continue;      // Tables read as noise
            if (/^[-=|:\s]{3,}$/.test(line)) continue; // Rules and table separators

            // A heading or a list item is a thought of its own, so it always closes.
            // A plain line only closes if nothing follows it that would continue it.
            const heading = /^#{1,6}\s/.test(line);
            const item = /^(?:[-*+]|\d+[.)])\s/.test(line);
            // One marker per line, never both: the "1." in "## 1. What are Ligands?"
            // is the section number, not a list bullet, and reads as part of it.
            line = heading ? line.replace(/^#{1,6}\s*/, "") : line.replace(/^(?:[-*+]|\d+[.)])\s+/, "");
            line = line.trim();
            if (line.length === 0) continue;

            const next = lines[i + 1] ?? "";
            if ((heading || item || next.length === 0 || opensBlock(next)) && !/[.!?:;,\u2026]$/.test(line))
                line += ".";
            spoken.push(line);
        }
        return spoken.join(" ");
    }

    /**
     * Written shorthand that is read out as letters. "e.g." becomes "ee gee", and
     * a unit symbol fares no better, so both are spelled into words.
     */
    function spokenAbbreviations(text) {
        return text
            .replace(/\be\.\s*g\.(?=\s|$)/gi, "for example")
            .replace(/\bi\.\s*e\.(?=\s|$)/gi, "that is")
            .replace(/\betc\.(?=\s+[A-Z])/g, "and so on.")
            .replace(/\betc\.(?=\s|$)/gi, "and so on")
            .replace(/\bvs\.?(?=\s|$)/gi, "versus")
            .replace(/\bet\s+al\.(?=\s|$)/gi, "and others")
            .replace(/\bcf\.(?=\s|$)/gi, "compare")
            .replace(/\bapprox\.(?=\s|$)/gi, "approximately")
            .replace(/\bFig\.\s*(\d)/gi, "figure $1")
            .replace(/\bdegrees C\b/g, "degrees Celsius")
            .replace(/\bdegrees F\b/g, "degrees Fahrenheit");
    }

    /**
     * Finds the maths and translates it. Spans are resolved first because the same
     * character means different things on either side of a delimiter: outside one,
     * a lone `$` really is a dollar sign.
     */
    function spokenMath(text) {
        const span = (match, body) => ` ${root.spokenFormula(body)} `;
        let out = text
            .replace(/\$\$([\s\S]+?)\$\$/g, span)
            .replace(/\\\[([\s\S]+?)\\\]/g, span)
            .replace(/\\\(([\s\S]+?)\\\)/g, span)
            // KaTeX's inline rule — a non-space just after the opening `$` and just
            // before the closing one. That is what keeps "it costs $5 and $10" from
            // being read as an equation.
            .replace(/\$(?!\s)([^$\n]*[^\s$]|[^\s$])\$/g, span);

        // A reply that mixes prose with half-hearted markup leaves commands and
        // glyphs loose in the text, where they read no better than inside a span.
        out = root.spokenOperators(out);

        return out
            // A price that survived the span rules is a real dollar sign.
            .replace(/\$(\d+(?:,\d{3})*(?:\.\d+)?)/g, " $1 dollars ")
            .replace(/\$/g, " ");
    }

    /**
     * One formula's worth of LaTeX, in spoken English.
     */
    function spokenFormula(latex) {
        let s = ` ${latex} `;

        // Cosmetic markup: it changes how the maths looks and nothing about how it
        // reads.
        s = s.replace(/\\(?:left|right|bigg?|Bigg?|displaystyle|textstyle|limits|nonumber|quad|qquad)(?![A-Za-z])/g, " ")
            .replace(/\\[!,;:\s]/g, " ")
            .replace(/\\\\/g, ". ") // Row break in an aligned block
            .replace(/&/g, " ");

        // A degree sign is written as a superscript, so it has to be read before
        // `^` is, or it comes out as "to the power degrees".
        s = s.replace(/\^\s*\{?\s*\\(?:circ|degree)\s*\}?/g, " degrees ");

        // Four passes is deeper than a chat reply nests: the innermost brace pair
        // resolves first, and the next pass sees its parent as flat.
        for (let i = 0; i < 4; ++i) {
            s = s.replace(/\\(?:text|textrm|textbf|textit|mathrm|mathbf|mathit|mathsf|mathbb|mathcal|operatorname|ce|si)\s*\{([^{}]*)\}/g, " $1 ")
                .replace(/\\[dt]?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}/g, " $1 over $2 ")
                .replace(/\\sqrt\s*\[([^\]]*)\]\s*\{([^{}]*)\}/g, " root $1 of $2 ")
                .replace(/\\sqrt\s*\{([^{}]*)\}/g, " square root of $1 ")
                .replace(/\\(?:overline|underline|overrightarrow|vec|hat|bar|tilde|boxed)\s*\{([^{}]*)\}/g, " $1 ");
        }

        s = root.spokenOperators(s);
        s = root.spokenScripts(s); // After the operators, so it still sees raw signs

        return s
            .replace(/\+/g, " plus ")
            .replace(/=/g, " equals ")
            // Only a `-` standing between values is a minus. The ones inside a word
            // — "counter-ions", pulled in from a \text escape — stay hyphens.
            .replace(/([\d)\]}])\s*-\s*([\d(\[{])|(\s)-(\s)/g, (match, left, right) => left ? `${left} minus ${right}` : " minus ")
            .replace(/(^|\s)-(\d)/g, "$1minus $2")
            .replace(/[{}]/g, " ")
            .replace(/\\([A-Za-z]+)/g, " $1 ") // Unmapped command: its name beats "backslash"
            .replace(/\\/g, " ")
            .replace(/\s+/g, " ")
            .trim();
    }

    /**
     * `^` and `_` mean two different things in the same sentence about chemistry.
     * `Cu^{2+}` is an ion and reads "Cu 2 plus"; `x^{2}` is a power and reads "x
     * squared". A sign inside the braces is what separates them — the same cue a
     * person reading the page out loud goes by.
     */
    function spokenScripts(s) {
        const power = exponent => {
            const e = exponent.trim();
            if (/^[+-]$/.test(e)) return e === "+" ? " plus " : " minus ";
            if (/^\d*\s*[+-]$/.test(e)) return ` ${e.replace(/\+/, " plus").replace(/-/, " minus")} `;
            if (/^[+-]\s*\d+$/.test(e)) return ` to the power ${e.replace(/\+/, "plus ").replace(/-/, "minus ")} `;
            if (e === "2") return " squared ";
            if (e === "3") return " cubed ";
            return ` to the power ${e} `;
        };
        return s
            .replace(/\^\s*\{([^{}]*)\}/g, (match, e) => power(e))
            .replace(/\^\s*([A-Za-z0-9]|[+-])/g, (match, e) => power(e))
            // A subscript is spoken as its bare value: "N H 3", not "N H sub 3".
            .replace(/_\s*\{([^{}]*)\}/g, " $1 ")
            .replace(/_\s*([A-Za-z0-9])/g, " $1 ");
    }

    /**
     * The named operators, and the same things again for a reply that writes the
     * glyph directly. Both tables are needed: a model asked for LaTeX still drops
     * a bare → into prose, and an engine reads that as silence.
     */
    function spokenOperators(s) {
        // A superscript digit next to a sign is a charge, not a power: Cu²⁺ reads
        // "Cu 2 plus", where a lone ² reads "squared". Resolved before the glyph
        // table, which therefore only ever sees the lone case.
        const superDigits = "⁰¹²³⁴⁵⁶⁷⁸⁹";
        let out = s.replace(/([⁰¹²³⁴⁵⁶⁷⁸⁹]+)([⁺⁻])/g, (match, digits, sign) =>
            " " + digits.replace(/./g, d => superDigits.indexOf(d)) + (sign === "⁺" ? " plus " : " minus "));

        const words = {
            times: "times", cdot: "dot", div: "divided by", pm: "plus or minus", mp: "minus or plus",
            approx: "approximately", sim: "about", simeq: "approximately", equiv: "identical to",
            neq: "not equal to", ne: "not equal to", leq: "less than or equal to", le: "less than or equal to",
            geq: "greater than or equal to", ge: "greater than or equal to", ll: "much less than",
            gg: "much greater than", propto: "proportional to", infty: "infinity", partial: "partial",
            rightarrow: "to", longrightarrow: "to", Rightarrow: "which gives", to: "to", mapsto: "maps to",
            leftarrow: "from", longleftarrow: "from", Leftarrow: "follows from",
            leftrightarrow: "in equilibrium with", rightleftharpoons: "in equilibrium with",
            implies: "which means", iff: "if and only if", therefore: "therefore", because: "because",
            sum: "sum of", prod: "product of", int: "integral of", forall: "for all", exists: "there exists",
            "in": "in", notin: "not in", subset: "inside", cup: "union", cap: "intersection",
            angle: "angle", perp: "perpendicular to", parallel: "parallel to", degree: "degrees",
            ldots: "and so on", dots: "and so on", cdots: "and so on", prime: "prime",
            alpha: "alpha", beta: "beta", gamma: "gamma", delta: "delta", Delta: "delta",
            epsilon: "epsilon", varepsilon: "epsilon", zeta: "zeta", eta: "eta", theta: "theta",
            Theta: "theta", iota: "iota", kappa: "kappa", lambda: "lambda", Lambda: "lambda", mu: "mu",
            nu: "nu", xi: "xi", pi: "pi", Pi: "pi", rho: "rho", sigma: "sigma", Sigma: "sigma",
            tau: "tau", upsilon: "upsilon", phi: "phi", Phi: "phi", varphi: "phi", chi: "chi",
            psi: "psi", Psi: "psi", omega: "omega", Omega: "omega"
        };
        // Longest name first, so \infty is never eaten as \in, and \in is never
        // eaten as \int.
        const names = Object.keys(words).sort((a, b) => b.length - a.length).join("|");
        out = out.replace(new RegExp(`\\\\(${names})(?![A-Za-z])`, "g"), (match, name) => ` ${words[name]} `);

        const glyphs = [
            ["→", " to "], ["⟶", " to "], ["⇒", " which gives "], ["⟹", " which gives "],
            ["←", " from "], ["⟵", " from "], ["⇐", " follows from "],
            ["↔", " in equilibrium with "], ["⇌", " in equilibrium with "],
            ["⇄", " in equilibrium with "], ["⇋", " in equilibrium with "],
            ["×", " times "], ["÷", " divided by "], ["±", " plus or minus "], ["·", " dot "],
            ["≈", " approximately "], ["≠", " not equal to "], ["≡", " identical to "],
            ["≤", " less than or equal to "], ["≥", " greater than or equal to "],
            ["∝", " proportional to "], ["∞", " infinity "], ["√", " square root of "],
            ["∑", " sum of "], ["∏", " product of "], ["∫", " integral of "], ["∂", " partial "],
            ["∈", " in "], ["∉", " not in "], ["∪", " union "], ["∩", " intersection "],
            ["°", " degrees "], ["∅", " empty set "], ["∴", " therefore "], ["∵", " because "],
            ["²", " squared "], ["³", " cubed "], ["–", " to "], ["—", ", "], ["…", " and so on "]
        ];
        for (let i = 0; i < glyphs.length; ++i)
            out = out.split(glyphs[i][0]).join(glyphs[i][1]);

        return out
            .replace(/[₀-₉]/g, m => ` ${m.charCodeAt(0) - 0x2080} `)
            .replace(/⁺/g, " plus ")
            .replace(/⁻/g, " minus ");
    }

    function speak(messageId, markdown) {
        if (!root.available) {
            root.failed(root.setupHint());
            return;
        }
        const text = root.speakable(markdown);
        if (text.length === 0) {
            root.failed("Nothing in that reply to read out loud.");
            return;
        }

        /*
         * A second press replaces the first: waiting for an unwanted memo to finish
         * synthesising is worse than losing it.
         *
         * The kill's exit arrives *after* this function returns — measured — and by
         * then messageId and audioPath below have been overwritten, while stdout
         * still holds whatever the old pipeline printed. Read as this request's
         * result, that points the player at a file that does not exist yet.
         */
        if (root.busy) {
            synth.discardNextExit = true;
            synth.running = false;
        }

        // Fresh filename every time — MediaPlayer keys off the URL, so an
        // overwritten path would replay the old audio.
        const out = `${root.workDir}/memo-${messageId}-${++root.sequence}.wav`;

        /*
         * piper's own failure for a missing voice is a Python traceback about a
         * config file, which explains nothing. So the voice is resolved and checked
         * here, in the same shell, and reported as an exit code.
         *
         * Resolved in bash rather than QML so a voice dropped into voiceDir is picked
         * up on the next press, with no reload.
         */
        let prelude = "";
        let engineCommand;
        if (root.engine === "piper") {
            prelude = `MODEL='${CF.StringUtils.shellSingleQuoteEscape(root.voice)}';`
                + ` [ -n "$MODEL" ] || MODEL="$(ls -1 '${root.voiceDir}'/*.onnx 2>/dev/null | head -1)";`
                + ` [ -s "$MODEL" ] || exit 4; [ -s "$MODEL.json" ] || exit 5;`;
            /*
             * This build's default pause between sentences is 0.00s — measured —
             * so the sentence boundaries speakable() recovers from the markdown
             * would land with no breathing room at all and the phrasing would be
             * wasted. 0.15s is what the pauses cost, at about 4% more audio.
             *
             * Underscore spelling: it is the one both the C++ piper and the newer
             * Python piper1-gpl accept, and either may be what is installed.
             */
            engineCommand = `'${root.binary}' --model "$MODEL" --output_file '${out}' --sentence_silence 0.15`;
        } else {
            engineCommand = `'${root.binary}' --stdin -w '${out}'`
                + (root.voice.length > 0 ? ` -v '${CF.StringUtils.shellSingleQuoteEscape(root.voice)}'` : "");
        }

        // The text goes through the environment, not argv: a reply can contain
        // anything, and this way no quoting rule has to hold for it.
        synth.messageId = messageId;
        synth.audioPath = out;
        synth.environment = ({ "CONDUIT_TTS_TEXT": text });
        synth.command = ["bash", "-c",
            `mkdir -p '${root.workDir}' && find '${root.workDir}' -name 'memo-*.wav' -mmin +120 -delete 2>/dev/null;`
            + ` ${prelude}`
            + ` printf '%s' "$CONDUIT_TTS_TEXT" | ${engineCommand} && exec python3 '${root.helper}' '${out}'`];
        root.speakingFor = messageId;
        synth.running = true;
    }

    function setupHint() {
        return "Voice replies need a speech engine, and this machine has none:\n\n"
            + "```\nsudo pacman -S espeak-ng\n```\n\n"
            + "That is the two-megabyte robotic one and it works with no further setup. "
            + "For a natural voice install `piper-tts`, download a `.onnx` voice, and point "
            + "the extension's `ttsVoice` setting at it.";
    }

    property Process synth: Process {
        id: synth
        property int messageId: -1
        property string audioPath: ""
        property bool discardNextExit: false

        stdout: StdioCollector { id: synthOut }
        stderr: StdioCollector { id: synthErrors }

        // Decided on exit, not on stream end: only here is the status known, and a
        // synth that dies half-way still leaves a stub WAV behind.
        onExited: exitCode => {
            if (synth.discardNextExit) { // Belongs to the run this one replaced
                synth.discardNextExit = false;
                return;
            }
            root.speakingFor = -1;
            if (exitCode === 4) {
                root.failed(`No piper voice found. Put a \`.onnx\` voice (with its \`.onnx.json\`) in \`${root.voiceDir}\`, or set **Reply voice** to the file's path.`);
                return;
            }
            if (exitCode === 5) {
                root.failed("That piper voice has no `.onnx.json` next to it. Both files come from the same download — piper reads the JSON before the model.");
                return;
            }
            if (exitCode !== 0) {
                const tail = (synthErrors.text ?? "").trim().split("\n").slice(-3).join("\n");
                root.failed(tail.length > 0
                    ? `Could not synthesise speech (exit ${exitCode}).\n\n\`\`\`\n${tail}\n\`\`\``
                    : `Could not synthesise speech (exit ${exitCode}).`);
                return;
            }
            try {
                const report = JSON.parse((synthOut.text ?? "").trim());
                root.ready(synth.messageId, synth.audioPath, report.bytes, report.bars);
            } catch (e) {
                root.failed(`The voice memo was produced but its waveform could not be read: ${e}`);
            }
        }
    }

    /* ---------- Capability detection --------------------------------------- */

    property Process binaryProbe: Process {
        command: ["bash", "-c", "command -v piper || command -v piper-tts || command -v espeak-ng || command -v espeak || true"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.binary = this.text.trim().split("\n")[0] ?? "";
                root.engine = root.binary.includes("piper") ? "piper" : "espeak-ng";
            }
        }
    }
}
