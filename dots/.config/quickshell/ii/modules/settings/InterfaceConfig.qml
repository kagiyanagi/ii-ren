import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "configs/widgets"

ContentPage {
    id: page

    readonly property int index: 4
    property bool register: parent.register ?? false

    forceWidth: true

    ContentSection {
        icon: "keyboard"
        title: Translation.tr("Cheat sheet")

        ContentSubsection {
            title: Translation.tr("Super key symbol")
            tooltip: Translation.tr("You can also manually edit cheatsheet.superKey")

            ConfigSelectionArray {
                currentValue: Config.options.cheatsheet.superKey
                onSelected: (newValue) => {
                    Config.options.cheatsheet.superKey = newValue;
                }
                // Use a nerdfont to see the icons
                options: (["󰖳", "", "󰨡", "", "󰌽", "󰣇", "", "", "", "", "", "󱄛", "", "", "", "⌘", "󰀲", "󰟍", ""]).map((icon) => {
                    return {
                        "displayName": icon,
                        "value": icon
                    };
                })
            }

        }

        ConfigSwitch {
            buttonIcon: "󰘵"
            text: Translation.tr("Use macOS-like symbols for mods keys")
            checked: Config.options.cheatsheet.useMacSymbol
            onCheckedChanged: {
                Config.options.cheatsheet.useMacSymbol = checked;
            }

            StyledToolTip {
                text: Translation.tr("e.g. 󰘴  for Ctrl, 󰘵  for Alt, 󰘶  for Shift, etc")
            }

        }

        ConfigSwitch {
            buttonIcon: "󱊶"
            text: Translation.tr("Use symbols for function keys")
            checked: Config.options.cheatsheet.useFnSymbol
            onCheckedChanged: {
                Config.options.cheatsheet.useFnSymbol = checked;
            }

            StyledToolTip {
                text: Translation.tr("e.g. 󱊫 for F1, 󱊶  for F12")
            }

        }

        ConfigSwitch {
            buttonIcon: "󰍽"
            text: Translation.tr("Use symbols for mouse")
            checked: Config.options.cheatsheet.useMouseSymbol
            onCheckedChanged: {
                Config.options.cheatsheet.useMouseSymbol = checked;
            }

            StyledToolTip {
                text: Translation.tr("Replace 󱕐   for \"Scroll ↓\", 󱕑   \"Scroll ↑\", L󰍽   \"LMB\", R󰍽   \"RMB\", 󱕒   \"Scroll ↑/↓\" and ⇞/⇟ for \"Page_↑/↓\"")
            }

        }

        ConfigSwitch {
            buttonIcon: "highlight_keyboard_focus"
            text: Translation.tr("Split buttons")
            checked: Config.options.cheatsheet.splitButtons
            onCheckedChanged: {
                Config.options.cheatsheet.splitButtons = checked;
            }

            StyledToolTip {
                text: Translation.tr("Display modifiers and keys in multiple keycap (e.g., \"Ctrl + A\" instead of \"Ctrl A\" or \"󰘴 + A\" instead of \"󰘴 A\")")
            }

        }

        ConfigSpinBox {
            text: Translation.tr("Keybind font size")
            value: Config.options.cheatsheet.fontSize.key
            from: 8
            to: 30
            stepSize: 1
            onValueChanged: {
                Config.options.cheatsheet.fontSize.key = value;
            }
        }

        ConfigSpinBox {
            text: Translation.tr("Description font size")
            value: Config.options.cheatsheet.fontSize.comment
            from: 8
            to: 30
            stepSize: 1
            onValueChanged: {
                Config.options.cheatsheet.fontSize.comment = value;
            }
        }

    }

    ContentSection {
        icon: "swap_horiz"
        title: Translation.tr("Alt+Tab switcher")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: Config.options.altTab.enable
            onCheckedChanged: {
                Config.options.altTab.enable = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "mouse"
            text: Translation.tr("Keep the cursor in place when switching")
            checked: Config.options.altTab.keepCursorInPlace
            onCheckedChanged: {
                Config.options.altTab.keepCursorInPlace = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "select_window"
            text: Translation.tr("Only show windows on the current workspace")
            checked: Config.options.altTab.currentWorkspaceOnly
            onCheckedChanged: {
                Config.options.altTab.currentWorkspaceOnly = checked;
            }
        }

    }

    ContentSection {
        icon: "call_to_action"
        title: Translation.tr("Dock")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: Config.options.dock.enable
            onCheckedChanged: {
                Config.options.dock.enable = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "desktop_windows"
            text: Translation.tr("Isolate monitors")
            checked: Config.options.dock.isolateMonitors ?? false
            onCheckedChanged: {
                Config.options.dock.isolateMonitors = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "ad"
            text: Translation.tr("Enable windows preview")
            checked: Config.options.dock.enablePreview
            onCheckedChanged: {
                Config.options.dock.enablePreview = checked;
            }
        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "computer_arrow_up"
                text: Translation.tr("Reveal on empty workspace")
                checked: Config.options.dock.revealOnEmptyWorkspace
                onCheckedChanged: {
                    Config.options.dock.revealOnEmptyWorkspace = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "keep"
                text: Translation.tr("Pinned on startup")
                checked: Config.options.dock.pinnedOnStartup
                onCheckedChanged: {
                    Config.options.dock.pinnedOnStartup = checked;
                }
            }

        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "colors"
                text: Translation.tr("Tint app icons")
                checked: Config.options.dock.monochromeIcons
                onCheckedChanged: {
                    Config.options.dock.monochromeIcons = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "contrast"
                text: Translation.tr("Dim inactive app icons")
                enabled: !Config.options.dock.monochromeIcons
                checked: Config.options.dock.dimInactiveIcons
                onCheckedChanged: {
                    Config.options.dock.dimInactiveIcons = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Greyscale icons for pinned apps that are not running.\nDisabled when 'Tint app icons' is active.")
                }

            }

        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "play_pause"
                text: Translation.tr("Enable media widget")
                checked: Config.options.dock.enableMediaWidget
                onCheckedChanged: {
                    Config.options.dock.enableMediaWidget = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "pan_tool_alt"
                text: Translation.tr("Media controls on hover")
                enabled: Config.options.dock.enableMediaWidget
                checked: Config.options.dock.mediaPopupOnHover
                onCheckedChanged: {
                    Config.options.dock.mediaPopupOnHover = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Show the media controls when hovering the widget.\nOff: click the widget to toggle them.")
                }

            }

        }

        ConfigSwitch {
            buttonIcon: "hide_source"
            text: Translation.tr("Hide media widget on empty workspace")
            enabled: Config.options.dock.enableMediaWidget
            checked: Config.options.dock.hideMediaOnEmptyWorkspace
            onCheckedChanged: {
                Config.options.dock.hideMediaOnEmptyWorkspace = checked;
            }

            StyledToolTip {
                text: Translation.tr("The desktop's own media widget is visible there anyway.")
            }

        }

        ConfigSpinBox {
            icon: "height"
            text: Translation.tr("Dock height")
            value: Config.options.dock.height
            from: 40
            to: 80
            stepSize: 1
            onValueChanged: {
                Config.options.dock.height = value;
            }
        }

        ConfigSpinBox {
            icon: "rounded_corner"
            text: Translation.tr("Corner radius")
            value: Config.options.dock.cornerRadius
            from: -1
            to: 40
            stepSize: 1
            onValueChanged: {
                Config.options.dock.cornerRadius = value;
            }
            StyledToolTip {
                text: Translation.tr("Set to -1 to use default large rounding")
            }
        }

        ConfigRow {
            uniform: true

            ConfigSpinBox {
                icon: "space_bar"
                text: Translation.tr("Item spacing")
                value: Config.options.dock.itemSpacing
                from: 0
                to: 32
                stepSize: 1
                onValueChanged: {
                    Config.options.dock.itemSpacing = value;
                }
            }

            ConfigSpinBox {
                icon: "format_line_spacing"
                text: Translation.tr("Section spacing")
                value: Config.options.dock.sectionSpacing
                from: 0
                to: 64
                stepSize: 1
                onValueChanged: {
                    Config.options.dock.sectionSpacing = value;
                }
            }

        }

        ConfigRow {
            uniform: true

            ConfigSpinBox {
                icon: "padding"
                text: Translation.tr("Horizontal padding")
                value: Config.options.dock.paddingHorizontal
                from: 0
                to: 64
                stepSize: 1
                onValueChanged: {
                    Config.options.dock.paddingHorizontal = value;
                }
            }

            ConfigSpinBox {
                icon: "padding"
                text: Translation.tr("Vertical padding")
                value: Config.options.dock.paddingVertical
                from: 0
                to: 64
                stepSize: 1
                onValueChanged: {
                    Config.options.dock.paddingVertical = value;
                }
            }

        }

        ContentSubsection {
            title: Translation.tr("Separator style")

            ConfigSelectionArray {
                currentValue: Config.options.dock.separatorStyle
                onSelected: (newValue) => {
                    Config.options.dock.separatorStyle = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Line"),
                    "icon": "remove",
                    "value": "Line"
                }, {
                    "displayName": Translation.tr("Dot"),
                    "icon": "fiber_manual_record",
                    "value": "Dot"
                }, {
                    "displayName": Translation.tr("Empty"),
                    "icon": "check_box_outline_blank",
                    "value": "Empty"
                }]
            }

        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "keep"
                text: Translation.tr("Show pin button")
                checked: Config.options.dock.showPinButton
                onCheckedChanged: {
                    Config.options.dock.showPinButton = checked;
                }

                StyledToolTip {
                    text: Translation.tr("The button that keeps the dock open.\nWithout it, 'Pinned on startup' decides whether the dock stays out.")
                }

            }

            ConfigSwitch {
                buttonIcon: "apps"
                text: Translation.tr("Show app menu button")
                checked: Config.options.dock.showAppsButton
                onCheckedChanged: {
                    Config.options.dock.showAppsButton = checked;
                }
            }

        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "vertical_align_bottom"
                text: Translation.tr("Attach to screen edge")
                checked: Config.options.dock.attachToEdge
                onCheckedChanged: {
                    Config.options.dock.attachToEdge = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Drop the gap under the dock and square off the two corners touching the edge.")
                }

            }

            ConfigSwitch {
                buttonIcon: "format_color_fill"
                text: Translation.tr("Apps button background")
                checked: Config.options.dock.showAppsButtonBackground
                onCheckedChanged: {
                    Config.options.dock.showAppsButtonBackground = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Show a filled background on the apps button.")
                }

            }

        }

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Dock position")

                ConfigSelectionArray {
                    currentValue: Config.options.dock.position
                    onSelected: (newValue) => {
                        Config.options.dock.position = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Auto"),
                        "icon": "expand",
                        "value": "auto"
                    }, {
                        "displayName": Translation.tr("Bottom"),
                        "icon": "vertical_align_bottom",
                        "value": "bottom"
                    }, {
                        "displayName": Translation.tr("Top"),
                        "icon": "vertical_align_top",
                        "value": "top"
                    }, {
                        "displayName": Translation.tr("Left"),
                        "icon": "keyboard_tab_rtl",
                        "value": "left"
                    }, {
                        "displayName": Translation.tr("Right"),
                        "icon": "keyboard_tab",
                        "value": "right"
                    }]
                }

            }

        }

        ContentSubsection {
            title: Translation.tr("App menu button shape")

            ConfigSelectionArray {
                currentValue: Config.options.dock.appsButtonShape
                onSelected: (newValue) => {
                    Config.options.dock.appsButtonShape = newValue;
                }
                options: (["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"]).map((shape) => {
                    return {
                        "displayName": "",
                        "shape": shape,
                        "value": shape
                    };
                })
            }

        }

        ContentSubsection {
            title: Translation.tr("Pin button shape")

            ConfigSelectionArray {
                currentValue: Config.options.dock.pinButtonShape
                onSelected: (newValue) => {
                    Config.options.dock.pinButtonShape = newValue;
                }
                options: (["Pill", "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"]).map((shape) => {
                    return {
                        "displayName": "",
                        "shape": shape,
                        "value": shape
                    };
                })
            }
        }

    }

    ContentSection {
        icon: "more"
        title: Translation.tr("Extra")

        ConfigSwitch {
            buttonIcon: "buttons_alt"
            text: Translation.tr("Show AI provider and model buttons")
            checked: Config.options.sidebar.ai.showProviderAndModelButtons
            onCheckedChanged: {
                Config.options.sidebar.ai.showProviderAndModelButtons = checked;
            }
        }

    }

    ContentSection {
        icon: "lock"
        title: Translation.tr("Lock screen")

        ConfigSwitch {
            buttonIcon: "water_drop"
            text: Translation.tr('Use Hyprlock (instead of Quickshell)')
            checked: Config.options.lock.useHyprlock
            onCheckedChanged: {
                Config.options.lock.useHyprlock = checked;
            }

            StyledToolTip {
                text: Translation.tr("If you want to somehow use fingerprint unlock...")
            }

        }

        ConfigSwitch {
            buttonIcon: "account_circle"
            text: Translation.tr('Launch on startup')
            checked: Config.options.lock.launchOnStartup
            onCheckedChanged: {
                Config.options.lock.launchOnStartup = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Security")

            ConfigSwitch {
                buttonIcon: "settings_power"
                text: Translation.tr('Require password to power off/restart')
                checked: Config.options.lock.security.requirePasswordToPower
                onCheckedChanged: {
                    Config.options.lock.security.requirePasswordToPower = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Remember that on most devices one can always hold the power button to force shutdown\nThis only makes it a tiny bit harder for accidents to happen")
                }

            }

            ConfigSwitch {
                buttonIcon: "key_vertical"
                text: Translation.tr('Also unlock keyring')
                checked: Config.options.lock.security.unlockKeyring
                onCheckedChanged: {
                    Config.options.lock.security.unlockKeyring = checked;
                }

                StyledToolTip {
                    text: Translation.tr("This is usually safe and needed for your browser and AI sidebar anyway\nMostly useful for those who use lock on startup instead of a display manager that does it (GDM, SDDM, etc.)")
                }

            }

        }

        ContentSubsection {
            title: Translation.tr("Style: general")

            ConfigSwitch {
                buttonIcon: "center_focus_weak"
                text: Translation.tr('Center clock')
                checked: Config.options.lock.centerClock
                onCheckedChanged: {
                    Config.options.lock.centerClock = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "info"
                text: Translation.tr('Show "Locked" text')
                checked: Config.options.lock.showLockedText
                onCheckedChanged: {
                    Config.options.lock.showLockedText = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "shapes"
                text: Translation.tr('Use varying shapes for password characters')
                checked: Config.options.lock.materialShapeChars
                onCheckedChanged: {
                    Config.options.lock.materialShapeChars = checked;
                }
            }

        }

        ContentSubsection {
            title: Translation.tr("Style: Blurred")

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr('Enable blur')
                checked: Config.options.lock.blur.enable
                onCheckedChanged: {
                    Config.options.lock.blur.enable = checked;
                }
            }

            ConfigSpinBox {
                icon: "loupe"
                text: Translation.tr("Extra wallpaper zoom (%)")
                value: Config.options.lock.blur.extraZoom * 100
                from: 1
                to: 150
                stepSize: 2
                onValueChanged: {
                    Config.options.lock.blur.extraZoom = value / 100;
                }
            }

        }

    }

    ContentSection {
        icon: "content_paste"
        title: Translation.tr("Clipboard")

        ConfigSwitch {
            buttonIcon: "content_copy"
            text: Translation.tr("Show a card when text is copied")
            checked: Config.options.clipboard.copyToast.enable
            onCheckedChanged: {
                Config.options.clipboard.copyToast.enable = checked;
            }

            StyledToolTip {
                text: Translation.tr("Android's clipboard overlay: a preview of what was copied slides into the bottom-left corner, with a link and send-to-phone action when they apply. Click it to open the clipboard history.")
            }

        }

        ContentSubsection {
            visible: Config.options.clipboard.copyToast.enable
            title: Translation.tr("Copy card")

            ConfigSelectionArray {
                currentValue: Config.options.clipboard.copyToast.corner
                onSelected: (newValue) => {
                    Config.options.clipboard.copyToast.corner = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Top left"),
                    "icon": "north_west",
                    "value": "top_left"
                }, {
                    "displayName": Translation.tr("Top right"),
                    "icon": "north_east",
                    "value": "top_right"
                }, {
                    "displayName": Translation.tr("Bottom left"),
                    "icon": "south_west",
                    "value": "bottom_left"
                }, {
                    "displayName": Translation.tr("Bottom right"),
                    "icon": "south_east",
                    "value": "bottom_right"
                }]
            }

            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Dismiss after (seconds)")
                value: Config.options.clipboard.copyToast.dismissAfter
                from: 0
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.clipboard.copyToast.dismissAfter = value;
                }

                StyledToolTip {
                    text: Translation.tr("0 keeps the card up until it is clicked")
                }

            }

        }

    }

    ContentSection {
        icon: "notifications"
        title: Translation.tr("Notifications")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Timeout duration (if not defined by notification) (ms)")
            value: Config.options.notifications.timeout
            from: 1000
            to: 60000
            stepSize: 1000
            onValueChanged: {
                Config.options.notifications.timeout = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "notifications_paused"
            text: Translation.tr("Notification cooldown")
            checked: Config.options.notifications.cooldown
            onCheckedChanged: {
                Config.options.notifications.cooldown = checked;
            }

            StyledToolTip {
                text: Translation.tr("Automatically suppress popups for rapid, consecutive alerts from the same app")
            }
        }

        ConfigSwitch {
            buttonIcon: "monitor"
            text: Translation.tr("Force specific monitor")
            checked: Config.options.notifications.monitor.enable
            onCheckedChanged: {
                Config.options.notifications.monitor.enable = checked;
            }

            StyledToolTip {
                text: Translation.tr("If you have multiple monitors and want notifications to only show on one of them, enable this and enter the monitor name below (e.g., eDP-1)")
            }

        }

        ConfigRow {
            enabled: Config.options.notifications.monitor.enable

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Monitor name to show notifications on (e.g., eDP-1)")
                text: Config.options.notifications.monitor.name
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.notifications.monitor.name = text;
                }
            }

        }

    }

    ContentSection {
        icon: "select_window"
        title: Translation.tr("Overlay: General")

        ConfigSwitch {
            buttonIcon: "high_density"
            text: Translation.tr("Enable opening zoom animation")
            checked: Config.options.overlay.openingZoomAnimation
            onCheckedChanged: {
                Config.options.overlay.openingZoomAnimation = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "texture"
            text: Translation.tr("Darken screen")
            checked: Config.options.overlay.darkenScreen
            onCheckedChanged: {
                Config.options.overlay.darkenScreen = checked;
            }
        }

    }

    ContentSection {
        icon: "point_scan"
        title: Translation.tr("Overlay: Crosshair")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Crosshair code (in Valorant's format)")
            text: Config.options.crosshair.code
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.crosshair.code = text;
            }
        }

        RowLayout {
            StyledText {
                Layout.leftMargin: 10
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallie
                text: Translation.tr("Press Super+G to open the overlay and pin the crosshair")
            }

            Item {
                Layout.fillWidth: true
            }

            RippleButtonWithIcon {
                id: editorButton

                buttonRadius: Appearance.rounding.full
                materialIcon: "open_in_new"
                mainText: Translation.tr("Open editor")
                onClicked: {
                    Qt.openUrlExternally(`https://www.vcrdb.net/builder?c=${Config.options.crosshair.code}`);
                }

                StyledToolTip {
                    text: "www.vcrdb.net"
                }

            }

        }

    }

    ContentSection {
        icon: "point_scan"
        title: Translation.tr("Overlay: Floating Image")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Image source")
            text: Config.options.overlay.floatingImage.imageSource
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.overlay.floatingImage.imageSource = text;
            }
        }

    }

    ContentSection {
        icon: "sticky_note_2"
        title: Translation.tr("Overlay: Notes")

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "tab"
                text: Translation.tr("Show tabs")
                checked: Config.options.overlay.notes.showTabs
                onCheckedChanged: {
                    Config.options.overlay.notes.showTabs = checked;
                }
            }

            ConfigSwitch {
                enabled: Config.options.overlay.notes.showTabs
                buttonIcon: "edit_note"
                text: Translation.tr("Allow editing the icon")
                checked: Config.options.overlay.notes.allowEditingIcon
                onCheckedChanged: {
                    Config.options.overlay.notes.allowEditingIcon = checked;
                }
            }

        }

    }

    ContentSection {
        icon: "music_note"
        title: Translation.tr("Overlay: Media")

        ConfigSwitch {
            buttonIcon: "sliders"
            text: Translation.tr("Show slider")
            checked: Config.options.overlay.media.showSlider
            onCheckedChanged: {
                Config.options.overlay.media.showSlider = checked;
            }
        }

        ConfigSpinBox {
            icon: "opacity"
            text: Translation.tr("Background opacity (%)")
            value: Config.options.overlay.media.backgroundOpacityPercentage
            from: 0
            to: 100
            stepSize: 10
            onValueChanged: {
                Config.options.overlay.media.backgroundOpacityPercentage = value;
            }
        }

        ContentSubsection {
            title: Translation.tr("Lyrics")

            ConfigSwitch {
                buttonIcon: "gradient"
                text: Translation.tr("Use gradient masking")
                checked: Config.options.overlay.media.useGradientMask
                onCheckedChanged: {
                    Config.options.overlay.media.useGradientMask = checked;
                }
            }

            ConfigSpinBox {
                icon: "format_size"
                text: Translation.tr("Lyrics font size (px)")
                value: Config.options.overlay.media.lyricSize
                from: 10
                to: 30
                stepSize: 1
                onValueChanged: {
                    Config.options.overlay.media.lyricSize = value;
                }
            }

        }

    }

    ContentSection {
        icon: "screenshot_frame_2"
        title: Translation.tr("Region selector (screen snipping/Google Lens)")

        ConfigSwitch {
            buttonIcon: "monitor"
            text: Translation.tr('Show only on focused monitor')
            checked: Config.options.regionSelector.showOnlyOnFocusedMonitor
            onCheckedChanged: {
                Config.options.regionSelector.showOnlyOnFocusedMonitor = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Hint target regions")

            ConfigRow {
                ConfigSwitch {
                    buttonIcon: "select_window"
                    text: Translation.tr('Windows')
                    checked: Config.options.regionSelector.targetRegions.windows
                    onCheckedChanged: {
                        Config.options.regionSelector.targetRegions.windows = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "right_panel_open"
                    text: Translation.tr('Layers')
                    checked: Config.options.regionSelector.targetRegions.layers
                    onCheckedChanged: {
                        Config.options.regionSelector.targetRegions.layers = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "nearby"
                    text: Translation.tr('Content')
                    checked: Config.options.regionSelector.targetRegions.content
                    onCheckedChanged: {
                        Config.options.regionSelector.targetRegions.content = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Could be images or parts of the screen that have some containment.\nMight not always be accurate.\nThis is done with an image processing algorithm run locally and no AI is used.")
                    }

                }

            }

        }

        ContentSubsection {
            title: Translation.tr("Google Lens")

            ConfigSelectionArray {
                currentValue: Config.options.search.imageSearch.useCircleSelection ? "circle" : "rectangles"
                onSelected: (newValue) => {
                    Config.options.search.imageSearch.useCircleSelection = (newValue === "circle");
                }
                options: [{
                    "icon": "activity_zone",
                    "value": "rectangles",
                    "displayName": Translation.tr("Rectangular selection")
                }, {
                    "icon": "gesture",
                    "value": "circle",
                    "displayName": Translation.tr("Circle to Search")
                }]
            }

        }

        ContentSubsection {
            title: Translation.tr("Rectangular selection")

            ConfigSwitch {
                buttonIcon: "point_scan"
                text: Translation.tr("Show aim lines")
                checked: Config.options.regionSelector.rect.showAimLines
                onCheckedChanged: {
                    Config.options.regionSelector.rect.showAimLines = checked;
                }
            }

        }

        ContentSubsection {
            title: Translation.tr("Circle selection")

            ConfigSpinBox {
                icon: "eraser_size_3"
                text: Translation.tr("Stroke width")
                value: Config.options.regionSelector.circle.strokeWidth
                from: 1
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.regionSelector.circle.strokeWidth = value;
                }
            }

            ConfigSpinBox {
                icon: "screenshot_frame_2"
                text: Translation.tr("Padding")
                value: Config.options.regionSelector.circle.padding
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.regionSelector.circle.padding = value;
                }
            }

        }

    }

    ContentSection {
        icon: "side_navigation"
        title: Translation.tr("Sidebars")

        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Uptime pill icon (empty = your user avatar)")
            text: Config.options.sidebar.uptimeIcon
            onTextChanged: {
                Config.options.sidebar.uptimeIcon = text;
            }

            StyledToolTip {
                text: Translation.tr("Path to an image shown next to the uptime in the right sidebar.\nLeave empty to use your user avatar, which falls back to the distro logo.")
            }

        }

        ConfigSwitch {
            buttonIcon: "memory"
            text: Translation.tr('Keep right sidebar loaded')
            checked: Config.options.sidebar.keepRightSidebarLoaded
            onCheckedChanged: {
                Config.options.sidebar.keepRightSidebarLoaded = checked;
            }

            StyledToolTip {
                text: Translation.tr("When enabled keeps the content of the right sidebar loaded to reduce the delay when opening,\nat the cost of around 15MB of consistent RAM usage. Delay significance depends on your system's performance.\nUsing a custom kernel like linux-cachyos might help")
            }

        }

        ConfigSwitch {
            buttonIcon: "memory"
            text: Translation.tr('Keep left sidebar loaded')
            checked: Config.options.sidebar.keepLeftSidebarLoaded
            onCheckedChanged: {
                Config.options.sidebar.keepLeftSidebarLoaded = checked;
            }

            StyledToolTip {
                text: Translation.tr("Same trade for the left sidebar. Off: its pages are built on the first open and thrown away when it closes.\nConversations and chat state live in the services, so nothing is lost either way")
            }

        }

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Sidebar position")

                ConfigSelectionArray {
                    currentValue: Config.options.sidebar.position
                    onSelected: (newValue) => {
                        Config.options.sidebar.position = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Default"),
                        "icon": "side_navigation",
                        "value": "default"
                    }, {
                        "displayName": Translation.tr("Inverted"),
                        "icon": "swap_horiz",
                        "value": "inverted"
                    }, {
                        "displayName": Translation.tr("Left"),
                        "icon": "align_horizontal_left",
                        "value": "left"
                    }, {
                        "displayName": Translation.tr("Right"),
                        "icon": "align_horizontal_right",
                        "value": "right"
                    }]
                }

            }

        }

        ContentSubsection {
            title: Translation.tr("Quick toggles")

            ConfigSelectionArray {
                Layout.fillWidth: false
                currentValue: Config.options.sidebar.quickToggles.style
                onSelected: (newValue) => {
                    Config.options.sidebar.quickToggles.style = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Classic"),
                    "icon": "password_2",
                    "value": "classic"
                }, {
                    "displayName": Translation.tr("Android"),
                    "icon": "action_key",
                    "value": "android"
                }]
            }

            ConfigSpinBox {
                enabled: Config.options.sidebar.quickToggles.style === "android"
                icon: "splitscreen_left"
                text: Translation.tr("Columns")
                value: Config.options.sidebar.quickToggles.android.columns
                from: 1
                to: 8
                stepSize: 1
                onValueChanged: {
                    Config.options.sidebar.quickToggles.android.columns = value;
                }
            }

            ConfigSwitch {
                enabled: Config.options.sidebar.quickToggles.style === "android"
                buttonIcon: "tune"
                text: Translation.tr("Three-way sliders")
                checked: Config.options.sidebar.quickToggles.useThreeWaySliders
                onCheckedChanged: {
                    Config.options.sidebar.quickToggles.useThreeWaySliders = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Draw the power profile toggle as a three-position slider when it is two cells wide")
                }

            }

        }

        ContentSubsection {
            title: Translation.tr("Sliders")

            ConfigSwitch {
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.sidebar.quickSliders.enable
                onCheckedChanged: {
                    Config.options.sidebar.quickSliders.enable = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "brightness_6"
                text: Translation.tr("Brightness")
                enabled: Config.options.sidebar.quickSliders.enable
                checked: Config.options.sidebar.quickSliders.showBrightness
                onCheckedChanged: {
                    Config.options.sidebar.quickSliders.showBrightness = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "backlight_low"
                text: Translation.tr("Gamma")
                enabled: Config.options.sidebar.quickSliders.enable
                checked: Config.options.sidebar.quickSliders.showGamma
                onCheckedChanged: {
                    Config.options.sidebar.quickSliders.showGamma = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("Volume")
                enabled: Config.options.sidebar.quickSliders.enable
                checked: Config.options.sidebar.quickSliders.showVolume
                onCheckedChanged: {
                    Config.options.sidebar.quickSliders.showVolume = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "mic"
                text: Translation.tr("Microphone")
                enabled: Config.options.sidebar.quickSliders.enable
                checked: Config.options.sidebar.quickSliders.showMic
                onCheckedChanged: {
                    Config.options.sidebar.quickSliders.showMic = checked;
                }
            }

        }

        ContentSubsection {
            title: Translation.tr("Corner open")
            tooltip: Translation.tr("Allows you to open sidebars by clicking or hovering screen corners regardless of bar position")

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.sidebar.cornerOpen.enable
                    onCheckedChanged: {
                        Config.options.sidebar.cornerOpen.enable = checked;
                    }
                }

            }

            ConfigSwitch {
                buttonIcon: "highlight_mouse_cursor"
                text: Translation.tr("Hover to trigger")
                checked: Config.options.sidebar.cornerOpen.clickless
                onCheckedChanged: {
                    Config.options.sidebar.cornerOpen.clickless = checked;
                }

                StyledToolTip {
                    text: Translation.tr("When this is off you'll have to click")
                }

            }

            Row {
                ConfigSwitch {
                    enabled: !Config.options.sidebar.cornerOpen.clickless
                    text: Translation.tr("Force hover open at absolute corner")
                    checked: Config.options.sidebar.cornerOpen.clicklessCornerEnd
                    onCheckedChanged: {
                        Config.options.sidebar.cornerOpen.clicklessCornerEnd = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("When the previous option is off and this is on,\nyou can still hover the corner's end to open sidebar,\nand the remaining area can be used for volume/brightness scroll")
                    }

                }

                ConfigSpinBox {
                    icon: "arrow_cool_down"
                    text: Translation.tr("with vertical offset")
                    value: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
                    from: 0
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset = value;
                    }
                }

            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "vertical_align_bottom"
                    text: Translation.tr("Place at bottom")
                    checked: Config.options.sidebar.cornerOpen.bottom
                    onCheckedChanged: {
                        Config.options.sidebar.cornerOpen.bottom = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Place the corners to trigger at the bottom")
                    }

                }

                ConfigSwitch {
                    buttonIcon: "unfold_more_double"
                    text: Translation.tr("Value scroll")
                    checked: Config.options.sidebar.cornerOpen.valueScroll
                    onCheckedChanged: {
                        Config.options.sidebar.cornerOpen.valueScroll = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Brightness and volume")
                    }

                }

            }

            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Visualize region")
                checked: Config.options.sidebar.cornerOpen.visualize
                onCheckedChanged: {
                    Config.options.sidebar.cornerOpen.visualize = checked;
                }
            }

            ConfigRow {
                ConfigSpinBox {
                    icon: "arrow_range"
                    text: Translation.tr("Region width")
                    value: Config.options.sidebar.cornerOpen.cornerRegionWidth
                    from: 1
                    to: 300
                    stepSize: 1
                    onValueChanged: {
                        Config.options.sidebar.cornerOpen.cornerRegionWidth = value;
                    }
                }

                ConfigSpinBox {
                    icon: "height"
                    text: Translation.tr("Region height")
                    value: Config.options.sidebar.cornerOpen.cornerRegionHeight
                    from: 1
                    to: 300
                    stepSize: 1
                    onValueChanged: {
                        Config.options.sidebar.cornerOpen.cornerRegionHeight = value;
                    }
                }

            }

        }

    }

    ContentSection {
        icon: "voting_chip"
        title: Translation.tr("On-screen display")

        ConfigSwitch {
            buttonIcon: "visibility"
            text: Translation.tr("Enable OSD")
            checked: Config.options.osd.enable
            onCheckedChanged: {
                Config.options.osd.enable = checked;
            }
        }

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Timeout (ms)")
            value: Config.options.osd.timeout
            from: 100
            to: 3000
            stepSize: 100
            onValueChanged: {
                Config.options.osd.timeout = value;
            }
        }

        ContentSubsection {
            title: Translation.tr("OSD Position")
            Layout.fillWidth: true
            visible: (Config.options.osd.style ?? "default") === "default"

            OsdPositionPicker {
                Layout.fillWidth: true
            }
        }

        ContentSubsection {
            title: Translation.tr("OSD Style")
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.osd.style ?? "default"
                onSelected: (newValue) => {
                    Config.options.osd.style = newValue;
                    GlobalStates.osdVolumeOpen = true;
                    GlobalStates.osdInteraction();
                }
                options: [{
                    "displayName": Translation.tr("Android"),
                    "icon": "smartphone",
                    "tooltip": Translation.tr("Edge vertical slider bar"),
                    "value": "default"
                }, {
                    "displayName": Translation.tr("Minimal"),
                    "icon": "horizontal_rule",
                    "tooltip": Translation.tr("Compact horizontal floating pill"),
                    "value": "minimalist"
                }, {
                    "displayName": Translation.tr("Material"),
                    "icon": "interests",
                    "tooltip": Translation.tr("Themed geometric slider card"),
                    "value": "material"
                }]
            }
        }

        ContentSubsection {
            title: Translation.tr("Material Style Options")
            Layout.fillWidth: true
            visible: Config.options.osd.style === "material"

            ConfigSwitch {
                buttonIcon: "compress"
                text: Translation.tr("Minimal variant")
                checked: Config.options.osd.material.minimal
                onCheckedChanged: {
                    Config.options.osd.material.minimal = checked;
                    GlobalStates.osdVolumeOpen = true;
                    GlobalStates.osdInteraction();
                }
            }

            ConfigSwitch {
                buttonIcon: "shapes"
                text: Translation.tr("Shaped value labels")
                checked: Config.options.osd.material.shapedValues
                onCheckedChanged: {
                    Config.options.osd.material.shapedValues = checked;
                    GlobalStates.osdVolumeOpen = true;
                    GlobalStates.osdInteraction();
                }
            }

            ConfigSwitch {
                buttonIcon: "circle"
                text: Translation.tr("Circled shapes")
                checked: Config.options.osd.material.circledShapes
                onCheckedChanged: {
                    Config.options.osd.material.circledShapes = checked;
                    GlobalStates.osdVolumeOpen = true;
                    GlobalStates.osdInteraction();
                }
            }

            ConfigSwitch {
                buttonIcon: "rotate_right"
                text: Translation.tr("Rotate shapes when changing values")
                checked: Config.options.osd.material.rotateShape
                onCheckedChanged: {
                    Config.options.osd.material.rotateShape = checked;
                    GlobalStates.osdVolumeOpen = true;
                    GlobalStates.osdInteraction();
                }
            }
        }
    }

    ContentSection {
        icon: "translate"
        title: Translation.tr("Language switcher notification")
        tooltip: Translation.tr("To add keyboard layouts (max 4 per device with XKB), set kb_layout in general.lua.\nSet kb_options = \"grp:alt_shift_toggle\" to switch with Alt+Shift.\nRefer to Hyprland wiki documentation for more details.")

        ConfigRow {
            ConfigSwitch {
                buttonIcon: "check"
                text: Translation.tr("Enable switcher notification")
                checked: Config.options.languageSwitcher.enable ?? true
                onCheckedChanged: {
                    Config.options.languageSwitcher.enable = checked;
                }
            }

        }

    }

    ContentSection {
        icon: "overview_key"
        title: Translation.tr("Overview")

        ConfigRow {
            ConfigSwitch {
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.overview.enable
                onCheckedChanged: {
                    Config.options.overview.enable = checked;
                }
            }

        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Show icons")
                checked: Config.options.overview.showIcons
                onCheckedChanged: {
                    Config.options.overview.showIcons = checked;
                }
            }

            ConfigSwitch {
                enabled: Config.options.overview.showIcons
                buttonIcon: "center_focus_strong"
                text: Translation.tr("Center icons")
                checked: Config.options.overview.centerIcons
                onCheckedChanged: {
                    Config.options.overview.centerIcons = checked;
                }
            }

        }

        ConfigSwitch {
            buttonIcon: "grid_3x3"
            text: Translation.tr("Use workspace map")
            checked: Config.options.overview.useWorkspaceMap
            onCheckedChanged: {
                Config.options.overview.useWorkspaceMap = checked;
            }

            StyledToolTip {
                text: Translation.tr("Only for multi-monitor setups, you must edit the workspace map manually in config.json\n Refer to the repo wiki for more information")
            }

        }

        ConfigSpinBox {
            icon: "loupe"
            text: Translation.tr("Scale (%)")
            value: Config.options.overview.scale * 100
            from: 1
            to: 100
            stepSize: 1
            onValueChanged: {
                Config.options.overview.scale = value / 100;
            }
        }

        ConfigRow {
            ConfigSwitch {
                buttonIcon: "high_density"
                text: Translation.tr("Enable zoom animation")
                checked: Config.options.overview.showOpeningAnimation
                onCheckedChanged: {
                    Config.options.overview.showOpeningAnimation = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Using zoom-in style zoomes the wallpaper in default state, may look pixelated on crisp wallpapers")
                }

            }

            Item {
                Layout.fillWidth: true
            }

            ConfigSelectionArray {
                Layout.fillWidth: false
                enabled: Config.options.overview.showOpeningAnimation
                currentValue: Config.options.overview.scrollingStyle.zoomStyle
                onSelected: (newValue) => {
                    Config.options.overview.scrollingStyle.zoomStyle = newValue;
                }
                options: [{
                    "displayName": Translation.tr("In"),
                    "icon": "zoom_in_map",
                    "value": "in"
                }, {
                    "displayName": Translation.tr("Out"),
                    "icon": "zoom_out_map",
                    "value": "out"
                }]
            }

        }

        ContentSubsection {
            title: Translation.tr("Classic overview style")

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "splitscreen_bottom"
                    text: Translation.tr("Rows")
                    value: Config.options.overview.rows
                    from: 1
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        Config.options.overview.rows = value;
                    }
                }

                ConfigSpinBox {
                    icon: "splitscreen_right"
                    text: Translation.tr("Columns")
                    value: Config.options.overview.columns
                    from: 1
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        Config.options.overview.columns = value;
                    }
                }

            }

            ConfigRow {
                uniform: true

                ConfigSelectionArray {
                    currentValue: Config.options.overview.orderRightLeft
                    onSelected: (newValue) => {
                        Config.options.overview.orderRightLeft = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Left to right"),
                        "icon": "arrow_forward",
                        "value": 0
                    }, {
                        "displayName": Translation.tr("Right to left"),
                        "icon": "arrow_back",
                        "value": 1
                    }]
                }

                ConfigSelectionArray {
                    Layout.leftMargin: 50
                    currentValue: Config.options.overview.orderBottomUp
                    onSelected: (newValue) => {
                        Config.options.overview.orderBottomUp = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Top-down"),
                        "icon": "arrow_downward",
                        "value": 0
                    }, {
                        "displayName": Translation.tr("Bottom-up"),
                        "icon": "arrow_upward",
                        "value": 1
                    }]
                }

            }

        }

        ConfigSpinBox {
            enabled: Config.options.overview.scrollingStyle.backgroundStyle === "dim"
            icon: "backlight_low"
            text: Translation.tr("Dim percentage")
            value: Config.options.overview.scrollingStyle.dimPercentage
            from: 0
            to: 75
            stepSize: 5
            onValueChanged: {
                Config.options.overview.scrollingStyle.dimPercentage = value;
            }
        }

        ContentSubsection {
            title: Translation.tr("Scrolling overview style")

            ConfigSelectionArray {
                currentValue: Config.options.overview.scrollingStyle.backgroundStyle
                onSelected: (newValue) => {
                    Config.options.overview.scrollingStyle.backgroundStyle = newValue;
                }
                options: [{
                    "displayName": Translation.tr("Blur"),
                    "icon": "blur_on",
                    "value": "blur"
                }, {
                    "displayName": Translation.tr("Dim"),
                    "icon": "ev_shadow",
                    "value": "dim"
                }, {
                    "displayName": Translation.tr("Transparent"),
                    "icon": "opacity",
                    "value": "transparent"
                }]
            }

        }

    }

    ContentSection {
        icon: "wallpaper_slideshow"
        title: Translation.tr("Wallpaper selector")

        ConfigSwitch {
            buttonIcon: "ad"
            text: Translation.tr('Use system file picker')
            checked: Config.options.wallpaperSelector.useSystemFileDialog
            onCheckedChanged: {
                Config.options.wallpaperSelector.useSystemFileDialog = checked;
            }
        }

    }

}
