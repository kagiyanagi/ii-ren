pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Successive ionisation enthalpies as columns, first to last.
 *
 * The point of the chart is the *jump* -- the step where the next electron has
 * to come out of a full shell -- so the columns are on a linear scale against
 * the largest value shown, and they stand side by side so the jump reads as a
 * step up. Every column carries its value and its ordinal, so the colour says
 * nothing on its own.
 *
 * The data never holds more than four values, so the columns take a quarter of
 * the width each, whatever the count: the first ionisation sits in the same
 * place for every element, and one value is one column, not a slab.
 */
Item {
    id: root
    required property var values
    required property color accent
    // 0 -> 1 as the card opens; the columns grow out of the baseline on it.
    property real progress: 1

    readonly property int slots: 4
    readonly property real maximum: {
        let max = 0;
        for (let i = 0; i < root.values.length; i++)
            max = Math.max(max, root.values[i]);
        return max;
    }
    readonly property list<string> ordinals: [
        Translation.tr("1st"), Translation.tr("2nd"), Translation.tr("3rd"), Translation.tr("4th")
    ]

    implicitHeight: 96

    Row {
        id: columns
        anchors.fill: parent
        spacing: 12
        visible: root.values.length > 0

        Repeater {
            model: root.values.slice(0, root.slots)
            delegate: ColumnLayout {
                id: column
                required property int index
                required property real modelData
                width: (columns.width - columns.spacing * (root.slots - 1)) / root.slots
                height: columns.height
                spacing: 4

                Item { // the column's full height, so every bar shares one baseline
                    id: track
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        id: bar
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(track.width, 40)
                        // The value rides on top of its column, so the room it
                        // needs comes off the scale rather than off the top.
                        height: root.maximum > 0
                            ? Math.max(width / 2, (track.height - reading.height - 4) * (column.modelData / root.maximum) * root.progress)
                            : 0
                        // The top is round and the foot sits square on the
                        // baseline, the way a column grows out of an axis.
                        topLeftRadius: Appearance.rounding.small
                        topRightRadius: Appearance.rounding.small
                        bottomLeftRadius: Appearance.rounding.unsharpenmore
                        bottomRightRadius: Appearance.rounding.unsharpenmore
                        color: root.accent
                    }

                    StyledText {
                        id: reading
                        anchors.bottom: bar.top
                        anchors.bottomMargin: 4
                        anchors.horizontalCenter: bar.horizontalCenter
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.variableAxes: Appearance.font.variableAxes.title
                        color: Appearance.colors.colOnLayer1
                        text: Math.round(column.modelData)
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                    text: root.ordinals[column.index] ?? ""
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.values.length === 0
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnSurfaceVariant
        text: Translation.tr("Not measured")
    }
}
