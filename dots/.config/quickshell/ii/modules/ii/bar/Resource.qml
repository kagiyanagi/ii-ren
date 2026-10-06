import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property string iconName
    required property double percentage
    property int warningThreshold: 100
    property bool shown: true
    clip: true
    visible: width > 0 && height > 0
    implicitWidth: resourceRowLayout.x < 0 ? 0 : resourceRowLayout.implicitWidth
    implicitHeight: Appearance.sizes.barHeight
    property string customText: ""
    property bool warning: percentage * 100 >= warningThreshold

    RowLayout {
        id: resourceRowLayout
        spacing: Config.options.bar.barGroupStyle === 3 ? 4 : 2
        x: shown ? 0 : -resourceRowLayout.width
        anchors {
            verticalCenter: parent.verticalCenter
        }

        ClippedFilledCircularProgress {
            id: resourceCircProg
            Layout.alignment: Qt.AlignVCenter
            lineWidth: Appearance.rounding.unsharpen
            value: percentage
            implicitSize: 20
            colPrimary: root.warning ? Appearance.colors.colError : Appearance.colors.colOnSecondaryContainer
            accountForLightBleeding: !root.warning
            enableAnimation: false

            // Crossing the threshold is a colour change, not a pulse (law 8).
            Behavior on colPrimary {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            Item {
                anchors.centerIn: parent
                width: resourceCircProg.implicitSize
                height: resourceCircProg.implicitSize
                
                MaterialSymbol {
                    anchors.centerIn: parent
                    font.weight: Font.DemiBold
                    fill: 1
                    text: iconName
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.max(fullPercentageTextMetrics.width, currentTextMetrics.width)
            implicitHeight: percentageText.implicitHeight

            TextMetrics {
                id: fullPercentageTextMetrics
                text: "100"
                font.pixelSize: Appearance.font.pixelSize.small
            }

            TextMetrics {
                id: currentTextMetrics
                text: root.customText.length > 0 ? root.customText : `${Math.round(percentage * 100).toString()}`
                font.pixelSize: Appearance.font.pixelSize.small
            }

            StyledText {
                id: percentageText
                anchors.centerIn: parent
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                text: root.customText.length > 0 ? root.customText : `${Math.round(percentage * 100).toString()}`
            }
        }

        Behavior on x {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
    }

    // The slide-out (`x`) and the collapse (`implicitWidth`) are one movement and
    // travel on one spec, so the row cannot leave its own gap behind.
    Behavior on implicitWidth {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
}
