import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    readonly property bool wantsCard: true
    spacing: 10

    property string text: ""
    property string buttonIcon: ""
    property alias value: slider.value
    property alias stopIndicatorValues: slider.stopIndicatorValues
    property bool usePercentTooltip: true
    property real from: slider.from
    property real to: slider.to
    property real textWidth: 120

    // Emitted only for actual user interaction. valueChanged also fires for
    // every frame of StyledSlider's settle animation, so a handler that writes
    // config on it will both save garbage on load and feed itself in a loop.
    signal moved(real value)

    SearchHandler {
        visible: false // Root is a RowLayout; don't take up a cell
        searchString: root.text
    }

    RowLayout {
        id: row
        Layout.leftMargin: 8
        Layout.alignment: Qt.AlignVCenter
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
            Layout.preferredWidth: root.textWidth
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
        Layout.rightMargin: 8
        Layout.topMargin: 10
        Layout.bottomMargin: 10
        configuration: StyledSlider.Configuration.XS
        usePercentTooltip: root.usePercentTooltip
        value: root.value
        from: root.from
        to: root.to
        onMoved: root.moved(value)
    }
}