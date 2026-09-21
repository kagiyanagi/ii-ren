pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

StyledFlickable {
    id: root

    required property int length
    property int selectionStart
    property int selectionEnd
    property int cursorPosition

    property color color: Appearance.colors.colPrimary
    property color selectedTextColor: Appearance.colors.colOnSecondaryContainer
    property color selectionColor: Appearance.colors.colSecondaryContainer

    property int charSize: 20
    // The shape inside the cell, so the two cannot drift apart.
    property int charShapeSize: 18

    contentWidth: dotsRow.implicitWidth
    contentX: (Math.max(contentWidth - width, 0))
    Behavior on contentX {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    Rectangle {
        id: cursor
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            leftMargin: root.charSize * root.cursorPosition
        }
        color: root.color
        implicitWidth: 2
        implicitHeight: root.charSize
        Behavior on anchors.leftMargin {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(cursor)
        }
    }

    Row {
        id: dotsRow
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
            leftMargin: 4 - 5 // -5 to account for spacing being simulated by char item width
        }
        spacing: 0

        ListModel {
            id: charsModel
        }

        Connections {
            target: root
            function onLengthChanged() {
                while (charsModel.count < root.length) {
                    charsModel.append({});
                }
                while (charsModel.count > root.length) {
                    charsModel.remove(charsModel.count - 1);
                }
            }
        }
        
        Component.onCompleted: {
            while (charsModel.count < root.length) {
                charsModel.append({});
            }
        }

        Repeater {
            model: charsModel

            delegate: Rectangle {
                id: charItem
                required property int index
                implicitWidth: root.charSize
                implicitHeight: root.charSize
                property bool selected: index >= root.selectionStart && index < root.selectionEnd

                color: ColorUtils.transparentize(root.selectionColor, selected ? 0 : 1)

                MaterialShape {
                    id: materialShape
                    anchors.centerIn: parent
                    property list<var> charShapes: [
                        MaterialShape.Shape.Clover4Leaf,
                        MaterialShape.Shape.Arrow,
                        MaterialShape.Shape.Pill,
                        MaterialShape.Shape.SoftBurst,
                        MaterialShape.Shape.Diamond,
                        MaterialShape.Shape.ClamShell,
                        MaterialShape.Shape.Pentagon,
                    ]
                    shape: charShapes[charItem.index % charShapes.length]
                    color: charItem.selected ? root.selectedTextColor : Appearance.colors.colOnLayer1
                    implicitSize: 0
                    opacity: 0
                    scale: 0.5
                    Component.onCompleted: {
                        appearAnim.start();
                    }
                    /*
                     * A char landing: size and scale are spatial and small, so
                     * they ride the fast spatial spec and may overshoot; the
                     * fade and the accent settling out of colPrimary are effects
                     * and may not. Three of these four were assembled from parts
                     * of different specs -- an exit duration on a fade in, an
                     * effects duration under a spatial curve, and a grow with no
                     * duration at all, which is Qt's 250 and not a token.
                     *
                     * A char *leaving* is deliberately instant: backspace has to
                     * read as immediate, and the row it leaves behind reflows
                     * under the caret's own animation.
                     */
                    ParallelAnimation {
                        id: appearAnim
                        NumberAnimation {
                            target: materialShape
                            properties: "opacity"
                            to: 1
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                        NumberAnimation {
                            target: materialShape
                            properties: "scale"
                            to: 1
                            duration: Appearance.animation.elementMoveSmall.duration
                            easing.type: Appearance.animation.elementMoveSmall.type
                            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                        }
                        NumberAnimation {
                            target: materialShape
                            properties: "implicitSize"
                            to: root.charShapeSize
                            duration: Appearance.animation.elementMoveSmall.duration
                            easing.type: Appearance.animation.elementMoveSmall.type
                            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                        }
                        ColorAnimation {
                            target: materialShape
                            properties: "color"
                            from: Appearance.colors.colPrimary
                            to: charItem.selected ? root.selectedTextColor : Appearance.colors.colOnLayer1
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }
            }
        }
    }
}
