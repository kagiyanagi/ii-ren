import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: advancedConfigRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage
    property bool register: parent.register ?? false

    Connections {
        target: root
        function onPendingSectionHighlightChanged() {
            if (root.pendingSectionHighlight && root.pendingSectionHighlight.endsWith(".qml")) {
                advancedConfigRoot.activeSubPage = Qt.resolvedUrl(root.pendingSectionHighlight);
                root.pendingSectionHighlight = "";
            }
        }
    }

    Component.onCompleted: {
        if (root.pendingSectionHighlight && root.pendingSectionHighlight.endsWith(".qml")) {
            advancedConfigRoot.activeSubPage = Qt.resolvedUrl(root.pendingSectionHighlight);
            root.pendingSectionHighlight = "";
        }
    }

    // The seven families, in the order the shell leans on them. `enableCustom`
    // swaps the live names between these stored ones and the shipped defaults,
    // which Config.qml declares; the defaults below must stay equal to those.
    readonly property var fontRoles: [
        { key: "main", icon: "text_fields", label: Translation.tr("Main"), fallback: "Google Sans Flex" },
        { key: "title", icon: "title", label: Translation.tr("Titles"), fallback: "Google Sans Flex" },
        { key: "numbers", icon: "123", label: Translation.tr("Numbers"), fallback: "Google Sans Flex" },
        { key: "reading", icon: "chrome_reader_mode", label: Translation.tr("Reading"), fallback: "Readex Pro" },
        { key: "expressive", icon: "brush", label: Translation.tr("Expressive"), fallback: "Space Grotesk" },
        { key: "monospace", icon: "code", label: Translation.tr("Monospace"), fallback: "JetBrains Mono NF" },
        { key: "iconNerd", icon: "emoji_symbols", label: Translation.tr("Nerd Font icons"), fallback: "JetBrains Mono NF" }
    ]

    // Committed on Enter or focus-out, not per keystroke: every write re-lays
    // out all text in the shell, on a half-typed family name. Written out seven
    // times rather than repeated, because ContentGroup reads a Repeater as a
    // bare row and would split the run around it.
    component FontField: ConfigTextField {
        required property var role
        enabled: Config.options.appearance.fonts.enableCustom
        icon: role.icon
        text: role.label
        placeholderText: role.fallback
        inputText: Persistent.states.settings.fonts[role.key]
        onEditingFinished: {
            const name = inputText.trim();
            if (name.length === 0 || name === Config.options.appearance.fonts[role.key])
                return;
            Persistent.states.settings.fonts[role.key] = name;
            Config.options.appearance.fonts[role.key] = name;
        }
    }

    ContentPage {
        id: page
        readonly property int index: 10
        property bool register: advancedConfigRoot.register
        anchors.fill: parent
        forceWidth: true

        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        ContentSection {
            icon: "colors"
            title: Translation.tr("Color generation")

            ConfigSwitch {
                buttonIcon: "hardware"
                text: Translation.tr("Shell & utilities")
                checked: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                onCheckedChanged: {
                    Config.options.appearance.wallpaperTheming.enableAppsAndShell = checked;
                }
            }
            // switchwall.sh returns before generating anything when the switch
            // above is off, so everything below it follows it.
            ConfigSwitch {
                buttonIcon: "tv_options_input_settings"
                enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                text: Translation.tr("Qt apps")
                checked: Config.options.appearance.wallpaperTheming.enableQtApps
                onCheckedChanged: {
                    Config.options.appearance.wallpaperTheming.enableQtApps = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "terminal"
                enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                text: Translation.tr("Terminal")
                checked: Config.options.appearance.wallpaperTheming.enableTerminal
                onCheckedChanged: {
                    Config.options.appearance.wallpaperTheming.enableTerminal = checked;
                }
            }

            ContentSubsection {
                title: Translation.tr("Terminal colours")
                enabled: Config.options.appearance.wallpaperTheming.enableAppsAndShell
                    && Config.options.appearance.wallpaperTheming.enableTerminal

                ConfigSwitch {
                    buttonIcon: "dark_mode"
                    text: Translation.tr("Force dark mode")
                    checked: Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode
                    onCheckedChanged: {
                        Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode = checked;
                    }
                }
                ConfigSpinBox {
                    icon: "invert_colors"
                    text: Translation.tr("Harmony (%)")
                    from: 0
                    to: 100
                    stepSize: 10
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony * 100
                    onValueChanged: {
                        Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmony = value / 100;
                    }
                }
                ConfigSpinBox {
                    icon: "gradient"
                    text: Translation.tr("Harmonize threshold")
                    from: 0
                    to: 100
                    stepSize: 10
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold
                    onValueChanged: {
                        Config.options.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold = value;
                    }
                }
                ConfigSpinBox {
                    icon: "format_color_text"
                    text: Translation.tr("Foreground boost (%)")
                    from: 0
                    to: 100
                    stepSize: 10
                    value: Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost * 100
                    onValueChanged: {
                        Config.options.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost = value / 100;
                    }
                }
            }
        }

        ContentSection {
            icon: "category"
            title: Translation.tr("Icons & cursor")

            ConfigNavRow {
                buttonIcon: "category"
                text: Translation.tr("Icon pack")
                searchString: Translation.tr("Icon Themes, Dynamic Icon Pack, Dolphin folders, App icons")
                summary: {
                    if (!IconThemes.enableThemed)
                        return Translation.tr("Off");
                    return IconThemes.currentSystemTheme.length > 0
                        ? IconThemes.currentSystemTheme + (IconThemes.isCurrentDynamic ? " · " + Translation.tr("Dynamic") : "")
                        : Translation.tr("Configure dynamic icon packs");
                }
                onClicked: advancedConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/ThemedIconsConfig.qml")
            }
            ConfigNavRow {
                buttonIcon: "arrow_selector_tool"
                text: Translation.tr("Cursor")
                searchString: Translation.tr("Cursor Theme, Cursor Size, Mouse, Pointer, Custom Cursor")
                summary: {
                    const theme = CursorTheme.configuredTheme.length > 0 ? CursorTheme.configuredTheme : Translation.tr("Default");
                    return `${theme} · ${CursorTheme.configuredSize}px`;
                }
                onClicked: advancedConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/CustomCursorConfig.qml")
            }
        }

        ContentSection {
            icon: "text_format"
            title: Translation.tr("Fonts")

            ConfigSwitch {
                buttonIcon: "custom_typography"
                text: Translation.tr("Use custom fonts")
                checked: Config.options.appearance.fonts.enableCustom
                onCheckedChanged: {
                    if (Config.options.appearance.fonts.enableCustom === checked)
                        return;
                    Config.options.appearance.fonts.enableCustom = checked;
                    for (const role of advancedConfigRoot.fontRoles)
                        Config.options.appearance.fonts[role.key] = checked ? Persistent.states.settings.fonts[role.key] : role.fallback;
                }
            }

            FontField { role: advancedConfigRoot.fontRoles[0] }
            FontField { role: advancedConfigRoot.fontRoles[1] }
            FontField { role: advancedConfigRoot.fontRoles[2] }
            FontField { role: advancedConfigRoot.fontRoles[3] }
            FontField { role: advancedConfigRoot.fontRoles[4] }
            FontField { role: advancedConfigRoot.fontRoles[5] }
            FontField { role: advancedConfigRoot.fontRoles[6] }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
