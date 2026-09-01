pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.utils
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property double scaleFactor: 1
    property color overlayColor: "#BB000000"
    property color textColor: "white"
    required property string screenshotPath

    readonly property string textColorDetectionScriptPath: Quickshell.shellPath("scripts/images/text-color-venv.sh")

    property bool loading: true
    property var paragraphs: []
    property list<string> translationKeys: []
    property var translation: ({})

    function translate(s: string): string {
        return translation[s] ?? s;
    }

    // `trans` round-trips text that is already in the target language almost
    // unchanged, but "almost" is not "exactly": it drops a trailing dot, swaps a
    // quote. Comparing bare strings would paper the screen with boxes that just
    // repeat what is under them, so compare only the letters and digits.
    function isRealTranslation(source: string, translated: string): bool {
        const strip = (t) => t.toLowerCase()
            .replace(/[\s\u00a0-\u00bf\u2000-\u206f\u3000-\u303f]/g, "")
            .replace(/[!-\/:-@\[-`{-~]/g, "");
        return translated.length > 0 && strip(translated) !== strip(source);
    }

    property bool error: false
    property string errorMessage: ""
    function showError() {
        error = true;
    }

    Component.onCompleted: {
        if (Config.options.language.translator.mode === "local_model") {
            localModelProc.runSequence([
                ["bash", "-c", `python3 ${StringUtils.shellSingleQuoteEscape(Quickshell.shellPath("scripts/images/local_model_translator.py"))} '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' 2>/dev/null`],
                (out) => {
                    try {
                        const res = JSON.parse(out);
                        if (res.error) {
                            root.handleError(res.error);
                            return;
                        }
                        root.paragraphs = res.data;
                        root.translation = ({});
                        for (let p of res.data) {
                            Object.assign(root.translation, { [p.text]: p.translated });
                        }
                        root.loading = false;
                    } catch (e) {
                        root.handleError(Translation.tr("Failed to parse local model output: ") + e);
                    }
                }
            ]);
        } else {
            ocr.recognize(root.screenshotPath);
        }
    }

    MultiTurnProcess {
        id: localModelProc
    }

    Rectangle {
        id: loadingOverlay
        anchors.fill: parent
        opacity: root.loading ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }
        color: root.overlayColor

        Column {
            visible: !root.error
            anchors.centerIn: parent
            spacing: 10 * root.scaleFactor
            MaterialLoadingIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitSize: 100 * root.scaleFactor
                scale: 1 + ((1 - loadingOverlay.opacity) * 0.5) * root.scaleFactor
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    if (Config.options.language.translator.mode === "local_model")
                        return Translation.tr("Running Local AI Model...");
                    else if (ocr.state == AsyncTask.State.Processing)
                        return Translation.tr("Reading screen");
                    else if (translator.state == AsyncTask.State.Processing)
                        return Translation.tr("Translating");
                    else
                        return " ";
                }
                font.pixelSize: Appearance.font.pixelSize.small * root.scaleFactor
                animateChange: true
                color: root.textColor
            }
        }

        Column {
            visible: root.error
            anchors.centerIn: parent
            spacing: 10 * root.scaleFactor

            MaterialShapeWrappedMaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "exclamation"
                iconSize: 80 * root.scaleFactor
                padding: 6 * root.scaleFactor
                color: Appearance.colors.colError
                colSymbol: Appearance.colors.colOnError
                shape: MaterialShape.Shape.Sunny
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(root.windowWidth / 2, 800) * root.scaleFactor
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.MarkdownText
                wrapMode: Text.Wrap
                text: `**${Translation.tr("Screen Translator")}**\n\n${root.errorMessage}`
                font.pixelSize: Appearance.font.pixelSize.small * root.scaleFactor
                color: root.textColor
            }
        }
    }

    function handleError(msg) {
        root.errorMessage = msg?.length > 0 ? msg : Translation.tr("Something went wrong.");
        root.showError();
    }

    TextRecognizer {
        id: ocr
        onError: (msg) => {
            root.handleError(msg);
        }
        onFinished: {
            root.paragraphs = ocr.paragraphs;
            root.translationKeys = ocr.paragraphs.map(p => p.text);
            translator.translateStrings(root.translationKeys);
        }
    }

    TextTranslator {
        id: translator
        onError: (msg) => {
            root.handleError(msg);
        }
        onFinished: {
            const values = translator.translations;
            const keys = root.translationKeys;
            root.translation = ({});
            for (var i = 0; i < keys.length; i++) {
                Object.assign(root.translation, {
                    [keys[i]]: values[i]
                });
            }
            // print("TRANSLATION:", JSON.stringify(root.translation));
            root.loading = false;
        }
    }

    property real windowWidth: QsWindow.window.screen.width
    property real windowHeight: QsWindow.window.screen.height

    StyledImage {
        id: screenshotImage
        z: 1
        asynchronous: false
        width: root.windowWidth
        height: root.windowHeight
        source: Qt.resolvedUrl(root.screenshotPath)
        visible: false
    }

    Item {
        id: blurMaskItem
        z: 2
        width: root.windowWidth
        height: root.windowHeight
        layer.enabled: true
        visible: false
        Repeater {
            model: root.loading ? [] : root.paragraphs
            delegate: VisionBoundingBoxRect {
                scaleFactor: 1
            }
        }
    }

    MaskMultiEffect {
        z: 4
        implicitWidth: parent.width
        implicitHeight: parent.height
        width: parent.width
        height: parent.height

        // Mask
        source: screenshotImage
        maskSource: blurMaskItem

        // Blur
        blurEnabled: true
        blur: 1
        blurMax: 50
        blurMultiplier: root.scaleFactor
        autoPaddingEnabled: false
    }

    Item {
        id: textItems
        z: 999
        Repeater {
            model: root.loading ? [] : root.paragraphs
            // An entry looks like this:
            delegate: TextItem {}
        }
    }

    component VisionBoundingBoxRect: Rectangle {
        required property var modelData
        readonly property string text: modelData.text
        readonly property string translatedText: root.translate(text)
        visible: root.isRealTranslation(text, translatedText)
        property real scaleFactor: root.scaleFactor
        property list<var> boundingVertices: modelData.boundingBox.vertices
        property real unscaledX: boundingVertices[0].x
        property real unscaledY: boundingVertices[0].y
        property real unscaledWidth: boundingVertices[1].x - boundingVertices[0].x
        property real unscaledHeight: boundingVertices[3].y - boundingVertices[0].y
        
        // Calculate rotation based on first two vertices (top-left to top-right)
        property real dx: boundingVertices[1].x - boundingVertices[0].x
        property real dy: boundingVertices[1].y - boundingVertices[0].y
        transformOrigin: Item.TopLeft
        rotation: {
            // Note rotation in qml is degrees clockwise
            var angle = Math.atan2(dy, dx) * 180 / Math.PI;
            return angle;
        }
        
        x: unscaledX * scaleFactor
        y: unscaledY * scaleFactor
        width: unscaledWidth * scaleFactor
        height: unscaledHeight * scaleFactor
        radius: 4
    }

    component TextItem: VisionBoundingBoxRect {
        id: ti
        // {"boundingPoly": {"vertices": [{"x": 536,"y": 236},{"x": 583,"y": 236},{"x": 583,"y": 262},{"x": 536,"y": 262}]},"description": "宮坂"}
        color: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0.4)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Loader {
            active: ti.visible
            sourceComponent: MultiTurnProcess {
                Component.onCompleted: {
                    runSequence([ //
                        [ //
                            "bash", "-c", //
                            `magick ${StringUtils.shellSingleQuoteEscape(root.screenshotPath)} +repage -crop ${StringUtils.shellSingleQuoteEscape(ti.unscaledWidth)}x${StringUtils.shellSingleQuoteEscape(ti.unscaledHeight)}+${StringUtils.shellSingleQuoteEscape(ti.unscaledX)}+${StringUtils.shellSingleQuoteEscape(ti.unscaledY)} png:- | ${root.textColorDetectionScriptPath}`
                        ],
                        (out => {
                            var colorData = JSON.parse(out);
                            ti.color = ColorUtils.transparentize(colorData.background, 0.4);
                            tiText.color = colorData.text;
                        })
                    ]);
                }
            }
        }

        SqueezedAnnotationStyledText {
            id: tiText
            width: parent.width
            height: parent.height
            text: ti.translatedText
            scaleFactor: root.scaleFactor

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
