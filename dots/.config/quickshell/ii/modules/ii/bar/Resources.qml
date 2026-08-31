import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    readonly property bool showCpu: Config.options.bar.resources.showCpu ?? true
    readonly property bool showRam: Config.options.bar.resources.showRam ?? true
    readonly property bool showTemp: Config.options.bar.resources.showTemp ?? true
    readonly property bool showNetwork: Config.options.bar.resources.showNetwork ?? false
    readonly property bool showSwap: Config.options.bar.resources.showSwap ?? false
    readonly property bool showGpu: Config.options.bar.resources.showGpu ?? false
    readonly property bool showDisk: Config.options.bar.resources.showDisk ?? false

    readonly property real netSpeedBytes: NetworkUsage.networkDownloadSpeed + NetworkUsage.networkUploadSpeed
    readonly property int maxNetSpeedBytes: Math.max(1, (Config.options.bar.resources.networkMaxSpeed ?? 100) * 125000)
    readonly property real netLoadFraction: Math.min(1.0, netSpeedBytes / maxNetSpeedBytes)

    function formatSpeedBrief(bytes) {
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + "G";
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + "M";
        if (bytes >= 1024) return Math.round(bytes / 1024).toString() + "K";
        return Math.round(bytes).toString();
    }

    readonly property bool showSymbols: Config.options.bar.resources.showSymbols ?? false
    readonly property string ramUnit: Config.options.bar.resources.ramUnit ?? "percent"

    // Custom formatted text helpers
    readonly property string cpuText: {
        const val = Math.round(ResourceUsage.cpuUsage * 100);
        return showSymbols ? `${val}%` : `${val}`;
    }

    readonly property string ramText: {
        if (ramUnit === "gb") {
            const gb = (ResourceUsage.memoryUsed / (1024 * 1024)).toFixed(1);
            return showSymbols ? `${gb}G` : `${gb}`;
        } else if (ramUnit === "mb") {
            const mb = Math.round(ResourceUsage.memoryUsed / 1024);
            return showSymbols ? `${mb}M` : `${mb}`;
        }
        const pct = Math.round(ResourceUsage.memoryUsedPercentage * 100);
        return showSymbols ? `${pct}%` : `${pct}`;
    }

    readonly property string tempText: {
        const val = Math.round(ResourceUsage.cpuTemp);
        return showSymbols ? `${val}°C` : `${val}`;
    }

    readonly property string netText: {
        if (Config.options.bar.resources.networkUnit === "speed") {
            return formatSpeedBrief(netSpeedBytes);
        }
        const val = Math.round(netLoadFraction * 100);
        return showSymbols ? `${val}%` : `${val}`;
    }

    readonly property string swapText: {
        if (ramUnit === "gb") {
            const gb = (ResourceUsage.swapUsed / (1024 * 1024)).toFixed(1);
            return showSymbols ? `${gb}G` : `${gb}`;
        } else if (ramUnit === "mb") {
            const mb = Math.round(ResourceUsage.swapUsed / 1024);
            return showSymbols ? `${mb}M` : `${mb}`;
        }
        const pct = Math.round(ResourceUsage.swapUsedPercentage * 100);
        return showSymbols ? `${pct}%` : `${pct}`;
    }

    readonly property string gpuText: {
        const val = Math.round(ResourceUsage.gpuUsage * 100);
        return showSymbols ? `${val}%` : `${val}`;
    }

    readonly property string diskText: {
        const val = Math.round(ResourceUsage.diskUsedPercentage * 100);
        return showSymbols ? `${val}%` : `${val}`;
    }

    onShowNetworkChanged: {
        if (showNetwork) NetworkUsage.activeInstances++;
        else NetworkUsage.activeInstances = Math.max(0, NetworkUsage.activeInstances - 1);
    }
    Component.onCompleted: {
        if (showNetwork) NetworkUsage.activeInstances++;
    }
    Component.onDestruction: {
        if (showNetwork) NetworkUsage.activeInstances = Math.max(0, NetworkUsage.activeInstances - 1);
    }

    RowLayout {
        id: rowLayout

        spacing: 0
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        Resource {
            iconName: "planner_review"
            percentage: ResourceUsage.cpuUsage
            customText: root.cpuText
            shown: root.showCpu
            warningThreshold: Config.options.bar.resources.cpuWarningThreshold ?? 90
        }

        Resource {
            iconName: "memory"
            percentage: ResourceUsage.memoryUsedPercentage
            customText: root.ramText
            shown: root.showRam
            Layout.leftMargin: shown && root.showCpu ? 6 : 0
            warningThreshold: Config.options.bar.resources.memoryWarningThreshold ?? 95
        }

        Resource {
            iconName: "thermostat"
            percentage: ResourceUsage.cpuTemp / 100
            customText: root.tempText
            shown: root.showTemp
            Layout.leftMargin: shown && (root.showCpu || root.showRam) ? 6 : 0
            warningThreshold: Config.options.bar.resources.tempWarningThreshold ?? 85
        }

        Resource {
            iconName: "swap_vert"
            percentage: root.netLoadFraction
            customText: root.netText
            shown: root.showNetwork
            Layout.leftMargin: shown && (root.showCpu || root.showRam || root.showTemp) ? 6 : 0
            warningThreshold: 90
        }

        Resource {
            iconName: "swap_horiz"
            percentage: ResourceUsage.swapUsedPercentage
            customText: root.swapText
            shown: root.showSwap
            Layout.leftMargin: shown && (root.showCpu || root.showRam || root.showTemp || root.showNetwork) ? 6 : 0
            warningThreshold: Config.options.bar.resources.swapWarningThreshold ?? 85
        }

        Resource {
            iconName: "videogame_asset"
            percentage: ResourceUsage.gpuUsage
            customText: root.gpuText
            shown: root.showGpu
            Layout.leftMargin: shown && (root.showCpu || root.showRam || root.showTemp || root.showNetwork || root.showSwap) ? 6 : 0
            warningThreshold: 90
        }

        Resource {
            iconName: "hard_drive"
            percentage: ResourceUsage.diskUsedPercentage
            customText: root.diskText
            shown: root.showDisk
            Layout.leftMargin: shown && (root.showCpu || root.showRam || root.showTemp || root.showNetwork || root.showSwap || root.showGpu) ? 6 : 0
            warningThreshold: 90
        }
    }

    ResourcesPopup {
        hoverTarget: root
    }
}
