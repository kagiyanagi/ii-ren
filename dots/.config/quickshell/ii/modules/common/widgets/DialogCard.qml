import qs.modules.common
import QtQuick
import QtQuick.Layouts

// The sidebar dialogs' list card: rows stacked flush on one
// colSurfaceContainerHigh card (DESIGN.md 5.5). The first and last row take its
// rounding.large corners themselves. Was a `component Card` copied into four
// dialogs.
Rectangle {
    id: card
    default property alias rows: cardColumn.data
    property real padding: 0

    Layout.fillWidth: true
    implicitHeight: cardColumn.implicitHeight + card.padding * 2
    radius: Appearance.rounding.large
    color: Appearance.colors.colSurfaceContainerHigh

    ColumnLayout {
        id: cardColumn
        anchors {
            fill: parent
            margins: card.padding
        }
        spacing: 0
    }
}
