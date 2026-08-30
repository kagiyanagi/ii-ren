import qs.modules.common
import qs.modules.common.widgets
import QtQuick

GroupButton {
    id: button
    property string buttonIcon
    // Tiles fill only while on; the dashboard header row is filled either way,
    // the way Android draws its header icons.
    property real iconFill: toggled ? 1 : 0
    baseWidth: 40
    baseHeight: 40
    clickedWidth: baseWidth + 20
    toggled: false

    readonly property bool sharpMode: Config.options.appearance.sharpMode
    buttonRadius: (altAction && toggled) ? Appearance?.rounding.normal : sharpMode ? 0 : Math.min(baseHeight, baseWidth) / 2
    buttonRadiusPressed: Appearance?.rounding?.small

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        iconSize: 22
        fill: button.iconFill
        color: toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: buttonIcon

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

}
