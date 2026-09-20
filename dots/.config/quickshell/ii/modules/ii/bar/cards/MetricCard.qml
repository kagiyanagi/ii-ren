import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.animations

Rectangle {
    id: root

    radius: Appearance.rounding.normal
    color: Appearance.colors.colSurfaceContainerHigh
    implicitWidth: rowLayout.implicitWidth + 24
    implicitHeight: rowLayout.implicitHeight + 20
    Layout.fillWidth: true

    property alias title: title.text
    property alias value: value.text
    property string symbol: ""
    property string shapeString: "Slanted"
    property color accentColor: Appearance.colors.colPrimaryContainer
    property color symbolColor: Appearance.colors.colOnPrimaryContainer
    
    // Internal animation control
    property bool startAnim: false
    property int animDelay: 0

    // One entrance for the whole tile: opacity on an effects spec, one
    // transform on the enter spec (DESIGN.md 2.1/2.5). The icon, title and
    // value used to enter separately inside a tile that is itself entering
    // inside a popup that is itself scaling open -- three choreographies deep.
    onStartAnimChanged: {
        if (!root.startAnim) return;
        root.opacity = 0;
        root.scale = 0.9;
        Qt.callLater(() => enterAnim.restart());
    }

    ParallelAnimation {
        id: enterAnim

        DelayedPropertyAnimation {
            target: root
            property: "opacity"
            from: 0
            to: 1
            delay: root.animDelay
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
        DelayedPropertyAnimation {
            target: root
            property: "scale"
            from: 0.9
            to: 1
            delay: root.animDelay
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }

    RowLayout {
        id: rowLayout
        spacing: 12
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
            leftMargin: 12
        }

        MaterialShape {
            id: iconShape
            shapeString: root.shapeString
            implicitSize: 36
            color: root.accentColor

            MaterialSymbol {
                id: symbolIcon
                anchors.centerIn: parent
                text: root.symbol
                fill: 0
                iconSize: Appearance.font.pixelSize.normal
                color: root.symbolColor
            }
        }

        ColumnLayout {
            spacing: 0

            StyledText {
                id: title
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                font.weight: Font.DemiBold
            }

            StyledText {
                id: value
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurface
                font.weight: Font.Bold
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
