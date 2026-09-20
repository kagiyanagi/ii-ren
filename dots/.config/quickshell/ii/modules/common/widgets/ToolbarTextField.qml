import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

TextField {
    id: filterField

    property alias colBackground: background.color

    Layout.fillHeight: true
    implicitWidth: 200
    padding: 10

    // Disabled is the whole control at 0.4, not a greyed-out colour (3.1). The
    // lock screen switches this off mid-unlock and nothing used to show it.
    opacity: filterField.enabled ? 1 : 0.4
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    placeholderTextColor: Appearance.colors.colSubtext
    color: Appearance.colors.colOnLayer1
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance.font.pixelSize.small
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    renderType: Text.NativeRendering
    selectedTextColor: Appearance.colors.colOnSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer

    background: Rectangle {
        id: background
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.full

        // The field had no state at all: hover did nothing and focus was an
        // activeFocus boolean nothing rendered, which 3.7 names outright. Both
        // are films over the container, so they stay right whatever colour a
        // caller gives it.
        StateOverlay {
            anchors.fill: parent
            radius: parent.radius
            hover: filterField.hovered
            focused: filterField.activeFocus
            contentColor: Appearance.colors.colOnLayer1
        }
    }
}
