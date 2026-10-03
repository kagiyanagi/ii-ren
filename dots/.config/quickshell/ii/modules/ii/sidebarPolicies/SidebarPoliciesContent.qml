import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent
    property bool translatorEnabled: Config.options.policies.translator !== 0
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool animeCloset: Config.options.policies.weeb === 2
    property bool continuityEnabled: Config.options.policies.continuity !== 0
    property bool hermesEnabled: Config.options.policies.hermes !== 0 && (Config.options.hermes?.enable ?? false)

    property bool _sidebarExtended: scopeRoot.extend
    property int _maxTextTabs: _sidebarExtended ? 4 : 3

    property var extensionPages: ExtensionManager.ready
        ? ExtensionManager.getContributionPoint("sidebarLeftPages") : []

    // Hermes sits in front of the built-in pages and is focused on open.
    readonly property int pinnedTabIndex: root.hermesEnabled ? 0 : -1

    Connections {
        target: GlobalStates
        function onPoliciesPanelOpenChanged() {
            if (GlobalStates.policiesPanelOpen && root.pinnedTabIndex >= 0)
                Persistent.states.sidebar.policies.tab = root.pinnedTabIndex
        }
    }

    // Clamped here and written back only on a real move: writing the clamp itself
    // back from a change handler re-entered this binding (a binding loop) and
    // overwrote the saved tab whenever a policy hid the page it named.
    readonly property int currentTab: Math.min(Persistent.states.sidebar.policies.tab, Math.max(0, root.tabButtonList.length - 1))

    property var tabButtonList: [
        ...(root.hermesEnabled ? [{"icon": "auto_awesome", "name": Translation.tr("Hermes")}] : []),
        ...(root.translatorEnabled ? [{"icon": "translate", "name": Translation.tr("Translator")}] : []),
        ...((root.animeEnabled && !root.animeCloset) ? [{"icon": "bookmark_heart", "name": Translation.tr("Anime")}] : []),
        ...(root.continuityEnabled ? [{"icon": "devices", "name": Translation.tr("Continuity")}] : []),
        ...root.extensionPages.map(p => ({icon: p.icon, name: p.title}))
    ]

    // Same order as tabButtonList, page for tab. The closet anime page has no tab, so it
    // goes last, reached by swiping past the last tab. A string, so a re-evaluation that
    // lands on the same pages (a language load, an extensions-file refresh, any config
    // write) notifies nothing and the Repeater keeps every page it has.
    readonly property string pages: JSON.stringify([
        ...(root.hermesEnabled ? [{kind: "hermes"}] : []),
        ...(root.translatorEnabled ? [{kind: "translator"}] : []),
        ...(root.tabButtonList.length === 0 ? [{kind: "placeholder"}] : []),
        ...((root.animeEnabled && !root.animeCloset) ? [{kind: "anime"}] : []),
        ...(root.continuityEnabled ? [{kind: "continuity"}] : []),
        ...root.extensionPages.map(p => ({kind: "extension", path: p.fullPath, extensionId: p.extensionId})),
        ...(root.animeCloset ? [{kind: "anime"}] : [])
    ])

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
            Layout.alignment: Qt.AlignHCenter
            enableShadow: false
            colBackground: Appearance.colors.colLayer3
            ToolbarTabBar {
                id: tabBar
                visible: tabButtonList.length > 1
                Layout.alignment: Qt.AlignHCenter
                tabButtonList: root.tabButtonList
                maxTextTabs: root._maxTextTabs
                currentIndex: root.currentTab
                onCurrentIndexChanged: if (currentIndex !== root.currentTab) Persistent.states.sidebar.policies.tab = currentIndex
            }
            IconToolbarButton {
                text: "keep"
                toggled: root.scopeRoot.pin
                iconFill: toggled
                onClicked: root.scopeRoot.togglePin()
                StyledToolTip {
                    text: root.scopeRoot.pin ? Translation.tr("Unpin (Ctrl+P)") : Translation.tr("Pin open, beside windows (Ctrl+P)")
                }
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
                currentIndex: root.currentTab
                onCurrentIndexChanged: if (currentIndex !== root.currentTab) Persistent.states.sidebar.policies.tab = currentIndex
                // Tabs change from the tab bar only: a sideways touchpad swipe paged it,
                // and did at the end of every scrolled formula or code block. The
                // closet page has no tab, so there the swipe is the way in.
                interactive: root.animeCloset

                clip: true
                layer.enabled: true
                // The card's own arc, not a tighter one: a message card cut by the
                // transcript's clip squares off at the 4px inset, outside a 17px arc.
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.normal
                    }
                }

                // A Repeater, not `contentChildren: [x.createObject(), ...]`. Reassigning
                // contentChildren only clears the model (Qt 6.11): if the ListView is not
                // wired to it yet -- the content is still incubating, as after a live
                // reload -- the old pages stay parented with the view listening, and when
                // the GC frees them each one walks currentIndex down by one, to -2: every
                // tab blank until a restart. A Repeater unparents a page while it is
                // still in the model, so the view removes it properly.
                Repeater {
                    model: JSON.parse(root.pages)
                    // Every page in the view re-evaluates on open, whether or not it is the
                    // tab being looked at: measured on this machine, Hermes ~40 and
                    // Continuity ~63 CPU ticks per open, and they add up. Only the current
                    // tab is kept alive; a page is built when you switch to it and dropped
                    // when you leave. Extension pages stay up and keep their state.
                    delegate: Loader {
                        required property var modelData
                        // Synchronous on purpose. Incubating these pages crashes Qt 6.11 in
                        // QQmlConnections::connectSignalsToMethods about half of all launches --
                        // measured 5/8 with async, 0/8 without. Several pages below have a
                        // Connections whose target is not a live QObject during incubation
                        // (`parent`, a Repeater model, a plain JS object); fix those and this can
                        // go back to async. Costs little: `active` already means only the visible
                        // tab is ever built.
                        asynchronous: false
                        active: SwipeView.isCurrentItem || modelData.kind === "extension"
                        sourceComponent: ({hermes, translator, anime, continuity, placeholder})[modelData.kind] ?? null
                        source: modelData.kind === "extension" ? "file://" + modelData.path + "?_t=" + Date.now() : ""
                        onLoaded: {
                            if (modelData.kind !== "extension") return
                            if ("extensionId" in item) item.extensionId = modelData.extensionId
                            else Object.defineProperty(item, "extensionId", {value: modelData.extensionId, writable: true, configurable: true, enumerable: true})
                        }
                    }
                }
            }
        }

        Component {
            id: hermes
            Hermes {}
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: anime
            Anime {}
        }
        Component {
            id: continuity
            Continuity {}
        }
        Component {
            id: placeholder
            Item {
                PagePlaceholder {
                    shown: true
                    icon: "view_sidebar"
                    // Closet mode keeps its bare "Nothing": it is the cover the hidden page sits behind.
                    title: root.animeCloset ? Translation.tr("Nothing") : Translation.tr("Nothing in this sidebar")
                    description: root.animeCloset ? "" : Translation.tr("Turn on Hermes, the translator or Anime in Settings > General > Policies")
                }
            }
        }
    }
}