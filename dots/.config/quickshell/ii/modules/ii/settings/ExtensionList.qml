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

    // With extensions off the notice above already holds the switch, and
    // "click refresh" pointed at a button that was disabled.
    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 40
        visible: root.model.length === 0 && Config.options.extensions.enable
        text: root.loading ? Translation.tr("Searching GitHub…")
            : root.searchText.trim() ? Translation.tr("No extensions match your search")
            : Translation.tr("No extensions found. Click refresh to search GitHub.")
        horizontalAlignment: Text.AlignHCenter
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.normal
    }
}
