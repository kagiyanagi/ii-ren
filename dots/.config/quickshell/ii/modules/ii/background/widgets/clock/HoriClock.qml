pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_hori"

    readonly property real contentScale: (Config.options.background.widgets.clock_hori.widgetSize ?? 100) / 100.0

    // The 320×200 canvas the layout fractions below were authored against. The
    // widget's own box is the digit ink inside it (see glyphInk), not this
    // canvas: a glyph tile is a Text line box, taller than the digits by the
    // font's ascent/descent leading and wider by its side bearings, and the
    // tiles stop short of the canvas edge. Boxing the canvas would hand the
    // drag area, the snap edges and the resize grip a third of a widget's
    // worth of empty air.
    readonly property real designW: 320 * contentScale
    readonly property real designH: 200 * contentScale

    implicitWidth: glyphInk.boxWidth
    implicitHeight: glyphInk.boxHeight

    // ── Time extraction (same approach as FlexClock) ──
    readonly property string hour:   DateTime.time.split(":")[0].padStart(2, "0")
    readonly property string minute: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0")

    readonly property string d0: hour.charAt(0)
    readonly property string d1: hour.charAt(1)
    readonly property string d2: minute.charAt(0)
    readonly property string d3: minute.charAt(1)

    // ── Colors (WidgetColorScheme tokens, same pattern as FlexClock) ──
    readonly property bool useAltColors: Config.options.background.widgets.clock_hori.useAltColors ?? false
    readonly property color tintSoft: useAltColors ? WidgetColorScheme.cardBgColor : WidgetColorScheme.textColorOnBg
    readonly property color tintBold: WidgetColorScheme.accentColor

    // ── Layout geometry (horizontal, on the 320×200 design canvas) ──
    readonly property real tileW:      root.designW * 0.22
    readonly property real tileH:      root.designH * 0.72
    readonly property real glyphSize:  root.designH * 0.60
    readonly property real posY:       root.designH * 0.14

    readonly property real pos0X:      root.designW * 0.00
    readonly property real pos1X:      root.designW * 0.17
    readonly property real pos2X:      root.designW * 0.48
    readonly property real pos3X:      root.designW * 0.65

    readonly property real colonX:     root.designW * 0.43
    readonly property real colonDotSize: root.designH * 0.07
    readonly property real colonGap:   root.designH * 0.08

    readonly property real fringeSize: root.designH * 0.02

    // Digit ink inside the tiles: the box, and the offset that lands the ink
    // on it. The colon sits between the middle tiles, well inside this.
    GlyphTileInk {
        id: glyphInk
        tileFont: glyphFont.font
        tileWidth: root.tileW
        tileHeight: root.tileH
        leftTileX: root.pos0X
        rightTileX: root.pos3X
        topTileY: root.posY
        bottomTileY: root.posY
    }

    // One shared definition of the tile face, so the measured ink and the
    // drawn glyphs can never drift apart. StyledText would impose its own
    // family, and Qt.font() silently drops variableAxes, which is what
    // carries the wght 1000 these glyphs are cut at.
    // design-ok: a font value, not text — it draws nothing.
    Text {
        id: glyphFont
        visible: false
        font {
            family: "Google Sans Flex"
            weight: 1000
            bold: true
            pixelSize: root.glyphSize
            variableAxes: ({ "wght": 1000 })
        }
    }

    // ── Fringe / stroke samples (PixelClock style) ──
    function ringSamples(count, radius) {
        let pts = [{ dx: 0, dy: 0 }]
        for (let i = 0; i < count; i++) {
            const a = (i / count) * Math.PI * 2
            pts.push({ dx: Math.cos(a) * radius, dy: Math.sin(a) * radius })
        }
        return pts
    }
    readonly property var fringeSamples: ringSamples(16, root.fringeSize)

    // ── Drop shadow ──
    StyledDropShadow {
        id: glyphShadow
        target: glyphStage
        visible: Config.options.background.widgets.enableShadows ?? false
    }

    // ── Main stage ──
    Item {
        id: glyphStage
        // The design canvas, shifted so its digit ink sits on the widget's box.
        // The slack it carries outside that box draws nothing.
        x: -glyphInk.left
        y: -glyphInk.top
        width: root.designW
        height: root.designH

        component GlyphTile: Text {
            width: root.tileW
            height: root.tileH
            font: glyphFont.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        // ── Layer 0: d0 (H0) cut by d1, d2, d3 ──
        Item {
            id: layer0Face
            anchors.fill: parent
            visible: false
            GlyphTile {
                x: root.pos0X; y: root.posY
                text: root.d0; color: root.tintSoft
            }
        }
        Item {
            id: layer0Punch
            anchors.fill: parent
            visible: false
            Repeater {
                model: root.fringeSamples
                Item {
                    required property var modelData
                    anchors.fill: parent
                    GlyphTile { x: root.pos1X + modelData.dx; y: root.posY + modelData.dy; text: root.d1; color: "black" }
                    GlyphTile { x: root.pos2X + modelData.dx; y: root.posY + modelData.dy; text: root.d2; color: "black" }
                    GlyphTile { x: root.pos3X + modelData.dx; y: root.posY + modelData.dy; text: root.d3; color: "black" }
                }
            }
        }
        OpacityMask {
            anchors.fill: parent
            source: layer0Face
            maskSource: layer0Punch
            invert: true
            z: 0
        }

        // ── Layer 1: d1 (H1) cut by d2, d3 ──
        Item {
            id: layer1Face
            anchors.fill: parent
            visible: false
            GlyphTile {
                x: root.pos1X; y: root.posY
                text: root.d1; color: root.tintBold
            }
        }
        Item {
            id: layer1Punch
            anchors.fill: parent
            visible: false
            Repeater {
                model: root.fringeSamples
                Item {
                    required property var modelData
                    anchors.fill: parent
                    GlyphTile { x: root.pos2X + modelData.dx; y: root.posY + modelData.dy; text: root.d2; color: "black" }
                    GlyphTile { x: root.pos3X + modelData.dx; y: root.posY + modelData.dy; text: root.d3; color: "black" }
                }
            }
        }
        OpacityMask {
            anchors.fill: parent
            source: layer1Face
            maskSource: layer1Punch
            invert: true
            z: 1
        }

        // ── Layer 2: d2 (M0) cut by d3 ──
        Item {
            id: layer2Face
            anchors.fill: parent
            visible: false
            GlyphTile {
                x: root.pos2X; y: root.posY
                text: root.d2; color: root.tintBold
            }
        }
        Item {
            id: layer2Punch
            anchors.fill: parent
            visible: false
            Repeater {
                model: root.fringeSamples
                Item {
                    required property var modelData
                    anchors.fill: parent
                    GlyphTile { x: root.pos3X + modelData.dx; y: root.posY + modelData.dy; text: root.d3; color: "black" }
                }
            }
        }
        OpacityMask {
            anchors.fill: parent
            source: layer2Face
            maskSource: layer2Punch
            invert: true
            z: 2
        }

        // ── Layer 3: d3 (M1) intact ──
        GlyphTile {
            x: root.pos3X; y: root.posY
            text: root.d3; color: root.tintSoft
            z: 3
        }

        // ── Colon separator between H1 and M0 ──
        Column {
            x: root.colonX
            y: root.posY + root.tileH / 2 - height / 2
            spacing: root.colonGap
            z: 4

            Rectangle {
                width: root.colonDotSize
                height: root.colonDotSize
                radius: width / 2
                color: root.tintBold
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Rectangle {
                width: root.colonDotSize
                height: root.colonDotSize
                radius: width / 2
                color: root.tintBold
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
