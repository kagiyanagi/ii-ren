import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent
    property bool aiChatEnabled: Config.options.policies.ai !== 0  
    property bool translatorEnabled: Config.options.policies.translator !== 0
    property bool animeEnabled: Config.options.policies.weeb !== 0  
    property bool animeCloset: Config.options.policies.weeb === 2  
    property bool continuityEnabled: Config.options.policies.continuity !== 0
    property bool conduitEnabled: Config.options.conduit.enable

    property bool _sidebarExtended: scopeRoot.extend
    property int _maxTextTabs: _sidebarExtended ? 4 : 3

    property var extensionPages: ExtensionManager.ready
        ? ExtensionManager.getContributionPoint("sidebarLeftPages") : []

    // Conduit sits in front of the built-in pages and is focused on open.
    readonly property int pinnedTabIndex: root.conduitEnabled ? 0 : -1

    // Reassigning extensionPages re-runs the contentChildren binding below, which
    // rebuilds every extension page from a fresh ?_t= URL and throws its state
    // away. The manager also refreshes on any config write - switching a model,
    // clearing a chat - so only reassign when the contributions really changed.
    function syncExtensionPages() {
        let next = ExtensionManager.getContributionPoint("sidebarLeftPages")
        if (JSON.stringify(next) === JSON.stringify(root.extensionPages)) return
        root.extensionPages = next
    }

    Connections {
        target: ExtensionManager
        function onRefreshExtensions() { root.syncExtensionPages() }
        function onExtensionInstalled() { root.syncExtensionPages() }
        function onExtensionRemoved() { root.syncExtensionPages() }
        function onExtensionToggled() { root.syncExtensionPages() }
    }

    Connections {
        target: GlobalStates
        function onPoliciesPanelOpenChanged() {
            if (GlobalStates.policiesPanelOpen && root.pinnedTabIndex >= 0)
                Persistent.states.sidebar.policies.tab = root.pinnedTabIndex
        }
    }

    property var tabButtonList: [  
        ...(root.conduitEnabled ? [{"icon": "electrical_services", "name": Translation.tr("Conduit")}] : []),
        ...(root.aiChatEnabled ? [{"icon": "neurology", "name": Translation.tr("Intelligence")}] : []),  
        ...(root.translatorEnabled ? [{"icon": "translate", "name": Translation.tr("Translator")}] : []), 
        ...((root.animeEnabled && !root.animeCloset) ? [{"icon": "bookmark_heart", "name": Translation.tr("Anime")}] : []),
        ...(root.continuityEnabled ? [{"icon": "devices", "name": Translation.tr("Continuity")}] : []),
        ...root.extensionPages.map(p => ({icon: p.icon, name: p.title}))
    ]
    property int tabCount: swipeView.count

    function focusActiveItem() {
        swipeView.currentItem.forceActiveFocus()
    }

    function createExtensionPage(page) {
        let loader = Qt.createQmlObject('import QtQuick; Loader { active: true }', swipeView)
        loader.source = "file://" + page.fullPath + "?_t=" + Date.now()
        let setExtId = () => {
            if (loader.item) {
                if ("extensionId" in loader.item) {
                    loader.item.extensionId = page.extensionId
                } else {
                    Object.defineProperty(loader.item, "extensionId", {
                        value: page.extensionId,
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
        return loader
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex()
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex()
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: sidebarPadding

        Toolbar {
            visible: tabButtonList.length > 1
            Layout.alignment: Qt.AlignHCenter
            enableShadow: false
            colBackground: Appearance.colors.colLayer3
            ToolbarTabBar {
                id: tabBar
                Layout.alignment: Qt.AlignHCenter
                tabButtonList: root.tabButtonList
                maxTextTabs: root._maxTextTabs
                currentIndex: Math.min(Persistent.states.sidebar.policies.tab, Math.max(0, root.tabButtonList.length - 1))
                onCurrentIndexChanged: Persistent.states.sidebar.policies.tab = currentIndex
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView { // Content pages
                id: swipeView
                anchors.fill: parent
                spacing: 10
                currentIndex: Math.min(Persistent.states.sidebar.policies.tab, Math.max(0, swipeView.count - 1))
                onCurrentIndexChanged: Persistent.states.sidebar.policies.tab = currentIndex

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                contentChildren: [
                    ...(root.conduitEnabled ? [conduit.createObject()] : []),
                    ...(root.aiChatEnabled ? [aiChat.createObject()] : []),
                    ...(root.translatorEnabled ? [translator.createObject()] : []),
                    ...((!root.conduitEnabled && (root.extensionPages.length === 0 && root.tabButtonList.length === 0 || (!root.aiChatEnabled && !root.translatorEnabled && !root.continuityEnabled && root.animeCloset && root.extensionPages.length === 0))) ? [placeholder.createObject()] : []),
                    ...(root.animeEnabled ? [anime.createObject()] : []),
                    ...(root.continuityEnabled ? [continuity.createObject()] : []),
                    ...root.extensionPages.map(p => root.createExtensionPage(p)).filter(item => item)
                ]
            }
        }

        // Every page in the view re-evaluates on open, whether or not it is the tab
        // being looked at: measured on this machine, Conduit ~40 and Continuity ~63 CPU
        // ticks per open, and they add up. Only the current tab is kept alive; a page is
        // built when you switch to it and dropped when you leave.
        component PageSlot: Loader {
            asynchronous: true
            active: SwipeView.isCurrentItem
        }

        Component {
            id: conduit
            PageSlot { sourceComponent: Conduit {} }
        }
        Component {
            id: aiChat
            PageSlot { sourceComponent: AiChat {} }
        }
        Component {
            id: translator
            PageSlot { sourceComponent: Translator {} }
        }
        Component {
            id: anime
            PageSlot { sourceComponent: Anime {} }
        }
        Component {
            id: continuity
            PageSlot { sourceComponent: Continuity {} }
        }
        Component {
            id: placeholder
            Item {
                StyledText {
                    anchors.centerIn: parent
                    text: root.animeCloset ? Translation.tr("Nothing") : Translation.tr("Enjoy your empty sidebar...")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}