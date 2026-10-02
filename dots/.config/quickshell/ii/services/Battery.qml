pragma Singleton

import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Wayland
import QtQuick
import Quickshell.Io

Singleton {
    id: root
    property bool available: UPower.displayDevice.isLaptopBattery
    property var chargeState: UPower.displayDevice.state
    property bool isCharging: chargeState == UPowerDeviceState.Charging
    property bool isPluggedIn: isCharging || chargeState == UPowerDeviceState.PendingCharge || chargeState == UPowerDeviceState.FullyCharged
    property real percentage: UPower.displayDevice?.percentage ?? 1
    readonly property bool allowAutomaticSuspend: Config.options.battery.automaticSuspend

    property bool isLow: available && (percentage <= Config.options.battery.low / 100)
    property bool isCritical: available && (percentage <= Config.options.battery.critical / 100)
    property bool isSuspending: available && (percentage <= Config.options.battery.suspend / 100)
    property bool isFull: available && (percentage >= Config.options.battery.full / 100)

    property bool isLowAndNotCharging: isLow && !isCharging
    property bool isCriticalAndNotCharging: isCritical && !isCharging
    property bool isSuspendingAndNotCharging: allowAutomaticSuspend && isSuspending && !isCharging
    property bool isFullAndCharging: isFull && isCharging

    property real energyRate: UPower.displayDevice.changeRate
    property real timeToEmpty: UPower.displayDevice.timeToEmpty
    property real timeToFull: UPower.displayDevice.timeToFull

    readonly property var laptopBattery: UPower.devices.values.find(dev => dev.isLaptopBattery) ?? null

    property real health: (function() {
        if (!root.laptopBattery?.healthSupported) return 0;
        const health = root.laptopBattery.healthPercentage;
        if (health === 0) return 0.01;
        return health < 1 ? health * 100 : health;
    })()

    property string batteryNativePath: root.laptopBattery?.nativePath ?? ""

    property int cycles: -1

    // Charge limit: standard kernel ABI first, then known vendor-specific locations (TLP-style)
    readonly property var chargeLimitCandidates: {
        const paths = [];
        if (!available) return paths;
        if (batteryNativePath) {
            paths.push({ path: `/sys/class/power_supply/${batteryNativePath}/charge_control_end_threshold`, type: "plain" });
            paths.push({ path: `/sys/devices/platform/smapi/${batteryNativePath}/stop_charge_thresh`, type: "plain" });
        }
        paths.push({ path: "/sys/devices/platform/huawei-wmi/charge_control_thresholds", type: "last" });
        paths.push({ path: "/sys/devices/platform/lg-laptop/battery_care_limit", type: "plain" });
        paths.push({ path: "/sys/devices/platform/sony-laptop/battery_care_limiter", type: "plain" });
        paths.push({ path: "/sys/devices/platform/samsung/battery_life_extender", type: "bool80" });
        return paths;
    }
    property int chargeLimitCandidateIndex: 0
    property int chargeLimit: 100 // 0 or 100 = no limit
    // Where the kernel has charge modes (charge_types, e.g. dell-laptop), the
    // thresholds only apply in Custom: in Adaptive or Standard the firmware
    // keeps them on file and charges straight past them. No file, no modes.
    property string chargeMode: ""
    readonly property bool chargeLimitActive: available && chargeLimit > 0 && chargeLimit < 100
        && (chargeMode === "" || chargeMode === "Custom")

    // At the limit the firmware reports Discharging/PendingCharge at ~0W even though AC is plugged in,
    // so the AC line (UPower.onBattery) is the reliable signal, not the battery state
    readonly property bool chargeLimitReached: chargeLimitActive && !UPower.onBattery
        && !isCharging && (percentage * 100 >= chargeLimit - 1)

    // Time until the effective full point (charge limit if active, otherwise UPower's estimate)
    readonly property real timeToFullEffective: {
        if (!chargeLimitActive) return timeToFull;
        const dev = UPower.displayDevice;
        const rate = Math.abs(dev.changeRate);
        if (dev.energyCapacity > 0 && rate > 0.01) {
            const remaining = dev.energyCapacity * (chargeLimit / 100) - dev.energy;
            return Math.max(0, remaining / rate * 3600);
        }
        if (percentage < 1 && timeToFull > 0) {
            return timeToFull * Math.max(0, chargeLimit / 100 - percentage) / (1 - percentage);
        }
        return 0;
    }

    function parseChargeLimit(content, type) {
        if (type === "bool80") return content === "1" ? 80 : 100;
        const parts = content.split(/\s+/);
        const val = parseInt(type === "last" ? parts[parts.length - 1] : parts[0], 10);
        if (isNaN(val) || val <= 0) return 100;
        return Math.min(val, 100);
    }

    FileView {
        id: chargeLimitFile
        printErrors: false // Walking a candidate list: most of them are absent by design
        path: root.chargeLimitCandidates[root.chargeLimitCandidateIndex]?.path ?? ""
        onLoaded: {
            const candidate = root.chargeLimitCandidates[root.chargeLimitCandidateIndex];
            root.chargeLimit = root.parseChargeLimit(text().trim(), candidate.type);
        }
        onLoadFailed: {
            if (root.chargeLimitCandidateIndex < root.chargeLimitCandidates.length - 1) {
                root.chargeLimitCandidateIndex++;
            } else {
                root.chargeLimit = 100;
            }
        }
    }

    FileView {
        id: chargeTypesFile
        printErrors: false // Only some drivers have charge modes
        path: root.batteryNativePath ? `/sys/class/power_supply/${root.batteryNativePath}/charge_types` : ""
        // "Trickle Fast Standard [Adaptive] Custom": the bracketed one is selected
        onLoaded: root.chargeMode = text().match(/\[([^\]]+)\]/)?.[1] ?? text().trim()
        onLoadFailed: root.chargeMode = ""
    }

    FileView {
        id: cycleCountFile
        printErrors: false // Plenty of batteries do not report a cycle count
        path: root.batteryNativePath ? `/sys/class/power_supply/${root.batteryNativePath}/cycle_count` : ""
        onLoaded: {
            const content = text().trim();
            const val = parseInt(content, 10);
            if (!isNaN(val) && val > 0) {
                root.cycles = val;
            } else {
                root.cycles = -1;
            }
        }
        onLoadFailed: {
            root.cycles = -1;
        }
    }

    // sysfs has no change notification, so this runs when something may have
    // moved it: the battery, its state, or the Battery page setting a limit.
    function reloadChargeLimit() {
        cycleCountFile.reload();
        root.chargeLimitCandidateIndex = 0;
        chargeLimitFile.reload();
        chargeTypesFile.reload();
    }
    onBatteryNativePathChanged: reloadChargeLimit()
    onChargeStateChanged: reloadChargeLimit()

    // Power saver at the low warning, handed back once plugged in, as GNOME and
    // Android's battery saver do. Only a switch this made is undone: a profile
    // picked by hand since then stays. ponytail: in memory, so a shell restart
    // in between leaves power saver on.
    property int profileBeforeSaver: -1
    onIsLowAndNotChargingChanged: {
        if (!root.available || !isLowAndNotCharging) return;
        if (Config.options.battery.autoPowerSaver && PowerProfiles.profile !== PowerProfile.PowerSaver) {
            root.profileBeforeSaver = PowerProfiles.profile;
            PowerProfiles.profile = PowerProfile.PowerSaver;
        }
        Quickshell.execDetached([
            "notify-send", 
            Translation.tr("Low battery"), 
            Translation.tr("Consider plugging in your device"), 
            "-u", "critical",
            "-a", "Shell",
            "--hint=int:transient:1",
            "--hint=boolean:suppress-sound:true",
        ])

        SoundService.playEvent("battery");
    }

    onIsCriticalAndNotChargingChanged: {
        if (!root.available || !isCriticalAndNotCharging) return;
        Quickshell.execDetached([
            "notify-send", 
            Translation.tr("Critically low battery"), 
            !root.allowAutomaticSuspend ? Translation.tr("Please charge!")
                : Config.options.battery.criticalAction === "hibernate" ? Translation.tr("Please charge!\nHibernates at %1%").arg(Config.options.battery.suspend)
                : Config.options.battery.criticalAction === "poweroff" ? Translation.tr("Please charge!\nShuts down at %1%").arg(Config.options.battery.suspend)
                : Translation.tr("Please charge!\nAutomatic suspend triggers at %1%").arg(Config.options.battery.suspend),
            "-u", "critical",
            "-a", "Shell",
            "--hint=int:transient:1",
            "--hint=boolean:suppress-sound:true",
        ]);

        // A theme with no caution sound of its own still has its low one.
        SoundService.playEvent("battery", ["battery-caution", "battery-low", "suspend-error", "dialog-error"]);
    }

    // Hibernate falls back to suspend: a failed one would leave nothing between
    // the session and an empty battery.
    onIsSuspendingAndNotChargingChanged: {
        if (!root.available || !isSuspendingAndNotCharging) return;
        const action = Config.options.battery.criticalAction;
        Quickshell.execDetached(["bash", "-c", action === "hibernate" ? "systemctl hibernate || systemctl suspend || loginctl suspend"
            : action === "poweroff" ? "systemctl poweroff || loginctl poweroff"
            : "systemctl suspend || loginctl suspend"]);
    }

    onIsFullAndChargingChanged: {
        if (!root.available || !isFullAndCharging) return;
        Quickshell.execDetached([
            "notify-send",
            Translation.tr("Battery full"),
            Translation.tr("Please unplug the charger"),
            "-a", "Shell",
            "--hint=int:transient:1",
            "--hint=boolean:suppress-sound:true",
        ]);

        SoundService.playEvent("battery", ["battery-full", "complete", "dialog-information"]);
    }

    onIsPluggedInChanged: {
        if (!root.available) return;
        if (isPluggedIn && root.profileBeforeSaver !== -1) {
            if (PowerProfiles.profile === PowerProfile.PowerSaver) PowerProfiles.profile = root.profileBeforeSaver;
            root.profileBeforeSaver = -1;
        }
        SoundService.playEvent("charging", isPluggedIn ? "power-plug" : "power-unplug");
    }

    // Shorter idle timeouts on battery. hypridle's own still run, so whichever is
    // sooner wins, and an idle inhibitor (a video playing) holds both.
    readonly property bool batteryIdle: available && UPower.onBattery && Config.options.battery.idle.enable
    IdleMonitor {
        enabled: root.batteryIdle && timeout > 0
        timeout: Config.options.battery.idle.screenOff * 60
        onIsIdleChanged: Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.dpms("${isIdle ? "off" : "on"}")`])
    }
    IdleMonitor {
        enabled: root.batteryIdle && timeout > 0
        timeout: Config.options.battery.idle.sleep * 60
        onIsIdleChanged: if (isIdle) Quickshell.execDetached(["bash", "-c", "systemctl suspend || loginctl suspend"])
    }
}
