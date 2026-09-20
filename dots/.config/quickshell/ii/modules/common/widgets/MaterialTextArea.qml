import qs.modules.common
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls

/**
 * Material 3 styled TextArea (filled style)
 * https://m3.material.io/components/text-fields/overview
 * Note: We don't use NativeRendering because it makes the small placeholder text look weird
 */
TextArea {
    id: root
    Material.theme: Material.System
    Material.accent: Appearance.m3colors.m3primary
    Material.primary: Appearance.m3colors.m3primary
    Material.background: Appearance.m3colors.m3surface
    Material.foreground: Appearance.m3colors.m3onSurface
    Material.containerStyle: Material.Filled
    renderType: Text.QtRendering

    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    placeholderTextColor: Appearance.m3colors.m3outline

    background: Rectangle {
        implicitHeight: 56
        color: Appearance.m3colors.m3surface
        topLeftRadius: Appearance.rounding.unsharpenmore
        topRightRadius: Appearance.rounding.unsharpenmore
        // The M3 filled field's active indicator -- a component part, not a
        // separator line (5.5 is about dividers between sections). 1dp at rest,
        // 2dp focused, which is what makes the focus state something you can see
        // rather than an activeFocus nothing renders (3.7).
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            // activeFocus, not focus: `focus` is true for whichever item holds
            // it inside its focus scope, so a field in a closed panel drew
            // itself focused alongside the one actually being typed into.
            height: root.activeFocus ? 2 : 1
            color: root.activeFocus ? Appearance.m3colors.m3primary :
                root.hovered ? Appearance.m3colors.m3outline : Appearance.m3colors.m3outlineVariant

            Behavior on height {
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    font {
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    wrapMode: TextEdit.Wrap

    // 3.4: text gets an I-beam, and a TextArea sets no cursor of its own.
    HoverHandler {
        cursorShape: Qt.IBeamCursor
    }
}
