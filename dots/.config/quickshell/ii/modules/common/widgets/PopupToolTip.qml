pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property string text: ""
    property bool extraVisibleCondition: true
    property bool alternativeVisibleCondition: false
    property real horizontalPadding: 10
    property real verticalPadding: 6
    property real horizontalMargin: horizontalPadding
    property real verticalMargin: verticalPadding
    // The same hover-intent wait StyledToolTip takes (DESIGN.md 9). A caller that
    // already gates its own condition on a timer passes 0.
    property int delay: 500

    function updateAnchor() {
        tooltipLoader.item?.anchor.updateAnchor();
    }

    // parent is briefly null while a tooltip's owner is still being parented, and
    // the unguarded read threw there -- the same fix StyledToolTip already has.
    readonly property bool internalVisibleCondition: (extraVisibleCondition && parent !== null && (parent.hovered === undefined || parent.hovered)) || alternativeVisibleCondition
    readonly property bool shown: root.internalVisibleCondition && hoverDelay.elapsed
    property var anchorEdges: Edges.Top
    property var anchorGravity: anchorEdges

    property Item contentItem: StyledToolTipContent {
        id: contentItem
        anchors.centerIn: parent
        text: root.text
        horizontalPadding: root.horizontalPadding
        verticalPadding: root.verticalPadding
    }

    Timer {
        id: hoverDelay
        property bool elapsed: false
        interval: root.delay
        running: root.internalVisibleCondition
        onTriggered: hoverDelay.elapsed = true
        onRunningChanged: if (!running) hoverDelay.elapsed = false
    }

    /**
     * The window used to be mapped and unmapped with nothing in either direction
     * (DESIGN.md 2.5, anti-pattern 10). The fade lives on root rather than on the
     * content so that a caller which swaps contentItem out -- WPopupToolTip does
     * -- gets it too, and so the loader can read it and stay alive until the exit
     * has finished. Spec picked inside the binding that writes it, per 2.9.
     */
    property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
    property real contentOpacity: {
        root.fadeSpec = root.shown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
        return root.shown ? 1 : 0;
    }
    Behavior on contentOpacity {
        NumberAnimation {
            duration: root.fadeSpec.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.fadeSpec.bezierCurve
        }
    }
    Binding {
        target: root.contentItem
        property: "opacity"
        value: root.contentOpacity
    }

    Loader {
        id: tooltipLoader
        anchors.fill: parent
        active: root.shown || root.contentOpacity > 0
        sourceComponent: PopupWindow {
            visible: true
            anchor {
                window: root.QsWindow.window
                item: root.parent
                edges: root.anchorEdges
                gravity: root.anchorGravity
            }
            mask: Region {
                item: null
            }

            color: "transparent"
            implicitWidth: root.contentItem.implicitWidth + root.horizontalMargin * 2
            implicitHeight: root.contentItem.implicitHeight + root.verticalMargin * 2

            data: [root.contentItem]
        }
    }
}
