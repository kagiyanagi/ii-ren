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
        }
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: 3
    }
}
