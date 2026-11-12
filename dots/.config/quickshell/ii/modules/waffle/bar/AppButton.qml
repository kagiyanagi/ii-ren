pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import qs.services
import qs.modules.common
import qs.modules.waffle.looks

BarButton {
    id: root

    required property string iconName
    property bool multiple: false
    property bool separateLightDark: false
    property alias tryCustomIcon: iconWidget.tryCustomIcon
    leftInset: 2
    rightInset: 2
    implicitWidth: height - topInset - bottomInset + leftInset + rightInset

    property real pressedScale: 5/6

    background: Item {
        id: background
        BackgroundAcrylicRectangle {
            id: mainBgRect
            anchors.fill: parent
            layer.enabled: root.multiple
            layer.effect: OpacityMask {
                invert: true
                maskSource: Item {
                    width: mainBgRect.width
                    height: mainBgRect.height
                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: 4
                        radius: mainBgRect.radius
                    }
                }
            }
        }
        Loader {
            anchors.fill: parent
            anchors.rightMargin: 4
            active: root.multiple
            sourceComponent: BackgroundAcrylicRectangle {}
        }
    }

    contentItem: Item {
        id: contentItem

        implicitHeight: iconWidget.implicitHeight
        implicitWidth: iconWidget.implicitWidth
        // Read by the Behaviors below: set from inside the driving binding, which runs
        // before the Behavior bakes its spec (DESIGN.md 2.9); a ternary on the state
        // itself could run the exit on the enter's spec.
        property bool pressing: false
        readonly property int pressDuration: pressing ? 150 : 200 // design-ok: Fluent button press micro-interaction
        readonly property var pressCurve: pressing ? Looks.transition.easing.bezierCurve.easeIn : Looks.transition.easing.bezierCurve.easeOut
        scale: {
            contentItem.pressing = root.down;
            return root.down ? root.pressedScale : 1;
        }

        Behavior on scale {
            NumberAnimation {
                id: scaleAnim
                duration: contentItem.pressDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: contentItem.pressCurve
            }
        }

        WAppIcon {
            id: iconWidget
            anchors.centerIn: parent
            iconName: root.iconName
            separateLightDark: root.separateLightDark
        }
    }

    component BackgroundAcrylicRectangle: AcrylicRectangle {
        shiny: ((root.hovered && !root.down) || root.checked)
        color: root.color
        border.width: 1
        border.color: root.colBackgroundBorder

        Behavior on border.color {
            animation: Looks.transition.color.createObject(this)
        }
    }
}
