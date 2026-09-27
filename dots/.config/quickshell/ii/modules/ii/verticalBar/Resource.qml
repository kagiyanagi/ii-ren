import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    required property string iconName
    required property double percentage
    property int warningThreshold: 100
    property bool shown: true
    visible: shown
    implicitHeight: shown ? resourceProgress.implicitHeight : 0
    implicitWidth: shown ? Appearance.sizes.verticalBarWidth : 0

    property bool warning: percentage * 100 >= warningThreshold

    // The horizontal bar's ring (bar/Resource.qml), without the number.
    ClippedFilledCircularProgress {
        id: resourceProgress
        anchors.centerIn: parent
        implicitSize: 20
        lineWidth: Appearance.rounding.unsharpen
        value: root.percentage
        enableAnimation: false
        colPrimary: root.warning ? Appearance.colors.colError : Appearance.colors.colOnSecondaryContainer
        accountForLightBleeding: !root.warning

        Behavior on colPrimary {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // The ring's OpacityMask stretches its mask over the whole ring, so the
        // mask has to be the ring's size with the icon centred in it. A bare
        // MaterialSymbol here was drawn stretched from its glyph box.
        Item {
            width: resourceProgress.implicitSize
            height: resourceProgress.implicitSize

            MaterialSymbol {
                anchors.centerIn: parent
                font.weight: Font.DemiBold
                fill: 1
                text: root.iconName
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }
}
