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
     */
    function speakable(markdown) {
        return (markdown ?? "")
            .replace(/<think>[\s\S]*?<\/think>/g, " ")
            .replace(/_\[[^\]]*\]_/g, " ")               // Tool-call notes from flattenParts
            .replace(/```[\s\S]*?```/g, " code block. ") // Named, not spelled out
            .replace(/`([^`]*)`/g, "$1")
            .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")   // Link text, never the URL
            .replace(/^\s{0,3}#{1,6}\s*/gm, "")
            .replace(/^\s*([-*+]|\d+\.)\s+/gm, "")
            .replace(/^\s*\|.*\|\s*$/gm, " ")            // Tables read as noise
            .replace(/^\s*[-=|:\s]{3,}$/gm, " ")         // Rules and table separators
            .replace(/[*_~>#]/g, "")
            .replace(/\s+/g, " ")
            .trim();
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
            engineCommand = `'${root.binary}' --model "$MODEL" --output_file '${out}'`;
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
