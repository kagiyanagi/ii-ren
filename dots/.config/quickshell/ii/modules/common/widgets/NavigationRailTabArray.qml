import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property int currentIndex: 0
    property bool expanded: false
    property bool _isInitialized: false
    Component.onCompleted: _isInitialized = true

    default property alias tabData: tabBarColumn.data
    implicitHeight: tabBarColumn.implicitHeight
    implicitWidth: tabBarColumn.implicitWidth
    Layout.topMargin: 24

    Rectangle {
        property real itemHeight: tabBarColumn.children[0]?.baseSize ?? 56
        property real baseHighlightHeight: tabBarColumn.children[0]?.baseHighlightHeight ?? 56
        anchors {
            top: tabBarColumn.top
            left: tabBarColumn.left
            topMargin: itemHeight * root.currentIndex + (root.expanded ? 0 : ((itemHeight - baseHighlightHeight) / 2))
        }
        radius: Appearance.rounding.full
        color: Appearance.colors.colSecondaryContainer
        implicitHeight: root.expanded ? itemHeight : baseHighlightHeight
        // Not children[currentIndex]: a Repeater parents each delegate at the end
        // (childrenChanged) and only then stacks it before itself, silently. So
        // while the last delegate is built, that slot holds the Repeater, and the
        // pill locks onto the 130 fallback until the tab changes.
        implicitWidth: tabBarColumn.children.filter(c => c.visualWidth !== undefined)[root.currentIndex]?.visualWidth ?? 130

        /*
         * This is the selection indicator, so all three legs ride
         * elementMoveSmall and it moves as one object (DESIGN.md 9). Its size
         * also changes when the rail expands, where 2.5 would want an
         * asymmetric pair -- but one Behavior cannot tell which cause moved it,
         * and tearing the pill's height away from its own travel is the worse
         * of the two. Height had no animation at all and simply jumped.
         */
        Behavior on implicitWidth {
            enabled: root._isInitialized

            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }

        Behavior on implicitHeight {
            enabled: root._isInitialized

            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }

        Behavior on anchors.topMargin {
            enabled: root._isInitialized

            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }
    }

    ColumnLayout {
        id: tabBarColumn
        anchors.fill: parent
        spacing: 0
    }
}
