import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Loader {
    id: root
    required property string icon
    property real iconSize: Appearance.font.pixelSize.larger
    Layout.alignment: Qt.AlignVCenter

    active: root.icon.length > 0
    visible: active

    // The symbol is the loaded item, not a child of a bare Item: that wrapper
    // declared no implicitHeight, so the Loader reported 0 and a row sized
    // itself as if the icon were not there.
    sourceComponent: MaterialSymbol {
        iconSize: root.iconSize
        color: Appearance.colors.colOnSecondaryContainer
        text: root.icon
    }
}
