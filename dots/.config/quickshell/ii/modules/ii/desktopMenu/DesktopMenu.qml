pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
// ponytail: DockMenuButton is a generic icon + label menu row with nothing dock
// specific in it. Move it to common/widgets if a third menu wants it.
import qs.modules.ii.dock
import qs.modules.ii.background.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    IpcHandler {
        target: "desktopMenu"

        // No cursor to open at, so centre it on the focused monitor.
        function toggle(): void {
            if (GlobalStates.desktopMenuOpen) {
                menuLoader.item?.dismiss();
                return;
            }
            const screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
            GlobalStates.desktopMenuScreen = screen;
            GlobalStates.desktopMenuX = screen.width / 2;
            GlobalStates.desktopMenuY = screen.height / 2;
            GlobalStates.desktopMenuOpen = true;
        }
    }

    Loader {
        id: menuLoader

        // Held open past the state flip so the close animation can finish.
        property bool closing: false
        active: GlobalStates.desktopMenuOpen || closing

        sourceComponent: PanelWindow {
            id: menuWindow

            function dismiss(): void {
                if (closeAnim.running)
                    return;
                menuLoader.closing = true;
                GlobalStates.desktopMenuOpen = false;
                closeAnim.start();
            }

            // Right clicking again mid-close has to catch the card on its way
            // out, or the window survives the animation faded to nothing.
            Connections {
                target: GlobalStates
                function onDesktopMenuOpenChanged(): void {
                    if (!GlobalStates.desktopMenuOpen)
                        return;
                    closeAnim.stop();
                    menuLoader.closing = false;
                    openAnim.restart();
                }
            }

            screen: GlobalStates.desktopMenuScreen ?? Quickshell.screens[0]
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:desktopMenu"
            WlrLayershell.layer: WlrLayer.Overlay
            // OnDemand never actually got the keyboard here -- the menu opens from
            // a right click on the desktop, so nothing ever handed focus over and
            // even Escape was dead. Grab it outright, the way a menu does, and give
            // it straight back the moment the close starts so the next keystroke
            // reaches the app rather than the card on its way out.
            WlrLayershell.keyboardFocus: menuLoader.closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Anywhere off the card dismisses, which is what a context menu does.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: menuWindow.dismiss()
            }

            StyledRectangularShadow {
                target: menuCard
                // anchors.fill doesn't follow a scale transform, so without this
                // the shadow sits full size around a half-size card.
                scale: menuCard.scale
                transformOrigin: menuCard.transformOrigin
                opacity: menuCard.opacity
            }

            Rectangle {
                id: menuCard

                readonly property real gutter: 8
                readonly property bool leftAligned: x >= GlobalStates.desktopMenuX
                readonly property bool topAligned: y >= GlobalStates.desktopMenuY

                // Opens with its top-left at the cursor, like every other context
                // menu, and slides back inside the screen near an edge.
                x: Math.max(gutter, Math.min(GlobalStates.desktopMenuX, menuWindow.width - width - gutter))
                y: Math.max(gutter, Math.min(GlobalStates.desktopMenuY, menuWindow.height - height - gutter))

                // Launcher3 stacks its rows with popup_margin 2dp between them and
                // the big radius only at the ends of the stack; bg_popup_item is
                // 216dp x 52dp, so keep roughly that proportion. Unlike the
                // launcher, the gaps show a card rather than the wallpaper.
                readonly property real innerRadius: Appearance.rounding.unsharpenmore
                // Ends of the stack, inset inside the card, so smaller than the
                // card's own corner.
                readonly property real outerRadius: Appearance.rounding.normal
                readonly property real padding: 6

                implicitWidth: 320
                implicitHeight: menuColumn.implicitHeight + 2 * padding
                radius: Appearance.rounding.large
                color: Appearance.m3colors.m3surfaceContainer

                opacity: 0
                scale: 0.5

                // Launcher3 ArrowPopup.setPivotForOpenCloseAnimation(): the popup
                // grows out of the corner nearest the touch point, so follow the
                // cursor rather than the corner the edge clamp left it on.
                transformOrigin: leftAligned ? (topAligned ? Item.TopLeft : Item.BottomLeft) : (topAligned ? Item.TopRight : Item.BottomRight)

                // ArrowPopup.animateOpen(), AOSP main: scale 0.5 -> 1.02 over
                // OPEN_DURATION_U 200ms on EMPHASIZED_DECELERATE, then settles
                // 1.02 -> 1 over OPEN_OVERSHOOT_DURATION_U 200ms on
                // PathInterpolator(0.3, 0, 0.33, 1). The card and its children
                // each fade in linearly over OPEN_FADE_DURATION_U 83ms, so the
                // content lands while the card is still growing.
                ParallelAnimation {
                    id: openAnim
                    running: true

                    SequentialAnimation {
                        NumberAnimation {
                            target: menuCard
                            property: "scale"
                            from: 0.5
                            to: 1.02
                            duration: 200
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                        NumberAnimation {
                            target: menuCard
                            property: "scale"
                            to: 1
                            duration: 200
                            easing.type: Easing.Bezier
                            easing.bezierCurve: [0.3, 0, 0.33, 1, 1, 1]
                        }
                    }
                    NumberAnimation {
                        target: menuCard
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 83
                    }
                    NumberAnimation {
                        target: menuColumn
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 83
                    }
                }

                // ArrowPopup.animateClose() shape -- half size on
                // EMPHASIZED_ACCELERATE with the fades held back -- but quicker
                // than AOSP's CLOSE_DURATION_U 233ms / CLOSE_FADE_START_DELAY_U
                // 150ms, which drags on a desktop where the menu is dismissed
                // constantly.
                ParallelAnimation {
                    id: closeAnim

                    NumberAnimation {
                        target: menuCard
                        property: "scale"
                        to: 0.5
                        duration: 190
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                    }
                    SequentialAnimation {
                        PauseAnimation {
                            duration: 60
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: menuCard
                                property: "opacity"
                                to: 0
                                duration: 83
                            }
                            NumberAnimation {
                                target: menuColumn
                                property: "opacity"
                                to: 0
                                duration: 83
                            }
                        }
                    }

                    onFinished: menuLoader.closing = false
                }

                // Swallows the clicks the dismiss handler underneath would take.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    id: menuColumn

                    opacity: 0

                    // Reshuffled on every open, since the whole component is
                    // rebuilt per right click. The current one leads so its check
                    // mark is always on screen without scrolling.
                    // isValidImageByName also drops the subdirectories the model
                    // carries, which have no thumbnail to show.
                    // Snapshotted, not bound: picking a wallpaper writes the config
                    // back, and a live read here would reshuffle the strip and yank
                    // the tile out from under the pointer.
                    property string initialWallpaper: ""
                    Component.onCompleted: menuColumn.initialWallpaper = Config.options.background.wallpaperPath

                    readonly property var shuffledWallpapers: {
                        const current = menuColumn.initialWallpaper;
                        const rest = Wallpapers.wallpapers.filter(path => Images.isValidImageByName(path.toLowerCase()) && path !== current);
                        for (let i = rest.length - 1; i > 0; i--) {
                            const j = Math.floor(Math.random() * (i + 1));
                            [rest[i], rest[j]] = [rest[j], rest[i]];
                        }
                        return Images.isValidImageByName(current.toLowerCase()) ? [current, ...rest] : rest;
                    }

                    anchors.fill: parent
                    anchors.margins: menuCard.padding
                    spacing: 2

                    focus: true
                    // Any key closes it, not just Escape: the keyboard belongs to
                    // whatever was focused, so the first keystroke is the signal the
                    // menu is done.
                    Keys.onPressed: event => {
                        menuWindow.dismiss();
                        event.accepted = true;
                    }

                    Item {
                        id: stripViewport

                        Layout.fillWidth: true
                        Layout.preferredHeight: 132
                        Layout.bottomMargin: 6
                        visible: wallpaperStrip.count > 0 && GlobalStates.desktopMenuWidgetId === null

                        // The viewport cuts the tiles at each end square, so round
                        // the cut itself the same as the tiles.
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: stripViewport.width
                                height: stripViewport.height
                                topLeftRadius: menuCard.outerRadius
                                topRightRadius: menuCard.outerRadius
                                bottomLeftRadius: menuCard.outerRadius
                                bottomRightRadius: menuCard.outerRadius
                            }
                        }

                        // Backs the strip so the edge fade has something to fade
                        // into, now that there is no card behind it.
                        Rectangle {
                            anchors.fill: parent
                            color: Appearance.m3colors.m3surfaceContainer
                        }

                        ListView {
                            id: wallpaperStrip

                            // Set on click so the tile grows right away; switchwall
                            // writing the config back is a good second later. The
                            // Connections puts it back in sync with reality after.
                            property string selectedPath: Config.options.background.wallpaperPath

                            Connections {
                                target: Config.options.background
                                function onWallpaperPathChanged(): void {
                                    wallpaperStrip.selectedPath = Config.options.background.wallpaperPath;
                                }
                            }

                            anchors.fill: parent
                            orientation: ListView.Horizontal
                            spacing: 6
                            clip: true
                            // Rubber band past the ends, like every other list here.
                            boundsBehavior: Flickable.DragOverBounds
                            model: menuColumn.shuffledWallpapers

                            // Smooths the wheel's jumps into a glide. Off while the
                            // drag or the flick owns contentX, or it fights them and
                            // the strip goes rubbery under the pointer.
                            Behavior on contentX {
                                enabled: !wallpaperStrip.dragging && !wallpaperStrip.flicking
                                NumberAnimation {
                                    id: scrollAnim
                                    duration: Appearance.animation.scroll.duration
                                    easing.type: Appearance.animation.scroll.type
                                    easing.bezierCurve: Appearance.animation.scroll.bezierCurve
                                }
                            }

                            delegate: Item {
                                id: wallpaperTile

                                required property string modelData
                                readonly property bool current: modelData === wallpaperStrip.selectedPath

                                // The one in use gets the wider tile, like the launcher's.
                                // The list repositions its neighbours every frame of
                                // this, so the whole strip slides along with it.
                                width: current ? 152 : 98
                                // Size is spatial, so it runs on the spatial spring
                                // token and is allowed the overshoot; the scrim
                                // fading over it is an effect and is not.
                                Behavior on width {
                                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                                }
                                height: wallpaperStrip.height

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colSurfaceContainerHigh
                                }

                                ThumbnailImage {
                                    id: wallpaperThumbnail
                                    anchors.fill: parent
                                    sourcePath: wallpaperTile.modelData
                                    fillMode: Image.PreserveAspectCrop
                                    // Cropping paints past the item, and the layer the
                                    // rounding mask sits on grows with it, so the top
                                    // corners come out square without this.
                                    clip: true
                                    // A tile this size crops a landscape wallpaper down
                                    // to its middle, so both the cached thumbnail and the
                                    // decode have to be bigger than the tile itself or it
                                    // is all upscale.
                                    thumbnailSizeName: "x-large"
                                    sourceSize: Qt.size(0, height * 2)
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: wallpaperThumbnail.width
                                            height: wallpaperThumbnail.height
                                            radius: Appearance.rounding.normal
                                        }
                                    }
                                }

                                // Scrim, because a light wallpaper under a light
                                // accent leaves the check mark invisible.
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Appearance.rounding.normal
                                    color: Qt.rgba(0, 0, 0, 0.35)

                                    opacity: wallpaperTile.current ? 1 : 0
                                    visible: opacity > 0
                                    Behavior on opacity {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        implicitWidth: 26
                                        implicitHeight: 26
                                        radius: Appearance.rounding.full
                                        color: Appearance.colors.colPrimary

                                        scale: wallpaperTile.current ? 1 : 0.5
                                        Behavior on scale {
                                            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                                        }

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "check"
                                            iconSize: 16
                                            color: Appearance.m3colors.m3onPrimary
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    // Stays open, so several can be tried in a row.
                                    onClicked: {
                                        wallpaperStrip.selectedPath = wallpaperTile.modelData;
                                        Wallpapers.apply(wallpaperTile.modelData);
                                    }
                                }
                            }
                        }

                        // Softens the tile the viewport cuts in half at each end.
                        ScrollEdgeFade {
                            target: wallpaperStrip
                            vertical: false
                            fadeSize: 28
                            color: Appearance.m3colors.m3surfaceContainer
                        }

                        // A horizontal Flickable ignores a vertical wheel, so without
                        // this the strip only moves by dragging. Deltas stack onto the
                        // target while the glide is still running, the way
                        // WheelScrollHandler does it for the vertical lists.
                        MouseArea {
                            id: wheelCatcher

                            property real scrollTarget: 0

                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            // It covers the tiles, so it owns the strip's cursor as
                            // well: a MouseArea claims the cursor whether or not it
                            // sets a shape, and a tile-level one is never seen.
                            cursorShape: wallpaperStrip.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                            onWheel: event => {
                                const angle = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                                const scrolling = Config?.options.interactions.scrolling;
                                const threshold = scrolling?.mouseScrollDeltaThreshold ?? 120;
                                // A wheel arrives in multiples of 120, a touchpad in
                                // small continuous deltas, so they scale differently.
                                const factor = Math.abs(angle) >= threshold ? (scrolling?.mouseScrollFactor ?? 120) : (scrolling?.touchpadScrollFactor ?? 450);
                                const base = scrollAnim.running ? wheelCatcher.scrollTarget : wallpaperStrip.contentX;
                                const maxX = Math.max(0, wallpaperStrip.contentWidth - wallpaperStrip.width);
                                wheelCatcher.scrollTarget = Math.max(0, Math.min(base - angle / threshold * factor, maxX));
                                wallpaperStrip.contentX = wheelCatcher.scrollTarget;
                            }
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        visible: GlobalStates.desktopMenuWidgetId === null
                        // Launcher3 popup rows: bg_popup_item_height 52dp,
                        // system_shortcut_icon_size 20dp, margin_start 16dp,
                        // deep_shortcut_drawable_padding 16dp between the two,
                        // each row its own surface with popup_margin 2dp between.
                        implicitHeight: 52
                        symbolSize: 20
                        sidePadding: 16
                        contentSpacing: 16
                        fontSize: Appearance.font.pixelSize.normal
                        buttonRadius: menuCard.innerRadius
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.08)
                        colRipple: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.1)
                        topLeftRadius: menuCard.outerRadius
                        topRightRadius: topLeftRadius
                        symbolName: "wallpaper"
                        labelText: Translation.tr("Change wallpaper")
                        onTriggered: {
                            menuWindow.dismiss();
                            GlobalStates.wallpaperSelectorOpen = true;
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        visible: GlobalStates.desktopMenuWidgetId === null
                        // Launcher3 popup rows: bg_popup_item_height 52dp,
                        // system_shortcut_icon_size 20dp, margin_start 16dp,
                        // deep_shortcut_drawable_padding 16dp between the two,
                        // each row its own surface with popup_margin 2dp between.
                        implicitHeight: 52
                        symbolSize: 20
                        sidePadding: 16
                        contentSpacing: 16
                        fontSize: Appearance.font.pixelSize.normal
                        buttonRadius: menuCard.innerRadius
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.08)
                        colRipple: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.1)
                        symbolName: "shuffle"
                        labelText: Translation.tr("Random wallpaper")
                        onTriggered: {
                            menuWindow.dismiss();
                            Wallpapers.randomFromCurrentFolder();
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        visible: GlobalStates.desktopMenuWidgetId === null
                        // Launcher3 popup rows: bg_popup_item_height 52dp,
                        // system_shortcut_icon_size 20dp, margin_start 16dp,
                        // deep_shortcut_drawable_padding 16dp between the two,
                        // each row its own surface with popup_margin 2dp between.
                        implicitHeight: 52
                        symbolSize: 20
                        sidePadding: 16
                        contentSpacing: 16
                        fontSize: Appearance.font.pixelSize.normal
                        buttonRadius: menuCard.innerRadius
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.08)
                        colRipple: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.1)
                        symbolName: "folder_open"
                        labelText: Translation.tr("Open wallpaper file...")
                        onTriggered: {
                            menuWindow.dismiss();
                            Wallpapers.openFallbackPicker();
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        visible: GlobalStates.desktopMenuWidgetId === null
                        // Launcher3 popup rows: bg_popup_item_height 52dp,
                        // system_shortcut_icon_size 20dp, margin_start 16dp,
                        // deep_shortcut_drawable_padding 16dp between the two,
                        // each row its own surface with popup_margin 2dp between.
                        implicitHeight: 52
                        symbolSize: 20
                        sidePadding: 16
                        contentSpacing: 16
                        fontSize: Appearance.font.pixelSize.normal
                        buttonRadius: menuCard.innerRadius
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.08)
                        colRipple: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.1)
                        symbolName: "stacks"
                        labelText: DropShelf.items.length > 0
                            ? Translation.tr("Drop shelf (%1)").arg(DropShelf.items.length)
                            : Translation.tr("Drop shelf")
                        onTriggered: {
                            menuWindow.dismiss();
                            // Reuse the click point so the shelf lands where the
                            // menu was, not back at the last drop.
                            GlobalStates.dropShelfX = GlobalStates.desktopMenuX;
                            GlobalStates.dropShelfY = GlobalStates.desktopMenuY;
                            GlobalStates.dropShelfOpen = true;
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        visible: GlobalStates.desktopMenuWidgetId === null
                        // Launcher3 popup rows: bg_popup_item_height 52dp,
                        // system_shortcut_icon_size 20dp, margin_start 16dp,
                        // deep_shortcut_drawable_padding 16dp between the two,
                        // each row its own surface with popup_margin 2dp between.
                        implicitHeight: 52
                        symbolSize: 20
                        sidePadding: 16
                        contentSpacing: 16
                        fontSize: Appearance.font.pixelSize.normal
                        buttonRadius: menuCard.innerRadius
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.08)
                        colRipple: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.1)
                        bottomLeftRadius: menuCard.outerRadius
                        bottomRightRadius: bottomLeftRadius
                        symbolName: "settings"
                        labelText: Translation.tr("Settings")
                        onTriggered: {
                            menuWindow.dismiss();
                            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")]);
                        }
                    }
                    DockMenuButton {
                        Layout.fillWidth: true
                        visible: GlobalStates.desktopMenuWidgetId !== null
                        implicitHeight: 52
                        symbolSize: 20
                        sidePadding: 16
                        contentSpacing: 16
                        fontSize: Appearance.font.pixelSize.normal
                        buttonRadius: menuCard.innerRadius
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.08)
                        colRipple: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.1)
                        topLeftRadius: menuCard.outerRadius
                        topRightRadius: topLeftRadius
                        symbolName: "flip_to_front"
                        labelText: Translation.tr("Move to upper layer")
                        onTriggered: {
                            menuWindow.dismiss();
                            let cloned = JSON.parse(JSON.stringify(Config.options.background.activeWidgets || []));
                            const index = cloned.findIndex(w => w.id === GlobalStates.desktopMenuWidgetId);
                            if (index >= 0) {
                                const item = cloned.splice(index, 1)[0];
                                cloned.push(item);
                                Config.options.background.activeWidgets = cloned;
                            }
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        visible: GlobalStates.desktopMenuWidgetId !== null
                        implicitHeight: 52
                        symbolSize: 20
                        sidePadding: 16
                        contentSpacing: 16
                        fontSize: Appearance.font.pixelSize.normal
                        buttonRadius: menuCard.innerRadius
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.08)
                        colRipple: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.1)
                        symbolName: "settings"
                        labelText: Translation.tr("Config")
                        onTriggered: {
                            menuWindow.dismiss();
                            let cloned = Config.options.background.activeWidgets || [];
                            const widgetData = cloned.find(w => w.id === GlobalStates.desktopMenuWidgetId);
                            let configPage = "";
                            if (widgetData) {
                                // Have to use absolute import path for singleton since this file is deep in a different directory
                                const meta = WidgetsRegistry.getWidgetMetadata(widgetData.widgetId);
                                if (meta && meta.configPage) {
                                    configPage = meta.configPage;
                                }
                            }
                            if (configPage !== "") {
                                Quickshell.execDetached(["env", "II_SETTINGS_PAGE=widgets", "II_SETTINGS_HIGHLIGHT=" + configPage, "qs", "-p", Quickshell.shellPath("settings.qml")]);
                            } else {
                                Quickshell.execDetached(["env", "II_SETTINGS_PAGE=widgets", "qs", "-p", Quickshell.shellPath("settings.qml")]);
                            }
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        visible: GlobalStates.desktopMenuWidgetId !== null
                        implicitHeight: 52
                        symbolSize: 20
                        sidePadding: 16
                        contentSpacing: 16
                        fontSize: Appearance.font.pixelSize.normal
                        buttonRadius: menuCard.innerRadius
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.08)
                        colRipple: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.1)
                        bottomLeftRadius: menuCard.outerRadius
                        bottomRightRadius: bottomLeftRadius
                        symbolName: "delete"
                        labelText: Translation.tr("Remove")
                        onTriggered: {
                            menuWindow.dismiss();
                            let cloned = JSON.parse(JSON.stringify(Config.options.background.activeWidgets || []));
                            cloned = cloned.filter(w => w.id !== GlobalStates.desktopMenuWidgetId);
                            Config.options.background.activeWidgets = cloned;
                        }
                    }

                }
            }
        }
    }
}
