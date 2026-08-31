pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

Slider {
    id: root
    orientation: Qt.Vertical

    property list<real> stopIndicatorValues: [to]
    property list<real> dividerValues: []
    enum Configuration {
        Wavy = 4,
        X0 = 3,
        XS = 12,
        S = 18,
        M = 30,
        L = 42,
        XL = 72
    }

    property var configuration: StyledVerticalSlider.Configuration.S

    // M3E handle: 4dp, narrowing to 2dp while pressed.
    property real handleDefaultHeight: 4
    property real handlePressedHeight: 2
    property real rawValue: value
    property bool showValueLabel: Config.options.osd.showValues
    property color highlightColor: rawValue > to ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimary
    property color trackColor: Appearance.colors.colSecondaryContainer
    property color handleColor: rawValue > to ? Appearance.colors.colError : Appearance.colors.colPrimary
    property color dotColor: Appearance.m3colors.m3onSecondaryContainer
    property color dotColorHighlighted: Appearance.m3colors.m3onPrimary
    property real unsharpenRadius: Appearance.rounding.unsharpen
    property real trackWidth: configuration

    readonly property bool sharpMode: Config.options.appearance.sharpMode
    property real trackRadius: sharpMode ? 0 : trackWidth >= StyledVerticalSlider.Configuration.XL ? 21
        : trackWidth >= StyledVerticalSlider.Configuration.L ? 12
        : trackWidth >= StyledVerticalSlider.Configuration.M ? 12
        : trackWidth >= StyledVerticalSlider.Configuration.S ? 6
        : width / 2
        
    property real handleWidth: (configuration === StyledVerticalSlider.Configuration.Wavy) ? 24 : (configuration === StyledVerticalSlider.Configuration.X0) ? 14 : Math.max(33, trackWidth + 12)
    property real handleHeight: root.pressed ? handlePressedHeight : handleDefaultHeight
    property real handleMargins: 6
    property real dividerMargins: 2
    property real trackDotSize: 3
    property bool usePercentTooltip: true
    property string tooltipContent: usePercentTooltip ? `${Math.round(((value - from) / (to - from)) * 100)}%` : `${Math.round(value)}`

    // Icon properties
    property string materialSymbol: ""
    // Icon slot, per AOSP: a track-width square at the top of the inactive track, dropping to
    // the top of the active track once the inactive segment is shorter than the slot
    // (VolumeDialogSliderTrack.kt, Contents.Active/Inactive).
    readonly property real inactiveTrackHeight: visualPosition * effectiveDraggingHeight
        + topPadding - handleMargins - handleHeight / 2
    readonly property bool iconOnInactiveTrack: inactiveTrackHeight > trackWidth
    readonly property real iconSlotY: iconOnInactiveTrack ? 0
        : topPadding + handleMargins + handleHeight / 2 + visualPosition * effectiveDraggingHeight
    property var shape: MaterialShape.Shape.Circle

    topPadding: handleMargins
    bottomPadding: handleMargins
    property real effectiveDraggingHeight: height - topPadding - bottomPadding

    Layout.fillHeight: true
    from: 0
    to: 1

    property int valueAnimationDuration: 0

    Behavior on value {
        enabled: root.valueAnimationDuration > 0 && !root.pressed
        NumberAnimation {
            duration: root.valueAnimationDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on handleMargins {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    component TrackDot: Rectangle {
        required property real value
        property real normalizedValue: (value - root.from) / (root.to - root.from)
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.topPadding + ((1.0 - normalizedValue) * root.effectiveDraggingHeight) - (root.trackDotSize / 2)
        width: root.trackDotSize
        height: root.trackDotSize
        radius: Appearance.rounding.full
        color: normalizedValue > root.visualPosition ? root.dotColorHighlighted : root.dotColor

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: (mouse) => mouse.accepted = false
        cursorShape: root.pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor 
    }

    background: Item {
        id: background
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        width: trackWidth
        implicitWidth: trackWidth
        height: root.height
        property var normalized: root.dividerValues.map(v => (v - root.from) / (root.to - root.from))
        property var filtered: normalized.filter(v => Math.abs(v - root.visualPosition) * effectiveDraggingHeight > handleMargins + handleHeight / 2 - dividerMargins)
        property var inactiveValues: [0, ...filtered.filter(v => v < root.visualPosition), root.visualPosition]
        property var activeValues: [root.visualPosition, ...filtered.filter(v => v > root.visualPosition), 1]
        property var inactiveHeights: inactiveValues.map((v, i, a) => a[i + 1] - v).slice(0, -1)
        property var activeHeights: activeValues.map((v, i, a) => a[i + 1] - v).slice(0, -1)

        // Fill inactive (top part: 0 to visualPosition)
        Repeater {
            model: background.inactiveHeights.length

            Rectangle {
                required property int index
                anchors.horizontalCenter: background.horizontalCenter
                property real topMargin: index > 0 ? root.dividerMargins : 0
                property real bottomMargin: index < background.inactiveHeights.length - 1 ? root.dividerMargins : root.handleMargins
                y: background.inactiveValues[index] * root.effectiveDraggingHeight + topMargin + (index > 0 ? topPadding : 0)
                width: trackWidth
                height: background.inactiveHeights[index] * root.effectiveDraggingHeight - topMargin - bottomMargin - (index === background.inactiveHeights.length - 1 ? handleHeight / 2 : 0) + (index === 0 ? topPadding : 0)
                color: root.trackColor
                topLeftRadius: index === 0 ? root.trackRadius : root.unsharpenRadius
                topRightRadius: index === 0 ? root.trackRadius : root.unsharpenRadius
                bottomLeftRadius: root.unsharpenRadius
                bottomRightRadius: root.unsharpenRadius
            }
        }

        // Fill active (bottom part: visualPosition to 1)
        Repeater {
            model: background.activeHeights.length

            Rectangle {
                required property int index
                anchors.horizontalCenter: background.horizontalCenter
                property real topMargin: index > 0 ? root.dividerMargins : root.handleMargins
                property real bottomMargin: index < background.activeHeights.length - 1 ? root.dividerMargins : 0
                y: background.activeValues[index] * root.effectiveDraggingHeight + topMargin + (index === 0 ? handleHeight / 2 : 0) + topPadding
                width: trackWidth
                height: background.activeHeights[index] * root.effectiveDraggingHeight - topMargin - bottomMargin - (index === 0 ? handleHeight / 2 : 0) + (index === background.activeHeights.length - 1 ? bottomPadding : 0)
                color: root.highlightColor
                topLeftRadius: root.unsharpenRadius
                topRightRadius: root.unsharpenRadius
                bottomLeftRadius: index === background.activeHeights.length - 1 ? root.trackRadius : root.unsharpenRadius
                bottomRightRadius: index === background.activeHeights.length - 1 ? root.trackRadius : root.unsharpenRadius
            }
        }
    }

    handle: Rectangle {
        id: handle

        implicitWidth: Math.round(root.handleWidth)
        implicitHeight: Math.round(root.handleHeight)
        width: implicitWidth
        height: implicitHeight
        x: Math.round(parent.width / 2 - width / 2)
        y: Math.round(root.topPadding + (root.visualPosition * root.effectiveDraggingHeight) - (root.handleHeight / 2))
        radius: Appearance.rounding.full
        color: root.handleColor

        layer.enabled: true
        layer.samples: 4

        Behavior on implicitHeight {
            animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        StyledToolTip {
            extraVisibleCondition: root.pressed || root.hovered
            text: root.tooltipContent
            font {
                family: Appearance.font.family.numbers
                variableAxes: Appearance.font.variableAxes.numbers
            }
        }
    }

    // Stream icon, in the slot above.
    MaterialSymbol {
        id: icon
        visible: root.materialSymbol.length > 0
        anchors.horizontalCenter: root.horizontalCenter
        y: root.iconSlotY + (root.trackWidth - height) / 2
        iconSize: 20
        text: root.materialSymbol
        fill: 1.0

        color: {
            if (root.rawValue > root.to) return Appearance.colors.colOnErrorContainer;
            return root.iconOnInactiveTrack ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary;
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(icon)
        }
    }

    StyledText {
        id: valueTooltipInline
        parent: background  // fica sobre o track ativo
        anchors.horizontalCenter: background.horizontalCenter
        y: {
            var handleY = root.topPadding + (root.visualPosition * root.effectiveDraggingHeight);
            return Math.min(Math.round(handleY + 12), root.height - root.bottomPadding - height - 12);
        }
        text: Math.round(root.rawValue * 100)
        color: {
            if (root.rawValue > root.to) return Appearance.colors.colOnErrorContainer;
            return Appearance.colors.colOnPrimary;
        }
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.bold: true
        visible: root.showValueLabel
        Behavior on y { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
    }
}
