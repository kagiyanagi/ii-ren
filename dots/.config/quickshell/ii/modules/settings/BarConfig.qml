import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

import QtQml.Models

ContentPage {
    id: page
    forceWidth: true
    readonly property int index: 2 
    property bool register: parent.register ?? false

    property var componentMap: ({
        "clock": clockSection,
        "system_monitor": resourcesSection,
        "active_window": activeWindow,
        "music_player": musicPlayer,
        "utility_buttons": utilityButtons,
        "system_tray": systemTray,
        "workspaces": workspaces,
        "timer": indicators,
        "record_indicator": indicators,
        "privacy_indicator": indicators,
        "network_speed": networkSpeed
    })

    function scrollTo(stringId) {
        const item = componentMap[stringId]
        page.contentY = item.y
    }


    ContentSection {
        icon: "mobile_layout"
        title: Translation.tr("Bar layout")
        ContentSubsection {
            title: Translation.tr("Left layout")
            tooltip: Translation.tr("Top layout in vertical mode")
            ConfigListView {
                barSection: 0
                listModel: Config.options.bar.layouts.left
                onUpdated: (newList) => {
                    Config.options.bar.layouts.left = newList
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Center layout")
            tooltip: Translation.tr("Center the component with the button")
            ConfigListView {
                barSection: 1
                listModel: Config.options.bar.layouts.center
                onUpdated: (newList) => {
                    Config.options.bar.layouts.center = newList
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Right layout")
            tooltip: Translation.tr("Bottom layout in vertical mode")
            ConfigListView {
                barSection: 2
                listModel: Config.options.bar.layouts.right
                onUpdated: (newList) => {
                    Config.options.bar.layouts.right = newList
                }
            }
        }
    }

    ContentSection {
        icon: "open_in_full"
        title: Translation.tr("Bar sizes")

        ConfigSpinBox {
            icon: "height"
            text: Translation.tr("Bar height")
            value: Config.options.bar.sizes.height
            from: 30
            to: 50
            stepSize: 1
            onValueChanged: {
                Config.options.bar.sizes.height = value;
            }
        }
        ConfigSpinBox {
            icon: "width"
            text: Translation.tr("Bar width")
            value: Config.options.bar.sizes.width
            from: 30
            to: 50
            stepSize: 1
            onValueChanged: {
                Config.options.bar.sizes.width = value;
            }
        }
    }

    ContentSection {
        icon: "spoke"
        title: Translation.tr("Positioning & appearance")

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Bar position")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        const newVertical = (newValue & 2) !== 0;
                        if (newVertical && !Config.options.bar.vertical) {
                            if (Config.options.bar.networkSpeed.displayMode < 4) {
                                Config.options.bar.networkSpeed.displayMode = 4;
                            }
                        }
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = newVertical;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Top"),
                            icon: "arrow_upward",
                            value: 0 // bottom: false, vertical: false
                        },
                        {
                            displayName: Translation.tr("Left"),
                            icon: "arrow_back",
                            value: 2 // bottom: false, vertical: true
                        },
                        {
                            displayName: Translation.tr("Bottom"),
                            icon: "arrow_downward",
                            value: 1 // bottom: true, vertical: false
                        },
                        {
                            displayName: Translation.tr("Right"),
                            icon: "arrow_forward",
                            value: 3 // bottom: true, vertical: true
                        }
                    ]
                }
            }
            ContentSubsection {
                title: Translation.tr("Automatically hide")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.bar.autoHide.enable
                    onSelected: newValue => {
                        Config.options.bar.autoHide.enable = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: false
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: true
                        }
                    ]
                }
            }
        }

        ConfigRow {
            Layout.fillHeight: false
            ContentSubsection {
                title: Translation.tr("Corner style")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => {
                        Config.options.bar.cornerStyle = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Hug"),
                            icon: "line_curve",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Float"),
                            icon: "page_header",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "toolbar",
                            value: 2
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Group style")
                tooltip: Translation.tr("Island style makes the group background opaque when bar is transparent")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.bar.barGroupStyle
                    onSelected: newValue => {
                        Config.options.bar.barGroupStyle = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Pills"),
                            icon: "location_chip",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Island"),
                            icon: "shadow",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Transparent"),
                            icon: "opacity",
                            value: 2
                        }
                    ]
                }
            }
        }

        ConfigSpinBox {
            icon: "rounded_corner"
            text: Translation.tr("Corner radius")
            value: Config.options.bar.cornerRadius
            from: 0
            to: 64
            stepSize: 1
            onValueChanged: { Config.options.bar.cornerRadius = value; }
        }

        ContentSubsection {
            title: Translation.tr("Bar background style")
            tooltip: Translation.tr("Adaptive style makes the bar background transparent when there are no active windows")
            Layout.fillWidth: false

            ConfigSelectionArray {
                currentValue: Config.options.bar.barBackgroundStyle
                onSelected: newValue => {
                    Config.options.bar.barBackgroundStyle = newValue;
                }
                options: [ 
                    {
                        displayName: Translation.tr("Visible"),
                        icon: "visibility",
                        value: 1
                    }, 
                    {
                        displayName: Translation.tr("Adaptive"),
                        icon: "masked_transitions",
                        value: 2
                    },        
                    {
                        displayName: Translation.tr("Transparent"),
                        icon: "opacity",
                        value: 0
                    }
                ]
            }
        }
    }
    
    ContentSection {
        id: clockSection
        icon: "schedule"
        title: Translation.tr("Clock")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "calendar_today"
                text: Translation.tr("Show date")
                checked: Config.options.bar.clock.showDate ?? true
                onCheckedChanged: {
                    Config.options.bar.clock.showDate = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("Show seconds")
                checked: Config.options.bar.clock.showSeconds ?? false
                onCheckedChanged: {
                    Config.options.bar.clock.showSeconds = checked;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Time format")
            tooltip: Translation.tr("Custom format tokens: hh (24h), h (12h), mm (min), ss (sec), ap (am/pm), AP (AM/PM)")

            ConfigSelectionArray {
                currentValue: Config.options.bar.clock.timeFormat || Config.options.time.format || "hh:mm"
                onSelected: newValue => {
                    Config.options.bar.clock.timeFormat = newValue;
                }
                options: [
                    { displayName: Translation.tr("24h (hh:mm)"), value: "hh:mm" },
                    { displayName: Translation.tr("12h (h:mm ap)"), value: "h:mm ap" },
                    { displayName: Translation.tr("12h (h:mm AP)"), value: "h:mm AP" },
                    { displayName: Translation.tr("With seconds (hh:mm:ss)"), value: "hh:mm:ss" }
                ]
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialTextField {
                    id: barCustomTimeFormatInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Custom time format (e.g. hh:mm, h:mm ap)")
                    text: Config.options.bar.clock.timeFormat || Config.options.time.format || ""
                    onEditingFinished: {
                        Config.options.bar.clock.timeFormat = text.trim();
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: Translation.tr("Preview: ") + Qt.locale().toString(DateTime.clock.date, barCustomTimeFormatInput.text.trim() || Config.options.bar.clock.timeFormat || Config.options.time.format || "hh:mm")
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Date format")
            tooltip: Translation.tr("Custom format tokens: ddd (short day), dddd (full day), dd (day), MM (month), yyyy (year)")

            ConfigSelectionArray {
                currentValue: Config.options.bar.clock.dateFormat || Config.options.time.dateFormat || "ddd, dd/MM"
                onSelected: newValue => {
                    Config.options.bar.clock.dateFormat = newValue;
                }
                options: [
                    { displayName: Translation.tr("Date First (ddd, dd/MM)"), value: "ddd, dd/MM" },
                    { displayName: Translation.tr("Month First (ddd, MM/dd)"), value: "ddd, MM/dd" },
                    { displayName: Translation.tr("Full (dddd, MMMM dd)"), value: "dddd, MMMM dd" },
                    { displayName: Translation.tr("ISO (yyyy-MM-dd)"), value: "yyyy-MM-dd" }
                ]
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialTextField {
                    id: barCustomDateFormatInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Custom date format (e.g. ddd, dd/MM)")
                    text: Config.options.bar.clock.dateFormat || Config.options.time.dateFormat || ""
                    onEditingFinished: {
                        Config.options.bar.clock.dateFormat = text.trim();
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: Translation.tr("Preview: ") + Qt.locale().toString(DateTime.clock.date, barCustomDateFormatInput.text.trim() || Config.options.bar.clock.dateFormat || Config.options.time.dateFormat || "ddd, dd/MM")
                }
            }
        }
    }

    ContentSection {
        id: activeWindow
        icon: "ad"
        title: Translation.tr("Active window")
        ConfigSwitch {
            buttonIcon: "crop_free"
            text: Translation.tr("Use fixed size")
            checked: Config.options.bar.activeWindow.fixedSize
            onCheckedChanged: {
                Config.options.bar.activeWindow.fixedSize = checked;
            }
        }
    }

    ContentSection {
        id: musicPlayer
        icon: "music_cast"
        title: Translation.tr("Media player")

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "crop_free"
                text: Translation.tr("Use fixed size")
                checked: Config.options.bar.mediaPlayer.useFixedSize
                onCheckedChanged: {
                    Config.options.bar.mediaPlayer.useFixedSize = checked;
                }
            }   

            ConfigSpinBox {
                enabled: !Config.options.bar.vertical && Config.options.bar.mediaPlayer.useFixedSize
                icon: "width_full"
                text: Translation.tr("Custom size")
                value: Config.options.bar.mediaPlayer.customSize
                from: 100
                to: 500
                stepSize: 25
                onValueChanged: {
                    Config.options.bar.mediaPlayer.customSize = value;
                }
            }
        }

        ConfigSpinBox {
            enabled: !Config.options.bar.vertical
            icon: "width_full"
            text: Translation.tr("Lyrics width")
            value: Config.options.bar.mediaPlayer.lyrics.customSize
            from: 100
            to: 750
            stepSize: 25
            onValueChanged: {
                Config.options.bar.mediaPlayer.lyrics.customSize = value;
            }
        }

        ContentSubsection {
            title: Translation.tr("Artwork")

            ConfigSwitch {
                enabled: !Config.options.bar.vertical
                buttonIcon: "image"
                text: Translation.tr("Enable artwork")
                checked: Config.options.bar.mediaPlayer.artwork.enable
                onCheckedChanged: {
                    Config.options.bar.mediaPlayer.artwork.enable = checked;
                }
            }
        }
        
        ContentSubsection {
            title: Translation.tr("Lyrics")

            ConfigRow {
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    Layout.fillWidth: false
                    checked: Config.options.bar.mediaPlayer.lyrics.enable
                    onCheckedChanged: {
                        Config.options.bar.mediaPlayer.lyrics.enable = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Lyrics will be visible when they are fetched with API")
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                ConfigSelectionArray {
                    Layout.fillWidth: false
                    currentValue: Config.options.bar.mediaPlayer.lyrics.style
                    onSelected: newValue => {
                        Config.options.bar.mediaPlayer.lyrics.style = newValue
                    }
                    options: [
                        {
                            displayName: Translation.tr("Static"),
                            icon: "format_size",
                            value: "static"
                        },
                        {
                            displayName: Translation.tr("Scroller"),
                            icon: "keyboard_double_arrow_up",
                            value: "scroller"
                        }
                    ]
                }
            }

            ConfigSwitch {
                enabled: Config.options.bar.mediaPlayer.lyrics.enable && Config.options.bar.mediaPlayer.lyrics.style === "scroller"
                buttonIcon: "gradient"
                text: Translation.tr("Use gradient mask")
                checked: Config.options.bar.mediaPlayer.lyrics.useGradientMask
                onCheckedChanged: {
                    Config.options.bar.mediaPlayer.lyrics.useGradientMask = checked;
                }
            }
            
        }

    }
    

    ContentSection {
        icon: "notifications"
        title: Translation.tr("Notifications")
        ConfigSwitch {
            buttonIcon: "counter_2"
            text: Translation.tr("Unread indicator: show count")
            checked: Config.options.bar.indicators.notifications.showUnreadCount
            onCheckedChanged: {
                Config.options.bar.indicators.notifications.showUnreadCount = checked;
            }
        }
    }

    ContentSection {
        id: systemTray
        icon: "shelf_auto_hide"
        title: Translation.tr("Tray")

        ConfigSwitch {
            buttonIcon: "keep"
            text: Translation.tr('Make icons pinned by default')
            checked: Config.options.tray.invertPinnedItems
            onCheckedChanged: {
                Config.options.tray.invertPinnedItems = checked;
            }
        }
        
        ConfigSwitch {
            buttonIcon: "colors"
            text: Translation.tr('Tint icons')
            checked: Config.options.tray.monochromeIcons
            onCheckedChanged: {
                Config.options.tray.monochromeIcons = checked;
            }
        }
    }

    ContentSection {
        id: indicators
        icon: "ad"
        title: Translation.tr("Indicators")

        ContentSubsection {
            title: Translation.tr("Timer and pomodoro")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "timer"
                    text: Translation.tr("Show stopwatch")
                    checked: Config.options.bar.timers.showStopwatch
                    onCheckedChanged: {
                        Config.options.bar.timers.showStopwatch = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "search_activity"
                    text: Translation.tr("Show pomodoro")
                    checked: Config.options.bar.timers.showPomodoro
                    onCheckedChanged: {
                        Config.options.bar.timers.showPomodoro = checked;
                    }
                }
            }
        }
        
        ContentSubsection {
            title: Translation.tr("Record")

            ConfigSwitch {
                buttonIcon: "check_indeterminate_small"
                text: Translation.tr("Minimal mode")
                checked: Config.options.bar.indicators.record.minimal
                onCheckedChanged: {
                    Config.options.bar.indicators.record.minimal = checked;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Privacy")
            tooltip: Translation.tr("Shows what is using your microphone, camera, screen and location")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "mic"
                    text: Translation.tr("Microphone")
                    checked: Config.options.bar.indicators.privacy.microphone
                    onCheckedChanged: {
                        Config.options.bar.indicators.privacy.microphone = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "photo_camera"
                    text: Translation.tr("Camera")
                    checked: Config.options.bar.indicators.privacy.camera
                    onCheckedChanged: {
                        Config.options.bar.indicators.privacy.camera = checked;
                    }
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "screen_share"
                    text: Translation.tr("Screen sharing")
                    checked: Config.options.bar.indicators.privacy.screen
                    onCheckedChanged: {
                        Config.options.bar.indicators.privacy.screen = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "location_on"
                    text: Translation.tr("Location")
                    checked: Config.options.bar.indicators.privacy.location
                    onCheckedChanged: {
                        Config.options.bar.indicators.privacy.location = checked;
                    }
                }
            }
        }
    }

    ContentSection {
        id: networkSpeed
        icon: "speed"
        title: Translation.tr("Network speed")
        
        ContentSubsection {
            title: Translation.tr("Mode selector")
            ConfigSelectionArray {
                currentValue: Config.options.bar.networkSpeed.displayMode
                onSelected: newValue => {
                    Config.options.bar.networkSpeed.displayMode = newValue;
                }
                options: [
                    { displayName: Translation.tr("Total"), icon: "expand", value: 0, enabled: !Config.options.bar.vertical },
                    { displayName: Translation.tr("Download"), icon: "arrow_downward", value: 1, enabled: !Config.options.bar.vertical },
                    { displayName: Translation.tr("Upload"), icon: "arrow_upward", value: 2, enabled: !Config.options.bar.vertical },
                    { displayName: Translation.tr("Both"), icon: "unfold_more", value: 3, enabled: !Config.options.bar.vertical },
                    { displayName: Translation.tr("Icon"), icon: "wifi", value: 4 }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Icon settings")
            
            ConfigSwitch {
                buttonIcon: "vertical_align_center"
                text: Translation.tr("Show speed indicators (↑↓)")
                enabled: Config.options.bar.networkSpeed.displayMode !== 4
                opacity: enabled ? 1.0 : 0.5
                checked: Config.options.bar.networkSpeed.showIcons
                onCheckedChanged: {
                    Config.options.bar.networkSpeed.showIcons = checked;
                }
            }

            ContentSubsection {
                title: Translation.tr("Icon position")
                enabled: Config.options.bar.networkSpeed.showIcons
                opacity: enabled ? 1.0 : 0.5
                ConfigSelectionArray {
                    currentValue: Config.options.bar.networkSpeed.iconPosition
                    onSelected: newValue => {
                        Config.options.bar.networkSpeed.iconPosition = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Left"), icon: "align_horizontal_left", value: 0 },
                        { displayName: Translation.tr("Right"), icon: "align_horizontal_right", value: 1 }
                    ]
                }
            }
            }

            ContentSubsection {
                title: Translation.tr("Performance & Layout")
                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Update interval (ms)")
                    value: Config.options.bar.networkSpeed.updateInterval
                    from: 100
                    to: 5000
                    stepSize: 100
                    onValueChanged: {
                        Config.options.bar.networkSpeed.updateInterval = value; 
                    }
                }
                ConfigSwitch {
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Auto-hide when idle")
                    checked: Config.options.bar.networkSpeed.autoHide
                    onCheckedChanged: { 
                        Config.options.bar.networkSpeed.autoHide = checked; 
                    }
                }
            }
    }

    ContentSection {
        id: resourcesSection
        icon: "memory"
        title: Translation.tr("Resource monitor")

        ContentSubsection {
            title: Translation.tr("Visible statistics")
            tooltip: Translation.tr("Choose which resource monitors to display on the bar")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "planner_review"
                    text: Translation.tr("CPU usage")
                    checked: Config.options.bar.resources.showCpu ?? true
                    onCheckedChanged: {
                        Config.options.bar.resources.showCpu = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "memory"
                    text: Translation.tr("RAM usage")
                    checked: Config.options.bar.resources.showRam ?? true
                    onCheckedChanged: {
                        Config.options.bar.resources.showRam = checked;
                    }
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "thermostat"
                    text: Translation.tr("Temperature")
                    checked: Config.options.bar.resources.showTemp ?? true
                    onCheckedChanged: {
                        Config.options.bar.resources.showTemp = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "swap_vert"
                    text: Translation.tr("Network load")
                    checked: Config.options.bar.resources.showNetwork ?? false
                    onCheckedChanged: {
                        Config.options.bar.resources.showNetwork = checked;
                    }
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "swap_horiz"
                    text: Translation.tr("Swap usage")
                    checked: Config.options.bar.resources.showSwap ?? false
                    onCheckedChanged: {
                        Config.options.bar.resources.showSwap = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "videogame_asset"
                    text: Translation.tr("GPU usage")
                    checked: Config.options.bar.resources.showGpu ?? false
                    onCheckedChanged: {
                        Config.options.bar.resources.showGpu = checked;
                    }
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "hard_drive"
                    text: Translation.tr("Disk usage")
                    checked: Config.options.bar.resources.showDisk ?? false
                    onCheckedChanged: {
                        Config.options.bar.resources.showDisk = checked;
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Formatting & units")

            ConfigSwitch {
                buttonIcon: "percent"
                text: Translation.tr("Show unit symbols (% / °C)")
                checked: Config.options.bar.resources.showSymbols ?? false
                onCheckedChanged: {
                    Config.options.bar.resources.showSymbols = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Displays unit symbols after numbers (e.g. 20%, 51°C, 3.8G)")
                }
            }

            ContentSubsection {
                title: Translation.tr("RAM & Swap measurement unit")

                ConfigSelectionArray {
                    currentValue: Config.options.bar.resources.ramUnit ?? "percent"
                    onSelected: newValue => {
                        Config.options.bar.resources.ramUnit = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Percentage (%)"), icon: "percent", value: "percent" },
                        { displayName: Translation.tr("Gigabytes (GB)"), icon: "database", value: "gb" },
                        { displayName: Translation.tr("Megabytes (MB)"), icon: "memory", value: "mb" }
                    ]
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Network load settings")
            visible: Config.options.bar.resources.showNetwork ?? false

            ConfigSpinBox {
                icon: "speed"
                text: Translation.tr("Max bandwidth reference (Mbps)")
                value: Config.options.bar.resources.networkMaxSpeed ?? 100
                from: 10
                to: 10000
                stepSize: 50
                onValueChanged: {
                    Config.options.bar.resources.networkMaxSpeed = value;
                }
                StyledToolTip {
                    text: Translation.tr("Speed corresponding to 100% network load on the progress ring")
                }
            }

            ContentSubsection {
                title: Translation.tr("Display value")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.resources.networkUnit ?? "percent"
                    onSelected: newValue => {
                        Config.options.bar.resources.networkUnit = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Load percentage (%)"), icon: "percent", value: "percent" },
                        { displayName: Translation.tr("Speed value (e.g. 1.2M)"), icon: "speed", value: "speed" }
                    ]
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Warning thresholds")

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "planner_review"
                    text: Translation.tr("CPU threshold (%)")
                    value: Config.options.bar.resources.cpuWarningThreshold ?? 90
                    from: 50
                    to: 100
                    stepSize: 5
                    onValueChanged: {
                        Config.options.bar.resources.cpuWarningThreshold = value;
                    }
                }
                ConfigSpinBox {
                    icon: "memory"
                    text: Translation.tr("RAM threshold (%)")
                    value: Config.options.bar.resources.memoryWarningThreshold ?? 95
                    from: 50
                    to: 100
                    stepSize: 5
                    onValueChanged: {
                        Config.options.bar.resources.memoryWarningThreshold = value;
                    }
                }
            }

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "thermostat"
                    text: Translation.tr("Temperature threshold (°C)")
                    value: Config.options.bar.resources.tempWarningThreshold ?? 85
                    from: 40
                    to: 110
                    stepSize: 5
                    onValueChanged: {
                        Config.options.bar.resources.tempWarningThreshold = value;
                    }
                }
                ConfigSpinBox {
                    icon: "swap_horiz"
                    text: Translation.tr("Swap threshold (%)")
                    value: Config.options.bar.resources.swapWarningThreshold ?? 85
                    from: 50
                    to: 100
                    stepSize: 5
                    onValueChanged: {
                        Config.options.bar.resources.swapWarningThreshold = value;
                    }
                }
            }
        }
    }

    ContentSection {
        id: utilityButtons
        icon: "widgets"
        title: Translation.tr("Utility buttons")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "content_cut"
                text: Translation.tr("Screen snip")
                checked: Config.options.bar.utilButtons.showScreenSnip
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showScreenSnip = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "colorize"
                text: Translation.tr("Color picker")
                checked: Config.options.bar.utilButtons.showColorPicker
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showColorPicker = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Keyboard toggle")
                checked: Config.options.bar.utilButtons.showKeyboardToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showKeyboardToggle = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "keyboard_full"
                text: Translation.tr("Keyboard backlight")
                checked: Config.options.bar.utilButtons.showKeyboardBacklight
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showKeyboardBacklight = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "mic"
                text: Translation.tr("Mic toggle")
                checked: Config.options.bar.utilButtons.showMicToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showMicToggle = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "dark_mode"
                text: Translation.tr("Dark/Light toggle")
                checked: Config.options.bar.utilButtons.showDarkModeToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showDarkModeToggle = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "speed"
                text: Translation.tr("Performance Profile toggle")
                checked: Config.options.bar.utilButtons.showPerformanceProfileToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showPerformanceProfileToggle = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "videocam"
                text: Translation.tr("Record")
                checked: Config.options.bar.utilButtons.showScreenRecord
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showScreenRecord = checked;
                }
            }
        }
    }

    ContentSection {
        id: workspaces
        icon: "workspaces"
        title: Translation.tr("Workspaces")

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "grid_3x3"
                text: Translation.tr('Use workspace map')
                checked: Config.options.bar.workspaces.useWorkspaceMap
                onCheckedChanged: {
                    Config.options.bar.workspaces.useWorkspaceMap = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Only for multi-monitor setups, you must edit the workspace map manually in config.json\n Refer to the repo wiki for more information")
                }
            }

            ConfigSwitch {
                buttonIcon: "counter_1"
                text: Translation.tr('Always show numbers')
                checked: Config.options.bar.workspaces.alwaysShowNumbers
                onCheckedChanged: {
                    Config.options.bar.workspaces.alwaysShowNumbers = checked;
                }
            }
        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "award_star"
                text: Translation.tr('Show app icons')
                checked: Config.options.bar.workspaces.showAppIcons
                onCheckedChanged: {
                    Config.options.bar.workspaces.showAppIcons = checked;
                }
            }

            ConfigSwitch {
                enabled: Config.options.bar.workspaces.showAppIcons
                buttonIcon: "colors"
                text: Translation.tr('Tint app icons')
                checked: Config.options.bar.workspaces.monochromeIcons
                onCheckedChanged: {
                    Config.options.bar.workspaces.monochromeIcons = checked;
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "hdr_weak"
            text: Translation.tr("Dynamic workspaces")
            checked: Config.options.bar.workspaces.dynamicWorkspaces
            onCheckedChanged: {
                Config.options.bar.workspaces.dynamicWorkspaces = checked;
            }
            StyledToolTip {
                text: Translation.tr("Hides the empty workspaces and only shows the ones with windows")
            }
        }

        ConfigSpinBox {
            enabled: !Config.options.bar.workspaces.dynamicWorkspaces
            icon: "view_column"
            text: Translation.tr("Workspaces shown")
            value: Config.options.bar.workspaces.shown
            from: 1
            to: 30
            stepSize: 1
            onValueChanged: {
                Config.options.bar.workspaces.shown = value;
            }
        }

        ConfigSpinBox {
            icon: "select_window"
            text: Translation.tr("Maximum window count per workspace")
            value: Config.options.bar.workspaces.maxWindowCount
            from: 1
            to: 20
            stepSize: 1
            onValueChanged: {
                Config.options.bar.workspaces.maxWindowCount = value;
            }
        }

        ConfigSpinBox {
            icon: "touch_long"
            text: Translation.tr("Number show delay when pressing Super (ms)")
            value: Config.options.bar.workspaces.showNumberDelay
            from: 0
            to: 1000
            stepSize: 50
            onValueChanged: {
                Config.options.bar.workspaces.showNumberDelay = value;
            }
        }

        ContentSubsection {
            title: Translation.tr("Number style")

            ConfigSelectionArray {
                currentValue: JSON.stringify(Config.options.bar.workspaces.numberMap)
                onSelected: newValue => {
                    Config.options.bar.workspaces.numberMap = JSON.parse(newValue)
                }
                options: [
                    {
                        displayName: Translation.tr("Normal"),
                        icon: "timer_10",
                        value: '[]'
                    },
                    {
                        displayName: Translation.tr("Han chars"),
                        icon: "square_dot",
                        value: '["一","二","三","四","五","六","七","八","九","十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十"]'
                    },
                    {
                        displayName: Translation.tr("Roman"),
                        icon: "account_balance",
                        value: '["I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII","XIII","XIV","XV","XVI","XVII","XVIII","XIX","XX"]'
                    }
                ]
            }
        }
    }

    ContentSection {
        icon: "tooltip"
        title: Translation.tr("Tooltips")
        ConfigRow {
            ConfigSwitch {
                buttonIcon: "ads_click"
                text: Translation.tr("Click to show")
                Layout.fillWidth: true
                checked: Config.options.bar.tooltips.clickToShow
                onCheckedChanged: {
                    Config.options.bar.tooltips.clickToShow = checked;
                }
                StyledToolTip {
                    text: Translation.tr("You will not be able to use the buttons on some popups if you enable this option.")
                }
            }
            ConfigSwitch {
                buttonIcon: "compress"
                text: Translation.tr("Compact popups")
                Layout.fillWidth: true
                checked: Config.options.bar.tooltips.compactPopups
                onCheckedChanged: {
                    Config.options.bar.tooltips.compactPopups = checked;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Resources")
            ConfigSwitch {
                buttonIcon: "swap_horiz"
                text: Translation.tr("Show Swap")
                Layout.fillWidth: true
                checked: Config.options.bar.tooltips.showSwap
                onCheckedChanged: {
                    Config.options.bar.tooltips.showSwap = checked;
                }
            }
        }
    }

    
}
