import QtQuick

/*
 * Raster content — a Canvas, or anything behind `layer.enabled` — rasterises at
 * its own item size and is then stretched by the ancestor Item.scale that makes
 * a desktop widget bigger. That stretch is a bilinear upsample of a finished
 * bitmap, which is where the jagged or blurry edges on clock dials and widgets come from.
 *
 * This wrapper keeps its own layout box at the natural size, but hands its
 * child a box `factor` times larger and scales that back down with supersampling.
 * The child's paint code is untouched — it still draws in terms of its own width/height —
 * so it produces the picture at double or higher resolution, rendering ultra-sharp.
 */
Item {
    id: root

    // Usually bound to AbstractBackgroundWidget.renderScale.
    property real factor: 1
    // Baseline 2x supersampling ensures crystal-clear rendering even at 100% scale
    readonly property real _f: Math.max(2, Math.min(4, root.factor * 2))

    default property alias content: holder.data

    Item {
        id: holder
        width: root.width * root._f
        height: root.height * root._f
        // Top-left origin so the shrink lands the child exactly back on the
        // wrapper's box instead of around its centre.
        transformOrigin: Item.TopLeft
        scale: 1 / root._f
    }
}
