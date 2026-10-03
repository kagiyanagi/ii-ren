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

    // Every row in the card, in both modes. Written once because ten copies of
    // the same twelve properties is ten places for one of them to drift.
    //
    // Launcher3 popup rows: bg_popup_item 216x52dp, system_shortcut_icon_size
    // 20dp, margin_start 16dp, deep_shortcut_drawable_padding 16dp between the
    // two, each row its own surface with popup_margin 2dp between. The big
    // radius belongs to the ends of the stack, so the first and last row of
    // each mode's group sets it and the rest keep the small one.
    component MenuRow: DockMenuButton {
        id: menuRow

        Layout.fillWidth: true
        implicitHeight: 52
        symbolSize: 20
        sidePadding: 16
        contentSpacing: 16
        fontSize: Appearance.font.pixelSize.normal
        buttonRadius: Appearance.rounding.unsharpenmore

        // The rows sit on their own surface, not on the card, so the state
        // layers mix against that one: hover 0.08, pressed 0.10 (DESIGN 6).
        colBackground: Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.08)
        colRipple: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.1)

        // The card grabs the keyboard outright, and `ipc call desktopMenu
        // toggle` opens it with no cursor anywhere near it, so the keyboard has
        // to be able to work it. RippleButton fires its actions from its own
        // MouseArea, so the keys take the same path (DESIGN 3.7), exactly as
        // SysTrayMenuEntry does. Anything not handled here falls through to the
        // column, which dismisses.
        focusPolicy: Qt.StrongFocus
        Keys.onUpPressed: menuRow.nextItemInFocusChain(false)?.forceActiveFocus(Qt.TabFocusReason)
        Keys.onDownPressed: menuRow.nextItemInFocusChain(true)?.forceActiveFocus(Qt.TabFocusReason)
        Keys.onReturnPressed: menuRow.triggered()
        Keys.onEnterPressed: menuRow.triggered()
        Keys.onSpacePressed: menuRow.triggered()
    }

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
                // Which half of the placed card the cursor fell in, which is the
                // same question as which corner is nearest to it. Comparing the
                // card's edge against the cursor instead -- `x >= cursorX` --
                // agrees everywhere until the edge clamp bites, and then is
                // wrong for the next half a card width: the card shifts one
                // pixel, the cursor is one pixel inside the left edge, and the
                // menu grows out of the far corner instead. That is a 160px band
                // down the right edge of every screen, and another down the
                // bottom. check-desktop-menu.py sweeps both.
                readonly property bool leftAligned: GlobalStates.desktopMenuX <= x + width / 2
                readonly property bool topAligned: GlobalStates.desktopMenuY <= y + height / 2

                // Opens with its top-left at the cursor, like every other context
                // menu, and slides back inside the screen near an edge.
                x: Math.max(gutter, Math.min(GlobalStates.desktopMenuX, menuWindow.width - width - gutter))
                y: Math.max(gutter, Math.min(GlobalStates.desktopMenuY, menuWindow.height - height - gutter))

                // Ends of the stack, inset inside the card, so smaller than the
                // card's own corner. The rows' own small radius is MenuRow's.
                readonly property real outerRadius: Appearance.rounding.normal
                readonly property real padding: 6

                implicitWidth: 320
                implicitHeight: menuColumn.implicitHeight + 2 * padding
                radius: Appearance.rounding.large
                color: Appearance.m3colors.m3surfaceContainer

                opacity: 0
                scale: Appearance.animationCurves.arrowPopupScale

                // Launcher3 ArrowPopup.setPivotForOpenCloseAnimation(): the popup
                // grows out of the corner nearest the touch point, so follow the
                // cursor rather than the corner the edge clamp left it on.
                transformOrigin: leftAligned ? (topAligned ? Item.TopLeft : Item.BottomLeft) : (topAligned ? Item.TopRight : Item.BottomRight)

                // ArrowPopup.animateOpen(), assembled from the transcribed
                // composite (DESIGN.md 9): the scale overshoots and settles on
                // its own curve while the alpha rides underneath, so the content
                // lands while the card is still growing. Same shape, from the
                // same tokens, as StyledPopup and SysTrayMenu -- typing the
                // numbers again beside them is how the four drift apart.
                ParallelAnimation {
                    id: openAnim
                    running: true

                    SequentialAnimation {
                        NumberAnimation {
                            target: menuCard
                            property: "scale"
                            from: Appearance.animationCurves.arrowPopupScale
                            to: Appearance.animationCurves.arrowPopupOvershoot
                            duration: Appearance.animationCurves.arrowPopupScaleDuration
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                        NumberAnimation {
                            target: menuCard
                            property: "scale"
                            to: 1
                            duration: Appearance.animationCurves.arrowPopupScaleDuration
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Appearance.animationCurves.arrowPopupSettle
                        }
                    }
                    NumberAnimation {
                        target: menuCard
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Appearance.animationCurves.arrowPopupFadeDuration
                    }
                    NumberAnimation {
                        target: menuColumn
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Appearance.animationCurves.arrowPopupFadeDuration
                    }
                }

                // ArrowPopup.animateClose(): accelerating, with the fades held
                // back, and shorter than the open so leaving does not feel like
                // entering played backwards (DESIGN.md 2.5). The hold plus the
                // fade is the close duration exactly.
                ParallelAnimation {
                    id: closeAnim

                    NumberAnimation {
                        target: menuCard
                        property: "scale"
                        to: Appearance.animationCurves.arrowPopupScale
                        duration: Appearance.animationCurves.arrowPopupCloseDuration
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                    }
                    SequentialAnimation {
                        PauseAnimation {
                            duration: Appearance.animationCurves.arrowPopupFadeHold
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: menuCard
                                property: "opacity"
                                to: 0
                                duration: Appearance.animationCurves.arrowPopupFadeDuration
                            }
                            NumberAnimation {
                                target: menuColumn
                                property: "opacity"
                                to: 0
                                duration: Appearance.animationCurves.arrowPopupFadeDuration
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
                        const isImageOrVideo = (p) => Images.isValidImageByName(p.toLowerCase()) || Wallpapers.isVideoFile(p.toLowerCase());
                        const rest = Wallpapers.wallpapers.filter(path => isImageOrVideo(path) && path !== current);
                        for (let i = rest.length - 1; i > 0; i--) {
                            const j = Math.floor(Math.random() * (i + 1));
                            [rest[i], rest[j]] = [rest[j], rest[i]];
                        }
                        return isImageOrVideo(current) ? [current, ...rest] : rest;
                    }

                    anchors.fill: parent
                    anchors.margins: menuCard.padding
                    spacing: 2

                    focus: true
                    // Up and Down step into the row chain -- from the column,
                    // forward lands on the first row and backward wraps to the
                    // last, which is what a menu does. Any other key is the
                    // signal the menu is done: the keyboard belongs to whatever
                    // was focused before this took it.
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up)
                            menuColumn.nextItemInFocusChain(event.key === Qt.Key_Down)?.forceActiveFocus(Qt.TabFocusReason);
                        else
                            menuWindow.dismiss();
                        event.accepted = true;
                    }

                    Item {
                        id: stripViewport

                        Layout.fillWidth: true
                        Layout.preferredHeight: 132
                        Layout.bottomMargin: 6
                        // One entry means the only wallpaper on offer is the one
                        // already applied, so the strip is 132dp of card that can
                        // only re-select what is selected. It earns its space from
                        // two up.
                        visible: wallpaperStrip.count > 1 && GlobalStates.desktopMenuWidgetId === null

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
                                    // An effect inside a delegate, which rule 8
                                    // forbids, and kept anyway: it is in
                                    // check-effect-budget.py's KNOWN set and every
                                    // way out costs more per tile than the one
                                    // framebuffer it removes. See notes.md.
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

                    // -- Desktop mode ------------------------------------------

                    MenuRow {
                        visible: GlobalStates.desktopMenuWidgetId === null
                        topLeftRadius: menuCard.outerRadius
                        topRightRadius: topLeftRadius
                        symbolName: "wallpaper"
                        labelText: Translation.tr("Change wallpaper")
                        onTriggered: {
                            menuWindow.dismiss();
                            GlobalStates.wallpaperSelectorOpen = true;
                        }
                    }

                    MenuRow {
                        visible: GlobalStates.desktopMenuWidgetId === null
                        symbolName: "shuffle"
                        labelText: Translation.tr("Random wallpaper")
                        onTriggered: {
                            menuWindow.dismiss();
                            Wallpapers.randomFromCurrentFolder();
                        }
                    }

                    MenuRow {
                        visible: GlobalStates.desktopMenuWidgetId === null
                        symbolName: "folder_open"
                        labelText: Translation.tr("Open wallpaper file")
                        onTriggered: {
                            menuWindow.dismiss();
                            Wallpapers.openFallbackPicker();
                        }
                    }

                    MenuRow {
                        visible: GlobalStates.desktopMenuWidgetId === null
                        symbolName: "stacks"
                        labelText: DropShelf.items.length > 0 ? Translation.tr("Drop shelf (%1)").arg(DropShelf.items.length) : Translation.tr("Drop shelf")
                        onTriggered: {
                            menuWindow.dismiss();
                            // Reuse the click point so the shelf lands where the
                            // menu was, not back at the last drop.
                            GlobalStates.dropShelfScreen = GlobalStates.desktopMenuScreen;
                            GlobalStates.dropShelfX = GlobalStates.desktopMenuX;
                            GlobalStates.dropShelfY = GlobalStates.desktopMenuY;
                            GlobalStates.dropShelfOpen = true;
                        }
                    }

                    MenuRow {
                        visible: GlobalStates.desktopMenuWidgetId === null
                        bottomLeftRadius: menuCard.outerRadius
                        bottomRightRadius: bottomLeftRadius
                        symbolName: "settings"
                        labelText: Translation.tr("Settings")
                        onTriggered: {
                            menuWindow.dismiss();
                            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")]);
                        }
                    }

                    // -- Widget mode -------------------------------------------

                    MenuRow {
                        visible: GlobalStates.desktopMenuWidgetId !== null
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

                    MenuRow {
                        visible: GlobalStates.desktopMenuWidgetId !== null
                        symbolName: "flip_to_back"
                        labelText: Translation.tr("Move to lower layer")
                        onTriggered: {
                            menuWindow.dismiss();
                            let cloned = JSON.parse(JSON.stringify(Config.options.background.activeWidgets || []));
                            const index = cloned.findIndex(w => w.id === GlobalStates.desktopMenuWidgetId);
                            if (index >= 0) {
                                const item = cloned.splice(index, 1)[0];
                                cloned.unshift(item);
                                Config.options.background.activeWidgets = cloned;
                            }
                        }
                    }

                    // Which side of the wallpaper's subject this widget sits
                    // on. Only worth offering once there is a subject to sit
                    // behind, so it hides itself the rest of the time.
                    MenuRow {
                        id: depthButton

                        readonly property bool above: {
                            const widgets = Config.options.background.activeWidgets || [];
                            const entry = widgets.find(w => w.id === GlobalStates.desktopMenuWidgetId);
                            return entry?.aboveSubject ?? false;
                        }

                        visible: GlobalStates.desktopMenuWidgetId !== null && Config.options.background.depth.desktop.enable && WallpaperSubject.hasSubject
                        // Depth of field, which is what the effect is: the
                        // widget either sits in the sharp foreground or falls
                        // in behind it. Both glyphs are old enough to be in
                        // every Material Symbols build in the wild, which the
                        // newer format_image_front/back pair is not.
                        symbolName: depthButton.above ? "center_focus_weak" : "center_focus_strong"
                        labelText: depthButton.above ? Translation.tr("Move behind subject") : Translation.tr("Move in front of subject")
                        onTriggered: {
                            menuWindow.dismiss();
                            let cloned = JSON.parse(JSON.stringify(Config.options.background.activeWidgets || []));
                            const index = cloned.findIndex(w => w.id === GlobalStates.desktopMenuWidgetId);
                            if (index >= 0) {
                                cloned[index].aboveSubject = !depthButton.above;
                                Config.options.background.activeWidgets = cloned;
                            }
                        }
                    }

                    MenuRow {
                        visible: GlobalStates.desktopMenuWidgetId !== null
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

                    MenuRow {
                        visible: GlobalStates.desktopMenuWidgetId !== null
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
