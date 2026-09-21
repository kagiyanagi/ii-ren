pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Successive ionisation enthalpies as horizontal bars.
 *
 * The point of the chart is the *jump* -- the step where the next electron has
 * to come out of a full shell -- so the bars are on a linear scale against the
 * largest value shown, which is what makes that step obvious. Every bar is
 * directly labelled, so the colour carries no information on its own.
 */
ColumnLayout {
    id: root
    required property var values
    required property color accent

    readonly property real maximum: {
        let max = 0;
        for (let i = 0; i < root.values.length; i++)
            max = Math.max(max, root.values[i]);
        return max;
    }

    spacing: 6

    Repeater {
        model: root.values
        delegate: RowLayout {
            id: bar
            required property int index
            required property real modelData
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.preferredWidth: 32
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colSubtext
                text: `ΔH${bar.index + 1}`
            }

            Item { // the track, so every bar shares one baseline
                id: track
                Layout.fillWidth: true
                implicitHeight: 14

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: 10
                    width: root.maximum > 0
                        ? Math.max(4, track.width * (bar.modelData / root.maximum))
                        : 0
                    radius: Appearance.rounding.verysmall
                    color: root.accent
                    Behavior on width {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
            }

            StyledText {
                Layout.preferredWidth: 64
                horizontalAlignment: Text.AlignRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colOnLayer2
                text: Math.round(bar.modelData)
            }
        }
    }

    StyledText {
        visible: root.values.length === 0
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
        text: Translation.tr("Not measured")
    }
}
