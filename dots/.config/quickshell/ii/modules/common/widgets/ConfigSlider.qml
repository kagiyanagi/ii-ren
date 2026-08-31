import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts

// Label above, track below: side by side the track only got whatever the label
// left over, and a long label squeezed it to a stub.
ColumnLayout {
    id: root
    readonly property bool wantsCard: true
    spacing: 4

    property string text: ""
    property string buttonIcon: ""
    property alias value: slider.value
    property alias stopIndicatorValues: slider.stopIndicatorValues
    property alias tooltipContent: slider.tooltipContent
    property bool usePercentTooltip: true
    property real from: slider.from
    property real to: slider.to

    // Emitted only for actual user interaction. valueChanged also fires for
    // every frame of StyledSlider's settle animation, so a handler that writes
    // config on it will both save garbage on load and feed itself in a loop.
    signal moved(real value)

    SearchHandler {
        visible: false // Root is a layout; don't take up a cell
        searchString: root.text
    }

    RowLayout {
        id: row
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.topMargin: 8
        spacing: 10

        OptionalMaterialSymbol {
            opacity: 1 - highlightOverlay.opacity
            id: iconWidget
            icon: root.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
        }
        StyledText {
            opacity: 1 - highlightOverlay.opacity
            id: labelWidget
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
        }
        HighlightOverlay {
            id: highlightOverlay
            visible: false
        }
    }

    StyledSlider {
        id: slider
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.bottomMargin: 8
        configuration: StyledSlider.Configuration.XS
        usePercentTooltip: root.usePercentTooltip
        value: root.value
        from: root.from
        to: root.to
        onMoved: root.moved(value)
    }
}
