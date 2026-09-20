import qs.modules.common
import QtQuick
import QtQuick.Controls

/**
 * Does not include visual layout, but includes the easily neglected colors.
 */
TextInput {
    color: Appearance.colors.colOnLayer1
    renderType: Text.NativeRendering
    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }

    // 3.4: text gets an I-beam. A TextInput sets no cursor of its own, so every
    // caller was laying a no-button MouseArea over it to get one -- a handler
    // does it in a line and, unlike a MouseArea, does not take hover off
    // whatever is underneath.
    HoverHandler {
        cursorShape: Qt.IBeamCursor
    }
}
