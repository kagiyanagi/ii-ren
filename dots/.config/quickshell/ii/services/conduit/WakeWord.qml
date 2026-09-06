import qs.modules.common
import qs.modules.common.functions as CF
import Quickshell.Io
import QtQuick

/**
 * Hands-free wake word. Says nothing to the network: detection is three small
 * ONNX models run locally by scripts/wakeword/wakeword.py, and the request that
 * follows goes to the same local whisper.cpp everything else here uses.
 *
 * The script owns the microphone for the whole cycle - listen, detect, then keep
 * recording the request and endpoint it on silence - and hands back a finished
 * WAV. That is deliberate: waking QML and *then* starting a recorder loses the
 * first word of every request in the gap where the mic is reopened.
 *
 * Idle cost is near zero. The script gates on signal level and never reaches the
 * models at all in a quiet room, so this can sit running permanently.
 */
QtObject {
    id: root

    property bool enabled: false
    /** Which phrase models to load, as [{ name, file, threshold }]. */
    property var phrases: []
    property string modelDir: CF.FileUtils.trimFileProtocol(`${Directories.home}/.local/share/vynx-conduit/wakeword`)
    property string source: ""
    readonly property string utterancePath: "/tmp/quickshell/vynx-conduit/stt/utterance.wav"

    // Suspends listening without tearing the models down - set while the shell is
    // speaking (else it hears its own reply and wakes itself) and while locked.
    property bool suspended: false

    property bool listening: false
    property bool capturing: false
    // 0-1, drives the visualiser. Only meaningful while listening.
    property real level: 0

    property bool downloading: false
    property bool modelsReady: false
    signal woke(string phrase, real score)
    signal utterance(string path)
    signal failed(string reason)

    readonly property bool shouldRun: root.enabled && !root.suspended && root.modelsReady
        && root.phrases.length > 0

    /*
     * The two shared models are the same for every phrase and are what the
     * per-phrase classifiers are trained against, so they are pinned to the
     * release the classifiers came from rather than tracking latest.
     */
    readonly property string releaseUrl: "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1"
    readonly property var sharedModels: ["melspectrogram.onnx", "embedding_model.onnx"]

    function phraseArgs() {
        return root.phrases.map(phrase =>
            ["--model", `${phrase.name}=${root.modelDir}/${phrase.file}:${phrase.threshold}`]);
    }

    /* ---------- Models ------------------------------------------------------ */

    /**
     * Fetch whatever is missing. Downloaded to .part and moved into place, so an
     * interrupted transfer can never leave a truncated ONNX that onnxruntime
     * fails on at load - the same care SpeechToText takes with whisper models.
     */
    function downloadModels() {
        if (root.downloading) return;
        root.downloading = true;
        const wanted = root.sharedModels.concat(root.phrases.map(phrase => phrase.file));
        const fetches = wanted.map(file =>
            `[ -s '${root.modelDir}/${file}' ] || { curl -sSL --fail -o '${root.modelDir}/${file}.part' '${root.releaseUrl}/${file}' && mv -f '${root.modelDir}/${file}.part' '${root.modelDir}/${file}'; }`
        ).join(" && ");
        downloader.command = ["bash", "-c", `mkdir -p '${root.modelDir}' && ${fetches}`];
        downloader.running = true;
    }

    property Process downloader: Process {
        id: downloader
        onExited: exitCode => {
            root.downloading = false;
            if (exitCode === 0) {
                root.modelsReady = true;
                return;
            }
            /*
             * A custom-trained phrase is not on the release page, so a failure here
             * is expected and harmless the moment somebody selects one before
             * training has finished. Say which file is missing rather than blaming
             * the network.
             */
            root.failed(`Could not fetch the wake word models. A custom phrase has to be trained first — see tools/wakeword/README.md — and dropped into \`${root.modelDir}\`.`);
        }
    }

    property Process modelProbe: Process {
        // Every shared model and every selected phrase has to be present, else the
        // detector exits on the first missing file.
        command: ["bash", "-c",
            root.phrases.length === 0 ? "exit 1" :
            root.sharedModels.concat(root.phrases.map(phrase => phrase.file))
                .map(file => `[ -s '${root.modelDir}/${file}' ]`).join(" && ")]
        onExited: exitCode => {
            root.modelsReady = (exitCode === 0);
            if (!root.modelsReady && root.enabled) root.downloadModels();
        }
    }

    function recheckModels() {
        if (!root.enabled) return;
        modelProbe.running = true;
    }

    onEnabledChanged: root.recheckModels()
    onPhrasesChanged: root.recheckModels()

    /* ---------- The detector ------------------------------------------------ */

    property Process detector: Process {
        id: detector

        // exec, so the pid QML holds is python itself and terminating this really
        // does stop the microphone rather than orphaning it behind a shell.
        command: ["bash", "-c",
            `exec "$(eval echo \${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv})/bin/python" '${Directories.wakeWordScript}' ` +
            `--model-dir '${root.modelDir}' --source '${CF.StringUtils.shellSingleQuoteEscape(root.source)}' ` +
            `--utterance '${root.utterancePath}' ` +
            root.phraseArgs().map(pair => `${pair[0]} '${CF.StringUtils.shellSingleQuoteEscape(pair[1])}'`).join(" ")]

        running: root.shouldRun

        onRunningChanged: {
            if (detector.running) return;
            root.listening = false;
            root.capturing = false;
            root.level = 0;
        }

        onExited: exitCode => {
            // 0 is a clean stop (we asked). Anything else and the detector fell
            // over, which must not silently leave a dead "listening" indicator.
            if (exitCode !== 0 && root.shouldRun)
                root.failed(`The wake word listener stopped unexpectedly (exit ${exitCode}).`);
        }

        stdout: SplitParser {
            onRead: line => {
                let event;
                try {
                    event = JSON.parse(line);
                } catch (error) {
                    return; // Not ours - onnxruntime occasionally prints notices.
                }
                switch (event.event) {
                case "ready":
                    root.listening = true;
                    break;
                case "level":
                    root.level = event.rms ?? 0;
                    break;
                case "wake":
                    root.capturing = true;
                    root.woke(event.phrase ?? "", event.score ?? 0);
                    break;
                case "utterance":
                    root.capturing = false;
                    root.utterance(event.path ?? root.utterancePath);
                    break;
                case "error":
                    root.failed(event.reason ?? "The wake word listener failed.");
                    break;
                }
            }
        }
    }
}
