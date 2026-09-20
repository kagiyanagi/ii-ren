import QtQuick
import qs.modules.common
import qs.modules.common.functions

Canvas {
    id: root
    property color color: Appearance.colors.colOnLayer0
    property int dashLength: 6
    property int gapLength: 4
    property int borderWidth: 1

    // Canvas repaints on request only, so every property onPaint reads needs
    // one - colour above all, since it follows the wallpaper theme.
    onColorChanged: requestPaint()
    onBorderWidthChanged: requestPaint()
    onDashLengthChanged: requestPaint()
    onGapLengthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        ctx.save();
        ctx.strokeStyle = root.color;
        ctx.lineWidth = root.borderWidth;
        if (root.gapLength > 0) {
            ctx.setLineDash([root.dashLength, root.gapLength]); // Set dash pattern
        }
        ctx.strokeRect(root.borderWidth / 2, root.borderWidth / 2, width - root.borderWidth, height - root.borderWidth); // Draw it
        ctx.restore();
    }
}
