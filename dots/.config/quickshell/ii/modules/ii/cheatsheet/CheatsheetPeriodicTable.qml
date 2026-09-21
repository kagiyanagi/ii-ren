import "periodic_table.js" as PTable
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls

Item {
    id: root
    readonly property var elements: PTable.elements
    readonly property var series: PTable.series
    property real spacing: 4
    implicitWidth: flickable.contentWidth
    implicitHeight: flickable.contentHeight

    // The table was a Column centred in a bare Item: at 1364px it fits this
    // screen and does not fit a 1366 laptop, and whatever fell outside was
    // simply unreachable. The keybinds tab gets the same two bars.
    StyledFlickable {
        id: flickable
        anchors.fill: parent
        contentWidth: mainLayout.implicitWidth
        contentHeight: mainLayout.implicitHeight
        ScrollBar.horizontal: StyledScrollBar {}

        Column {
            id: mainLayout
            spacing: root.spacing

            Repeater { // Main table rows
                model: root.elements

                delegate: Row { // Table cells
                    id: tableRow
                    spacing: root.spacing
                    required property var modelData

                    Repeater {
                        model: tableRow.modelData
                        delegate: ElementTile {
                            required property var modelData
                            element: modelData
                        }
                    }
                }
            }

            Item { // Gap before the lanthanides and actinides
                implicitHeight: 16
            }

            Repeater { // Series rows
                model: root.series

                delegate: Row { // Table cells
                    id: seriesTableRow
                    spacing: root.spacing
                    required property var modelData

                    Repeater {
                        model: seriesTableRow.modelData
                        delegate: ElementTile {
                            required property var modelData
                            element: modelData
                        }
                    }
                }
            }
        }
    }
}
