import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import qs.modules.common
import qs.modules.common.widgets

PopupWindow {
    id: rootToolTipPopup

    property Item parentItem: parent
    property string text: ""
    property bool showTooltip: false
    // Gap from the dock window's edge, not from the button - this is what makes
    // the pill start exactly where the window preview card starts. 5 is the
    // preview background's own margin.
    property int tooltipOffset: 5
    
    property string dockPosition: {
        const pos = Config.options?.dock?.position ?? "bottom"
        if (pos !== "auto") return pos
        return (Config.options?.bar?.bottom && !Config.options?.bar?.vertical) ? "top" : "bottom"
    }

    // The window has to be bigger than the pill for the shadow to have
    // somewhere to fall; every anchor below adds it back so the pill still
    // lands the same distance from the button.
    readonly property real shadowPad: Appearance.sizes.elevationMargin

    anchor.window: parentItem?.QsWindow?.window
    implicitWidth: tooltipRect.implicitWidth + shadowPad * 2
    implicitHeight: tooltipRect.implicitHeight + shadowPad * 2

    anchor.rect.x: {
        if (!parentItem) return 0
        let _ = parentItem.x + parentItem.y + parentItem.width + rootToolTipPopup.width
        const mapped = parentItem.mapToItem(null, 0, 0)
        
        const windowWidth = rootToolTipPopup.anchor.window?.width ?? 0
        if (dockPosition === "left") {
            return windowWidth + tooltipOffset - rootToolTipPopup.shadowPad
        } else if (dockPosition === "right") {
            return -tooltipOffset - rootToolTipPopup.width + rootToolTipPopup.shadowPad
        } else {
            return mapped.x + (parentItem.width - rootToolTipPopup.width) / 2
        }
    }
    
    anchor.rect.y: {
        if (!parentItem) return 0
        let _ = parentItem.x + parentItem.y + parentItem.height + rootToolTipPopup.height
        const mapped = parentItem.mapToItem(null, 0, 0)
        
        const windowHeight = rootToolTipPopup.anchor.window?.height ?? 0
        if (dockPosition === "top") {
            return windowHeight + tooltipOffset - rootToolTipPopup.shadowPad
        } else if (dockPosition === "bottom") {
            return -tooltipOffset - rootToolTipPopup.height + rootToolTipPopup.shadowPad
        } else {
            return mapped.y + (parentItem.height - rootToolTipPopup.height) / 2
        }
    }

    visible: showTooltip || tooltipRect.opacity > 0.01
    color: "transparent"

    StyledRectangularShadow {
        target: tooltipRect
        opacity: tooltipRect.opacity
    }

    Rectangle {
        id: tooltipRect
        anchors.centerIn: parent
        implicitWidth: tooltipText.implicitWidth + 32
        implicitHeight: tooltipText.implicitHeight + 18
        opacity: rootToolTipPopup.showTooltip ? 1.0 : 0.0
        scale: rootToolTipPopup.showTooltip ? 1.0 : 0.8
        transformOrigin: {
            if (rootToolTipPopup.dockPosition === "top") return Item.Top
            if (rootToolTipPopup.dockPosition === "bottom") return Item.Bottom
            if (rootToolTipPopup.dockPosition === "left") return Item.Left
            if (rootToolTipPopup.dockPosition === "right") return Item.Right
            return Item.Bottom
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(tooltipRect)
        }
        Behavior on scale {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(tooltipRect)
        }

        // A pill on its own shadow rather than a bordered box - the hairline
        // was doing the work elevation should be doing. Alpha forced to 1: the
        // themed colours carry the shell's content transparency, which is meant
        // for surfaces sitting on the blurred panel, not for a floating window
        // over the wallpaper.
        readonly property color base: Appearance.m3colors.m3surfaceContainerHigh
        color: Qt.rgba(base.r, base.g, base.b, 1)
        radius: Appearance.rounding.full

        StyledText {
            id: tooltipText
            anchors.centerIn: parent
            text: rootToolTipPopup.text
            color: Appearance.colors.colOnSurface
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
        }
    }
}
