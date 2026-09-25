pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.utils
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property real scaleFactor: 1
    required property string screenshotPath

    readonly property string textColorDetectionScriptPath: Quickshell.shellPath("scripts/images/text-color-venv.sh")
    readonly property bool localModel: Config.options.language.translator.mode === "local_model"

    // Text and boxes first, then each block's translation and the colours under
    // it, side by side. Nothing is drawn until both are in, so no box changes
    // colour on screen.
    property var paragraphs: []
    property var translations: null // aligned with paragraphs
    property var colours: null // aligned with paragraphs, null where a box has no pixels
    property var boxes: [] // the paragraphs that really were translated
    property bool loading: true
    property bool error: false
    property string errorMessage: ""
    readonly property bool empty: !root.loading && root.boxes.length === 0
    readonly property string status: {
        if (root.error)
            return root.errorMessage;
        if (root.empty)
            return Translation.tr("Nothing to translate");
        if (root.localModel)
            return Translation.tr("Running Local AI Model...");
        return ocr.state === AsyncTask.State.Processing ? Translation.tr("Reading screen") : Translation.tr("Translating");
    }

    // `trans` round-trips text that is already in the target language almost
    // unchanged, but "almost" is not "exactly": it drops a trailing dot, swaps a
    // quote. Comparing bare strings would paper the screen with boxes that just
    // repeat what is under them, so compare only the letters and digits.
    function isRealTranslation(source: string, translated: string): bool {
        const strip = (t) => t.toLowerCase()
            .replace(/[\s -¿ -⁯　-〿]/g, "")
            .replace(/[!-\/:-@\[-`{-~]/g, "");
        return translated.length > 0 && strip(translated) !== strip(source);
    }

    function handleError(msg) {
        root.errorMessage = msg?.length > 0 ? msg : Translation.tr("Something went wrong.");
        root.error = true;
    }

    function read(paragraphs) {
        root.paragraphs = paragraphs;
        colourProc.command = [root.textColorDetectionScriptPath, root.screenshotPath].concat(paragraphs.map(p => {
            const v = p.boundingBox.vertices;
            return `${v[0].x},${v[0].y},${v[1].x - v[0].x},${v[3].y - v[0].y}`;
        }));
        colourProc.running = true;
    }

    function finish() {
        if (root.translations === null || root.colours === null)
            return;
        root.boxes = root.paragraphs.map((p, i) => ({
            text: p.text,
            translated: root.translations[i] ?? "",
            colour: root.colours[i] ?? null,
            vertices: p.boundingBox.vertices
        })).filter(b => root.isRealTranslation(b.text, b.translated));
        root.loading = false;
    }

    Component.onCompleted: {
        if (!root.localModel) {
            ocr.recognize(root.screenshotPath);
            return;
        }
        localModelProc.runSequence([
            ["bash", "-c", `python3 ${StringUtils.shellSingleQuoteEscape(Quickshell.shellPath("scripts/images/local_model_translator.py"))} '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' 2>/dev/null`],
            (out) => {
                try {
                    const res = JSON.parse(out);
                    if (res.error) {
                        root.handleError(res.error);
                        return;
                    }
                    root.translations = res.data.map(p => p.translated);
                    root.read(res.data);
                } catch (e) {
                    root.handleError(Translation.tr("Failed to parse local model output: ") + e);
                }
            }
        ]);
    }

    MultiTurnProcess {
        id: localModelProc
    }

    TextRecognizer {
        id: ocr
        onError: (msg) => root.handleError(msg)
        onFinished: {
            root.read(ocr.paragraphs);
            translator.translateStrings(ocr.paragraphs.map(p => p.text));
        }
    }

    TextTranslator {
        id: translator
        onError: (msg) => root.handleError(msg)
        onFinished: {
            root.translations = Array.from(translator.translations);
            root.finish();
        }
    }

    // One process for every box. A Python start with cv2 is ~200ms, and this
    // was one per box, all at once: 30 boxes held all 8 cores for 1.7s.
    // Colour is not worth an error, so a failure falls back to the theme.
    Process {
        id: colourProc
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(text);
                } catch (e) {}
                root.colours = Array.isArray(parsed) ? parsed : [];
                root.finish();
            }
        }
    }

    Repeater {
        model: root.boxes
        delegate: TextItem {}
    }

    // One of `boxes`: text, translated, colour, vertices. Opaque in the colour
    // under it, which is what erases the source: at 60% over a blur, the blurred
    // glyphs still showed wherever the translation was shorter than the text.
    component TextItem: Rectangle {
        id: ti
        required property var modelData
        readonly property var vertices: modelData.vertices

        // From the top edge. QML rotation is degrees clockwise.
        transformOrigin: Item.TopLeft
        rotation: Math.atan2(vertices[1].y - vertices[0].y, vertices[1].x - vertices[0].x) * 180 / Math.PI

        x: vertices[0].x * root.scaleFactor
        y: vertices[0].y * root.scaleFactor
        width: (vertices[1].x - vertices[0].x) * root.scaleFactor
        height: (vertices[3].y - vertices[0].y) * root.scaleFactor
        radius: Appearance.rounding.unsharpenmore
        color: ti.modelData.colour?.background ?? Appearance.colors.colSecondaryContainer

        SqueezedAnnotationStyledText {
            width: parent.width
            height: parent.height
            text: ti.modelData.translated
            scaleFactor: root.scaleFactor
            color: ti.modelData.colour?.text ?? Appearance.colors.colOnSecondaryContainer
        }
    }
}
