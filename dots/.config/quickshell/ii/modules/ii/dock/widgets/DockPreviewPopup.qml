import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

import "../"

PopupWindow {
    id: previewPopup

    property var dockRoot: null
    property var appTopLevel: null
    property var dockWindow: null

    readonly property bool isVertical: dockRoot?.isVertical ?? false
    readonly property string dockPos: dock.dockEffectivePosition
    
    readonly property int maxPreviews: {
        if (!dockWindow || !dockRoot) return 1

        const spacing = 6
        const previewSize = isVertical ? dockRoot.maxWindowPreviewHeight + dockRoot.windowControlsHeight : dockRoot.maxWindowPreviewWidth

        const availableSpace = isVertical ? (dockWindow.height ?? 1080) - popupBackground.margins * 2 - popupBackground.padding * 2 : (dockWindow.width ?? 1920) - popupBackground.margins * 2 - popupBackground.padding * 2
        return Math.max(1, Math.floor((availableSpace + spacing) / (previewSize + spacing)))
    }

    readonly property string appName: {
        if (!appTopLevel?.appId) return "";
        return TaskbarApps.getCachedDesktopEntry(appTopLevel.appId)?.name || appTopLevel.appId;
    }
    // Folded into the window size below, otherwise the card grows past the
    // popup and gets clipped at the top.
    readonly property real headerHeight: Appearance.font.pixelSize.normal + 10

    property bool show: false
    readonly property bool shouldShow:
        !dockRoot.dragActive &&
        !dockRoot.anyContextMenuOpen &&
        (backgroundHover.hovered || dockRoot.buttonHovered || dockRoot.popupIsResizing) &&
        (appTopLevel?.toplevels?.length > 0)

    onShouldShowChanged: {
        if (shouldShow)
            show = true
        else if (dockRoot.anyContextMenuOpen)
            show = false
        else
            hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: 150
        onTriggered: previewPopup.show = previewPopup.shouldShow
    }

    visible: show || popupBackground.opacity > 0
    color: "transparent"

    anchor {
        window: dockWindow
        adjustment: PopupAdjustment.None

        rect {
            x: dockPos === "left" ? (dockWindow?.width ?? 0) : 0
            y: dockPos === "bottom" ? 0 : dockPos === "top" ? (dockWindow?.height ?? 0) : 0
        }

        gravity: {
            if (dockPos === "left") return Edges.Right | Edges.Bottom
            if (dockPos === "right") return Edges.Left | Edges.Bottom
            if (dockPos === "top") return Edges.Bottom | Edges.Right
            return Edges.Top | Edges.Right
        }

        edges: Edges.Top | Edges.Left
    }

    readonly property int _extra: popupBackground.padding * 2 + popupBackground.margins * 2

    implicitWidth: isVertical ? dockRoot.maxWindowPreviewWidth + dockRoot.windowControlsHeight + _extra - 25 : dockWindow?.width ?? 0
    implicitHeight: isVertical ? dockWindow?.height ?? 0 : dockRoot.maxWindowPreviewHeight + dockRoot.windowControlsHeight + _extra + 5 + previewPopup.headerHeight + previewColumn.spacing

    StyledRectangularShadow {
        target: popupBackground
        opacity: popupBackground.opacity
        visible: popupBackground.visible
    }

    Rectangle {
        id: popupBackground

        property real margins: 5
        property real padding: 6

        onImplicitWidthChanged: { dockRoot.popupIsResizing = true; resizeTimer.restart() }
        onImplicitHeightChanged: { dockRoot.popupIsResizing = true; resizeTimer.restart() }

        Timer {
            id: resizeTimer
            interval: 500
            onTriggered: dockRoot.popupIsResizing = false
        }

        readonly property real _clampedX: Math.max(margins, Math.min(dockRoot.hoveredButtonCenter.x - implicitWidth  / 2, parent.width  - implicitWidth  - margins))
        readonly property real _clampedY: Math.max(margins, Math.min(dockRoot.hoveredButtonCenter.y - implicitHeight / 2, parent.height - implicitHeight - margins))
        x: isVertical ? (dockPos === "left" ? margins : parent.width - implicitWidth - margins) : _clampedX
        y: isVertical ? _clampedY : (dockPos === "top" ? margins : parent.height - implicitHeight - margins)

        opacity: previewPopup.show ? 1 : 0
        visible: (appTopLevel?.toplevels?.length ?? 0) > 0
        clip: true
        color: Appearance.m3colors.m3surfaceContainer
        radius: Appearance.rounding.normal
        implicitHeight: previewColumn.implicitHeight + padding * 2
        implicitWidth: previewColumn.implicitWidth + padding * 2

        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(previewPopup)
        }

        HoverHandler {
            id: backgroundHover
        }

        ColumnLayout {
            id: previewColumn
            anchors {
                top: parent.top
                left: parent.left
                topMargin: popupBackground.padding
                leftMargin: popupBackground.padding
            }
            spacing: 4

            // The only place the app itself is named once it is running - the
            // cards below carry window titles, not the app's.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.preferredHeight: previewPopup.headerHeight
                spacing: 6

                StyledText {
                    text: previewPopup.appName
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    // One window is obvious from the single card; only say it
                    // when the count is the useful part.
                    visible: (appTopLevel?.toplevels?.length ?? 0) > 1
                    text: `\u00b7 ${Translation.tr("%1 windows").arg(appTopLevel?.toplevels?.length ?? 0)}`
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                Item { Layout.fillWidth: true }
            }

        GridLayout {
            id: previewRowLayout
            flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            columnSpacing: 6
            rowSpacing: 6

            Repeater {
                model: ScriptModel { values: (appTopLevel?.toplevels ?? []).slice(0, previewPopup.maxPreviews) }

                delegate: RippleButton {
                    id: windowButton
                    required property var modelData
                    padding: 0

                    onClicked: {
                        modelData?.activate()
                        dockRoot.buttonHovered = false
                        dockRoot.lastHoveredButton = null
                    }
                    middleClickAction: () => modelData?.close()

                    contentItem: Item {
                        implicitWidth: screencopyView.implicitWidth
                        implicitHeight: screencopyView.implicitHeight

                        ScreencopyView {
                            id: screencopyView
                            captureSource: previewPopup.visible ? windowButton.modelData : null
                            live: true
                            paintCursor: true
                            constraintSize: Qt.size(
                                dockRoot.maxWindowPreviewWidth,
                                dockRoot.maxWindowPreviewHeight
                            )
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: screencopyView.width
                                    height: screencopyView.height
                                    radius: Appearance.rounding.normal
                                }
                            }
                        }

                        // Title rides on the shot instead of taking a bar of its
                        // own. Per-corner radii follow the thumbnail's mask, so
                        // no second layer is needed just to round two corners.
                        Rectangle {
                            id: titleScrim
                            anchors {
                                left: screencopyView.left
                                right: screencopyView.right
                                bottom: screencopyView.bottom
                            }
                            height: windowTitle.implicitHeight + 18
                            bottomLeftRadius: Appearance.rounding.normal
                            bottomRightRadius: Appearance.rounding.normal
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.45) }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.82) }
                            }

                            StyledText {
                                id: windowTitle
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                    leftMargin: 10
                                    rightMargin: 10
                                    bottomMargin: 6
                                }
                                font.pixelSize: Appearance.font.pixelSize.small
                                text: windowButton.modelData?.title ?? ""
                                elide: Text.ElideRight
                                // Fixed white: it sits on the shot's own pixels,
                                // not on a themed surface.
                                color: "#ffffff"
                            }
                        }

                        RippleButton {
                            id: closeButton
                            anchors {
                                right: screencopyView.right
                                top: screencopyView.top
                                margins: 6
                            }
                            implicitWidth: dockRoot.windowControlsHeight
                            implicitHeight: dockRoot.windowControlsHeight
                            buttonRadius: Appearance.rounding.full
                            colBackground: Qt.rgba(0, 0, 0, 0.55)
                            colBackgroundHover: Appearance.colors.colError
                            // Out of the way until the card is under the pointer.
                            opacity: windowButton.hovered ? 1 : 0
                            visible: opacity > 0

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: Appearance.font.pixelSize.normal
                                color: "#ffffff"
                            }
                            onClicked: windowButton.modelData?.close()
                        }
                    }
                }
            }
        }
        }
    }
}
