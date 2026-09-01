import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

/**
 * A progress bar with both ends rounded and text acts as clipping like OneUI 7's battery indicator.
 */
ProgressBar {
    id: root
    padding: 0
    topPadding: 0
    bottomPadding: 0
    leftPadding: 0
    rightPadding: 0
    property bool vertical: false
    property real valueBarWidth: 30
    property real valueBarHeight: 18
    property color highlightColor: Appearance?.colors.colOnSecondaryContainer ?? "#685496"
    property color trackColor: ColorUtils.transparentize(highlightColor, 0.5) ?? "#F1D3F9"
    property alias radius: contentItem.radius
    property string text
    default property Item textMask: Item {
        width: valueBarWidth
        height: valueBarHeight
        StyledText {
            anchors.centerIn: parent
            font: root.font
            text: root.text
        }
    }

    text: Math.round(value * 100)
    font {
        pixelSize: 13
        weight: text.length > 2 ? 575 : 675
    }

    background: Item {
        implicitHeight: valueBarHeight
        implicitWidth: valueBarWidth
    }

    contentItem: Rectangle {
        id: contentItem
        anchors.fill: parent
        radius: 9999
        color: root.trackColor
        visible: false

        Rectangle {
            id: progressFill
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
                right: undefined
            }
            width: parent.width * root.visualPosition
            height: parent.height

            states: State {
                name: "vertical"
                when: root.vertical
                AnchorChanges {
                    target: progressFill
                    anchors {
                        top: undefined
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                    }
                }
                PropertyChanges {
                    target: progressFill
                    width: parent.width
                    height: parent.height * root.visualPosition
                }
            }

            radius: Appearance.rounding.unsharpen
            color: root.highlightColor
        }
    }

    // The bar itself, rounded to the pill silhouette.
    OpacityMask {
        anchors.fill: parent
        source: contentItem
        maskSource: Rectangle {
            width: contentItem.width
            height: contentItem.height
            radius: contentItem.radius
        }
    }

    // The same bar with the fill and track colours swapped, painted only inside
    // the glyphs, so text and icons read as the exact inverse of whatever is
    // behind them. Masking to the glyphs rather than punching them out keeps
    // this off the rounded corners, which it would otherwise square off.
    Rectangle {
        id: inverseContent
        visible: false
        anchors.fill: parent
        color: root.highlightColor

        Rectangle {
            x: progressFill.x
            y: progressFill.y
            width: progressFill.width
            height: progressFill.height
            radius: progressFill.radius
            color: root.trackColor
        }
    }

    OpacityMask {
        anchors.fill: parent
        source: inverseContent
        maskSource: root.textMask
    }
}
