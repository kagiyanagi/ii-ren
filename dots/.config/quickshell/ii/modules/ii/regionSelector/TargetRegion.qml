pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root
    required property var clientDimensions
    // What the target settles at; the config keeps targets faint.
    required property real restingOpacity

    property bool showLabel: Config.options.regionSelector.targetRegions.showLabel
    property bool showIcon: false
    property bool targeted: false
    // Out of the way while a drag chooses its own region.
    property bool hidden: false
    property color borderColor
    property color fillColor: "transparent"
    property string text: ""
    z: 2
    color: fillColor
    border.color: borderColor
    border.width: targeted ? 4 : 2
    radius: Appearance.rounding.unsharpenmore

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    // Content regions arrive when detection finishes, after the window has
    // faded in, so each target fades in on its own. A Behavior never animates
    // the value a delegate is created with, hence the flag flipped after.
    property bool entered: false
    Component.onCompleted: root.entered = true
    opacity: root.entered && !root.hidden ? root.restingOpacity : 0
    visible: opacity > 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    x: clientDimensions.at[0]
    y: clientDimensions.at[1]
    width: clientDimensions.size[0]
    height: clientDimensions.size[1]

    // A plain tooltip's colours: a label floating over content it knows
    // nothing about, opaque so it reads over any of it.
    Loader {
        anchors {
            top: parent.top
            left: parent.left
            topMargin: 8
            leftMargin: 8
        }

        active: root.showLabel
        sourceComponent: Rectangle {
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colTooltip
            implicitWidth: regionInfoRow.implicitWidth + 8 * 2
            implicitHeight: regionInfoRow.implicitHeight + 4 * 2

            Row {
                id: regionInfoRow
                anchors.centerIn: parent
                spacing: 4

                Loader {
                    id: regionIconLoader
                    active: root.showIcon
                    visible: active
                    sourceComponent: IconImage {
                        implicitSize: Appearance.font.pixelSize.larger
                        source: Quickshell.iconPath(AppSearch.guessIcon(root.text), "image-missing")
                    }
                }

                StyledText {
                    id: regionText
                    text: root.text
                    color: Appearance.colors.colOnTooltip
                }
            }
        }
    }
}
