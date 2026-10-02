pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell.Io
import qs.modules.common
import QtQuick
import Quickshell

/**
 * Renders LaTeX snippets with MicroTeX.
 * For every request:
 *   1. Hash it
 *   2. Check if the hash is already processed
 *   3. If not, render it with MicroTeX and mark as processed
 */
Singleton {
    id: root
    
    readonly property var renderPadding: 4 // This is to prevent cutoff in the rendered images

    property var processedExpressions: ({})
    property var renderedImagePaths: ({})
    /** Each render's natural [width, height], for the text to reserve its space. */
    property var renderedSizes: ({})
    /**
     * A blank image. Sized by its tag, it holds a formula's place in rich text.
     * One transparent PNG pixel: a size-less SVG gave Qt no pixels, and it stretched
     * uninitialised texture over the formulas, measured as white smears.
     */
    readonly property string placeholder: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg=="
    property string microtexBinaryDir: "/opt/MicroTeX"
    property string microtexBinaryName: "LaTeX"
    property string latexOutputPath: Directories.latexOutput

    signal renderFinished(string hash, string imagePath)

    // A local image loads synchronously, so the probe knows its size on creation
    function measure(hash, imagePath) {
        const probe = sizeProbe.createObject(root, { source: `file://${imagePath}` });
        root.renderedSizes[hash] = [probe.implicitWidth, probe.implicitHeight];
        probe.destroy();
    }

    // A component, not a createQmlObject string: that compiled QML once per formula
    Component {
        id: sizeProbe
        Image {
            cache: false
        }
    }

    // Qt.md5 is ~45us, and every formula of a streaming reply is looked up again
    // on every chunk: 90k hashes for one 234-formula answer
    property var hashes: ({})

    function hashOf(expression) {
        return root.hashes[expression] ?? (root.hashes[expression] = Qt.md5(expression))
    }

    /**
    * Requests rendering of a LaTeX expression.
    * Returns the [hash, isNew]
    */
    function requestRender(expression) {
        // 1. Hash it and initialize necessary variables
        const hash = root.hashOf(expression)
        const imagePath = `${latexOutputPath}/${hash}.svg`
        
        // 2. Check if the hash is already processed. Asked again for every formula
        // on every streamed chunk, so a lookup rather than a list scan, and no
        // renderFinished: the caller reads what is ready, and one still queued
        // reports when it lands.
        if (root.processedExpressions[hash] !== undefined)
            return [hash, false]
        root.processedExpressions[hash] = expression

        // 3. If not, queue it for MicroTeX
        root.pending.push({ hash: hash, expression: expression, imagePath: imagePath })
        root.drain()
        return [hash, true]
    }

    /*
     * A few renders at a time. One is ~25ms, but a reply can hold hundreds, and
     * compiling and forking a process for each of 211 formulas on one frame
     * stalled the shell for seconds and the whole machine with it.
     */
    readonly property int maxRenders: 4
    property var pending: []
    property int rendering: 0

    function drain() {
        while (root.rendering < root.maxRenders && root.pending.length > 0) {
            root.rendering++
            microtexProcess.createObject(root, root.pending.shift())
        }
    }

    Component {
        id: microtexProcess

        Process {
            id: proc
            required property string hash
            required property string expression
            required property string imagePath

            running: true
            // The formula is an argument, never part of the script: it is model
            // output, and bash only ever sees "$@". Through bash rather than exec'd
            // directly, so a missing MicroTeX still ends in `exited` and frees its slot.
            command: ["bash", "-c", 'cd "$0" && exec "$@"', root.microtexBinaryDir, `./${root.microtexBinaryName}`,
                "-headless", `-input=${proc.expression}`, `-output=${proc.imagePath}`,
                `-textsize=${Appearance.font.pixelSize.normal}`, `-padding=${root.renderPadding}`,
                `-foreground=${Appearance.colors.colOnLayer1}`, "-maxwidth=0.85"]
            onExited: {
                root.renderedImagePaths[proc.hash] = proc.imagePath
                root.measure(proc.hash, proc.imagePath)
                root.rendering--
                root.renderFinished(proc.hash, proc.imagePath)
                root.drain()
                proc.destroy()
            }
        }
    }
}