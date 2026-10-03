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
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import qs.modules.settings

ApplicationWindow {
    id: root
    property string firstRunFilePath: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property real contentPadding: 8
    property bool showNextTime: false

    property int currentPage: {
        const p = Quickshell.env("II_SETTINGS_PAGE");
        if (p) {
            const idx = root.pages.findIndex(x => x.id === p);
            return idx !== -1 ? idx : 0;
        }
        return 0;
    }
    property real scrollPos: 0
    property string lastSearch: ""
    property int lastSearchIndex: -1
    property int resultsCount: 0
    property string pendingSectionHighlight: Quickshell.env("II_SETTINGS_HIGHLIGHT") || ""


    property var pages: [
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
            name: Translation.tr("Lock Screen"),
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
            id: "hermes",
            name: Translation.tr("Hermes"),
            summary: Translation.tr("Dictation, persona, display"),
            icon: "smart_toy",
            component: "modules/settings/HermesConfig.qml"
        },
        {
            id: "profiles",
            name: Translation.tr("Profiles"),
            summary: Translation.tr("Saved setups"),
            icon: "switch_account",
            component: "modules/settings/ProfilesConfig.qml"
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
    

    visible: true
    onClosing: Qt.quit()
    title: "illogical-impulse Settings"
    
    Component.onCompleted: {
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

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 4

                    // AOSP's search bar shape, a pill with the icon inside it, at
                    // the height of the buttons beside it.
                    ToolbarTextField {
                        id: searchInput
                        Layout.fillWidth: true
                        implicitHeight: 40
                        leftPadding: 44
                        rightPadding: resultText.visible ? resultText.implicitWidth + 24 : 12
                        font.pixelSize: Appearance.font.pixelSize.small
                        placeholderText: Translation.tr("Search all settings..")
                        transform: Translate { id: searchShake }

                        SequentialAnimation {
                            id: noMoreResultsAnim
                            NumberAnimation { target: searchShake; property: "x"; to: -30; duration: 50 }
                            NumberAnimation { target: searchShake; property: "x"; to: 30; duration: 50 }
                            NumberAnimation { target: searchShake; property: "x"; to: -15; duration: 40 }
                            NumberAnimation { target: searchShake; property: "x"; to: 15; duration: 40 }
                            NumberAnimation { target: searchShake; property: "x"; to: 0; duration: 30 }
                        }

                        MaterialSymbol {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "search"
                            iconSize: 20
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        StyledText {
                            id: resultText
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.lastSearchIndex !== -1 && root.resultsCount > 0
                            text: (root.lastSearchIndex % root.resultsCount + 1) + "/" + root.resultsCount
                            font.family: Appearance.font.family.numbers
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        Component.onCompleted: {
                            searchInput.forceActiveFocus()
                        }

                        onTextChanged: {
                            root.lastSearchIndex = -1
                            root.resultsCount = 0
                        }

                        // We may use this in the future, this only searches the best result
                        /* onAccepted: {
                            if (!searchInput.text || searchInput.text.trim() === "") return
                            
                            let normalizedText = searchInput.text.toLowerCase()
                            let bestResult = SearchRegistry.getBestResult(normalizedText)

                            if (!bestResult) {
                                noMoreResultsAnim.restart()
                                return
                            }

                            root.currentPage = bestResult.pageIndex
                            root.scrollPos = bestResult.yPos
                            SearchRegistry.currentSearch = bestResult.matchedString
                        } */

                        onAccepted: {
                            const result = SearchRegistry.getResultsRanked(searchInput.text)

                            if (result == null) {
                                noMoreResultsAnim.restart();
                                return
                            }

                            let length = SearchRegistry.getResultsRanked(searchInput.text).length

                            if (length == 0) {
                                noMoreResultsAnim.restart();
                                return
                            }
                            
                            if (root.lastSearch != searchInput.text) {
                                root.lastSearchIndex = 0
                                root.lastSearch = searchInput.text
                                
                            } else {
                                root.lastSearchIndex++
                                if (SearchRegistry.getResultsRanked(searchInput.text).length === 1) {
                                    noMoreResultsAnim.restart()
                                }
                            }

                            let normalizedText = searchInput.text.toLowerCase()
                            let results = SearchRegistry.getResultsRanked(normalizedText)
                            if (results.length > 0) {
                                let index = root.lastSearchIndex % results.length
                                let result = results[index]
                                
                                root.resultsCount = results.length
                                root.currentPage = result.pageIndex
                                //root.scrollPos = result.yPos
                                SearchRegistry.currentSearch = result.matchedString
                            }
                        }
                    }

                    // Where Android puts the account avatar.
                    RippleButton {
                        id: configButton
                        property bool justCopied: false
                        implicitWidth: 40
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.full
                        colBackgroundHover: Appearance.colors.colLayer0Hover
                        colRipple: Appearance.colors.colLayer0Active
                        colStateLayer: Appearance.colors.colOnLayer0
                        onClicked: Qt.openUrlExternally(`${Directories.config}/illogical-impulse/config.json`)
                        altAction: () => {
                            Quickshell.clipboardText = CF.FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                            configButton.justCopied = true;
                            revertTextTimer.restart();
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: configButton.justCopied ? "check" : "edit"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer0
                        }

                        Timer {
                            id: revertTextTimer
                            interval: 1500
                            onTriggered: configButton.justCopied = false
                        }

                        StyledToolTip {
                            text: configButton.justCopied ? Translation.tr("Path copied") : Translation.tr("Open the shell config file\nAlternatively right-click to copy path")
                        }
                    }
                }

                // The pages outgrow the window's starting height, so they scroll
                // under the search row instead of clipping off the bottom. Each
                // edge fades in step with how far content runs past it.
                StyledFlickable {
                    id: tabFlick
                    readonly property real fadeLength: 24
                    readonly property real topFade: Math.max(0, Math.min(contentY, fadeLength))
                    readonly property real bottomFade: Math.max(0, Math.min(contentHeight - height - contentY, fadeLength))
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: tabColumn.implicitHeight

                    layer.enabled: contentHeight > height
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: tabFlick.width
                            height: tabFlick.height
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 1 - tabFlick.topFade / tabFlick.fadeLength) }
                                GradientStop { position: tabFlick.fadeLength / tabFlick.height; color: "black" }
                                GradientStop { position: 1 - tabFlick.fadeLength / tabFlick.height; color: "black" }
                                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 1 - tabFlick.bottomFade / tabFlick.fadeLength) }
                            }
                        }
                    }

                    // Ctrl+Tab, search and II_SETTINGS_PAGE can open a page whose
                    // row is scrolled away; bring it in so the list always shows
                    // where you are. contentHeight settling is the first moment
                    // the rows have their final y, which is what the launch case needs.
                    function revealCurrentTab() {
                        const tab = tabRepeater.itemAt(root.currentPage);
                        if (!tab) return;
                        tabFlick.contentY = Math.max(Math.min(tabFlick.contentY, tab.y), tab.y + tab.height - tabFlick.height);
                    }
                    onContentHeightChanged: revealCurrentTab()

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
                            model: root.pages

                            RippleButton {
                                id: tab
                                required property int index
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: tabContent.implicitHeight + 12 * 2
                                leftPadding: 16
                                rightPadding: 16
                                buttonRadius: Appearance.rounding.large
                                toggled: root.currentPage === index
                                onClicked: root.currentPage = index

                                colBackground: CF.ColorUtils.transparentize(Appearance.colors.colLayer0Hover, 1)
                                colBackgroundHover: Appearance.colors.colLayer0Hover
                                colRipple: Appearance.colors.colLayer0Active
                                colBackgroundToggled: Appearance.colors.colSecondary
                                colBackgroundToggledHover: Appearance.colors.colSecondaryHover
                                colRippleToggled: Appearance.colors.colSecondaryActive
                                colStateLayer: toggled ? Appearance.colors.colOnSecondary : Appearance.colors.colOnLayer0
                                readonly property color colContent: toggled ? Appearance.colors.colOnSecondary : Appearance.colors.colOnLayer0

                                contentItem: RowLayout {
                                    id: tabContent
                                    spacing: 16

                                    MaterialSymbol {
                                        text: tab.modelData.icon
                                        rotation: tab.modelData.iconRotation || 0
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
                                            text: tab.modelData.name
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
                                            text: tab.modelData.summary
                                            font.pixelSize: Appearance.font.pixelSize.smallie
                                            color: tab.toggled ? Appearance.colors.colOnSecondary : Appearance.colors.colOnSurfaceVariant
                                            Behavior on color {
                                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                            }
                                        }
                                    }
                                }
                            }
                        }
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
                        function onScrollPosChanged() {
                            if (root.scrollPos == -1) return
                            scrollTimer.start()
                        }
                    }

                    Timer {
                        id: scrollTimer
                        interval: 250
                        onTriggered: {
                            pageLoader.item.contentY = root.scrollPos
                            root.scrollPos = -1
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