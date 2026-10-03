pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.sidebarDashboard.calendar
import qs.modules.ii.sidebarDashboard.todo
import qs.modules.ii.sidebarDashboard.pomodoro
import "../bar/duration.js" as Duration
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    clip: true
    implicitHeight: collapsed ? collapsedBottomWidgetGroupRow.implicitHeight : 350
    // Persistent is the one source; writing selectedTab would break this binding.
    // Clamped, so a tab whose extension was removed lands on the last one.
    readonly property int selectedTab: Math.max(0, Math.min(Persistent.states.sidebar.bottomGroup.tab, tabs.length - 1))
    property int lastTab // which way a switch slides; seeded once, not bound, or it races the change
    readonly property bool collapsed: Persistent.states.sidebar.bottomGroup.collapsed
    readonly property var shown: Config.options.sidebar.bottomGroup

    function selectTab(index) {
        Persistent.states.sidebar.bottomGroup.tab = Math.max(0, Math.min(index, root.tabs.length - 1));
    }
    property var extensionTabs: ExtensionManager.ready ? ExtensionManager.getContributionPoint("sidebarRightBottom") : []

    function syncExtensionTabs() {
        root.extensionTabs = ExtensionManager.getContributionPoint("sidebarRightBottom")
    }

    Connections {
        target: ExtensionManager
        function onRefreshExtensions() { root.syncExtensionTabs() }
        function onExtensionInstalled() { root.syncExtensionTabs() }
        function onExtensionRemoved() { root.syncExtensionTabs() }
        function onExtensionToggled() { root.syncExtensionTabs() }
    }

    function refreshCurrentTab() {
        if (!root.tabs.length) return
        let tab = root.tabs[root.selectedTab]
        if (!tab) return
        if (tab.isExtension) {
            let comp = ExtensionManager.loadExtensionQmlComponent(tab.fullPath)
            if (comp && comp.status === Component.Ready) {
                tabStack.sourceComponent = comp
            } else if (comp) {
                comp.statusChanged.connect(() => {
                    if (comp.status === Component.Ready) {
                        tabStack.sourceComponent = comp
                    }
                })
            }
        } else {
            tabStack.source = tab.widget
        }
    }

    // Toggling a tab shifts the ones after it, so whatever now sits at the index loads.
    onTabsChanged: refreshCurrentTab()
    property var tabs: [
        ...[
            {
                "type": "calendar",
                "name": Translation.tr("Calendar"),
                "icon": "calendar_month",
                "widget": "calendar/CalendarWidget.qml",
                "shown": root.shown.calendar
            },
            {
                "type": "todo",
                "name": Translation.tr("To do"),
                "icon": "done_outline",
                "widget": "todo/TodoWidget.qml",
                "shown": root.shown.todo
            },
            {
                "type": "timer",
                "name": Translation.tr("Timer"),
                "icon": "schedule",
                "widget": "pomodoro/PomodoroWidget.qml",
                "shown": root.shown.timer
            }
        ].filter(tab => tab.shown),
        ...root.extensionTabs.map(p => ({
            "type": "ext_" + p.identifier,
            "name": p.title,
            "icon": p.icon,
            "widget": "file://" + p.fullPath + "?_t=" + Date.now(),
            "fullPath": p.fullPath,
            "isExtension": true,
            "extensionId": p.extensionId
        }))
    ]

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    function setCollapsed(state) {
        Persistent.states.sidebar.bottomGroup.collapsed = state;
    }

    // Fade-through: the leaving row goes at once, the arriving one waits out its exit.
    onCollapsedChanged: fadeThroughGap.restart()
    Timer {
        id: fadeThroughGap
        interval: Appearance.animation.elementMoveExit.duration
    }

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.ControlModifier) {
            root.selectTab(root.selectedTab + (event.key === Qt.Key_PageDown ? 1 : -1));
            event.accepted = true;
        }
    }

    RowLayout { // Collapsed
        id: collapsedBottomWidgetGroupRow
        opacity: root.collapsed && !fadeThroughGap.running ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            id: collapsedFade
            FadeThrough { owner: collapsedFade }
        }

        spacing: 15

        CalendarHeaderButton {
            Layout.margins: 10
            Layout.rightMargin: 0
            forceCircle: true
            downAction: () => {
                root.setCollapsed(false);
            }
            contentItem: MaterialSymbol {
                text: "keyboard_arrow_up"
                iconSize: Appearance.font.pixelSize.larger
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colOnLayer1
            }
        }

        StyledText {
            Layout.margins: 10
            Layout.leftMargin: 0
            // One part per enabled tab; the timer only speaks up while it runs,
            // unless it is the only tab.
            text: {
                const parts = [];
                if (root.shown.calendar)
                    parts.push(DateTime.collapsedCalendarFormat);
                if (root.shown.todo)
                    parts.push(Translation.tr("%1 tasks").arg(Todo.list.filter(task => !task.done).length));
                if (root.shown.timer) {
                    if (TimerService.pomodoroRunning)
                        parts.push(Translation.tr("%1 left").arg(Duration.format(TimerService.pomodoroSecondsLeft)));
                    else if (TimerService.stopwatchRunning)
                        parts.push(Duration.format10ms(TimerService.stopwatchTime));
                    else if (!parts.length)
                        parts.push(Translation.tr("Timer idle"));
                }
                return parts.join("   •   ");
            }
            font.pixelSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
        }
    }

    RowLayout { // Expanded
        id: bottomWidgetGroupRow

        opacity: !root.collapsed && !fadeThroughGap.running ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            id: expandedFade
            FadeThrough { owner: expandedFade }
        }

        anchors.fill: parent
        spacing: 20

        Item { // Navigation rail
            id: rail
            Layout.fillHeight: true
            Layout.fillWidth: false
            Layout.leftMargin: 10
            Layout.topMargin: 10
            // A rail of one tab switches nothing; only the collapse button stays.
            implicitWidth: tabBar.visible ? tabBar.implicitWidth : collapseButton.implicitWidth
            NavigationRailTabArray {
                id: tabBar
                visible: root.tabs.length > 1
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 5
                currentIndex: root.selectedTab
                expanded: false
                Repeater {
                    model: root.tabs
                    NavigationRailButton {
                        required property int index
                        required property var modelData
                        showToggledHighlight: false
                        toggled: root.selectedTab == index
                        buttonText: modelData.name
                        buttonIcon: modelData.icon
                        onPressed: root.selectTab(index)
                    }
                }
            }
            CalendarHeaderButton {
                id: collapseButton
                anchors.left: parent.left
                anchors.top: parent.top
                forceCircle: true
                downAction: () => {
                    root.setCollapsed(true);
                }
                contentItem: MaterialSymbol {
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        Item { // Content area
            Layout.fillWidth: true
            // With no rail, the chevron's inset is mirrored so the widget sits centred in the card.
            Layout.rightMargin: tabBar.visible ? 0 : rail.Layout.leftMargin + rail.implicitWidth + bottomWidgetGroupRow.spacing
            Layout.fillHeight: true

            Loader {
                id: tabStack
                anchors.fill: parent
                anchors.bottomMargin: -anchors.topMargin

                onLoaded: {
                    let tab = root.tabs[root.selectedTab]
                    if (tab && tab.extensionId && item) {
                        if ("extensionId" in item) {
                            item.extensionId = tab.extensionId
                        } else {
                            Object.defineProperty(item, "extensionId", {
                                value: tab.extensionId,
                                writable: true,
                                configurable: true,
                                enumerable: true
                            })
                        }
                    }
                }

                Component.onCompleted: {
                    root.lastTab = root.selectedTab;
                    tabStack.source = root.tabs[root.selectedTab].widget;
                }

                Connections {
                    target: root
                    function onSelectedTabChanged() {
                        tabSwitchBehavior.animation.down = root.selectedTab > root.lastTab;
                        root.lastTab = root.selectedTab;
                        tabStack.source = root.tabs[root.selectedTab].widget;
                    }
                }

                Behavior on source {
                    id: tabSwitchBehavior
                    animation: TabSwitchAnim {
                        id: upAnim
                        down: true
                    }
                }
            }
        }
    }

    component TabSwitchAnim: SequentialAnimation {
        id: switchAnim
        property bool down: false
        ParallelAnimation {
            PropertyAnimation {
                target: tabStack
                properties: "opacity"
                to: 0
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
            PropertyAnimation {
                target: tabStack.anchors
                properties: "topMargin"
                to: 10 * (switchAnim.down ? -1 : 1)
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
        }
        PropertyAction {
            target: tabStack
            property: "source"
            value: root.tabs[root.selectedTab]?.widget ?? "" // tabs shrinks a beat before selectedTab clamps
        } // The source change happens here
        ParallelAnimation {
            PropertyAnimation {
                target: tabStack.anchors
                properties: "topMargin"
                from: 10 * -(switchAnim.down ? -1 : 1)
                to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            PropertyAnimation {
                target: tabStack
                properties: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }

    // Behavior writes targetValue before it builds the transition, so the spec is
    // picked per direction: out on fast effects, in on default effects.
    component FadeThrough: NumberAnimation {
        required property Behavior owner
        duration: owner.targetValue > 0 ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMoveExit.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.expressiveEffects
    }
}
