import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.ii.bar.weather

import qs.modules.ii.verticalBar as Vertical

Item {
    id: rootItem

    property int barSection // 0: left, 1: center, 2: right
    property var list
    required property var modelData
    required property int index
    property var originalIndex: index
    property bool vertical: false
    property bool highlighted: false

    // Seed from the layout entry so a rebuilt delegate already matches the config;
    // otherwise it defaults to true and the widget writes `false` back on every
    // rebuild, which re-evaluates the Repeater's model and rebuilds it again.
    // toggleVisible() overwrites this imperatively on a real change.
    property bool shown: modelData?.visible !== false

    /**
     * A widget that comes and goes -- the record and privacy indicators, the
     * timer, a tray that empties -- used to pop out of the row
     * with nothing in either direction (DESIGN.md 2.5, anti-pattern 10). It
     * collapses along the bar's axis instead: in on fast spatial, out on fast
     * effects at about a third, staying in the layout until the collapse has
     * finished so the row does not swallow it mid-animation.
     *
     * The spec is assigned from inside the binding that writes the size, which
     * looks backwards and is the only order that holds: a Behavior bakes
     * duration and curve at the instant the write happens, so a spec read from
     * a binding of its own is a frame late and the exit runs on the enter's
     * curve (2.9, the shape Revealer already uses).
     */
    property AnimSpec sizeSpec: Appearance.animation.elementResize

    function pickSizeSpec(): void {
        rootItem.sizeSpec = rootItem.shown ? Appearance.animation.elementResize : Appearance.animation.elementMoveExit;
    }

    implicitWidth: {
        rootItem.pickSizeSpec();
        return (rootItem.shown || rootItem.vertical) ? wrapper.implicitWidth : 0;
    }
    implicitHeight: {
        rootItem.pickSizeSpec();
        return (rootItem.shown || !rootItem.vertical) ? wrapper.implicitHeight : 0;
    }
    // An id with nothing behind it (a retired widget, an uninstalled extension)
    // left in the saved layout would otherwise draw an empty pill.
    visible: !!wrapper._currentComp && (rootItem.shown || (rootItem.vertical ? rootItem.implicitHeight > 0 : rootItem.implicitWidth > 0))
    // Only while a collapse is under way. A permanent scissor on every bar
    // delegate costs more than the frames it is wanted for (DESIGN.md 8).
    clip: rootItem.vertical ? (rootItem.implicitHeight < wrapper.implicitHeight) : (rootItem.implicitWidth < wrapper.implicitWidth)

    Behavior on implicitWidth {
        enabled: !rootItem.vertical
        SizeAnim {}
    }
    Behavior on implicitHeight {
        enabled: rootItem.vertical
        SizeAnim {}
    }

    component SizeAnim: NumberAnimation {
        alwaysRunToEnd: false
        duration: rootItem.sizeSpec.duration
        easing.type: rootItem.sizeSpec.type
        easing.bezierCurve: rootItem.sizeSpec.bezierCurve
    }

    function toggleVisible(visibility) {
        // This writes the layout back, and the layout is the Repeater's model, so
        // an unconditional write rebuilds every delegate and calls us again.
        // Callers (SysTray, timer, record/privacy indicators) fire on every
        // update, so only write on a real change.
        if (rootItem.shown === visibility) return;
        rootItem.shown = visibility
        const section = barSection == 0 ? Config.options.bar.layouts.left : barSection == 1 ? Config.options.bar.layouts.center : Config.options.bar.layouts.right;
        if (section?.[originalIndex]) section[originalIndex].visible = visibility;
    }

    property bool isolated: false
    property var customHighlightColor: null

    function toggleHighlight(highlight) {
        rootItem.highlighted = highlight
    }

    property var compMap: ({ // [horizontal, vertical]
        "workspaces": [workspaceComp,workspaceComp],
        "music_player": [musicPlayerComp, musicPlayerCompVert],
        "system_monitor": [systemMonitorComp, systemMonitorCompVert],
        "clock": [clockComp, clockCompVert],
        "battery": [batteryComp, batteryCompVert],
        "utility_buttons": [utilityButtonsComp, utilityButtonsComp],
        "system_tray": [systemTrayComp, systemTrayComp],
        "active_window": [activeWindowComp, activeWindowComp],
        "date": [dateCompVert, dateCompVert],
        "record_indicator": [recordIndicatorComp, recordIndicatorComp],
        "timer": [timerComp, timerCompVert],
        "weather": [weatherComp, weatherComp],
        "policies_panel_button": [policiesPanelButton, policiesPanelButton],
        "dashboard_panel_button": [dashboardPanelButton, dashboardPanelButtonVert],
        "network_speed": [networkSpeedComp, networkSpeedComp],
        "privacy_indicator": [privacyIndicatorComp, privacyIndicatorComp],
        "visualizer": [visualizerComp, visualizerComp],
        "sacebar": [spacebarComp, spacebarComp],
        "spacebar": [spacebarComp, spacebarComp],
    })

    readonly property bool isSpacer: modelData?.id === "sacebar" || modelData?.id === "spacebar"

    // Material (3): every widget its own pill, none joining corners, and the
    // clock, weather, battery, media, network speed and visualizer draw theirs
    // (BarMaterialPill) over a bare group.
    readonly property bool material: Config.options.bar.barGroupStyle === 3
    readonly property bool drawsOwnPill: material && !rootItem.vertical
        && ["clock", "weather", "battery", "music_player", "network_speed", "visualizer"].includes(modelData?.id)
    // And no inset where the widget is one control with its own hover film, so
    // the film fills the pill rather than sitting 4 inside it -- or, for the
    // util buttons, insets its own circles.
    readonly property bool fillsPill: drawsOwnPill || (material && !rootItem.vertical
        && ["system_monitor", "policies_panel_button", "dashboard_panel_button", "system_tray", "utility_buttons"].includes(modelData?.id))

    property real startRadius: {
        if (rootItem.isolated || rootItem.isSpacer || rootItem.material) return Appearance.rounding.full
        if (barSection === 0) {
            if (originalIndex == 0) return Appearance.rounding.full
            let prevList = list.slice(0, originalIndex).reverse()
            let prevVisible = prevList.find(item => item.visible !== false && item.id !== "record_indicator" && item.id !== "privacy_indicator")
            if (prevVisible && (prevVisible.id === "sacebar" || prevVisible.id === "spacebar")) return Appearance.rounding.full
            return Appearance.rounding.verysmall
        } else if (barSection === 2) {
            let prevList = list.slice(0, originalIndex).reverse()
            let prevVisible = prevList.find(item => item.visible !== false && item.id !== "record_indicator" && item.id !== "privacy_indicator")
            if (!prevVisible || prevVisible.id === "sacebar" || prevVisible.id === "spacebar") return Appearance.rounding.full
            return Appearance.rounding.verysmall
        } else { // barSection 1 
            if (list.length === 1) return Appearance.rounding.full
            let prevList = list.slice(0, originalIndex).reverse()
            let prevVisible = prevList.find(item => item.visible !== false && item.id !== "record_indicator" && item.id !== "privacy_indicator")
            if (!prevVisible || prevVisible.id === "sacebar" || prevVisible.id === "spacebar") return Appearance.rounding.full
            return Appearance.rounding.verysmall
        }
    }

    property real endRadius: {
        if (rootItem.isolated || rootItem.isSpacer || rootItem.material) return Appearance.rounding.full
        if (barSection === 2) {
            if (originalIndex == list.length - 1) return Appearance.rounding.full
            let nextVisible = list.slice(originalIndex + 1).find(item => item.visible !== false && item.id !== "record_indicator" && item.id !== "privacy_indicator")
            if (nextVisible && (nextVisible.id === "sacebar" || nextVisible.id === "spacebar")) return Appearance.rounding.full
            return Appearance.rounding.verysmall
        } else if (barSection === 0) {
            let nextVisible = list.slice(originalIndex + 1).find(item => item.visible !== false && item.id !== "record_indicator" && item.id !== "privacy_indicator")
            if (!nextVisible || nextVisible.id === "sacebar" || nextVisible.id === "spacebar") return Appearance.rounding.full
            return Appearance.rounding.verysmall
        } else { // barSection 1 
            if (list.length === 1) return Appearance.rounding.full
            let nextVisible = list.slice(originalIndex + 1).find(item => item.visible !== false && item.id !== "record_indicator" && item.id !== "privacy_indicator")
            if (!nextVisible || nextVisible.id === "sacebar" || nextVisible.id === "spacebar") return Appearance.rounding.full
            return Appearance.rounding.verysmall
        }
    }

    // Layer 2, not 1: surfaceContainerLow sits one tone above the bar and the
    // pills all but vanish on a dark scheme.
    property color colBackground: (material && !isSpacer && !drawsOwnPill) ? Appearance.colors.colLayer2 : "transparent"
    
    property color colBackgroundHighlight: rootItem.customHighlightColor ?? Appearance.colors.colPrimary

    BarGroup {
        id: wrapper
        vertical: rootItem.vertical
        padding: (rootItem.isSpacer || rootItem.fillsPill) ? 0 : 4
        anchors {
            // `root` here was BarContent's id, not this file's -- it has no
            // `vertical`, so the group took the horizontal branch in both bars.
            verticalCenter: rootItem.vertical ? rootItem.verticalCenter : undefined
            horizontalCenter: rootItem.vertical ? undefined : rootItem.horizontalCenter
        }
        
        startRadius: rootItem.startRadius
        endRadius: rootItem.endRadius
        colBackground: rootItem.highlighted ? rootItem.colBackgroundHighlight : rootItem.colBackground

        readonly property var _currentComp: {
            BarComponentRegistry._extensionCompVersion
            let builtin = compMap[modelData.id]
            if (builtin) return builtin[vertical ? 1 : 0]
            return BarComponentRegistry.getComponentForId(modelData.id, vertical)
        }

        Loader {
            id: itemLoader
            active: true
            sourceComponent: wrapper._currentComp
            onLoaded: {
                let extId = BarComponentRegistry.getExtensionIdForComponent(modelData.id)
                if (extId && item) {
                    if ("extensionId" in item) {
                        item.extensionId = extId
                    } else {
                        Object.defineProperty(item, "extensionId", {
                            value: extId,
                            writable: true,
                            configurable: true,
                            enumerable: true
                        })
                    }
                }
            }
        }
    }


    Component { id: weatherComp; WeatherBar { vertical: rootItem.vertical } }

    Component { id: timerComp; TimerWidget {} }
    Component { id: timerCompVert; Vertical.VerticalTimerWidget {} }

    Component { id: privacyIndicatorComp; PrivacyIndicator { vertical: rootItem.vertical } }

    Component { id: recordIndicatorComp; RecordIndicator { vertical: rootItem.vertical } }

    Component { id: activeWindowComp; ActiveWindow { vertical: rootItem.vertical } }

    Component { id: systemMonitorComp; Resources {} }
    Component { id: systemMonitorCompVert; Vertical.Resources {} }

    Component { id: musicPlayerCompVert; Vertical.VerticalMedia {} }
    Component { id: musicPlayerComp; Media {} }

    Component { id: utilityButtonsComp; UtilButtons { vertical: rootItem.vertical } }

    Component { id: batteryComp; BatteryIndicator {} }
    Component { id: batteryCompVert; Vertical.BatteryIndicator {} }

    Component { id: clockCompVert; Vertical.VerticalClockWidget {} }
    Component { id: clockComp; ClockWidget {} }

    Component { id: systemTrayComp; SysTray { vertical: rootItem.vertical } }

    Component { id: dateCompVert; Vertical.VerticalDateWidget {} }

    Component { id: workspaceComp; Workspaces { vertical: rootItem.vertical } }

    Component { id: policiesPanelButton; PoliciesPanelButton {} }
    
    Component { id: dashboardPanelButton; DashboardPanelButton {} }
    Component { id: networkSpeedComp; NetworkSpeed { vertical: rootItem.vertical } }
    Component { id: visualizerComp; Visualizer { vertical: rootItem.vertical } }
    Component { id: spacebarComp; Spacebar { vertical: rootItem.vertical; modelData: rootItem.modelData } }
    Component { id: dashboardPanelButtonVert; DashboardPanelButton { vertical: true } }
}
