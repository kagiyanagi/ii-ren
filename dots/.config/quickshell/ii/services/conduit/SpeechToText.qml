import qs.modules.common
import qs.modules.common.functions as CF
import Quickshell.Io
import QtQuick

/**
 * Local speech-to-text via whisper.cpp. Nothing is uploaded: recording and
 * transcription both run on this machine.
 *
 * Pipeline: pw-record captures 16 kHz mono s16 WAV (exactly what whisper.cpp
 * expects, so no resampling step is needed), then the whisper binary transcribes
 * it to stdout.
 *
 * The binary name is detected rather than assumed: whisper.cpp renamed `main` to
 * `whisper-cli` in 1.7, and distributions also ship it as `whisper-cpp`.
 */
QtObject {
    id: root

    property string modelPath: ""
    // Fetched on demand when modelPath is missing, so picking a higher accuracy level
    // does not require the user to go and find a file first.
    property string modelUrl: ""
    property bool downloading: false
    signal modelDownloaded()
    property string language: "auto"
    property int threads: 6
    // Vocabulary bias. Whisper conditions on this text, which is the cheapest way to stop
    // it mangling domain words (names, jargon) — far more effective per millisecond than
    // moving to a bigger model.
    property string prompt: ""
    /**
     * Which input to record from.
     *   ""        pick a non-Bluetooth hardware input automatically (default)
     *   "default" use whatever the system default is
     *   <name>    an explicit PipeWire node name
     *
     * This exists because the system default here is often a Bluetooth headset mic, and
     * opening it makes PipeWire switch the card from A2DP to HSP/HFP — which stops music
     * mid-track and renegotiates the link. Recording from the built-in mic instead leaves
     * the Bluetooth card alone entirely.
     */
    property string source: ""

    readonly property string workDir: "/tmp/quickshell/vynx-conduit/stt"
    readonly property string wavPath: `${root.workDir}/dictation.wav`

    property string binary: ""
    property bool modelReady: false
    readonly property bool available: root.binary.length > 0 && root.modelReady

    // Armed by the keybinding path: that flow stops and sends in one press, whereas the
    // mic button inserts the text for review first.
    property bool autoSend: false
    property bool recording: false
    property bool transcribing: false

    signal transcribed(string text)
    signal failed(string reason)

    function toggle() {
        if (root.recording) {
            root.stopRecording();
        } else {
            root.startRecording();
        }
    }

    function startRecording() {
        if (root.recording || root.transcribing) return;
        if (root.downloading) {
            root.failed("Still downloading the voice model — try again in a moment.");
            return;
        }
        if (root.binary.length > 0 && !root.modelReady && root.modelUrl.length > 0) {
            root.downloadModel();
            return;
        }
        if (!root.available) {
            root.failed(root.setupHint());
            return;
        }
        // The target is resolved inside the same command so this stays one process launch.
        // An empty TARGET expands to nothing, leaving pw-record on the system default.
        let pickTarget;
        if (root.source === "default") {
            pickTarget = `TARGET=""`;
        } else if (root.source.length > 0) {
            pickTarget = `TARGET='${CF.StringUtils.shellSingleQuoteEscape(root.source)}'`;
        } else {
            // First real capture device that is neither a monitor nor Bluetooth.
            pickTarget = `TARGET="$(pactl list short sources 2>/dev/null | awk '$2 ~ /^alsa_input\./ && $2 !~ /\.monitor$/ {print $2; exit}')"`;
        }

        recorder.command = ["bash", "-c",
            `mkdir -p '${root.workDir}' && ${pickTarget} && exec pw-record \${TARGET:+--target "\$TARGET"} --rate 16000 --channels 1 --format s16 '${root.wavPath}'`];
        recorder.running = true;
        root.recording = true;
    }

    function stopRecording() {
        if (!root.recording) return;
        root.recording = false;
        // SIGINT, so pw-record finalises the WAV header instead of leaving a stub.
        recorder.signal(2);
    }

    /**
     * Turns whisper's stderr into something actionable. The common one is worth
     * special-casing: distributions split the ggml compute backends into their own
     * packages, and whisper-cpp depends only on base ggml, so a stock install has no
     * device to run on and aborts inside backend registration.
     */
    function explainFailure(fallback) {
        const errors = transcriberErrors.text ?? "";
        if (/\/usr\/lib\/ggml does not exist|GGML_ASSERT\(device\)|ggml_backend_load_best/.test(errors)) {
            return "whisper.cpp has no compute backend installed:\n\n```\nsudo pacman -S ggml-cpu\n```\n\n`whisper-cpp` depends only on base `ggml`, which ships no backend of its own.";
        }
        if (/failed to load model|invalid model file|not a ggml file/i.test(errors)) {
            return `The model at \`${root.modelPath}\` could not be loaded — it may be incomplete. Re-download it.`;
        }
        const tail = errors.trim().split("\n").slice(-3).join("\n");
        return tail.length > 0 ? `${fallback}\n\n\`\`\`\n${tail}\n\`\`\`` : fallback;
    }

    /** Strips whisper's own markers, and anything that is plainly not speech. */
    function cleanTranscript(raw) {
        return raw
            .split("\n")
            .map(line => line.trim())
            .filter(line => line.length > 0
                // whisper markers such as [BLANK_AUDIO]
                && !/^[\[(].*[\])]$/.test(line)
                // Crash output must never be mistaken for dictation
                && !/^#\d+\s|0x[0-9a-f]{8,}|GGML_ASSERT|ggml_backend|libggml|in \?\? \(\)/.test(line))
            .join(" ")
            .trim();
    }

    function downloadModel() {
        if (root.downloading || root.modelUrl.length === 0) return;
        root.downloading = true;
        const dest = CF.FileUtils.trimFileProtocol(root.modelPath);
        // Downloaded to .part and moved into place, so an interrupted transfer can never
        // leave a truncated file that whisper would fail to load.
        downloader.command = ["bash", "-c",
            `mkdir -p "$(dirname '${dest}')" && curl -sSL --fail -C - -o '${dest}.part' '${root.modelUrl}' && mv -f '${dest}.part' '${dest}'`];
        downloader.running = true;
        root.failed(`Downloading the voice model once (${root.modelUrl.split("/").pop()}). You'll get a message when it's ready.`);
    }

    property Process downloader: Process {
        id: downloader
        onExited: exitCode => {
            root.downloading = false;
            if (exitCode === 0) {
                root.modelReady = true;
                root.modelDownloaded();
            } else {
                root.failed(`Could not download the voice model (exit ${exitCode}). Check the connection, or set a model path manually.`);
            }
        }
    }

    function setupHint() {
        if (root.binary.length === 0) {
            return "Voice input needs whisper.cpp:\n\n```\nsudo pacman -S whisper-cpp\n```";
        }
        if (!root.modelReady) {
            return `No Whisper model at \`${root.modelPath}\`.\n\nDownload one:\n\n\`\`\`\ncurl -L --create-dirs -o '${root.modelPath}' https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin\n\`\`\``;
        }
        return "Voice input is unavailable.";
    }

    /* ---------- Capability detection --------------------------------------- */

    property Process binaryProbe: Process {
        command: ["bash", "-c", "command -v whisper-cli || command -v whisper-cpp || command -v whisper || true"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.binary = this.text.trim().split("\n")[0] ?? ""
        }
    }

    property Process modelProbe: Process {
        command: ["test", "-s", CF.FileUtils.trimFileProtocol(root.modelPath)]
        onExited: exitCode => root.modelReady = (exitCode === 0)
    }

    onModelPathChanged: if (root.modelPath.length > 0) modelProbe.running = true

    /* ---------- Record, then transcribe ------------------------------------ */

    property Process recorder: Process {
        id: recorder

        // pw-record exits non-zero when stopped by a signal, which is the normal path
        // here, so the recording is judged by whether a usable file exists.
        onExited: transcriber.start()
    }

    property Process transcriber: Process {
        id: transcriber

        function start() {
            root.transcribing = true;
            const model = CF.FileUtils.trimFileProtocol(root.modelPath);
            // -nt drops timestamps, -np drops progress chatter, so stdout is just text.
            // Whisper continues the prompt's style, so a prompt ending mid-sentence
            // returns a lowercase, unpunctuated transcript.
            let bias = "";
            const hint = root.prompt.trim();
            if (hint.length > 0) {
                const terminated = /[.!?]$/.test(hint) ? hint : `${hint}.`;
                bias = ` --prompt '${CF.StringUtils.shellSingleQuoteEscape(terminated)}' --carry-initial-prompt`;
            }
            transcriber.command = ["bash", "-c",
                `[ -s '${root.wavPath}' ] || exit 3; '${root.binary}' -m '${model}' -f '${root.wavPath}' -l '${root.language}' -t ${root.threads}${bias} -nt -np`];
            transcriber.running = true;
        }

        stderr: StdioCollector {
            id: transcriberErrors
        }

        stdout: StdioCollector {
            id: transcriptCollector
        }

        // The result is decided here, not in onStreamFinished, because only here is the
        // exit status known. ggml_abort prints a GDB backtrace to STDOUT before dying, so
        // treating stdout as a transcript regardless of success typed a stack trace into
        // the message box.
        onExited: exitCode => {
            root.transcribing = false;

            if (exitCode === 3) {
                root.failed("Nothing was recorded. Is an input device active?");
                return;
            }
            if (exitCode !== 0) {
                root.failed(root.explainFailure(`Transcription failed (exit ${exitCode}).`));
                return;
            }

            const text = root.cleanTranscript(transcriptCollector.text ?? "");
            if (text.length === 0) {
                root.failed(root.explainFailure("Didn't catch anything — try again a bit closer to the mic."));
                return;
            }
            root.transcribed(text);
        }
    }
}
