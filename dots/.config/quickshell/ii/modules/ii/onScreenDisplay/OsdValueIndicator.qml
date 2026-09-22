import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

Item {
    id: root
    required property real value
    required property string icon
    required property string name
    property var shape
    property bool rotateIcon: false
    property bool scaleIcon: false
    property real maxLimit: 1.0
    property alias from: valueProgressBar.from
    property alias to: valueProgressBar.to

    property real valueIndicatorVerticalPadding: 8
    property real valueIndicatorLeftPadding: 16
    property real valueIndicatorRightPadding: 16 // An icon is circle ish, a column isn't, hence the extra padding

    implicitWidth: Appearance.sizes.osdWidth + 2 * Appearance.sizes.elevationMargin
    implicitHeight: valueIndicator.implicitHeight + 2 * Appearance.sizes.elevationMargin

    StyledRectangularShadow {
        target: valueIndicator
    }
    Rectangle {
        id: valueIndicator
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        radius: Appearance.rounding.full
        color: Appearance.m3colors.m3surfaceContainer

        implicitWidth: valueRow.implicitWidth
        implicitHeight: valueRow.implicitHeight

        RowLayout { // Icon on the left, stuff on the right
            id: valueRow
            anchors.fill: parent
            spacing: 16

            Item {
                implicitWidth: 30
                implicitHeight: 35
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: valueIndicatorLeftPadding
                Layout.topMargin: valueIndicatorVerticalPadding
                Layout.bottomMargin: valueIndicatorVerticalPadding

                MaterialShapeWrappedMaterialSymbol {
                    id: symbolWrapper
                    rotation: root.value * 360
                    anchors.centerIn: parent
                    iconSize: Appearance.font.pixelSize.huge
                    shape: root.shape
                    text: root.icon

                    // Rotation is spatial and may overshoot; elementMoveSmall is the
                    // fast-spatial spec at the same 350ms this was hand-written to.
                    Behavior on rotation {
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                    }

                    color: root.value > root.maxLimit ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
                    colSymbol: root.value > root.maxLimit ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    Behavior on colSymbol {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
            ColumnLayout { // Stuff
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: valueIndicatorRightPadding
                spacing: 4

                RowLayout { // Name fill left, value on the right end
                    Layout.leftMargin: valueProgressBar.height / 2 // Align text with progressbar radius curve's left end
                    Layout.rightMargin: valueProgressBar.height / 2 // Align text with progressbar radius curve's left end

                    StyledText {
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.small
                        Layout.fillWidth: true
                        text: root.name
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }

                    StyledText {
                        color: Appearance.colors.colOnLayer0
                        // Tabular figures: the number changes every frame of a drag and
                        // proportional digits shift the label beside it as it does.
                        font {
                            family: Appearance.font.family.numbers
                            pixelSize: Appearance.font.pixelSize.small
                            features: { "tnum": 1 }
                        }
                        Layout.fillWidth: false
                        Layout.preferredWidth: 36
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(root.value * 100)
                        wrapMode: Text.NoWrap
                    }
                }

                StyledProgressBar {
                    id: valueProgressBar
                    Layout.fillWidth: true
                    value: root.value
                }
            }
        }
    }
}