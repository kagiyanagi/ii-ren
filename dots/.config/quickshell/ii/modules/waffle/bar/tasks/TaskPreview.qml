pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import Quickshell

PopupWindow {
    id: root

    ///////////////////// Properties ////////////////////
    required property bool tasksHovered
    property var appEntry
    property Item anchorItem

    //////////////////// Functions ////////////////////
    function close() {
        if (!root.visible) return;
        openAnim.stop();
        closeAnim.restart();
    }

    function open() {
        closeAnim.stop();
        contentItem.sourceEdgeMargin = -root.implicitHeight;
        root.visible = true;
        openAnim.restart();
    }

    function show(appEntry: var, button: Item) {
        root.appEntry = appEntry;
        root.anchorItem = button;
        root.anchor.updateAnchor();
        root.open();
    }

    ///////////////////// Internals /////////////////////
    readonly property bool bottom: Config.options.waffles.bar.bottom
    property real visualMargin: 12
    property real ambientShadowWidth: 1

    visible: false
    color: "transparent"
    implicitWidth: contentItem.implicitWidth + ambientShadowWidth + (visualMargin * 2)
    implicitHeight: contentItem.implicitHeight + ambientShadowWidth + (visualMargin * 2)
    anchor {
        adjustment: PopupAdjustment.Slide
        item: root.anchorItem
        gravity: bottom ? Edges.Top : Edges.Bottom
        edges: bottom ? Edges.Top : Edges.Bottom
    }

    Timer {
        interval: 250
        running: root.visible && !hoverChecker.containsMouse && !root.tasksHovered
        onTriggered: {
            root.close();
        }
    }

    PropertyAnimation {
        id: openAnim
        target: contentItem
        property: "sourceEdgeMargin"
        to: (root.ambientShadowWidth + root.visualMargin)
        duration: 200 // design-ok: Fluent popup entry
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
    }

    SequentialAnimation {
        id: closeAnim
        PropertyAnimation {
            target: contentItem
            property: "sourceEdgeMargin"
            to: -root.implicitHeight
            duration: 150 // design-ok: Fluent popup exit
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Looks.transition.easing.bezierCurve.easeOut
        }
        ScriptAction {
            script: {
                root.visible = false;
            }
        }
    }

    // Content
    MouseArea {
        id: hoverChecker
        anchors.fill: parent
        hoverEnabled: true

        // Shadow
        WAmbientShadow {
            target: contentItem
        }

        Rectangle {
            id: contentItem
            property real sourceEdgeMargin: -root.implicitHeight
            clip: true

            anchors {
                left: parent.left
                right: parent.right
                top: root.bottom ? undefined : parent.top
                bottom: root.bottom ? parent.bottom : undefined
                margins: root.ambientShadowWidth + root.visualMargin
                // Opening anim
                bottomMargin: root.bottom ? sourceEdgeMargin : (root.ambientShadowWidth + root.visualMargin)
                topMargin: root.bottom ? (root.ambientShadowWidth + root.visualMargin) : sourceEdgeMargin
            }
            color: Looks.colors.bg1Base
            radius: Looks.radius.large

            implicitHeight: Math.min(160, windowsRow.implicitHeight)
            implicitWidth: windowsRow.implicitWidth

            RowLayout {
                id: windowsRow
                anchors.fill: parent

                Repeater {
                    model: ScriptModel {
                        values: root.appEntry?.toplevels ?? []
                    }
                    delegate: WindowPreview {
                        required property var modelData
                        toplevel: modelData
                    }
                }
            }
        }
    }
}
