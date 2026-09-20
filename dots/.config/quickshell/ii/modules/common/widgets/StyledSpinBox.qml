import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls

/**
 * Material 3 styled SpinBox component.
 */
SpinBox {
    id: root

    property real baseHeight: 36 // 5.1: on the grid, and 3.4's 32 minimum
    property real radius: Appearance.rounding.small
    property real innerButtonRadius: Appearance.rounding.unsharpen
    editable: true

    opacity: root.enabled ? 1 : 0.4 // 3.1: disabled is the whole control
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    background: Rectangle {
        // 3.7: the box is typed into, and nothing said which one had the
        // caret. colLayer2Active is the 0.10 focus mix for this layer
        // (3.1, mechanism 1). activeFocus, not visualFocus: a text field that
        // was clicked into is focused too.
        color: root.activeFocus ? Appearance.colors.colLayer2Active : Appearance.colors.colLayer2
        radius: root.radius

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    contentItem: Item {
        implicitHeight: root.baseHeight
        implicitWidth: Math.max(labelText.implicitWidth, 40)

        StyledTextInput {
            id: labelText
            anchors.centerIn: parent
            text: root.value // displayText would make the numbers weird like 1,000 instead of 1000
            color: Appearance.colors.colOnLayer2
            font.family: Appearance.font.family.numbers
            font.variableAxes: Appearance.font.variableAxes.numbers
            font.pixelSize: Appearance.font.pixelSize.small
            validator: root.validator
            onTextChanged: {
                // Fires while the input is still being built, and again for
                // every programmatic change of root.value. Writing back then is
                // a no-op that breaks whatever binding feeds root.value, which
                // leaves the box stuck on its clamped starting number whenever
                // the real value arrives asynchronously.
                const parsed = parseFloat(text);
                if (!isNaN(parsed) && parsed !== root.value)
                    root.value = parsed;
            }
        }
    }

    down.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topLeftRadius: root.radius
        bottomLeftRadius: root.radius
        topRightRadius: root.innerButtonRadius
        bottomRightRadius: root.innerButtonRadius

        color: root.down.pressed ? Appearance.colors.colLayer2Active : 
            root.down.hovered ? Appearance.colors.colLayer2Hover : 
            ColorUtils.transparentize(Appearance.colors.colLayer2)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        PointingHandInteraction {}

        MaterialSymbol {
            anchors.centerIn: parent
            text: "remove"
            iconSize: 20
            color: Appearance.colors.colOnLayer2
        }
    }

    up.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            right: parent.right
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topRightRadius: root.radius
        bottomRightRadius: root.radius
        topLeftRadius: root.innerButtonRadius
        bottomLeftRadius: root.innerButtonRadius

        color: root.up.pressed ? Appearance.colors.colLayer2Active : 
            root.up.hovered ? Appearance.colors.colLayer2Hover : 
            ColorUtils.transparentize(Appearance.colors.colLayer2)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        PointingHandInteraction {}

        MaterialSymbol {
            anchors.centerIn: parent
            text: "add"
            iconSize: 20
            color: Appearance.colors.colOnLayer2
        }
    }
}
