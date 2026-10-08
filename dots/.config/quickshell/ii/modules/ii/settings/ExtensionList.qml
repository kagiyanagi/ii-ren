import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "."

ColumnLayout {
    id: root
    property var model: []
    property string searchText: ""
    property bool loading: false

    spacing: 4

    Repeater {
        model: root.model
        delegate: ExtensionCard {
            listCount: root.model.length
        }
    }

    // With extensions off the switch above says so already, and
    // "click refresh" pointed at a button that was disabled.
    Item {
        Layout.fillWidth: true
        implicitHeight: Appearance.sizes.pagePlaceholderHeight
        visible: root.model.length === 0 && Config.options.extensions.enable

        PagePlaceholder {
            anchors.fill: parent
            shape: MaterialShape.Shape.Circle
            icon: root.loading ? "travel_explore" : root.searchText.trim() ? "search_off" : "extension"
            title: root.loading ? Translation.tr("Searching GitHub…")
                : root.searchText.trim() ? Translation.tr("No matches")
                : Translation.tr("No extensions yet")
            description: root.loading ? ""
                : root.searchText.trim() ? Translation.tr("No extensions match your search")
                : Translation.tr("Refresh to search GitHub for extensions.")
        }
    }
}
