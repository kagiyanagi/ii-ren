import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets

/**
 * A ConfigSelectionArray on a ConfigLabeledRow: label above, chips below, one
 * full-width card. Children declared on an instance go under the chips.
 */
ConfigLabeledRow {
    id: root
    property alias options: array.options
    property alias currentValue: array.currentValue
    signal selected(var newValue)

    ConfigSelectionArray {
        id: array
        Layout.fillWidth: true
        // A Flow reports the width of its chips on one line, and that width
        // changes as it wraps. Passed up, a page sized to its content
        // (ContentPage.forceWidth: false) widened to fit the line, wrapped
        // inside its own insets, shrank, unwrapped, and spun at 100% CPU
        // (the Weather options page froze the settings app). The row asks for
        // no width of its own; the card's width decides the wrap.
        Layout.preferredWidth: 0
        // The row's body already carries the card's insets.
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0
        onSelected: newValue => root.selected(newValue)
    }
}
