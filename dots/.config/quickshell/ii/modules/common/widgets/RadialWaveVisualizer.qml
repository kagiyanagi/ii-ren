import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects

Canvas { // Visualizer
    id: root
    property list<var> points: []
    property real maxVisualizerValue: 800
    property int smoothing: 2
    property bool live: true
    property color color: Appearance.m3colors.m3primary

    property real waveOpacity: 0.15
    property real waveBlur: 1

    // Cava pushes 60 updates a second, and each repaint costs a repaint of the
    // whole surface this sits on - which is what actually shows up in a CPU
    // profile, so the cost tracks the update rate. Integrated graphics is the
    // target and an ambient wave is indistinguishable at half that rate, so
    // admit at most one repaint per interval (leading edge first, so it still
    // reacts immediately) and stop the gate once the audio does. Matches
    // WaveVisualizer.
    property int maxFps: 30
    readonly property int minIntervalMs: Math.max(1, Math.round(1000 / Math.max(1, root.maxFps)))
    property bool pendingUpdate: false

    onPointsChanged: {
        if (!root.visible) return;
        root.pendingUpdate = true;
        if (!updateGate.running) {
            root.requestPaint();
            root.pendingUpdate = false;
            updateGate.start();
        }
    }

    // Going quiet has to land one last paint - the wave has to actually
    // collapse to the ring, and the gate above would otherwise skip it.
    onLiveChanged: if (root.visible) root.requestPaint()
    onVisibleChanged: if (root.visible) root.requestPaint()

    Timer {
        id: updateGate
        interval: root.minIntervalMs
        repeat: true
        onTriggered: {
            if (!root.pendingUpdate) {
                updateGate.stop();
                return;
            }
            root.pendingUpdate = false;
            if (root.visible) root.requestPaint();
        }
    }

    anchors.fill: parent
    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        var points = root.points;
        var maxVal = root.maxVisualizerValue || 1;
        var w = width;
        var h = height;
        var n = points.length;
        if (n < 3) return;

        var cx = w / 2;
        var cy = h / 2;
        var maxRadius = Math.min(w, h) / 2;
        var inwardOffset = maxRadius * 0.8;

        // Kept local. Publishing this as a property fired a list<var> change
        // notification on every one of those 60 frames, and nothing read it.
        var plotPoints = VisualizerUtils.smooth(points, root.smoothing);
        if (!root.live) plotPoints.fill(0);
        plotPoints.push(plotPoints[0]); // Close the ring back onto its start
        var visualN = plotPoints.length;

        ctx.beginPath();

        for (var i = visualN - 1; i >= 0; --i) {
            var normalized = plotPoints[i] / maxVal;
            var angle = (i / (visualN - 1)) * Math.PI * 2 - Math.PI / 2;

            var currentRadius = maxRadius - (normalized * inwardOffset);
            if (currentRadius < (maxRadius - inwardOffset)) {
                currentRadius = (maxRadius - inwardOffset);
            }

            var x = cx + Math.cos(angle) * currentRadius;
            var y = cy + Math.sin(angle) * currentRadius;

            if (i === visualN - 1)
                ctx.moveTo(x, y);
            else
                ctx.lineTo(x, y);
        }

        ctx.lineTo(cx, cy - maxRadius);

        for (var i = 0; i < visualN; ++i) {
            var angle = (i / (visualN - 1)) * Math.PI * 2 - Math.PI / 2;
            var x = cx + Math.cos(angle) * maxRadius;
            var y = cy + Math.sin(angle) * maxRadius;
            ctx.lineTo(x, y);
        }

        ctx.closePath();
        ctx.fillStyle = Qt.rgba(
            root.color.r,
            root.color.g,
            root.color.b,
            root.waveOpacity
        );
        ctx.fill();
    }

    // A layer plus a blur pass, re-run every frame, is most of what this widget
    // costs on integrated graphics - and at blur 0 it was re-running the whole
    // pipeline to produce an identical image. Only pay for it when it draws
    // something.
    layer.enabled: root.waveBlur > 0
    layer.effect: MultiEffect {
        source: root
        saturation: 1.0
        blurEnabled: true
        blurMax: 7
        blur: root.waveBlur
    }
}
