import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.animations

Rectangle {
    id: root

    Layout.fillWidth: true
    implicitHeight: 64
    radius: Appearance.rounding.full

    color: containerColor

    property string shapeString: "Circle"
    property int shapeSize: 40
    property string icon: ""

    property color containerColor: Appearance.colors.colSecondaryContainer
    property color shapeColor: Appearance.colors.colSecondary
    property color symbolColor: Appearance.colors.colOnSecondary
    property color textColor: Appearance.colors.colOnSecondaryContainer

    // Left Circle Interaction
    property bool leftInteractive: false
    property bool leftHovered: leftButton.hovered
    property real iconFill: 1
    signal leftClicked

    // Right Circle Action Button
    property bool showRightShape: false
    property string rightShapeString: "Circle"
    property string rightIcon: "stop"
    property real rightIconFill: 1
    property color rightShapeColor: Appearance.colors.colErrorContainer
    property color rightSymbolColor: Appearance.colors.colOnErrorContainer
    property bool rightHovered: rightButton.hovered
    signal rightClicked

    // Internal animation control
    property bool startAnim: false

    // Siblings enter staggerStep apart (DESIGN.md 2.8): shape, text, action.
    onStartAnimChanged: {
        if (!root.startAnim) return;
        shapeTranslate.x = -root.enterTravel;
        rightShapeTranslate.x = root.enterTravel;
        textContainer.opacity = 0;
        Qt.callLater(() => {
            shapeAnim.restart();
            textAnim.restart();
            if (root.showRightShape && rightShapeContainer.visible)
                rightShapeAnim.restart();
        });
    }

    // One transform per entering child, toward its resting place (2.8).
    readonly property int enterTravel: 24

    default property alias shapeContent: shapeItem.children
    property alias text: pillText.text
    property alias textContent: textContainer.children

    component EnterFade: DelayedPropertyAnimation {
        property: "opacity"
        from: 0
        to: 1
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Appearance.animation.elementMoveFast.type
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
    }

    component EnterMove: DelayedPropertyAnimation {
        to: 0
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }

    Item {
        id: shapeContainer
        width: root.shapeSize
        height: root.shapeSize
        anchors {
            left: parent.left
            leftMargin: 12
            verticalCenter: parent.verticalCenter
        }

        transform: Translate {
            id: shapeTranslate
            x: 0
        }

        EnterMove {
            id: shapeAnim
            target: shapeTranslate
            property: "x"
            from: -root.enterTravel
        }

        MaterialShape {
            id: shapeItem
            shapeString: root.shapeString
            implicitSize: root.shapeSize
            color: root.shapeColor
            anchors.centerIn: parent

            MaterialSymbol {
                id: iconSymbol
                visible: root.icon !== "" && shapeItem.children.length <= 1
                anchors.centerIn: parent
                text: root.icon
                iconSize: Appearance.font.pixelSize.large
                color: root.symbolColor
                fill: root.iconFill
            }
        }

        // Hover 0.08 / focus 0.10 / pressed 0.10 as a film over the shape, plus
        // ripple, pointing-hand cursor and the disabled 0.4, all from
        // RippleButton (DESIGN.md 3.1, 9 "Icon button"). The visual stays a
        // MaterialShape; the button only supplies the states, so its own fill is
        // the transparent base the film composites onto.
        RippleButton {
            id: leftButton
            anchors.fill: parent
            visible: root.leftInteractive
            enabled: root.leftInteractive
            buttonRadius: Appearance.rounding.full
            colBackground: ColorUtils.transparentize(root.symbolColor, 1)
            colBackgroundHover: ColorUtils.transparentize(root.symbolColor, 0.92)
            colBackgroundActive: ColorUtils.transparentize(root.symbolColor, 0.90)
            colRipple: ColorUtils.transparentize(root.symbolColor, 0.90)
            colStateLayer: root.symbolColor
            onClicked: root.leftClicked()
        }
    }

    Item {
        id: rightShapeContainer
        visible: root.showRightShape
        width: root.shapeSize
        height: root.shapeSize
        anchors {
            right: parent.right
            rightMargin: 12
            verticalCenter: parent.verticalCenter
        }

        transform: Translate {
            id: rightShapeTranslate
            x: 0
        }

        EnterMove {
            id: rightShapeAnim
            target: rightShapeTranslate
            property: "x"
            from: root.enterTravel
            delay: Appearance.animation.staggerStep * 2
        }

        MaterialShape {
            id: rightShapeItem
            shapeString: root.rightShapeString
            implicitSize: root.shapeSize
            color: root.rightShapeColor
            anchors.centerIn: parent

            MaterialSymbol {
                id: rightIconSymbol
                visible: root.rightIcon !== ""
                anchors.centerIn: parent
                text: root.rightIcon
                iconSize: Appearance.font.pixelSize.large
                color: root.rightSymbolColor
                fill: root.rightIconFill
            }
        }

        RippleButton {
            id: rightButton
            anchors.fill: parent
            enabled: root.showRightShape
            buttonRadius: Appearance.rounding.full
            colBackground: ColorUtils.transparentize(root.rightSymbolColor, 1)
            colBackgroundHover: ColorUtils.transparentize(root.rightSymbolColor, 0.92)
            colBackgroundActive: ColorUtils.transparentize(root.rightSymbolColor, 0.90)
            colRipple: ColorUtils.transparentize(root.rightSymbolColor, 0.90)
            colStateLayer: root.rightSymbolColor
            onClicked: root.rightClicked()
        }
    }

    Item {
        id: textContainer
        anchors {
            verticalCenter: parent.verticalCenter
            horizontalCenter: parent.horizontalCenter
            horizontalCenterOffset: root.showRightShape ? 0 : 8
        }
        opacity: 1.0

        Behavior on anchors.horizontalCenterOffset {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        EnterFade {
            id: textAnim
            target: textContainer
            delay: Appearance.animation.staggerStep
        }

        StyledText {
            id: pillText
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            font.weight: Font.Bold
            color: root.textColor
            visible: text !== "" && textContainer.children.length <= 1
        }
    }
}
