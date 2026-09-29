import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// One tile of a 2x2 grid of facts: About's hardware, Battery's health. `corner`
// is its place in the grid (0 top-left .. 3 bottom-right): the grid's outside
// corners take the large radius and its seams the small one, as ContentGroup
// rounds a list.
Rectangle {
    id: spec
    property int corner
    property string icon
    property string label
    property string value
    property string detail
    property real usage: -1 // 0..1 draws a bar under the value

    readonly property real outer: Appearance.rounding.large
    readonly property real inner: Appearance.rounding.verysmall

    Layout.fillWidth: true
    Layout.fillHeight: true
    implicitHeight: specBody.implicitHeight + 32
    color: Appearance.colors.colSurfaceContainerHigh
    topLeftRadius: corner === 0 ? outer : inner
    topRightRadius: corner === 1 ? outer : inner
    bottomLeftRadius: corner === 2 ? outer : inner
    bottomRightRadius: corner === 3 ? outer : inner

    ColumnLayout {
        id: specBody
        anchors.fill: parent
        anchors.margins: 16
        spacing: 4

        RowLayout {
            spacing: 8
            MaterialSymbol {
                text: spec.icon
                iconSize: Appearance.font.pixelSize.larger
                fill: 1
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                text: spec.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: spec.value
            font.pixelSize: Appearance.font.pixelSize.large
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }
        Item { Layout.fillHeight: true }
        StyledProgressBar {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: spec.usage >= 0
            value: Math.max(0, spec.usage)
            valueBarHeight: 8
        }
        StyledText {
            Layout.fillWidth: true
            visible: spec.detail !== ""
            text: spec.detail
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
