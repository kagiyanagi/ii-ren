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

    implicitWidth: wrapper.implicitWidth
    implicitHeight: wrapper.implicitHeight

    // Seed from the layout entry so a rebuilt delegate already matches the config;
    // otherwise it defaults to true and the widget writes `false` back on every
    // rebuild, which re-evaluates the Repeater's model and rebuilds it again.
    // toggleVisible() overwrites this imperatively on a real change.
    visible: modelData?.visible !== false

    function toggleVisible(visibility) {
        // This writes the layout back, and the layout is the Repeater's model, so
        // an unconditional write rebuilds every delegate and calls us again.
        // Callers (SysTray, timer, record/screenshare/privacy indicators) fire on
        // every update, so only write on a real change.
        if (visible === visibility) return;
        visible = visibility
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
        "screen_share_indicator": [screenshareIndicatorComp, screenshareIndicatorComp],
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

    property real startRadius: {
        if (rootItem.isolated || rootItem.isSpacer) return Appearance.rounding.full
        if (barSection === 0) {
            if (originalIndex == 0) return Appearance.rounding.full
            let prevList = list.slice(0, originalIndex).reverse()
            let prevVisible = prevList.find(item => item.visible !== false && item.id !== "record_indicator" && item.id !== "privacy_indicator" && item.id !== "screen_share_indicator")
            if (prevVisible && (prevVisible.id === "sacebar" || prevVisible.id === "spacebar")) return Appearance.rounding.full
            return Appearance.rounding.verysmall
        } else if (barSection === 2) {
            let prevList = list.slice(0, originalIndex).reverse()
            let prevVisible = prevList.find(item => item.visible !== false && item.id !== "record_indicator" && item.id !== "privacy_indicator" && item.id !== "screen_share_indicator")
            if (!prevVisible || prevVisible.id === "sacebar" || prevVisible.id === "spacebar") return Appearance.rounding.full
            return Appearance.rounding.verysmall
        } else { // barSection 1 
            if (list.length === 1) return Appearance.rounding.full
            let prevList = list.slice(0, originalIndex).reverse()
            let prevVisible = prevList.find(item => item.visible !== false && item.id !== "record_indicator" && item.id !== "privacy_indicator" && item.id !== "screen_share_indicator")
            if (!prevVisible || prevVisible.id === "sacebar" || prevVisible.id === "spacebar") return Appearance.rounding.full
            return Appearance.rounding.verysmall
        }
    }

    property real endRadius: {
        if (rootItem.isolated || rootItem.isSpacer) return Appearance.rounding.full
        if (barSection === 2) {
            if (originalIndex == list.length - 1) return Appearance.rounding.full
            let nextVisible = list.slice(originalIndex + 1).find(item => item.visible !== false && item.id !== "record_indicator" && item.id !== "privacy_indicator" && item.id !== "screen_share_indicator")
            if (nextVisible && (nextVisible.id === "sacebar" || nextVisible.id === "spacebar")) return Appearance.rounding.full
            return Appearance.rounding.verysmall
        } else if (barSection === 0) {
            let nextVisible = list.slice(originalIndex + 1).find(item => item.visible !== false && item.id !== "record_indicator" && item.id !== "privacy_indicator" && item.id !== "screen_share_indicator")
            if (!nextVisible || nextVisible.id === "sacebar" || nextVisible.id === "spacebar") return Appearance.rounding.full
            return Appearance.rounding.verysmall
        } else { // barSection 1 
            if (list.length === 1) return Appearance.rounding.full
            let nextVisible = list.slice(originalIndex + 1).find(item => item.visible !== false && item.id !== "record_indicator" && item.id !== "privacy_indicator" && item.id !== "screen_share_indicator")
            if (!nextVisible || nextVisible.id === "sacebar" || nextVisible.id === "spacebar") return Appearance.rounding.full
            return Appearance.rounding.verysmall
        }
    }

    readonly property int barGroupStyle: Config.options.bar.barGroupStyle
    readonly property int barBackgroundStyle: Config.options.bar.barBackgroundStyle
    property color colBackground: isSpacer ? "transparent" :
                                   barGroupStyle == 0 ? Appearance.colors.colLayer1 :
                                   (barGroupStyle == 1 && barBackgroundStyle == 1) ? Appearance.colors.colLayer1 :
                                   (barGroupStyle == 1) ? Appearance.m3colors.m3surfaceContainerLow :
                                   "transparent";
    
    property color colBackgroundHighlight: rootItem.customHighlightColor ?? Appearance.colors.colPrimary

    BarGroup {
        id: wrapper
        vertical: rootItem.vertical
        padding: rootItem.isSpacer ? 0 : 5
        anchors {
            verticalCenter: root.vertical ? rootItem.verticalCenter : undefined
            horizontalCenter: root.vertical ? undefined : rootItem.horizontalCenter
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

    Component { id: screenshareIndicatorComp; ScreenShareIndicator {} }

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
