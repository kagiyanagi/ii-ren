import QtQuick
import QtQuick.Layouts
import qs.modules.common

/**
 * Grouped settings list, Android 16 QPR2 style: plain rows sit on their own
 * card, and a run of them is rounded harder on the outside than on the seams
 * between rows so the run still reads as one block.
 *
 * Cards are opt-in (`wantsCard`). Anything that already paints its own
 * background - text fields, notice boxes, whole custom panels - stays bare
 * rather than picking up a second slab behind it.
 */
Item {
    id: root
    property color cardColor: Appearance.colors.colSurfaceContainerHigh
    property real horizontalBleed: 8
    property real outerRadius: Appearance.rounding.large
    property real innerRadius: Appearance.rounding.verysmall
    default property alias contentData: column.data

    Layout.fillWidth: true
    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    Repeater {
        model: column.visibleChildren.length

        Rectangle {
            id: card
            required property int index
            readonly property var rows: column.visibleChildren
            readonly property Item row: rows[index] ?? null
            readonly property bool carded: row?.wantsCard === true && (row?.height ?? 0) > 0
            // A chip group fills its cell but only draws across part of it, so
            // hug it - otherwise the card trails dead space past the last chip.
            // Mirror its own left padding on the right so both gaps match.
            readonly property real cardWidth: (row?.hugCard === true && row.implicitWidth > 0)
                ? Math.min(row.implicitWidth + (row.leftPadding ?? root.horizontalBleed), root.width)
                : root.width
            // Corners are per run, not per group: a card next to a bare row is
            // the end of its run and gets the outer radius there.
            // What actually paints on this card: the row itself, or - when the
            // row is a container like ConfigRow - the tiles inside it.
            readonly property var tiles: (row?.buttonRadius !== undefined) ? [row] : (row?.visibleChildren ?? [])
            readonly property bool runStart: rows[index - 1]?.wantsCard !== true
            readonly property bool runEnd: rows[index + 1]?.wantsCard !== true

            visible: carded
            color: root.cardColor
            x: -root.horizontalBleed
            width: cardWidth + root.horizontalBleed * 2
            y: row?.y ?? 0
            height: row?.height ?? 0
            topLeftRadius: runStart ? root.outerRadius : root.innerRadius
            topRightRadius: topLeftRadius
            bottomLeftRadius: runEnd ? root.outerRadius : root.innerRadius
            bottomRightRadius: bottomLeftRadius

            Behavior on topLeftRadius {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on bottomLeftRadius {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            // A tile paints its own hover/pressed background on top of this
            // card. Left to its own fixed radius and width it squares off the
            // corners the card rounds and stops short of the card's edges, so
            // hover reads as a slab floating inside the card - hand each tile
            // the corners and reach the card actually has, on the sides where
            // the tile is the one touching that edge.
            Repeater {
                model: card.tiles.length

                Item {
                    required property int index
                    readonly property Item tile: card.tiles[index] ?? null
                    readonly property bool paints: card.carded && tile?.buttonRadius !== undefined && tile?.wantsCard === true
                    readonly property bool atLeft: index === 0
                    readonly property bool atRight: index === card.tiles.length - 1

                    Binding {
                        target: tile
                        property: "backgroundBleedLeft"
                        value: atLeft ? root.horizontalBleed : 0
                        when: paints
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    Binding {
                        target: tile
                        property: "backgroundBleedRight"
                        value: atRight ? root.horizontalBleed : 0
                        when: paints
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    Binding {
                        target: tile
                        property: "topLeftRadius"
                        value: atLeft ? card.topLeftRadius : root.innerRadius
                        when: paints
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    Binding {
                        target: tile
                        property: "topRightRadius"
                        value: atRight ? card.topRightRadius : root.innerRadius
                        when: paints
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    Binding {
                        target: tile
                        property: "bottomLeftRadius"
                        value: atLeft ? card.bottomLeftRadius : root.innerRadius
                        when: paints
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    Binding {
                        target: tile
                        property: "bottomRightRadius"
                        value: atRight ? card.bottomRightRadius : root.innerRadius
                        when: paints
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: 3
    }
}
