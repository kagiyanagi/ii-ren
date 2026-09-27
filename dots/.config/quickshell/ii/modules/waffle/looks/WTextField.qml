pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.waffle.looks
import QtQuick
import QtQuick.Controls

TextField {
    id: root
    
    clip: true
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    color: Looks.colors.fg
    selectionColor: Looks.colors.selection
    selectedTextColor: Looks.colors.selectionFg

    font {
        hintingPreference: Font.PreferDefaultHinting
        family: Looks.font.family.ui
        pixelSize: Looks.font.pixelSize.normal
        weight: Looks.font.weight.regular
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
    }
}
