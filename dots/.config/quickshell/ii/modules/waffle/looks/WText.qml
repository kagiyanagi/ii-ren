pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.waffle.looks

// design-ok: Waffle Fluent text wrapper
Text {
    id: root

    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    color: Looks.colors.fg
    elide: Text.ElideRight

    font {
        hintingPreference: Font.PreferDefaultHinting
        family: Looks.font.family.ui
        pixelSize: Looks.font.pixelSize.normal
        weight: Looks.font.weight.regular
        variableAxes: Looks.font.variableAxes.ui
    }

    linkColor: Looks.colors.link
}
