pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.models.hyprland
import qs.modules.common.widgets

ContentPage {
    id: page
    readonly property int index: 7
    property bool register: parent.register ?? false
    forceWidth: true

    // Every control on this page reads the value Hyprland is actually running
    // (hyprctl getoption) instead of a mirror kept in config.json, so the page
    // can't drift from the compositor and there is no second schema to maintain.
    MonitorConfigOption { id: monitors }

    HyprlandConfigOption { id: optRounding; key: "decoration:rounding" }
    HyprlandConfigOption { id: optBlurEnabled; key: "decoration:blur:enabled" }
    HyprlandConfigOption { id: optBlurSize; key: "decoration:blur:size" }
    HyprlandConfigOption { id: optBlurPasses; key: "decoration:blur:passes" }
    HyprlandConfigOption { id: optActiveOpacity; key: "decoration:active_opacity" }
    HyprlandConfigOption { id: optInactiveOpacity; key: "decoration:inactive_opacity" }
    HyprlandConfigOption { id: optBorderSize; key: "general:border_size" }
    HyprlandConfigOption { id: optGapsIn; key: "general:gaps_in" }
    HyprlandConfigOption { id: optGapsOut; key: "general:gaps_out" }
    HyprlandConfigOption { id: optLayout; key: "general:layout" }
    HyprlandConfigOption { id: optAnimations; key: "animations:enabled" }
    HyprlandConfigOption { id: optKbLayout; key: "input:kb_layout" }
    HyprlandConfigOption { id: optNumlock; key: "input:numlock_by_default" }
    HyprlandConfigOption { id: optRepeatDelay; key: "input:repeat_delay" }
    HyprlandConfigOption { id: optRepeatRate; key: "input:repeat_rate" }
    HyprlandConfigOption { id: optFollowMouse; key: "input:follow_mouse" }
    HyprlandConfigOption { id: optNaturalScroll; key: "input:touchpad:natural_scroll" }
    HyprlandConfigOption { id: optDisableWhileTyping; key: "input:touchpad:disable_while_typing" }
    HyprlandConfigOption { id: optClickfinger; key: "input:touchpad:clickfinger_behavior" }
    HyprlandConfigOption { id: optScrollFactor; key: "input:touchpad:scroll_factor" }

    // Single funnel for every write. Switches, sliders and spin boxes all fire
    // their change handler once while being built, before the fetch has landed,
    // and again for every value the compositor itself just reported back — both
    // would write garbage or loop, so drop anything that isn't a real edit.
    // ponytail: a settle window, not a per-control "the user touched me" signal
    // — spin boxes and switches here don't have one. Raise it if a slower
    // machine is ever seen writing a clamped default on open.
    property bool settled: false
    Timer {
        running: true
        interval: 800
        onTriggered: page.settled = true
    }

    function put(opt: var, value: var): void {
        if (!page.settled || !opt.loaded)
            return;
        if (typeof value === "string") {
            if (value === String(opt.value)) return;
        } else if (typeof value === "boolean") {
            if (value === (opt.value === true)) return;
        } else if (Math.abs(value - opt.numericValue) < 1e-4) {
            return;
        }
        opt.setValue(value);
    }

    readonly property var selectedMonitor: monitors.monitors[monitorCanvas.selectedIndex] ?? null

    function updateSelected(changes: var): void {
        monitors.updateMonitor(monitorCanvas.selectedIndex, changes);
        monitors.applyAndSave(monitorCanvas.selectedIndex);
    }

    ContentSection {
        icon: "monitor"
        title: Translation.tr("Displays")
        visible: monitors.monitors.length > 0

        MonitorCanvas {
            id: monitorCanvas
            Layout.fillWidth: true
            monitorConfig: monitors
        }

        ContentSubsection {
            title: [page.selectedMonitor?.name, page.selectedMonitor?.description].filter(s => s).join(" · ")

            ConfigSwitch {
                buttonIcon: "tv_off"
                text: Translation.tr("Enabled")
                // Turning off the only display leaves nothing to turn it back on with.
                enabled: monitors.monitors.length > 1
                checked: !(page.selectedMonitor?.disabled ?? false)
                onCheckedChanged: {
                    if (!page.selectedMonitor || checked === !page.selectedMonitor.disabled)
                        return;
                    page.updateSelected({ disabled: !checked });
                }
            }

            ContentSubsection {
                title: Translation.tr("Resolution & refresh rate")

                StyledComboBox {
                    buttonIcon: "aspect_ratio"
                    model: page.selectedMonitor?.availableModes ?? []
                    currentIndex: Math.max(0, model.indexOf(page.selectedMonitor?.currentMode ?? ""))
                    onActivated: index => {
                        const mode = model[index];
                        const parts = mode.match(/(\d+)x(\d+)@([\d.]+)Hz/);
                        if (!parts) return;
                        page.updateSelected({
                            currentMode: mode,
                            width: parseInt(parts[1]),
                            height: parseInt(parts[2]),
                            refreshRate: parseFloat(parts[3])
                        });
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Orientation")

                ConfigSelectionArray {
                    currentValue: page.selectedMonitor?.transform ?? 0
                    onSelected: newValue => page.updateSelected({ transform: newValue })
                    options: [
                        { displayName: Translation.tr("Normal"), icon: "screen_rotation_alt", value: 0 },
                        { displayName: "90°", icon: "rotate_90_degrees_cw", value: 1 },
                        { displayName: "180°", icon: "screen_rotation", value: 2 },
                        { displayName: "270°", icon: "rotate_90_degrees_ccw", value: 3 }
                    ]
                }
            }

            ConfigSpinBox {
                icon: "zoom_in"
                text: Translation.tr("Scale (%)")
                from: 50
                to: 300
                stepSize: 5
                value: Math.round((page.selectedMonitor?.scale ?? 1) * 100)
                onValueChanged: {
                    const scale = value / 100;
                    if (!page.selectedMonitor || Math.abs(scale - page.selectedMonitor.scale) < 1e-4)
                        return;
                    page.updateSelected({ scale: scale });
                }
            }
        }
    }

    ContentSection {
        icon: "auto_awesome_mosaic"
        title: Translation.tr("Layout")

        ConfigSelectionArray {
            currentValue: String(optLayout.value ?? "dwindle")
            // Goes through setLayout rather than put(): the quick settings tile
            // reads the layout back out of Persistent, which setLayout keeps.
            onSelected: newValue => {
                if (optLayout.loaded && newValue !== String(optLayout.value))
                    HyprlandSettings.setLayout(newValue);
            }
            options: [
                { displayName: Translation.tr("Dwindle"), icon: "browse", value: "dwindle" },
                { displayName: Translation.tr("Master"), icon: "auto_awesome_mosaic", value: "master" },
                { displayName: Translation.tr("Scrolling"), icon: "view_carousel", value: "scrolling" }
            ]
        }
    }

    ContentSection {
        icon: "deblur"
        title: Translation.tr("Appearance")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "battery_alert"
            text: Translation.tr("Large blur sizes and extra passes cost GPU time every frame, which shows up as battery drain on a laptop.")
        }

        ConfigSlider {
            buttonIcon: "rounded_corner"
            text: Translation.tr("Window rounding")
            usePercentTooltip: false
            from: 0
            to: 30
            value: optRounding.numericValue
            onMoved: value => page.put(optRounding, Math.round(value))
        }

        ConfigSlider {
            buttonIcon: "border_outer"
            text: Translation.tr("Border size")
            usePercentTooltip: false
            from: 0
            to: 10
            value: optBorderSize.numericValue
            onMoved: value => page.put(optBorderSize, Math.round(value))
        }

        ConfigSlider {
            buttonIcon: "margin"
            text: Translation.tr("Gaps in")
            usePercentTooltip: false
            from: 0
            to: 40
            value: optGapsIn.numericValue
            onMoved: value => page.put(optGapsIn, Math.round(value))
        }

        ConfigSlider {
            buttonIcon: "open_in_full"
            text: Translation.tr("Gaps out")
            usePercentTooltip: false
            from: 0
            to: 60
            value: optGapsOut.numericValue
            onMoved: value => page.put(optGapsOut, Math.round(value))
        }

        ConfigSwitch {
            buttonIcon: "blur_on"
            text: Translation.tr("Blur")
            checked: optBlurEnabled.value === true
            onCheckedChanged: page.put(optBlurEnabled, checked)
        }

        ConfigSlider {
            buttonIcon: "blur_circular"
            text: Translation.tr("Blur size")
            usePercentTooltip: false
            enabled: optBlurEnabled.value === true
            from: 1
            to: 20
            value: optBlurSize.numericValue
            onMoved: value => page.put(optBlurSize, Math.round(value))
        }

        ConfigSlider {
            buttonIcon: "layers"
            text: Translation.tr("Blur passes")
            usePercentTooltip: false
            enabled: optBlurEnabled.value === true
            from: 1
            to: 6
            value: optBlurPasses.numericValue
            onMoved: value => page.put(optBlurPasses, Math.round(value))
        }

        ConfigSpinBox {
            icon: "opacity"
            text: Translation.tr("Active window opacity (%)")
            from: 10
            to: 100
            stepSize: 5
            value: Math.round(optActiveOpacity.numericValue * 100)
            onValueChanged: page.put(optActiveOpacity, value / 100)
        }

        ConfigSpinBox {
            icon: "opacity"
            text: Translation.tr("Inactive window opacity (%)")
            from: 10
            to: 100
            stepSize: 5
            value: Math.round(optInactiveOpacity.numericValue * 100)
            onValueChanged: page.put(optInactiveOpacity, value / 100)
        }
    }

    ContentSection {
        icon: "trackpad_input"
        title: Translation.tr("Input")

        ContentSubsection {
            title: Translation.tr("Keyboard")

            ConfigRow {
                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Layouts, e.g. us,es")
                    text: String(optKbLayout.value ?? "")
                    onEditingFinished: page.put(optKbLayout, text.trim())
                }
            }

            ConfigSwitch {
                buttonIcon: "numbers"
                text: Translation.tr("Numlock by default")
                checked: optNumlock.value === true
                onCheckedChanged: page.put(optNumlock, checked)
            }

            ConfigSpinBox {
                icon: "keyboard_return"
                text: Translation.tr("Repeat delay (ms)")
                from: 100
                to: 1000
                stepSize: 10
                value: optRepeatDelay.numericValue
                onValueChanged: page.put(optRepeatDelay, value)
            }

            ConfigSpinBox {
                icon: "speed"
                text: Translation.tr("Repeat rate (keys/s)")
                from: 10
                to: 100
                stepSize: 1
                value: optRepeatRate.numericValue
                onValueChanged: page.put(optRepeatRate, value)
            }
        }

        ContentSubsection {
            title: Translation.tr("Cursor")

            ConfigRow {
                StyledComboBox {
                    id: hyprCursorSelector
                    Layout.fillWidth: true
                    buttonIcon: "arrow_selector_tool"
                    textRole: "name"
                    model: CursorTheme.availableThemes
                    currentIndex: {
                        for (let i = 0; i < CursorTheme.availableThemes.length; i++) {
                            if (CursorTheme.availableThemes[i].id === CursorTheme.configuredTheme)
                                return i;
                        }
                        return -1;
                    }
                    onActivated: index => {
                        if (index >= 0 && index < CursorTheme.availableThemes.length) {
                            CursorTheme.setCursor(CursorTheme.availableThemes[index].id, CursorTheme.configuredSize);
                        }
                    }
                }

                ConfigSpinBox {
                    icon: "format_size"
                    text: Translation.tr("Size")
                    from: 12
                    to: 64
                    stepSize: 2
                    value: CursorTheme.configuredSize
                    onValueChanged: {
                        if (value !== CursorTheme.configuredSize) {
                            CursorTheme.setCursor(CursorTheme.configuredTheme, value);
                        }
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Focus follows mouse")

            ConfigSelectionArray {
                currentValue: optFollowMouse.numericValue
                onSelected: newValue => page.put(optFollowMouse, newValue)
                options: [
                    { displayName: Translation.tr("Off"), icon: "mouse", value: 0 },
                    { displayName: Translation.tr("Full"), icon: "open_with", value: 1 },
                    { displayName: Translation.tr("Loose"), icon: "drag_pan", value: 2 },
                    { displayName: Translation.tr("Explicit"), icon: "ads_click", value: 3 }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Touchpad")

            ConfigSwitch {
                buttonIcon: "swap_vert"
                text: Translation.tr("Natural scroll")
                checked: optNaturalScroll.value === true
                onCheckedChanged: page.put(optNaturalScroll, checked)
            }

            ConfigSwitch {
                buttonIcon: "keyboard_hide"
                text: Translation.tr("Disable while typing")
                checked: optDisableWhileTyping.value === true
                onCheckedChanged: page.put(optDisableWhileTyping, checked)
            }

            ConfigSwitch {
                buttonIcon: "touch_app"
                text: Translation.tr("Clickfinger behavior")
                checked: optClickfinger.value === true
                onCheckedChanged: page.put(optClickfinger, checked)
            }

            ConfigSpinBox {
                icon: "swipe"
                text: Translation.tr("Scroll speed (%)")
                from: 10
                to: 300
                stepSize: 10
                value: Math.round(optScrollFactor.numericValue * 100)
                onValueChanged: page.put(optScrollFactor, value / 100)
            }
        }
    }

    ContentSection {
        icon: "animation"
        title: Translation.tr("Animations")

        ConfigSwitch {
            buttonIcon: "animation"
            text: Translation.tr("Enable animations")
            checked: optAnimations.value === true
            onCheckedChanged: page.put(optAnimations, checked)
        }
    }
}
