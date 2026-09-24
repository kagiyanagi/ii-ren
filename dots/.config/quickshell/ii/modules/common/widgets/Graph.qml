import QtQuick
import qs.modules.common
import qs.modules.common.functions

/*
 * Simple one value line graph
 */
Canvas {
    id: root

    enum Alignment { Left, Right }

    required property list<real> values
    property int points: values.length
    property color color: Appearance.colors.colPrimary
    property real fillOpacity: 0.5
    property var alignment: Graph.Alignment.Left
    /*
     * Rounds the plot's own corners, so it can fill a rounded well edge to edge.
     * The clip is antialiased and lives inside the image the Canvas already
     * paints, so it costs nothing -- where `layer.enabled` + OpacityMask costs a
     * framebuffer (DESIGN.md 8). 0 leaves the plot square.
     */
    property real radius: 0

    // A Canvas repaints on request only. `color` follows the wallpaper theme and
    // `points` follows a config option, so a chart with a static `values` - the
    // battery history one - kept painting the old palette until the app restarted.
    onValuesChanged: root.requestPaint()
    onColorChanged: root.requestPaint()
    onFillOpacityChanged: root.requestPaint()
    onPointsChanged: root.requestPaint()
    onRadiusChanged: root.requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!root.values || root.values.length < 2)
            return

        // clip() intersects with the clip already set, and the context outlives
        // this paint: without the restore, a resize would keep the old corners.
        ctx.save()
        if (root.radius > 0) {
            ctx.beginPath()
            ctx.roundedRect(0, 0, width, height, root.radius, root.radius)
            ctx.clip()
        }

        var n = root.points
        var dx = width / (n - 1)
        ctx.strokeStyle = root.color
        ctx.fillStyle = ColorUtils.transparentize(root.color, 1 - root.fillOpacity)
        ctx.lineWidth = 2
        ctx.beginPath()
        var firstX = -1
        var lastX = 0
        for (var i = 0; i < n; ++i) {
            var valueIndex = (root.alignment === Graph.Alignment.Right) ? root.values.length - n + i : i
            if (valueIndex < 0 || valueIndex >= root.values.length) {
                continue; // No data for this point
            }
            var x = i * dx
            var norm = root.values[valueIndex] // already in 0-1 range
            var y = height - norm * height
            if (firstX < 0) {
                firstX = x
                ctx.moveTo(x, y)
            } else {
                ctx.lineTo(x, y)
            }
            lastX = x
        }
        // Only the data line is stroked. The path used to start at the bottom, so
        // the stroke also drew the plot's left edge, which lands on the left of a
        // well the plot fills: a 1px border on one side only.
        ctx.stroke()
        ctx.lineTo(lastX, height)
        ctx.lineTo(firstX, height)
        ctx.fill()
        ctx.restore()
    }
}
