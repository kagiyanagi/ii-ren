import qs.modules.common
import qs.modules.common.functions as CF
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Speech-to-text for dictation. The shell records; who transcribes is the
 * `engine` property.
 *
 * Pipeline: pw-record captures 16 kHz mono s16 WAV (what both engines want, so no
 * resampling step is needed), then either the Hermes bridge
 * (scripts/hermes/stt.sh) or the local whisper.cpp binary reads it.
 *
 * The shell keeps the microphone in both cases. The agent's own `voice.record`
 * opens a capture it never releases, which on a Bluetooth headset drags the card
 * from A2DP down to HSP -- so only the transcription is delegated, never the mic.
 *
 * The whisper binary name is detected rather than assumed: whisper.cpp renamed
 * `main` to `whisper-cli` in 1.7, and distributions also ship it as `whisper-cpp`.
 */
QtObject {
    id: root

    /**
     * Where the audio is transcribed.
     *   "hermes"  whichever provider Hermes itself is set to -- `stt.provider` in
     *             ~/.hermes/config.yaml, so groq, openai, a command provider or
     *             its local faster-whisper. Changing it there changes dictation
     *             too, which is the point: one setting, in one place.
     *   "local"   this machine only, via whisper.cpp. Nothing is uploaded.
     * "hermes" falls back to "local" on its own when there is no agent checkout,
     * and after the bridge dies holding a recording.
     */
    property string engine: "hermes"
    property string bridgeScript: ""
    // Whether an agent checkout exists at all; the bridge cannot run without one.
    // Optimistic until the probe answers: it settles a moment after startup, and
    // dictating in that moment must not be silently demoted to whisper.cpp. A
    // wrong guess costs nothing -- the launcher exits 127 and the audio is read
    // locally instead.
    property bool bridgeAvailable: true
    property bool bridgeReady: false
    // Resolved provider name, for the status line ("groq", "openai", "local"…).
    property string bridgeProvider: ""
    readonly property bool usingHermes: root.engine !== "local" && root.bridgeAvailable && root.bridgeScript.length > 0

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
    readonly property bool available: root.usingHermes || (root.binary.length > 0 && root.modelReady)

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
        if (root.usingHermes) {
            // Started now rather than when the recording ends: the agent's import
            // graph and config resolution cost over a second, and paying it while
            // the user is still speaking makes it free.
            root.startBridge();
        } else {
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
        onExited: root.transcribeRecording()
    }

    /** Hand the finished capture to whichever engine is in charge. */
    function transcribeRecording(path) {
        const audio = (path && path.length > 0) ? path : root.wavPath;
        if (root.usingHermes) {
            root.transcribing = true;
            bridge.request(audio);
            return;
        }
        transcriber.start(audio);
    }

    /*
     * The recording has served its purpose the moment it has been read. Deleted on
     * every path, including the failures - a transcript that could not be read is
     * not a reason to keep the audio lying in /tmp until the next reboot, and
     * re-recording costs a sentence.
     */
    function discardAudio(path) {
        if (!path || path.length === 0) return;
        Quickshell.execDetached(["rm", "-f", path]);
    }

    /* ---------- Transcribing through Hermes -------------------------------- */

    // Switched to whisper.cpp: the server is holding the agent's whole import graph
    // in memory for a path nothing takes any more.
    onUsingHermesChanged: if (!root.usingHermes && bridge.running) bridge.running = false

    function startBridge() {
        if (!root.usingHermes || bridge.running) return;
        bridge.running = true;
    }

    function finishBridgeReply(reply) {
        root.transcribing = false;
        root.discardAudio(bridge.audioPath);
        bridge.audioPath = "";

        const text = root.cleanTranscript(reply.text ?? "");
        if (!reply.ok || text.length === 0) {
            const reason = reply.error ?? "";
            root.failed(reason.length > 0 ? reason : "Didn't catch anything — try again a bit closer to the mic.");
            return;
        }
        root.transcribed(text);
    }

    property Process bridge: Process {
        id: bridge

        running: false
        stdinEnabled: true
        command: [root.bridgeScript]

        // Which file this run is reading, so it can be shredded afterwards - or
        // retried locally if the bridge dies still holding it.
        property string audioPath: ""
        // Sent as soon as the server says it is ready. The recording finishes first
        // whenever the utterance was shorter than the agent's import graph.
        property string pendingRequest: ""

        function request(audio) {
            bridge.audioPath = audio;
            const frame = JSON.stringify({ id: `stt-${Date.now()}`, wav: audio }) + "\n";
            if (!root.bridgeReady) {
                bridge.pendingRequest = frame;
                root.startBridge();
                return;
            }
            bridge.write(frame);
        }

        stdout: SplitParser {
            onRead: line => {
                if (line.trim().length === 0) return;
                let reply;
                try {
                    reply = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (reply.event === "ready") {
                    root.bridgeReady = true;
                    root.bridgeProvider = reply.provider ?? "";
                    const queued = bridge.pendingRequest;
                    bridge.pendingRequest = "";
                    if (queued.length > 0) bridge.write(queued);
                    return;
                }
                root.finishBridgeReply(reply);
            }
        }

        stderr: SplitParser {
            onRead: line => {
                if (line.trim().length > 0) console.log("[Hermes/stt]", line.trim());
            }
        }

        onExited: exitCode => {
            root.bridgeReady = false;
            bridge.pendingRequest = "";
            // 127 is the launcher saying there is no agent checkout and no
            // interpreter for one. Nothing will fix that before a restart, so stop
            // routing through it instead of failing every utterance the same way.
            if (exitCode === 127) root.bridgeAvailable = false;

            if (bridge.audioPath.length === 0) return;

            // Died holding a recording: read it here rather than lose what was said.
            const audio = bridge.audioPath;
            bridge.audioPath = "";
            if (root.binary.length > 0 && root.modelReady) {
                transcriber.start(audio);
                return;
            }
            root.transcribing = false;
            root.discardAudio(audio);
            root.failed(`Transcription through Hermes stopped (exit ${exitCode}).`);
        }
    }

    property Process bridgeProbe: Process {
        command: ["test", "-d", `${Quickshell.env("HERMES_HOME") || `${Quickshell.env("HOME")}/.hermes`}/hermes-agent`]
        running: true
        onExited: exitCode => root.bridgeAvailable = (exitCode === 0)
    }

    property Process transcriber: Process {
        id: transcriber

        // Which file this run is reading, so it can be shredded afterwards.
        property string audioPath: ""

        function start(path) {
            root.transcribing = true;
            const audio = (path && path.length > 0) ? path : root.wavPath;
            transcriber.audioPath = audio;
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
            /*
             * No --audio-ctx here, deliberately.
             *
             * Shrinking the context does cut encoder time proportionally - the
             * encoder always runs over a padded 30s window, so most of a short
             * clip's cost is silence. But it is not a lossless crop: the encoder
             * was only ever trained at the full 1500-position context, and running
             * it shorter hands the decoder an off-distribution embedding. Whisper's
             * failure mode there is not garbled text, it is fluent invented text -
             * a 2.5s "Hello sir, what are you doing today?" came back as a
             * confident unrelated sentence, and did so identically on every model
             * size, because the damage is upstream of the decoder.
             *
             * Latency is worth less than a transcript that says what was said.
             */
            transcriber.command = ["bash", "-c",
                `[ -s '${audio}' ] || exit 3; ` +
                `'${root.binary}' -m '${model}' -f '${audio}' -l '${root.language}' -t ${root.threads}${bias} -nt -np`];
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

            root.discardAudio(transcriber.audioPath);
            transcriber.audioPath = "";

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
