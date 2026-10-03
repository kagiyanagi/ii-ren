import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

MouseArea {
    id: wallpaperSelectorContent
    property int columns: 4
    property real previewCellAspectRatio: 4 / 3
    property bool useDarkMode: Appearance.m3colors.darkmode
    // Single source of truth; the two bools below are the read-only views of it.
    property string viewMode: "folder" // "folder" | "favourites" | "browser"
    readonly property bool favMode: viewMode === "favourites"
    readonly property bool browserMode: viewMode === "browser"

    property var moreOptionsModelData: null
    readonly property string filterText: extraOptions.field.text

    property string activeColorFilter: ""
    property real colorCacheProgress: 0

    /** Emitted when the exit has finished, which is what unmaps the window. */
    signal closed

    // null while the wallpaper browser extension is not installed
    readonly property var browserService: ExtensionServices.get("vynx-wallpaper-browser", "wallpaperBrowserService")

    property var apiImages: {
        let allImages = [];
        const responses = browserService?.responses ?? [];
        for (let i = 0; i < responses.length; i++) {
            const images = responses[i].images ?? [];
            for (let j = 0; j < images.length; j++) {
                const img = images[j];
                allImages.push({
                    filePath: img.preview_url,
                    fileUrl: img.file_url,
                    fileName: "wallhaven-" + img.id,
                    fileIsDir: false,
                    isApi: true,
                    imageData: img
                });
            }
        }
        return allImages;
    }

    // Favourites and the colour filter are plain bindings over arrays: a ListModel
    // refilled by hand on every change needed four handlers and a deferral timer.
    readonly property var favouriteEntries: {
        const query = filterText.toLowerCase();
        return Array.from(Persistent.states.wallpaper.favourites)
            .map(path => ({ filePath: path, fileName: path.split("/").pop(), fileIsDir: false }))
            .filter(entry => entry.fileName.toLowerCase().includes(query));
    }

    readonly property var colorEntries: {
        if (!activeColorFilter) return [];
        const matches = [];
        for (const path of Wallpapers.wallpapers) {
            const colors = Wallpapers.colorCache[path] ?? [];
            let bestDist = Infinity;
            for (const color of colors)
                bestDist = Math.min(bestDist, ColorUtils.calculateDistance(activeColorFilter, color));
            if (bestDist < 0.2) matches.push({ path, bestDist });
        }
        return matches.sort((a, b) => a.bestDist - b.bestDist)
            .map(m => ({ filePath: m.path, fileName: m.path.split("/").pop(), fileIsDir: false }));
    }

    // The tile's geometry, owned here because two things draw it: the tile, and the
    // grid's mask, which cuts the tile's corners. If they disagree the mask cuts
    // the picture square or clips its label.
    readonly property real tileInset: Appearance.sizes.wallpaperSelectorItemMargins
    readonly property real tileLabelGap: 4
    TextMetrics {
        id: labelMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.smaller
        text: "Ag"
    }
    readonly property real tileLabelHeight: Math.ceil(labelMetrics.height)

    function updateThumbnails() {
        const totalImageMargin = tileInset * 2;
        const thumbnailSizeName = Images.thumbnailSizeNameForDimensions(grid.cellWidth - totalImageMargin, grid.cellHeight - totalImageMargin);
        Wallpapers.generateThumbnail(thumbnailSizeName);
    }

    Connections {
        target: Wallpapers
        function onDirectoryChanged() {
            wallpaperSelectorContent.viewMode = "folder";
            wallpaperSelectorContent.updateThumbnails();
        }
        function onChanged() {
            GlobalStates.wallpaperSelectorOpen = false;
        }
    }

    Process {
        id: colorCacheProc
        command: ["bash", Directories.extractColorsScriptPath, Wallpapers.effectiveDirectory]
        stdout: SplitParser {
            onRead: data => {
                const [progress, wallpaperCount] = data.split("/");
                wallpaperSelectorContent.colorCacheProgress = progress / wallpaperCount;
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) Wallpapers.loadColorCache();
        }
    }

    function updateColorCache() {
        colorCacheProc.running = true;
    }

    function handleFilePasting(event) {
        const currentClipboardEntry = Cliphist.entries[0];
        if (/^\d+\tfile:\/\/\S+/.test(currentClipboardEntry)) {
            const url = StringUtils.cleanCliphistEntry(currentClipboardEntry);
            Wallpapers.setDirectory(FileUtils.trimFileProtocol(decodeURIComponent(url)));
            event.accepted = true;
        } else {
            event.accepted = false; // No image, let text pasting proceed
        }
    }

    function selectWallpaperPath(filePath) {
        if (!filePath || filePath.length === 0) return;
        Wallpapers.select(filePath, wallpaperSelectorContent.useDarkMode);
        extraOptions.field.text = "";
        wallpaperSelectorContent.viewMode = "folder";
    }

    // A browser tile's filePath is its preview; the wallpaper is the full image.
    function activate(entry) {
        if (!entry) return;
        selectWallpaperPath(entry.isApi ? entry.fileUrl : entry.filePath);
    }

    function getWallhavenId(url) {
        if (!url) return null;
        const fileName = url.toString().split('/').pop();
        const match = fileName.split('.')[0].match(/^wallhaven-([a-zA-Z0-9]{6})$/i);
        return match ? match[1] : null;
    }

    function searchForSimilarImages(id) {
        browserService.clearResponses();
        browserService.moreLikeThisPicture(id, 1);
        wallpaperSelectorContent.viewMode = "browser";
        extraOptions.field.text = "";
    }

    function toggleFavourite(path) {
        const favs = Array.from(Persistent.states.wallpaper.favourites);
        const index = favs.indexOf(path);
        if (index === -1)
            favs.push(path);
        else
            favs.splice(index, 1);
        Persistent.states.wallpaper.favourites = favs;
    }

    acceptedButtons: Qt.BackButton | Qt.ForwardButton
    onPressed: event => {
        if (event.button === Qt.BackButton)
            Wallpapers.folderModel.navigateBack();
        else if (event.button === Qt.ForwardButton)
            Wallpapers.folderModel.navigateForward();
    }

    Keys.onPressed: event => {
        const field = extraOptions.field;
        event.accepted = true;
        if (event.key === Qt.Key_Escape) {
            // The contextual toolbar is the innermost thing open, so it goes first.
            if (wallpaperSelectorContent.moreOptionsModelData)
                wallpaperSelectorContent.moreOptionsModelData = null;
            else
                GlobalStates.wallpaperSelectorOpen = false;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { // "paste to go to"
            wallpaperSelectorContent.handleFilePasting(event);
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Up) {
            Wallpapers.folderModel.navigateUp();
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Left) {
            Wallpapers.folderModel.navigateBack();
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Right) {
            Wallpapers.folderModel.navigateForward();
        } else if (event.key === Qt.Key_Left) {
            grid.moveSelection(-1);
        } else if (event.key === Qt.Key_Right) {
            grid.moveSelection(1);
        } else if (event.key === Qt.Key_Up) {
            grid.moveSelection(-grid.columns);
        } else if (event.key === Qt.Key_Down) {
            grid.moveSelection(grid.columns);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            grid.activateCurrent();
        } else if (event.key === Qt.Key_Backspace) {
            field.remove(field.length - 1, field.length);
            field.forceActiveFocus();
        } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_L) {
            addressBar.focusBreadcrumb();
        } else if (event.key === Qt.Key_Slash) {
            field.forceActiveFocus();
        } else if (event.text.length > 0) {
            field.insert(field.length, event.text);
            field.forceActiveFocus();
        }
    }

    implicitHeight: mainLayout.implicitHeight
    implicitWidth: mainLayout.implicitWidth

    Item {
        id: surface
        anchors.fill: parent
        // A sheet hanging from the bar: it slides down out of the window's top
        // edge, right under the bar, and back up into it (DESIGN.md 9, sheet).
        // No fade and no scale -- the window clips it, so it reads as coming out
        // from under the bar rather than appearing in place.

        // Flipped after creation so the Behavior is live for the enter: a Behavior
        // does not run during initial binding evaluation.
        property bool shown: false
        Component.onCompleted: shown = true

        // Enter over the elementMoveFast duration (200ms) on
        // emphasizedDecel -- 500 and 350 both read as slow -- and exit half of it on
        // emphasizedAccel (2.4, 2.5), both assigned inside the one binding that
        // writes `reveal` (2.9). emphasizedDecel does not overshoot, so the sheet
        // never dips below its rest and gets its bottom cut by the window.
        property int revealDuration: Appearance.animation.elementMoveFast.duration
        property list<real> revealCurve: Appearance.animationCurves.emphasizedDecel
        property real reveal: {
            const entering = surface.shown && GlobalStates.wallpaperSelectorOpen;
            surface.revealDuration = entering ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMoveExit.duration;
            surface.revealCurve = entering ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel;
            return entering ? 1 : 0;
        }
        Behavior on reveal {
            NumberAnimation {
                duration: surface.revealDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: surface.revealCurve
            }
        }
        onRevealChanged: {
            if (surface.reveal === 0 && !GlobalStates.wallpaperSelectorOpen) wallpaperSelectorContent.closed();
            // The thumbnail job spawns a process and floods the grid with image
            // loads; started with the slide, it made the slide drop frames.
            if (surface.reveal === 1 && !surface.thumbnailsStarted) {
                surface.thumbnailsStarted = true;
                wallpaperSelectorContent.updateThumbnails();
            }
        }
        property bool thumbnailsStarted: false

        transform: Translate {
            y: -surface.height * (1 - surface.reveal)
        }

        StyledRectangularShadow {
            target: wallpaperGridBackground
        }
        Rectangle {
            id: wallpaperGridBackground
            anchors {
                fill: parent
                margins: Appearance.sizes.elevationMargin
            }
            focus: true
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            color: Appearance.colors.colLayer0
            radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

            implicitWidth: gridColumnLayout.implicitWidth
            implicitHeight: gridColumnLayout.implicitHeight

            RowLayout {
                id: mainLayout
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    Layout.fillHeight: true
                    Layout.margins: 4
                    Layout.rightMargin: 0
                    implicitWidth: quickDirColumnLayout.implicitWidth
                    implicitHeight: quickDirColumnLayout.implicitHeight
                    color: Appearance.colors.colLayer1
                    radius: wallpaperGridBackground.radius - Layout.margins

                    ColumnLayout {
                        id: quickDirColumnLayout
                        anchors.fill: parent
                        spacing: 0

                        StyledText {
                            Layout.margins: 12
                            font {
                                pixelSize: Appearance.font.pixelSize.normal
                                weight: Font.Medium
                            }
                            text: Translation.tr("Pick a wallpaper")
                        }
                        Item {
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                            implicitWidth: 160

                            Flickable {
                                id: sideBarFlickable
                                anchors.fill: parent
                                contentHeight: sideBarRail.implicitHeight
                                clip: true
                                interactive: contentHeight > height

                                ScrollBar.vertical: StyledScrollBar {
                                    visible: sideBarFlickable.interactive
                                }

                                NavigationRailTabArray {
                                    id: sideBarRail
                                    anchors {
                                        top: parent.top
                                        left: parent.left
                                        right: parent.right
                                        leftMargin: 8
                                        rightMargin: 8
                                    }
                                    expanded: true
                                    currentIndex: {
                                        const model = sideBarRepeater.model;
                                        for (let i = 0; i < model.length; i++) {
                                            const path = model[i].path;
                                            if (path === "FAVOURITES_MODE" ? wallpaperSelectorContent.favMode
                                                : path === "BROWSER_MODE" ? wallpaperSelectorContent.browserMode
                                                : wallpaperSelectorContent.viewMode === "folder" && Wallpapers.directory === Qt.resolvedUrl(path))
                                                return i;
                                        }
                                        return -1;
                                    }

                                    Repeater {
                                        id: sideBarRepeater
                                        // Where wallpapers are kept first, then the two views
                                        // over them, then the places they may have landed.
                                        // No divider row between the groups (law 11): the rail's
                                        // indicator assumes rows of one height.
                                        model: [
                                            ...Config.options.wallpaperSelector.directories,
                                            ...(Config.options.policies.weeb === 1 ? [{ icon: "favorite", name: Translation.tr("Homework"), path: `${Directories.pictures}/homework` }] : []),
                                            { icon: "favorite", name: Translation.tr("Favourites"), path: "FAVOURITES_MODE" },
                                            ...(ExtensionManager.installedExtensions["vynx-wallpaper-browser"] ? [{ icon: "public", name: Translation.tr("Browser"), path: "BROWSER_MODE" }] : []),
                                            { icon: "image", name: Translation.tr("Pictures"), path: Directories.pictures },
                                            { icon: "download", name: Translation.tr("Downloads"), path: Directories.downloads },
                                            { icon: "movie", name: Translation.tr("Videos"), path: Directories.videos },
                                            { icon: "home", name: Translation.tr("Home"), path: Directories.home },
                                        ]
                                        delegate: NavigationRailButton {
                                            id: quickDirButton
                                            required property var modelData
                                            required property int index

                                            baseSize: 40
                                            baseHighlightHeight: 32
                                            iconSize: 18

                                            buttonIcon: modelData.icon
                                            buttonText: modelData.name
                                            expanded: true
                                            toggled: sideBarRail.currentIndex === index
                                            showToggledHighlight: false

                                            onClicked: {
                                                const path = quickDirButton.modelData.path;
                                                if (path === "FAVOURITES_MODE") {
                                                    wallpaperSelectorContent.viewMode = "favourites";
                                                } else if (path === "BROWSER_MODE") {
                                                    wallpaperSelectorContent.viewMode = "browser";
                                                } else {
                                                    wallpaperSelectorContent.viewMode = "folder";
                                                    Wallpapers.setDirectory(path);
                                                }
                                                wallpaperSelectorContent.moreOptionsModelData = null;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    id: gridColumnLayout
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    AddressBar {
                        id: addressBar
                        Layout.margins: 4
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        directory: Wallpapers.effectiveDirectory
                        visible: wallpaperSelectorContent.viewMode === "folder"
                        onNavigateToDirectory: path => {
                            Wallpapers.setDirectory(path.length == 0 ? "/" : path);
                        }
                        radius: wallpaperGridBackground.radius - Layout.margins
                    }

                    Rectangle {
                        visible: wallpaperSelectorContent.viewMode !== "folder"
                        Layout.margins: 4
                        Layout.fillWidth: true
                        implicitHeight: addressBar.implicitHeight
                        color: Appearance.colors.colLayer2
                        radius: wallpaperGridBackground.radius - Layout.margins

                        RowLayout {
                            spacing: 12
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 16
                            }

                            MaterialSymbol {
                                text: wallpaperSelectorContent.browserMode ? "public" : "favorite"
                                color: Appearance.colors.colPrimary
                                iconSize: Appearance.font.pixelSize.larger
                            }
                            ConfigSelectionArray {
                                options: {
                                    const items = [{ displayName: wallpaperSelectorContent.browserMode ? Translation.tr("Wallpaper browser") : Translation.tr("Favourites"), isRoot: true }];
                                    if (wallpaperSelectorContent.browserMode)
                                        for (const tag of wallpaperSelectorContent.browserService?.currentSearchTags ?? [])
                                            items.push({ displayName: tag, value: tag });
                                    return items;
                                }
                                onSelected: newValue => {
                                    if (!newValue) return;
                                    wallpaperSelectorContent.moreOptionsModelData = null;
                                    wallpaperSelectorContent.browserService.clearResponses();
                                    wallpaperSelectorContent.browserService.makeRequest([newValue], 20, 1);
                                }
                            }
                        }
                    }

                    Item {
                        id: gridDisplayRegion
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        StyledIndeterminateProgressBar {
                            id: indeterminateProgressBar
                            visible: (Wallpapers.thumbnailGenerationRunning && Wallpapers.thumbnailGenerationProgress == 0)
                                || (wallpaperSelectorContent.browserMode && wallpaperSelectorContent.browserService?.runningRequests > 0)
                                || (wallpaperSelectorContent.colorCacheProgress === 0 && colorCacheProc.running)
                            anchors {
                                bottom: parent.top
                                left: parent.left
                                right: parent.right
                                leftMargin: 4
                                rightMargin: 4
                            }
                        }

                        StyledProgressBar {
                            visible: wallpaperSelectorContent.colorCacheProgress > 0 && wallpaperSelectorContent.colorCacheProgress < 1
                            value: wallpaperSelectorContent.colorCacheProgress
                            anchors.fill: indeterminateProgressBar
                        }

                        StyledProgressBar {
                            visible: Wallpapers.thumbnailGenerationRunning && value > 0
                            value: Wallpapers.thumbnailGenerationProgress
                            anchors.fill: indeterminateProgressBar
                        }

                        PagePlaceholder {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -extraOptions.implicitHeight / 2
                            // A folder reads as empty for a frame while it is still being listed.
                            shown: grid.count === 0 && !indeterminateProgressBar.visible
                                && (wallpaperSelectorContent.viewMode !== "folder" || Wallpapers.folderModel.status === FolderListModel.Ready)
                            // Checked in the order the grid picks its model, so it
                            // names the view that is actually empty.
                            readonly property var why: {
                                const c = wallpaperSelectorContent;
                                const searched = c.filterText.length > 0;
                                if (c.browserMode) return ["public", Translation.tr("Search for wallpapers"), Translation.tr("Type tags in the search field and press Enter")];
                                if (c.favMode && searched) return ["search_off", Translation.tr("No matches"), Translation.tr("No favourite is named like that")];
                                if (c.favMode) return ["favorite", Translation.tr("No favourites yet"), Translation.tr("Right-click a wallpaper and tap the heart")];
                                if (c.activeColorFilter) return ["palette", Translation.tr("Nothing in that colour"), Translation.tr("Try another colour, or turn the filter off")];
                                if (searched) return ["search_off", Translation.tr("No matches"), Translation.tr("Nothing in this folder is named like that")];
                                return ["hide_image", Translation.tr("No wallpapers here"), Translation.tr("This folder has no pictures or videos in it")];
                            }
                            icon: why[0]
                            title: why[1]
                            description: why[2]
                        }

                        GridView {
                            id: grid

                            readonly property int columns: wallpaperSelectorContent.columns
                            property int currentIndex: 0
                            // Focus only shows once the keyboard has moved it or a filter
                            // says what Enter would pick. A pointer resting on one tile
                            // must not leave a second one looking selected.
                            property bool keyboardMoved: false
                            readonly property bool showFocus: keyboardMoved || wallpaperSelectorContent.filterText.length > 0

                            anchors.fill: parent
                            cellWidth: width / wallpaperSelectorContent.columns
                            cellHeight: cellWidth / wallpaperSelectorContent.previewCellAspectRatio
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            bottomMargin: extraOptions.implicitHeight
                            // Outside the grid, or the mask below would cut it away.
                            ScrollBar.vertical: StyledScrollBar {
                                parent: gridDisplayRegion
                                anchors {
                                    top: grid.top
                                    bottom: grid.bottom
                                    right: grid.right
                                }
                            }


                            function moveSelection(delta) {
                                keyboardMoved = true;
                                currentIndex = Math.max(0, Math.min(count - 1, currentIndex + delta));
                                positionViewAtIndex(currentIndex, GridView.Contain);
                            }

                            function activateCurrent() {
                                positionViewAtIndex(currentIndex, GridView.Contain);
                                wallpaperSelectorContent.activate(itemAtIndex(currentIndex)?.fileModelData);
                            }

                            model: wallpaperSelectorContent.browserMode ? wallpaperSelectorContent.apiImages
                                : wallpaperSelectorContent.favMode ? wallpaperSelectorContent.favouriteEntries
                                : wallpaperSelectorContent.activeColorFilter ? wallpaperSelectorContent.colorEntries
                                : Wallpapers.folderModel
                            onModelChanged: currentIndex = 0
                            onCountChanged: currentIndex = Math.min(currentIndex, Math.max(0, count - 1))

                            delegate: WallpaperDirectoryItem {
                                required property var modelData
                                required property int index
                                fileModelData: modelData
                                width: grid.cellWidth
                                height: grid.cellHeight
                                inset: wallpaperSelectorContent.tileInset
                                labelGap: wallpaperSelectorContent.tileLabelGap
                                labelHeight: wallpaperSelectorContent.tileLabelHeight
                                current: modelData.filePath === Config.options.background.wallpaperPath
                                ringed: (grid.showFocus && index === grid.currentIndex)
                                    || (wallpaperSelectorContent.moreOptionsModelData !== null && modelData.filePath === wallpaperSelectorContent.moreOptionsModelData.filePath)

                                onPositionChanged: grid.keyboardMoved = false
                                onActivated: wallpaperSelectorContent.activate(modelData)
                                onMoreOptionsRequested: data => {
                                    grid.currentIndex = index;
                                    wallpaperSelectorContent.moreOptionsModelData = data;
                                }
                            }

                            // One mask for the whole grid, drawn from one rounded card per
                            // visible cell, instead of an OpacityMask inside every tile
                            // (DESIGN.md 8). Cells are uniform, so the mask is the same
                            // tile repeated, shifted by how far into a row the view is.
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: tileMask
                            }
                        }

                        Item {
                            id: tileMask
                            visible: false
                            width: grid.width
                            height: grid.height
                            readonly property real phase: {
                                const offset = (grid.contentY - grid.originY) % grid.cellHeight;
                                return offset < 0 ? offset + grid.cellHeight : offset;
                            }

                            Repeater {
                                model: grid.cellHeight > 0 ? grid.columns * (Math.ceil(grid.height / grid.cellHeight) + 1) : 0
                                delegate: Item {
                                    required property int index
                                    // Same numbers the tile lays its card out with.
                                    readonly property real inset: wallpaperSelectorContent.tileInset
                                    readonly property real cardHeight: grid.cellHeight - inset * 2 - wallpaperSelectorContent.tileLabelGap - wallpaperSelectorContent.tileLabelHeight
                                    x: (index % grid.columns) * grid.cellWidth
                                    y: Math.floor(index / grid.columns) * grid.cellHeight - tileMask.phase
                                    width: grid.cellWidth
                                    height: grid.cellHeight

                                    Rectangle {
                                        x: parent.inset
                                        y: parent.inset
                                        width: parent.width - parent.inset * 2
                                        height: parent.cardHeight
                                        radius: Appearance.rounding.normal
                                    }
                                    Rectangle { // the label strip
                                        x: parent.inset
                                        y: parent.inset + parent.cardHeight
                                        width: parent.width - parent.inset * 2
                                        height: parent.height - y
                                    }
                                }
                            }
                        }

                        ColorFilterToolbar {
                            id: colorFilterToolbar
                            colBackground: Appearance.m3colors.m3surfaceContainerLow
                            anchors {
                                bottom: parent.bottom
                                left: parent.left
                                leftMargin: 16
                                bottomMargin: 8
                            }
                        }

                        ExtraOptionsToolbar {
                            id: extraOptions
                            colBackground: Appearance.m3colors.m3surfaceContainerLow
                            anchors {
                                bottom: parent.bottom
                                horizontalCenter: parent.horizontalCenter
                                bottomMargin: 8
                            }
                        }

                        ImageOptionsToolbar {
                            z: 1
                            colBackground: Appearance.colors.colPrimary
                            anchors {
                                bottom: parent.bottom
                                bottomMargin: 8
                                right: parent.right
                                rightMargin: 16
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen) {
                if (panelWindow.monitorIsFocused) extraOptions.field.forceActiveFocus();
            } else {
                colorCacheProc.signal(9);
                // Closed before the enter began: there is no exit to wait for.
                if (surface.reveal === 0) wallpaperSelectorContent.closed();
            }
        }
    }

    Component.onCompleted: if (panelWindow.monitorIsFocused) extraOptions.field.forceActiveFocus()
}
