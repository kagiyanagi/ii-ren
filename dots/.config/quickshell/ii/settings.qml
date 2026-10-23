//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Qt 6.11 defaults to its native PipeWire audio backend, whose QAudioContext thread
// segfaults the shell inside libpipewire-module-protocol-native when sounds play.
// Its PulseAudio backend (through pipewire-pulse) does not.
//@ pragma Env QT_AUDIO_BACKEND=pulseaudio

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import qs.modules.settings
// Unused here, and load-bearing: Quickshell only registers the types of a
// directory something imports as a qs. module. Without it the widget config
// pages, loaded by URL, cannot see their siblings (DesktopWidgetVisualOptions,
// FingerprintEnrollOverlay) and open empty.
import qs.modules.settings.widgets

ApplicationWindow {
    id: root
    property string firstRunFilePath: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property real contentPadding: 8
    property bool showNextTime: false

    property int currentPage: {
        const idx = root.pageIndexById(Quickshell.env("II_SETTINGS_PAGE"));
        return idx !== -1 ? idx : root.pageIndexById("quick");
    }
    property string pendingSectionHighlight: Quickshell.env("II_SETTINGS_HIGHLIGHT") || ""

    // Search. Results show in place of the page list while there is a query;
    // the cursor is where Enter goes, moved with the arrow keys, and the opened
    // result stays marked so another can be tried without typing again.
    readonly property string searchQuery: searchInput.text.trim()
    readonly property bool searching: searchQuery.length > 0
    readonly property var searchResults: searching && SearchRegistry.ready ? SearchRegistry.query(searchQuery) : []
    property int searchCursor: 0
    property string openedResult: ""
    // A result on another page waits here until that page has loaded.
    property var pendingSearch: null

    property var pages: [
        {
            id: "profiles",
            name: Translation.tr("Profiles"),
            summary: Translation.tr("Saved setups"),
            icon: "switch_account",
            component: "modules/settings/ProfilesConfig.qml"
        },
        {
            id: "quick",
            name: Translation.tr("Quick"),
            summary: Translation.tr("Wallpaper, colours, eye protection"),
            icon: "instant_mix",
            component: "modules/settings/QuickConfig.qml"
        },
        {
            id: "general",
            name: Translation.tr("General"),
            summary: Translation.tr("Audio, language, policies, time"),
            icon: "browse",
            component: "modules/settings/GeneralConfig.qml"
        },
        {
            id: "battery",
            name: Translation.tr("Battery"),
            summary: Translation.tr("Power mode, charging, health"),
            icon: "battery_android_full",
            component: "modules/settings/BatteryConfig.qml"
        },
        {
            id: "sounds",
            name: Translation.tr("Sounds"),
            summary: Translation.tr("Alerts, system sounds"),
            icon: "volume_up",
            component: "modules/settings/SoundsConfig.qml"
        },
        {
            id: "bar",
            name: Translation.tr("Bar"),
            summary: Translation.tr("Layout, position, clock"),
            icon: "toast",
            iconRotation: 180,
            component: "modules/settings/BarConfig.qml"
        },
        {
            id: "background",
            name: Translation.tr("Background"),
            summary: Translation.tr("Wallpaper, parallax, effects"),
            icon: "texture",
            component: "modules/settings/BackgroundConfig.qml"
        },
        {
            id: "widgets",
            name: Translation.tr("Widgets"),
            summary: Translation.tr("Clocks, media, weather, desktop"),
            icon: "widgets",
            component: "modules/settings/WidgetsConfig.qml"
        },
        {
            id: "interface",
            name: Translation.tr("Interface"),
            summary: Translation.tr("Dock, notifications, overlay"),
            icon: "bottom_app_bar",
            component: "modules/settings/InterfaceConfig.qml"
        },
        {
            id: "services",
            name: Translation.tr("Services"),
            summary: Translation.tr("Media, networking, recording"),
            icon: "api",
            component: "modules/settings/ServicesConfig.qml"
        },
        {
            id: "agent",
            name: Translation.tr("Agent"),
            summary: Translation.tr("Claude Code, Codex, Antigravity"),
            icon: "auto_awesome",
            component: "modules/settings/AgentConfig.qml"
        },
        {
            id: "extensions",
            name: Translation.tr("Extensions"),
            summary: Translation.tr("Installed and available"),
            icon: "extension",
            component: "modules/settings/ExtensionsConfig.qml"
        },
        {
            id: "hyprland",
            name: Translation.tr("Hyprland"),
            summary: Translation.tr("Displays, input, windows"),
            icon: "desktop_windows",
            component: "modules/settings/HyprlandConfig.qml"
        },
        {
            id: "lock",
            name: Translation.tr("Lock screen"),
            summary: Translation.tr("Appearance, security"),
            icon: "lock",
            component: "modules/settings/LockConfig.qml"
        },
        {
            id: "advanced",
            name: Translation.tr("Advanced"),
            summary: Translation.tr("Colour generation, icons, fonts"),
            icon: "construction",
            component: "modules/settings/AdvancedConfig.qml"
        },
        {
            id: "about",
            name: Translation.tr("About"),
            summary: Translation.tr("Hardware, this shell, credits"),
            icon: "info",
            component: "modules/settings/About.qml"
        }
    ]

    function pageIndexById(id) {
        if (!id) return -1;
        for (let i = 0; i < pages.length; i++) {
            if (pages[i].id === id) return i;
        }
        return -1;
    }

    function openPage(index) {
        root.pendingSearch = null;
        SearchRegistry.target = null;
        root.currentPage = index;
    }

    function moveSearchCursor(delta) {
        if (root.searchResults.length === 0) return;
        root.searchCursor = Math.max(0, Math.min(root.searchCursor + delta, root.searchResults.length - 1));
        resultsList.positionViewAtIndex(root.searchCursor, ListView.Contain);
    }

    // Opens the page the result is on, then its sub-page, and leaves the row to
    // its SearchHandler, which scrolls to it and flashes it.
    function openSearchResult(index) {
        const result = root.searchResults[index];
        if (!result) return;
        const entry = result.entry;
        root.searchCursor = index;
        root.openedResult = result.key;
        SearchRegistry.target = null;
        root.pendingSearch = {
            subPage: entry.subPage,
            target: {
                label: result.label,
                section: entry.section ? Translation.tr(entry.section) : "",
                subsection: entry.subsection ? Translation.tr(entry.subsection) : ""
            }
        };
        if (root.currentPage !== entry.page)
            root.currentPage = entry.page; // the page switch delivers it once loaded
        else
            root.deliverSearch();
    }

    function deliverSearch() {
        const pending = root.pendingSearch;
        if (!pending) return;
        root.pendingSearch = null;
        const page = pageLoader.item;
        // Only the pages that host sub-pages have this; a result on the main
        // page closes one that is open.
        if (page && page.activeSubPage !== undefined)
            page.activeSubPage = pending.subPage ? Qt.resolvedUrl(`modules/settings/${pending.subPage}`) : "";
        SearchRegistry.target = pending.target;
    }

    onPagesChanged: SearchRegistry.pages = root.pages

    // One row of the list pane: a page, or a search result. A page row is given
    // its `pageIndex`; a result sets symbol, title and subtitle itself.
    component PaneRow: RippleButton {
        id: tab
        property int pageIndex: -1
        readonly property var page: pageIndex >= 0 ? root.pages[pageIndex] : null
        property string symbol: page?.icon ?? ""
        property real symbolRotation: page?.iconRotation ?? 0
        property string title: isAccount ? SystemInfo.username : (page?.name ?? "")
        property string subtitle: !isAccount ? (page?.summary ?? "") : Translation.tr("%1 profile").arg(activeProfileFile.text().trim() || Translation.tr("Default"))
        // The keyboard's place in the search results, drawn as focus (3.1):
        // the text field keeps the real focus so typing carries on.
        property bool cursor: false
        // Profiles is who you are here, so it is the account row above
        // search, the way Windows 11 Settings opens: your avatar, your
        // name, the profile your changes go into. Its 40px avatar is
        // centred on the 24px icons' column, so every row's text starts
        // at the same x.
        readonly property bool isAccount: page?.id === "profiles"
        Layout.fillWidth: true
        implicitHeight: tabContent.implicitHeight + 12 * 2
        leftPadding: isAccount ? 8 : 16
        rightPadding: 16
        buttonRadius: Appearance.rounding.large
        toggled: pageIndex >= 0 && root.currentPage === pageIndex
        onClicked: if (pageIndex >= 0) root.openPage(pageIndex)

        colBackground: CF.ColorUtils.transparentize(Appearance.colors.colLayer0Hover, 1)
        colBackgroundHover: Appearance.colors.colLayer0Hover
        colRipple: Appearance.colors.colLayer0Active
        colBackgroundToggled: Appearance.colors.colSecondary
        colBackgroundToggledHover: Appearance.colors.colSecondaryHover
        colRippleToggled: Appearance.colors.colSecondaryActive
        colStateLayer: toggled ? Appearance.colors.colOnSecondary : Appearance.colors.colOnLayer0
        readonly property color colContent: toggled ? Appearance.colors.colOnSecondary : Appearance.colors.colOnLayer0

        StateOverlay {
            anchors.fill: parent
            radius: tab.buttonRadius
            focused: tab.cursor
            contentColor: tab.colStateLayer
        }

        contentItem: RowLayout {
            id: tabContent
            spacing: tab.isAccount ? 8 : 16

            // A Loader, so the avatar's one mask layer exists once,
            // not in every row.
            Loader {
                active: tab.isAccount
                visible: active
                sourceComponent: Rectangle {
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimaryContainer

                    StyledText {
                        anchors.centerIn: parent
                        text: SystemInfo.username.charAt(0).toUpperCase()
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledImage { // The user's avatar, when one is set, covers the initial
                        id: avatar
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: Directories.userAvatarPathAccountsService
                        fallbacks: [Directories.userAvatarPathRicersAndWeirdSystems, Directories.userAvatarPathRicersAndWeirdSystems2]
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Circle {
                                diameter: avatar.height
                            }
                        }
                    }
                }
            }

            MaterialSymbol {
                visible: !tab.isAccount
                text: tab.symbol
                rotation: tab.symbolRotation
                iconSize: 24
                fill: tab.toggled ? 1 : 0
                color: tab.colContent
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: tab.title
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.variableAxes: Appearance.font.variableAxes.title
                    color: tab.colContent
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: tab.subtitle
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: tab.toggled ? Appearance.colors.colOnSecondary : Appearance.colors.colOnSurfaceVariant
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }
    }

    // Shows and hides what it holds on the effects specs, in on default and out
    // on fast (DESIGN 2.5). The spec is set inside the opacity binding, as in
    // PagePlaceholder, so the exit never runs on the enter's curve (2.9).
    component Fade: Item {
        id: fade
        property bool shown: true
        property AnimSpec spec: Appearance.animation.elementMoveFast
        opacity: {
            fade.spec = fade.shown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
            return fade.shown ? 1 : 0;
        }
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation {
                duration: fade.spec.duration
                easing.type: fade.spec.type
                easing.bezierCurve: fade.spec.bezierCurve
            }
        }
    }

    // The active config profile, named on the Profiles row. Re-read on every page
    // change too: .active only appears with the first switch, which no watch sees.
    FileView {
        id: activeProfileFile
        path: `${Directories.shellConfig}/profiles/.active`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }
    onCurrentPageChanged: activeProfileFile.reload()

    visible: true
    onClosing: Qt.quit()
    title: "illogical-impulse Settings"
    
    Component.onCompleted: {
        SearchRegistry.index(root.pages)
        MaterialThemeLoader.reapplyTheme()
        Config.readWriteDelay = 0 // Settings app always only sets one var at a time so delay isn't needed
        ExtensionManager.watchFileChanges = false // Settings app doesn't need file watching to prevent loops
    }

    minimumWidth: 750
    minimumHeight: 500
    width: 1100
    height: 750
    color: Appearance.m3colors.m3background

    ColumnLayout {
        id: windowContent
        anchors {
            fill: parent
            margins: contentPadding
        }

        Keys.onPressed: (event) => {
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown) {
                    root.currentPage = Math.min(root.currentPage + 1, root.pages.length - 1)
                    event.accepted = true;
                } 
                else if (event.key === Qt.Key_PageUp) {
                    root.currentPage = Math.max(root.currentPage - 1, 0)
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Tab) {
                    root.currentPage = (root.currentPage + 1) % root.pages.length;
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Backtab) {
                    root.currentPage = (root.currentPage - 1 + root.pages.length) % root.pages.length;
                    event.accepted = true;
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignCenter
            Layout.fillWidth: true
            Layout.fillHeight: false


            StyledText {
                id: titleText
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Settings")
                Layout.leftMargin: 20
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }

            Item {
                Layout.fillWidth: true
            }

            RippleButton {
                buttonRadius: Appearance.rounding.full
                implicitWidth: 35
                implicitHeight: 35
                onClicked: root.close()
                Layout.rightMargin: 10
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: 20
                }
            }
        }

        RowLayout { // Window content with the page list and content pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding
            // The list pane of Android 16's two-pane Settings: search on top, then
            // every page as a row with its icon, name and what lives there, with
            // AOSP's 28dp corners (Settings dimens.xml). The spacing is tighter
            // than AOSP's so the list sits at the density of the pages beside it.
            // The open page sits on secondary tone 80 with inverse text
            // (HighlightableTopLevelPreferenceAdapter, accent_select_background),
            // which in a dark scheme is colSecondary/colOnSecondary.
            ColumnLayout {
                id: navPane
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.preferredWidth: Math.min(360, root.width * 0.3)
                Layout.margins: 4
                spacing: 8

                PaneRow {
                    pageIndex: root.pageIndexById("profiles")
                }

                // AOSP's search bar shape, a pill with the icon inside it.
                ToolbarTextField {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.fillHeight: false // a toolbar field fills its bar; this one is a row
                    implicitHeight: 40
                    leftPadding: 44
                    rightPadding: clearSearch.shown ? 40 : 12
                    font.pixelSize: Appearance.font.pixelSize.small
                    placeholderText: Translation.tr("Search all settings..")

                    MaterialSymbol {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "search"
                        iconSize: 20
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    Fade {
                        id: clearSearch
                        shown: searchInput.text.length > 0
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 32
                        implicitHeight: 32

                        IconToolbarButton {
                            anchors.fill: parent
                            text: "close"
                            onClicked: {
                                searchInput.clear();
                                searchInput.forceActiveFocus();
                            }
                            StyledToolTip {
                                text: Translation.tr("Clear")
                            }
                        }
                    }

                    Component.onCompleted: {
                        searchInput.forceActiveFocus()
                    }

                    onTextChanged: {
                        root.searchCursor = 0
                        root.openedResult = ""
                        resultsList.positionViewAtBeginning()
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Down) {
                            root.moveSearchCursor(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            root.moveSearchCursor(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            // Escape lets go of the field and keeps what was
                            // typed (3.7); the clear button is what clears.
                            windowContent.forceActiveFocus();
                            event.accepted = true;
                        }
                    }

                    onAccepted: root.openSearchResult(root.searchCursor)
                }

                // Under the search field: the pages, or what search found. Both
                // outgrow the window's starting height, so they scroll under the
                // field instead of clipping off the bottom, and each edge fades in
                // step with how far the list showing runs past it -- one mask for
                // the pair, not one each.
                Item {
                    id: listArea
                    // Which list should show, and which does: the one leaving
                    // fades out on fast effects before the next fades in (M3's
                    // clean fade), rather than the two crossing. Typing before
                    // the index is read keeps the pages up, not an empty pane.
                    readonly property string wanted: !root.searching || !SearchRegistry.ready ? "pages"
                        : root.searchResults.length > 0 ? "results" : "empty"
                    property string showing: "pages"
                    onWantedChanged: {
                        listArea.showing = "";
                        paneSwap.restart();
                    }
                    Timer {
                        id: paneSwap
                        interval: Appearance.animation.elementMoveExit.duration
                        onTriggered: listArea.showing = listArea.wanted
                    }

                    readonly property Flickable list: listArea.showing === "pages" ? tabFlick : resultsList
                    readonly property real scrolled: list.contentY - list.originY
                    readonly property real fadeLength: 24
                    readonly property real topFade: Math.max(0, Math.min(scrolled, fadeLength))
                    readonly property real bottomFade: Math.max(0, Math.min(list.contentHeight - list.height - scrolled, fadeLength))
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    layer.enabled: list.contentHeight > list.height
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: listArea.width
                            height: listArea.height
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 1 - listArea.topFade / listArea.fadeLength) }
                                GradientStop { position: listArea.fadeLength / listArea.height; color: "black" }
                                GradientStop { position: 1 - listArea.fadeLength / listArea.height; color: "black" }
                                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 1 - listArea.bottomFade / listArea.fadeLength) }
                            }
                        }
                    }

                    Fade {
                        anchors.fill: parent
                        shown: listArea.showing === "pages"

                        StyledFlickable {
                            id: tabFlick
                            anchors.fill: parent
                            clip: true
                            contentWidth: width
                            contentHeight: tabColumn.implicitHeight

                            // Ctrl+Tab, search and II_SETTINGS_PAGE can open a page whose
                            // row is scrolled away; bring it in so the list always shows
                            // where you are. contentHeight settling is the first moment
                            // the rows have their final y, which is what the launch case needs;
                            // height settles after it, and a reveal against the half-laid-out
                            // height leaves the list scrolled a row down, so redo it then.
                            function revealCurrentTab() {
                                const tab = tabRepeater.itemAt(root.currentPage - 1);
                                if (!tab) return;
                                tabFlick.contentY = Math.max(Math.min(tabFlick.contentY, tab.y), tab.y + tab.height - tabFlick.height);
                            }
                            onContentHeightChanged: revealCurrentTab()
                            onHeightChanged: revealCurrentTab()

                            Connections {
                                target: root
                                function onCurrentPageChanged() {
                                    tabFlick.revealCurrentTab();
                                }
                            }

                            ColumnLayout {
                                id: tabColumn
                                width: parent.width
                                spacing: 4

                                Repeater {
                                    id: tabRepeater
                                    model: root.pages.length - 1 // Every page after Profiles, which sits above search

                                    PaneRow {
                                        required property int index
                                        pageIndex: index + 1
                                    }
                                }
                            }
                        }
                    }

                    // Each result names the setting, then where it lives, with its
                    // page's icon: the same row as a page, so the pane reads as one
                    // list whichever it shows. Keyed, so a row that survives the
                    // next keystroke stays put rather than being rebuilt (4.2).
                    Fade {
                        anchors.fill: parent
                        shown: listArea.showing === "results"

                        StyledListView {
                            id: resultsList
                            anchors.fill: parent
                            clip: true
                            // The list is the query's answer, so it changes with
                            // every keystroke and answers at once, as Android's
                            // does: no row slides in, out or along.
                            add: null
                            addDisplaced: null
                            displaced: null
                            move: null
                            moveDisplaced: null
                            remove: null
                            removeDisplaced: null
                            model: ScriptModel {
                                values: root.searchResults
                                objectProp: "key"
                            }
                            delegate: PaneRow {
                                required property var modelData
                                required property int index
                                width: resultsList.width
                                symbol: root.pages[modelData.entry.page]?.icon ?? ""
                                symbolRotation: root.pages[modelData.entry.page]?.iconRotation ?? 0
                                title: modelData.label
                                subtitle: modelData.where
                                toggled: modelData.key === root.openedResult
                                cursor: index === root.searchCursor && searchInput.activeFocus
                                onClicked: root.openSearchResult(index)
                            }
                        }
                    }

                    PagePlaceholder {
                        shown: listArea.showing === "empty"
                        icon: "search_off"
                        title: Translation.tr("No results")
                        description: Translation.tr("Nothing in settings matches “%1”").arg(root.searchQuery)
                        descriptionHorizontalAlignment: Text.AlignHCenter
                    }
                }
            }
            Rectangle { // Content container
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    opacity: 1.0

                    active: Config.ready
                    Component.onCompleted: {
                        source = root.pages[root.currentPage].component
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnim.complete();
                            switchAnim.start();
                        }
                    }

                    SequentialAnimation {
                        id: switchAnim

                        NumberAnimation {
                            target: pageLoader
                            properties: "opacity"
                            from: 1
                            to: 0
                            duration: 100
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                        }
                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
                                value: root.pages[root.currentPage].component
                            }
                            PropertyAction {
                                target: pageLoader
                                property: "anchors.topMargin"
                                value: 20
                            }
                        }
                        // The page exists from here: hand it the search result
                        // that switched to it.
                        ScriptAction {
                            script: root.deliverSearch()
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                properties: "opacity"
                                from: 0
                                to: 1
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                            NumberAnimation {
                                target: pageLoader
                                properties: "anchors.topMargin"
                                to: 0
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                        }
                    }
                }
            }
        }
    }
}