import QtQuick

/*
 * Where the digits actually land inside a run of `Text` glyph tiles.
 *
 * A glyph tile is a line box, not a glyph: it is taller than the digit it
 * draws by the font's ascent and descent leading, and wider by the glyph's
 * side bearings. A widget that sizes itself to its tiles therefore hands its
 * drag area, its snap edges and its resize grip a band of empty air on every
 * side — the grip ends up floating away from the art. Sizing to what this
 * reports instead makes the box hug the digits.
 *
 * Assumes the tiles centre their text on both axes (AlignHCenter/AlignVCenter),
 * which is what a fixed-size glyph tile does.
 *
 * Measured off fixed reference strings rather than the digits on screen, so
 * the box stays put as the time changes: `0123456789` spans the highest and
 * lowest digit ink in the face, and `0` is the widest digit in Google Sans
 * Flex at wght 1000 (measured across all ten), so any time fits the result.
 */
QtObject {
    id: root

    // The tiles' font, and the box of one tile.
    property font tileFont
    property real tileWidth: 0
    property real tileHeight: 0

    // Origins of the tiles that bound the run, in the caller's own coordinates.
    property real leftTileX: 0
    property real rightTileX: 0
    property real topTileY: 0
    property real bottomTileY: 0

    property TextMetrics widestDigit: TextMetrics {
        font: root.tileFont
        text: "0"
    }
    property TextMetrics digitRun: TextMetrics {
        font: root.tileFont
        text: "0123456789"
    }

    // boundingRect is the line box with its origin on the baseline, so its `y`
    // is -ascent; tightBoundingRect is the ink in that same space.
    readonly property real _baselineInTile: (root.tileHeight - digitRun.boundingRect.height) / 2 - digitRun.boundingRect.y
    readonly property real _inkTopInTile: _baselineInTile + digitRun.tightBoundingRect.y
    readonly property real _inkLeftInTile: (root.tileWidth - widestDigit.advanceWidth) / 2 + widestDigit.tightBoundingRect.x

    // Ink bounds of the whole run, in the caller's coordinates.
    readonly property real left: root.leftTileX + _inkLeftInTile
    readonly property real top: root.topTileY + _inkTopInTile
    readonly property real right: root.rightTileX + _inkLeftInTile + widestDigit.tightBoundingRect.width
    readonly property real bottom: root.bottomTileY + _inkTopInTile + digitRun.tightBoundingRect.height

    readonly property real boxWidth: Math.max(1, right - left)
    readonly property real boxHeight: Math.max(1, bottom - top)
}
