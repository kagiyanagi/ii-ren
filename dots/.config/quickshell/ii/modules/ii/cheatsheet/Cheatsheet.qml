import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.synchronizer
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    // Intent and mapping are separate: `Loader.active` destroys the window, so
    // an exit animation driven by it would never once render (DESIGN.md 2.5,
    // and the defect AltTab had with `visible: root.open`). `rendered` is
    // cleared by the exit animation landing on 0, not by the keybind.
    property bool open: false
    property bool rendered: false
    // 0.92 on a 1400x860 card is 112px of travel per axis; the card is the
    // largest surface in the shell and a fraction that suits AltTab's 400px one
    // reads as a lurch here. Less travel, more time (2.4: 500ms+ is the rung for
    // something screen-sized).
    readonly property real closedScale: 0.96

    onOpenChanged: if (root.open) root.rendered = true

    // Published so the bar can tell the sheet is up (the weather popup stands
    // down while it is).
    Binding {
        target: GlobalStates
        property: "cheatsheetOpen"
        value: root.open
    }

    // Stable names for the built-in tabs, in SwipeView order, so a caller can
    // ask for one without knowing where it sits or what it is called in the
    // user's language.
    readonly property var tabKeys: ["timetable", "keybinds", "elements", "weather"]
    signal tabRequested(int index)

    // Open on a tab. A closed sheet reads the persisted index when it builds;
    // an open one is told directly.
    function openTab(key: string): void {
        const index = root.tabKeys.indexOf(key);
        if (index < 0)
            return;
        Persistent.states.cheatsheet.tabIndex = index;
        root.tabRequested(index);
        root.open = true;
    }

    Connections {
        target: GlobalStates
        function onCheatsheetTabRequested(tab) {
            root.openTab(tab);
        }
    }

    property var extensionCheatsheetTabs: ExtensionManager.ready
        ? ExtensionManager.getContributionPoint("cheatsheet") : []

    Connections {
        target: ExtensionManager
        function onRefreshExtensions() { root.extensionCheatsheetTabs = ExtensionManager.getContributionPoint("cheatsheet") }
        function onExtensionInstalled() { root.extensionCheatsheetTabs = ExtensionManager.getContributionPoint("cheatsheet") }
        function onExtensionRemoved() { root.extensionCheatsheetTabs = ExtensionManager.getContributionPoint("cheatsheet") }
        function onExtensionToggled() { root.extensionCheatsheetTabs = ExtensionManager.getContributionPoint("cheatsheet") }
    }

    property var tabButtonList: [
        {
            "icon": "calendar_month",
            "name": Translation.tr("Timetable")
        },
        {
            "icon": "keyboard",
            "name": Translation.tr("Keybinds")
        },
        {
            "icon": "experiment",
            "name": Translation.tr("Elements")
        },
        {
            "icon": "partly_cloudy_day",
            "name": Translation.tr("Weather")
        },
        ...root.extensionCheatsheetTabs.map(p => ({icon: p.icon, name: p.title}))
    ]

    Loader {
        id: cheatsheetLoader
        active: root.rendered

        sourceComponent: PanelWindow { // Window
            id: cheatsheetRoot
            visible: true
            // Flipped after initialisation so the Behavior on `reveal` is live
            // when it changes -- a Behavior is skipped during initial binding
            // evaluation, which is how a card written this way opens at full
            // size with no enter at all.
            property bool shown: false

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            function hide() {
                root.open = false;
            }
            exclusiveZone: 0
            implicitWidth: cheatsheetBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: cheatsheetBackground.height + Appearance.sizes.elevationMargin * 2
            WlrLayershell.namespace: "quickshell:cheatsheet"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            mask: Region {
                item: cheatsheetBackground
            }

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(cheatsheetRoot);
                cheatsheetRoot.shown = true;
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(cheatsheetRoot);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    cheatsheetRoot.hide();
                }
            }

            // Background
            StyledRectangularShadow {
                target: cheatsheetBackground
            }
            Rectangle {
                id: cheatsheetBackground
                anchors.centerIn: parent
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.windowRounding
                property real padding: 20
                implicitWidth: cheatsheetColumnLayout.implicitWidth + padding * 2
                implicitHeight: cheatsheetColumnLayout.implicitHeight + padding * 2

                // Screen-centred and opened from a keybind, so there is nothing
                // on screen for it to grow out of (2.6).
                transformOrigin: Item.Center

                // Scale and opacity ride one driver, so the enter/exit spec is
                // assigned from the only binding that writes it -- the shape
                // 2.9's Behavior trap requires. Enter decelerates over the full
                // spec, exit accelerates at half of it (2.5).
                //
                // Default *spatial* duration, not effects: scale is a spatial
                // property and this is a screen-sized surface, which 2.4 puts at
                // 500ms. emphasizedDecel is front-loaded hard -- it is at 0.7 of
                // the distance by 5% of the time -- so it still reads as
                // immediate. Opacity rides the same curve, which is safe because
                // emphasizedDecel has no control point above 1 and so cannot
                // overshoot (2.1).
                property int revealDuration: Appearance.animation.elementMove.duration
                property list<real> revealCurve: Appearance.animationCurves.emphasizedDecel
                property real reveal: {
                    const entering = cheatsheetRoot.shown && root.open;
                    cheatsheetBackground.revealDuration = entering
                        ? Appearance.animation.elementMove.duration
                        : Math.round(Appearance.animation.elementMove.duration / 2);
                    cheatsheetBackground.revealCurve = entering
                        ? Appearance.animationCurves.emphasizedDecel
                        : Appearance.animationCurves.emphasizedAccel;
                    return entering ? 1 : 0;
                }
                Behavior on reveal {
                    NumberAnimation {
                        duration: cheatsheetBackground.revealDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: cheatsheetBackground.revealCurve
                    }
                }
                // The exit is what unmaps the window, not the keybind.
                onRevealChanged: if (cheatsheetBackground.reveal === 0 && !root.open) root.rendered = false

                scale: root.closedScale + (1 - root.closedScale) * cheatsheetBackground.reveal
                opacity: cheatsheetBackground.reveal

                Keys.onPressed: event => { // Esc to close
                    if (event.key === Qt.Key_Escape) {
                        cheatsheetRoot.hide();
                    }
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_PageDown) {
                            tabBar.incrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            tabBar.decrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex + 1) % root.tabButtonList.length);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex - 1 + root.tabButtonList.length) % root.tabButtonList.length);
                            event.accepted = true;
                        }
                    }
                }

                RippleButton { // Close button
                    id: closeButton
                    focus: cheatsheetRoot.visible
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    anchors {
                        top: parent.top
                        right: parent.right
                        topMargin: cheatsheetBackground.padding
                        rightMargin: cheatsheetBackground.padding
                    }

                    onClicked: {
                        cheatsheetRoot.hide();
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.title
                        text: "close"
                    }
                }

                // Mounted on the card, not inside the Keybinds tab, so its scrim
                // reaches the sheet's own padding. A WindowDialog measures its
                // own content, so one left mounted sits at full height before it
                // has ever been shown -- hence the load-on-demand, which is also
                // what hands it keyboard focus for the key capture.
                Loader {
                    id: keybindEditorLoader
                    anchors.fill: parent
                    z: 1
                    active: GlobalStates.cheatsheetKeybindEditorOpen
                    sourceComponent: KeybindEditor {
                        // The sheet's corner, not a dialog's own, so the scrim
                        // does not square off inside a rounded card.
                        radius: cheatsheetBackground.radius
                    }
                    onActiveChanged: if (active) {
                        item.show = true;
                        item.forceActiveFocus();
                    }
                    Connections {
                        target: keybindEditorLoader.item
                        function onDismiss() {
                            keybindEditorLoader.item.show = false;
                            GlobalStates.cheatsheetKeybindEditorOpen = false;
                        }
                        function onVisibleChanged() {
                            if (!keybindEditorLoader.item.visible && !GlobalStates.cheatsheetKeybindEditorOpen)
                                keybindEditorLoader.active = false;
                        }
                    }
                }

                ColumnLayout { // Real content
                    id: cheatsheetColumnLayout
                    anchors.centerIn: parent
                    spacing: 12

                    Toolbar {
                        Layout.alignment: Qt.AlignHCenter
                        enableShadow: false
                        ToolbarTabBar {
                            id: tabBar
                            tabButtonList: root.tabButtonList

                            Synchronizer on currentIndex {
                                property alias source: swipeView.currentIndex
                            }
                        }
                    }

                    SwipeView { // Content pages
                        id: swipeView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12
                        onCurrentIndexChanged: {
                            Persistent.states.cheatsheet.tabIndex = currentIndex;
                        }

                        // A share of the screen rather than the largest tab's
                        // implicit size. Two things follow from that: the sheet
                        // stays one size as you move between tabs instead of
                        // resizing under the pointer, and -- because the view no
                        // longer has to measure every page to size itself -- a
                        // page can wait until it is looked at before it exists.
                        // Building all three cost ~550ms of the open.
                        implicitWidth: (cheatsheetRoot.screen?.width ?? 1920) * 0.72
                        implicitHeight: (cheatsheetRoot.screen?.height ?? 1080) * 0.7

                        clip: true
                        // Tabs change from the tab bar only: a sideways touchpad swipe paged it
                        interactive: false

                        // The page slide is the style's own ListView, whose
                        // `highlightMoveDuration: 250` is a literal in
                        // QtQuick/Controls/Basic/SwipeView.qml. Bound rather than
                        // restated: overriding contentItem would copy fifteen
                        // lines of Qt's config that then drift. The easing is not
                        // exposed by ListView's highlight move, so the duration is
                        // all there is to take from the token.
                        Binding {
                            target: swipeView.contentItem
                            property: "highlightMoveDuration"
                            value: Appearance.animation.elementMove.duration
                            when: swipeView.contentItem !== null
                        }

                        Connections {
                            target: root
                            function onTabRequested(index) {
                                swipeView.currentIndex = index;
                            }
                        }

                        LazyTab { sourceComponent: CheatsheetTimetable {} }
                        LazyTab { sourceComponent: CheatsheetKeybinds {} }
                        LazyTab { sourceComponent: CheatsheetPeriodicTable {} }
                        LazyTab {
                            id: weatherTab
                            sourceComponent: CheatsheetWeather { live: weatherTab.current }
                        }

                        Component.onCompleted: {
                            for (const p of root.extensionCheatsheetTabs) {
                                let loader = Qt.createQmlObject(
                                    'import QtQuick; Loader { active: true }',
                                    swipeView
                                )
                                swipeView.addItem(loader)
                                loader.source = "file://" + p.fullPath + "?_t=" + Date.now()
                                let setExtId = () => {
                                    if (loader.item) {
                                        if ("extensionId" in loader.item) {
                                            loader.item.extensionId = p.extensionId
                                        } else {
                                            Object.defineProperty(loader.item, "extensionId", {
                                                value: p.extensionId,
                                                writable: true,
                                                configurable: true,
                                                enumerable: true
                                            })
                                        }
                                    }
                                }
                                if (loader.status === Loader.Ready) {
                                    setExtId()
                                } else {
                                    loader.loaded.connect(setExtId)
                                }
                            }
                            // Set once, after the extension tabs exist -- a
                            // `currentIndex:` binding here is destroyed by the
                            // first tab change anyway, and a persisted index
                            // can name an extension tab.
                            swipeView.currentIndex = Math.min(Persistent.states.cheatsheet.tabIndex, swipeView.count - 1);
                        }
                    }
                }
            }
        }
    }

    // A tab is built the first time it is looked at, and kept afterwards --
    // unloading on the way out would rebuild it, and throw away its scroll
    // position and whatever was typed in its search box.
    component LazyTab: Loader {
        id: lazyTab
        readonly property bool current: SwipeView.isCurrentItem
        property bool everCurrent: false

        active: lazyTab.everCurrent
        onCurrentChanged: if (lazyTab.current) lazyTab.everCurrent = true
        // `onCurrentChanged` never fires for the tab that starts selected.
        Component.onCompleted: if (lazyTab.current) lazyTab.everCurrent = true
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            root.open = !root.open;
        }

        function close(): void {
            root.open = false;
        }

        function open(): void {
            root.open = true;
        }

        // `qs -c ii ipc call cheatsheet openTab weather`
        function openTab(tab: string): void {
            root.openTab(tab);
        }
    }

    GlobalShortcut {
        name: "cheatsheetToggle"
        description: "Toggles cheatsheet on press"

        onPressed: {
            root.open = !root.open;
        }
    }

    GlobalShortcut {
        name: "cheatsheetOpen"
        description: "Opens cheatsheet on press"

        onPressed: {
            root.open = true;
        }
    }

    GlobalShortcut {
        name: "cheatsheetClose"
        description: "Closes cheatsheet on press"

        onPressed: {
            root.open = false;
        }
    }
}
