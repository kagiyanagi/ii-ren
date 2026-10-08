import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts

// Label above, track below: side by side the track only got whatever the label
// left over, and a long label squeezed it to a stub.
ColumnLayout {
    id: root
    // 35 of the 124 instantiations were setting this themselves; the other 89
    // sized to the label row's implicit width inside a full-width card (5.6).
    Layout.fillWidth: true
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
    property alias stepSize: slider.stepSize
    property alias configuration: slider.configuration
    property alias animateWave: slider.animateWave
    property alias waveAmplitudeMultiplier: slider.waveAmplitudeMultiplier
    // For a row that acts once the drag ends (the Sounds page plays a sample).
    readonly property alias pressed: slider.pressed

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
        // The value, always in view rather than only in a tooltip while the
        // thumb is held; the label carries its unit, as "(px)" or "(%)".
        StyledText {
            opacity: 1 - highlightOverlay.opacity
            text: slider.tooltipContent
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
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
        showTooltip: false
        // The real value. StyledSlider's own default is the thumb's place along
        // the track, which is right for a 0-1 level and wrong for anything else:
        // a widget at 100% scale on a 50-200 slider read "33%". A range that
        // tops out at 4 or less is a level or a multiplier (0-1, 0.5-2), so it
        // reads as a percent of 1.
        // ponytail: judged on the range alone; a small integer count (1-4)
        // would need its own flag.
        tooltipContent: root.to <= 4 ? `${Math.round(value * 100)}%` : `${Math.round(value)}`
        value: root.value
        from: root.from
        to: root.to
        onMoved: root.moved(value)
    }
}
