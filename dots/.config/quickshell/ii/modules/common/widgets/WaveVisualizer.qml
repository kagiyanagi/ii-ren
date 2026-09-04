import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

Item { // Visualizer
    id: root
    property list<var> points
    property list<var> smoothPoints: []
    property real maxVisualizerValue: 1000
    property int smoothing: 2
    property bool live: true
    property color color: Appearance.m3colors.m3primary
    property real waveOpacity: 0.15

    anchors.fill: parent

    // Every accepted update repaints the surface this sits on, and on the dock
    // that measured ~50% of a core at cava's 60 updates a second - the cost is
    // the surface repaint, so it tracks update *rate*, not how the wave is
    // drawn. Integrated graphics is the target, and an ambient audio wave is
    // indistinguishable at half that rate, so gate it here rather than slowing
    // cava down for the bar as well.
    property int maxFps: 30
    readonly property int minIntervalMs: Math.max(1, Math.round(1000 / Math.max(1, root.maxFps)))
    property var shownPoints: []
    property bool pendingUpdate: false

    function flushPoints() {
        root.shownPoints = root.points;
        root.pendingUpdate = false;
    }

    // Leading edge goes through immediately so the wave reacts at once; the
    // gate then admits at most one update per interval and stops itself once
    // the audio does, rather than ticking forever.
    onPointsChanged: {
        if (!root.visible) return;
        root.pendingUpdate = true;
        if (!updateGate.running) {
            root.flushPoints();
            updateGate.start();
        }
    }

    onVisibleChanged: if (root.visible) root.flushPoints()

    // Points that are set once and never change - a static preview, a caller
    // that assigns before this is visible - would otherwise sit at the empty
    // initial value forever, because only a *change* opens the gate.
    Component.onCompleted: root.flushPoints()
    onLiveChanged: root.flushPoints() // The paint that collapses a stopped wave

    Timer {
        id: updateGate
        interval: root.minIntervalMs
        repeat: true
        onTriggered: {
            if (root.pendingUpdate) root.flushPoints();
            else updateGate.stop();
        }
    }

    // A hidden dock or an unmapped popup can show none of it, so the geometry
    // is not built either.
    readonly property var wavePoints: {
        if (!root.visible || root.width <= 0 || root.height <= 0)
            return [];

        const pts = root.shownPoints;
        const n = pts.length;
        if (n < 2) return [];

        const smoothed = VisualizerUtils.smooth(pts, root.smoothing);
        if (!root.live) smoothed.fill(0); // If not playing, show no points
        root.smoothPoints = smoothed;

        const maxVal = root.maxVisualizerValue || 1;
        const w = root.width;
        const h = root.height;

        // Closed by the baseline at both ends, so the polyline fills as an
        // area rather than a stroke.
        const out = [Qt.point(0, h)];
        for (let i = 0; i < n; ++i)
            out.push(Qt.point(i * w / (n - 1), h - (smoothed[i] / maxVal) * h));
        out.push(Qt.point(w, h));
        return out;
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        asynchronous: false

        ShapePath {
            strokeWidth: -1 // Fill only, as the Canvas did
            fillColor: ColorUtils.applyAlpha(root.color, root.waveOpacity)

            PathPolyline {
                path: root.wavePoints
            }
        }
    }

    layer.enabled: true
    layer.effect: MultiEffect { // Blur a bit to obscure away the points
        source: root
        saturation: 0.2
        blurEnabled: true
        blurMax: 7
        blur: 1
    }
}
