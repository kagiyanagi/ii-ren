import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.settings

ContentPage {
    id: page
    readonly property int index: 3
    property bool register: parent.register ?? false
    forceWidth: true
    
    property bool allowHeavyLoads: false
    Component.onCompleted: Qt.callLater(() => page.allowHeavyLoads = true)

    ContentSection {
        icon: "sync_alt"
        title: Translation.tr("Parallax")

        ConfigSwitch {
            buttonIcon: "unfold_more_double"
            text: Translation.tr("Vertical")
            checked: Config.options.background.parallax.vertical
            onCheckedChanged: {
                HyprlandSettings.changeAnimation("workspaces", checked ? "slidevert" : "slide");
                Config.options.background.parallax.vertical = checked;
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "counter_1"
                text: Translation.tr("Depends on workspace")
                checked: Config.options.background.parallax.enableWorkspace
                onCheckedChanged: {
                    Config.options.background.parallax.enableWorkspace = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "side_navigation"
                text: Translation.tr("Depends on sidebars")
                checked: Config.options.background.parallax.enableSidebar
                onCheckedChanged: {
                    Config.options.background.parallax.enableSidebar = checked;
                }
            }
        }
        ConfigSpinBox {
            icon: "loupe"
            text: Translation.tr("Preferred wallpaper zoom (%)")
            value: Config.options.background.parallax.workspaceZoom * 100
            from: 10
            to: 200
            stepSize: 1
            onValueChanged: {
                Config.options.background.parallax.workspaceZoom = value / 100;
            }
        }
        ConfigSwitch {
            buttonIcon: "masked_transitions"
            text: Translation.tr("Animate wallpaper changes")
            checked: Config.options.background.animateWallpaperChanges
            onCheckedChanged: {
                Config.options.background.animateWallpaperChanges = checked;
            }
        }
        
        ContentSubsection {
            visible: Config.options.background.animateWallpaperChanges
            title: Translation.tr("Wallpaper transition style")
            
            StyledComboBox {
                Layout.fillWidth: true
                buttonIcon: "masked_transitions"
                textRole: "displayName"
                model: [
                    {
                        displayName: Translation.tr("Radial Wipe"),
                        icon: "circle",
                        value: "radial"
                    },
                    {
                        displayName: Translation.tr("Crossfade"),
                        icon: "blur_on",
                        value: "crossfade"
                    },
                    {
                        displayName: Translation.tr("Linear Wipe"),
                        icon: "swap_horiz",
                        value: "wipe"
                    },
                    {
                        displayName: Translation.tr("Diamond Wipe"),
                        icon: "diamond",
                        value: "diamond"
                    },
                    {
                        displayName: Translation.tr("Slash Wipe"),
                        icon: "timeline",
                        value: "slash"
                    },
                    {
                        displayName: Translation.tr("Outer Wipe"),
                        icon: "radio_button_unchecked",
                        value: "outer"
                    },
                    {
                        displayName: Translation.tr("Wave Wipe"),
                        icon: "water",
                        value: "wave"
                    }
                ]
                currentIndex: {
                    const index = model.findIndex(item => item.value === Config.options.background.transitionType);
                    return index !== -1 ? index : 0;
                }
                onActivated: index => {
                    Config.options.background.transitionType = model[index].value;
                }
            }

            ConfigSpinBox {
                visible: Config.options.background.transitionType === "wipe" || Config.options.background.transitionType === "wave"
                Layout.fillWidth: true
                icon: "rotate_right"
                text: Translation.tr("Wipe Angle (0° starts from left side)")
                value: Config.options.background.wipeAngle
                from: 0
                to: 359
                stepSize: 1
                onValueChanged: {
                    Config.options.background.wipeAngle = value;
                }
            }
        }
    }

    ContentSection {
        icon: "wallpaper"
        title: Translation.tr("Wallpaper")

        ConfigSwitch {
            buttonIcon: "add_photo_alternate"
            text: Translation.tr("Drop an image on the desktop to set it as wallpaper")
            checked: Config.options.background.dropToSetWallpaper
            onCheckedChanged: {
                Config.options.background.dropToSetWallpaper = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "stacks"
            text: Translation.tr("Drop other files on the desktop to hold them on a shelf")
            checked: Config.options.background.dropToShelf
            onCheckedChanged: {
                Config.options.background.dropToShelf = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "more_horiz"
            text: Translation.tr("Right-click the desktop for a context menu")
            checked: Config.options.background.rightClickMenu
            onCheckedChanged: {
                Config.options.background.rightClickMenu = checked;
            }
        }
    }

    // ---- Wallpaper effects ----------------------------------------------
    // The filter list and its maths mirror what custom ROMs ship (risingOS's
    // SystemUI WallpaperUtils, inherited by Evolution X, Matrixx, Mist,
    // Lunaris, PenguinOS). Fluted glass is ours.
    readonly property var effectOpt: Config.options.background.effects

    readonly property var wallpaperFilters: [
        { value: "none",       icon: "block",           name: Translation.tr("None") },
        { value: "grayscale",  icon: "filter_b_and_w",  name: Translation.tr("Grayscale") },
        { value: "sepia",      icon: "filter_vintage",  name: Translation.tr("Sepia") },
        { value: "negative",   icon: "invert_colors",   name: Translation.tr("Negative") },
        { value: "posterize",  icon: "gradient",        name: Translation.tr("Posterize") },
        { value: "pixelate",   icon: "grid_on",         name: Translation.tr("Pixelation") },
        { value: "sharpen",    icon: "deblur",          name: Translation.tr("Sharpen") },
        { value: "chromatic",  icon: "blur_linear",     name: Translation.tr("Chromatic") },
        { value: "radialBlur", icon: "blur_circular",   name: Translation.tr("Radial blur") }
    ]

    // Every key a preset writes, so switching presets never leaves a stray
    // value behind from the one before.
    readonly property var glassPresets: [
        { name: Translation.tr("Reeded"),   preset: { pattern: "lines",   profile: "lens",    fluteWidth: 22, angle: 0,  distortion: 55, dispersion: 25, smear: 10, highlights: 55, shadows: 35, edges: 30, frost: 0,  irregularity: 0,  waviness: 0 } },
        { name: Translation.tr("Fine rib"), preset: { pattern: "lines",   profile: "lens",    fluteWidth: 10, angle: 0,  distortion: 40, dispersion: 15, smear: 5,  highlights: 40, shadows: 30, edges: 20, frost: 0,  irregularity: 0,  waviness: 0 } },
        { name: Translation.tr("Prism"),    preset: { pattern: "lines",   profile: "prism",   fluteWidth: 60, angle: 0,  distortion: 60, dispersion: 35, smear: 0,  highlights: 30, shadows: 25, edges: 15, frost: 0,  irregularity: 0,  waviness: 0 } },
        { name: Translation.tr("Rain"),     preset: { pattern: "rain",    profile: "lens",    fluteWidth: 34, angle: 0,  distortion: 55, dispersion: 30, smear: 25, highlights: 45, shadows: 30, edges: 30, frost: 3,  irregularity: 0,  waviness: 60 } },
        { name: Translation.tr("Chevron"),  preset: { pattern: "chevron", profile: "lens",    fluteWidth: 30, angle: 0,  distortion: 55, dispersion: 25, smear: 10, highlights: 45, shadows: 30, edges: 25, frost: 0,  irregularity: 0,  waviness: 50 } },
        { name: Translation.tr("Bubble"),   preset: { pattern: "bubble",  profile: "lens",    fluteWidth: 46, angle: 0,  distortion: 65, dispersion: 40, smear: 5,  highlights: 60, shadows: 35, edges: 20, frost: 0,  irregularity: 0,  waviness: 0 } },
        { name: Translation.tr("Cracked"),  preset: { pattern: "lines",   profile: "lens",    fluteWidth: 26, angle: 0,  distortion: 50, dispersion: 20, smear: 15, highlights: 40, shadows: 30, edges: 25, frost: 0,  irregularity: 70, waviness: 0 } },
        { name: Translation.tr("Diagonal"), preset: { pattern: "lines",   profile: "contour", fluteWidth: 40, angle: 60, distortion: 55, dispersion: 25, smear: 10, highlights: 50, shadows: 30, edges: 30, frost: 0,  irregularity: 0,  waviness: 0 } },
        { name: Translation.tr("Frosted"),  preset: { pattern: "lines",   profile: "flat",    fluteWidth: 28, angle: 0,  distortion: 20, dispersion: 5,  smear: 55, highlights: 25, shadows: 15, edges: 10, frost: 10, irregularity: 0,  waviness: 0 } }
    ]

    function applyGlassPreset(preset) {
        const glass = Config.options.background.effects.glass;
        for (const key in preset)
            glass[key] = preset[key];
        glass.enable = true;
    }

    function glassPresetActive(preset) {
        const glass = Config.options.background.effects.glass;
        return glass.enable && Object.keys(preset).every(key => glass[key] === preset[key]);
    }

    // A live preview of the wallpaper under one effect, doubling as its picker.
    component EffectCard: RippleButton {
        id: card
        required property string label
        required property bool selected
        property var filterPreset: ({})
        property var glassPreset: null
        property real previewBlur: 0

        padding: 4
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colLayer2
        toggled: card.selected
        implicitWidth: 128
        implicitHeight: 106

        contentItem: ColumnLayout {
            spacing: 3
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 116
                implicitHeight: 65
                radius: Appearance.rounding.verysmall
                clip: true
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.m3colors.m3outlineVariant

                WallpaperEffectPreview {
                    anchors.fill: parent
                    anchors.margins: 1
                    // Previews are cheap but there are a lot of them; hold off
                    // until the page itself has settled.
                    visible: page.allowHeavyLoads
                    filter: card.filterPreset
                    glass: card.glassPreset
                    blurRadius: card.previewBlur
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 118
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: card.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: card.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
        }
    }

    ContentSection {
        icon: "auto_fix"
        title: Translation.tr("Wallpaper effects")
        tooltip: Translation.tr("Applied to the wallpaper image only - widgets, panels and the dock are untouched.\nA video wallpaper cannot be filtered.\nEach effect is a GPU pass over the whole wallpaper, so stacking several costs frames on weak hardware.")

        ContentSubsection {
            title: Translation.tr("Apply to")

            ConfigSelectionArray {
                currentValue: page.effectOpt.target
                onSelected: newValue => {
                    Config.options.background.effects.target = newValue;
                }
                options: [
                    { displayName: Translation.tr("Everywhere"), icon: "select_all",  value: "both" },
                    { displayName: Translation.tr("Desktop"),    icon: "desktop_windows", value: "desktop" },
                    { displayName: Translation.tr("Lock screen"), icon: "lock",       value: "lock" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Filter")
            tooltip: Translation.tr("One at a time, as on a ROM. The adjustments below stack on top of whichever you pick.")

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: page.wallpaperFilters
                    EffectCard {
                        required property var modelData
                        label: modelData.name
                        selected: page.effectOpt.filter === modelData.value
                        // Preview the filter alone, with the adjustments off.
                        filterPreset: ({
                            filter: modelData.value,
                            saturation: 100, dim: 0, vignette: 0, grain: 0
                        })
                        onClicked: {
                            Config.options.background.effects.filter = modelData.value;
                        }
                    }
                }
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: page.effectOpt.filter === "posterize"
                buttonIcon: "gradient"
                text: Translation.tr("Posterize levels")
                usePercentTooltip: false
                from: 2
                to: 16
                value: page.effectOpt.posterizeLevels
                onMoved: value => Config.options.background.effects.posterizeLevels = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: page.effectOpt.filter === "pixelate"
                buttonIcon: "grid_on"
                text: Translation.tr("Pixel size (px)")
                usePercentTooltip: false
                from: 2
                to: 40
                value: page.effectOpt.pixelSize
                onMoved: value => Config.options.background.effects.pixelSize = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: page.effectOpt.filter === "sharpen"
                buttonIcon: "deblur"
                text: Translation.tr("Sharpen amount")
                usePercentTooltip: false
                from: 0
                to: 300
                value: page.effectOpt.sharpen * 100
                onMoved: value => Config.options.background.effects.sharpen = Math.round(value) / 100
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: page.effectOpt.filter === "chromatic"
                buttonIcon: "blur_linear"
                text: Translation.tr("Colour separation (px)")
                usePercentTooltip: false
                from: 1
                to: 40
                value: page.effectOpt.chromatic
                onMoved: value => Config.options.background.effects.chromatic = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: page.effectOpt.filter === "radialBlur"
                buttonIcon: "blur_circular"
                text: Translation.tr("Radial blur (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.effectOpt.radialBlur
                onMoved: value => Config.options.background.effects.radialBlur = Math.round(value)
            }
        }

        ContentSubsection {
            title: Translation.tr("Blur")

            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "blur_on"
                text: Translation.tr("Blur the wallpaper")
                checked: page.effectOpt.blur.enable
                onCheckedChanged: {
                    Config.options.background.effects.blur.enable = checked;
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: page.effectOpt.blur.enable

                Repeater {
                    // Glass and Frosted are the ROMs' two styles, radius 50 and 9.
                    model: [
                        { value: "glass",   name: Translation.tr("Glass"),  radius: 50 },
                        { value: "frosted", name: Translation.tr("Frosted"), radius: 9 },
                        { value: "custom",  name: Translation.tr("Custom"), radius: -1 }
                    ]
                    EffectCard {
                        required property var modelData
                        label: modelData.name
                        selected: page.effectOpt.blur.style === modelData.value
                        previewBlur: modelData.radius < 0 ? page.effectOpt.blur.radius : modelData.radius
                        filterPreset: ({ filter: "none", saturation: 100, dim: 0, vignette: 0, grain: 0 })
                        onClicked: {
                            Config.options.background.effects.blur.style = modelData.value;
                        }
                    }
                }
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: page.effectOpt.blur.enable && page.effectOpt.blur.style === "custom"
                buttonIcon: "blur_on"
                text: Translation.tr("Blur radius")
                usePercentTooltip: false
                from: 1
                to: 150
                value: page.effectOpt.blur.radius
                onMoved: value => Config.options.background.effects.blur.radius = Math.round(value)
            }
        }

        ContentSubsection {
            title: Translation.tr("Adjustments")

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "palette"
                text: Translation.tr("Saturation (%)")
                usePercentTooltip: false
                from: 50
                to: 200
                value: page.effectOpt.saturation
                onMoved: value => Config.options.background.effects.saturation = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "brightness_medium"
                text: Translation.tr("Dim (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.effectOpt.dim
                onMoved: value => Config.options.background.effects.dim = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "vignette"
                text: Translation.tr("Vignette (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.effectOpt.vignette
                onMoved: value => Config.options.background.effects.vignette = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "grain"
                text: Translation.tr("Film grain (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.effectOpt.grain
                onMoved: value => Config.options.background.effects.grain = Math.round(value)
            }
        }
    }

    ContentSection {
        icon: "texture"
        title: Translation.tr("Fluted glass")
        tooltip: Translation.tr("Vertical cylindrical lenses refracted through Snell's law, so the flutes compress toward their seams like real cast glass.")

        ConfigSwitch {
            buttonIcon: "texture"
            text: Translation.tr("Fluted glass")
            checked: page.effectOpt.glass.enable
            onCheckedChanged: {
                Config.options.background.effects.glass.enable = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Style")
            visible: page.effectOpt.glass.enable

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: page.glassPresets
                    EffectCard {
                        required property var modelData
                        label: modelData.name
                        selected: page.glassPresetActive(modelData.preset)
                        glassPreset: modelData.preset
                        filterPreset: ({ filter: "none", saturation: 100, dim: 0, vignette: 0, grain: 0 })
                        onClicked: page.applyGlassPreset(modelData.preset)
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Pattern")
            visible: page.effectOpt.glass.enable

            StyledComboBox {
                Layout.fillWidth: true
                buttonIcon: "pattern"
                textRole: "displayName"
                model: [
                    { displayName: Translation.tr("Straight ribs"), value: "lines" },
                    { displayName: Translation.tr("Rain glass"),    value: "rain" },
                    { displayName: Translation.tr("Chevron"),       value: "chevron" },
                    { displayName: Translation.tr("Bubble grid"),   value: "bubble" }
                ]
                currentIndex: Math.max(0, model.findIndex(item => item.value === page.effectOpt.glass.pattern))
                onActivated: index => {
                    Config.options.background.effects.glass.pattern = model[index].value;
                }
            }

            StyledComboBox {
                Layout.fillWidth: true
                visible: page.effectOpt.glass.pattern !== "bubble"
                buttonIcon: "line_curve"
                textRole: "displayName"
                model: [
                    { displayName: Translation.tr("Lens (round)"),   value: "lens" },
                    { displayName: Translation.tr("Prism (facets)"), value: "prism" },
                    { displayName: Translation.tr("Contour"),        value: "contour" },
                    { displayName: Translation.tr("Cascade"),        value: "cascade" },
                    { displayName: Translation.tr("Flat"),           value: "flat" }
                ]
                currentIndex: Math.max(0, model.findIndex(item => item.value === page.effectOpt.glass.profile))
                onActivated: index => {
                    Config.options.background.effects.glass.profile = model[index].value;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Shape")
            visible: page.effectOpt.glass.enable

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "straighten"
                text: Translation.tr("Flute width (px)")
                usePercentTooltip: false
                from: 4
                to: 160
                value: page.effectOpt.glass.fluteWidth
                onMoved: value => Config.options.background.effects.glass.fluteWidth = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "rotate_right"
                text: Translation.tr("Angle (deg)")
                usePercentTooltip: false
                from: 0
                to: 180
                value: page.effectOpt.glass.angle
                onMoved: value => Config.options.background.effects.glass.angle = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: page.effectOpt.glass.pattern === "rain" || page.effectOpt.glass.pattern === "chevron"
                buttonIcon: "waves"
                text: Translation.tr("Rib bending (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.effectOpt.glass.waviness
                onMoved: value => Config.options.background.effects.glass.waviness = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: page.effectOpt.glass.pattern === "lines"
                buttonIcon: "shuffle"
                text: Translation.tr("Uneven widths (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.effectOpt.glass.irregularity
                onMoved: value => Config.options.background.effects.glass.irregularity = Math.round(value)
            }
        }

        ContentSubsection {
            title: Translation.tr("Optics")
            visible: page.effectOpt.glass.enable

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "lens_blur"
                text: Translation.tr("Refraction (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.effectOpt.glass.distortion
                onMoved: value => Config.options.background.effects.glass.distortion = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "colorize"
                text: Translation.tr("Dispersion (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.effectOpt.glass.dispersion
                onMoved: value => Config.options.background.effects.glass.dispersion = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "motion_blur"
                text: Translation.tr("Smear along rib (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.effectOpt.glass.smear
                onMoved: value => Config.options.background.effects.glass.smear = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "flare"
                text: Translation.tr("Highlights (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.effectOpt.glass.highlights
                onMoved: value => Config.options.background.effects.glass.highlights = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "line_weight"
                text: Translation.tr("Seam shadow (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.effectOpt.glass.shadows
                onMoved: value => Config.options.background.effects.glass.shadows = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "unfold_more"
                text: Translation.tr("Seam bend (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.effectOpt.glass.edges
                onMoved: value => Config.options.background.effects.glass.edges = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "grain"
                text: Translation.tr("Frost (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.effectOpt.glass.frost
                onMoved: value => Config.options.background.effects.glass.frost = Math.round(value)
            }
        }
    }

    ContentSection {
        icon: "music_note"
        title: Translation.tr("Media mode")
        tooltip: Translation.tr("Toggle the mode with a keybind that executes 'quickshell:mediaModeToggle'\nExample: bindd = Super, Z, Toggle media mode, global, quickshell:mediaModeToggle")

        ConfigRow {

            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "monitor"
                text: Translation.tr("Toggle per monitor")
                checked: Config.options.background.mediaMode.togglePerMonitor
                onCheckedChanged: {
                    Config.options.background.mediaMode.togglePerMonitor = checked;
                }
            }

            RippleButtonWithShape {
                Layout.fillWidth: false

                shapeString: Config.options.background.mediaMode.backgroundShape
                implicitWidth: 60
                extraIcon: "edit"

                onClicked: {
                    mediaModeBackgroundShapeLoader.active = !mediaModeBackgroundShapeLoader.active;
                }
                StyledToolTip {
                    text: Translation.tr("Edit the material shape")
                }
            }
        }
        

        Loader { 
            id: mediaModeBackgroundShapeLoader
            active: false
            visible: active
            Layout.fillWidth: true
            sourceComponent: ContentSubsection {
                title: Translation.tr("Background shape")
                
                ConfigSelectionArray {
                    currentValue: Config.options.background.mediaMode.backgroundShape
                    onSelected: newValue => {
                        Config.options.background.mediaMode.backgroundShape = newValue;
                    }
                    options: ([ 
                        "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle",
                        "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", 
                        "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", 
                        "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart" 
                    ]).map(icon => { 
                        return { 
                            displayName: "", 
                            shape: icon, 
                            value: icon 
                        } 
                    })
                }
            }
        }

        ConfigRow {
            ConfigSwitch {
                Layout.fillWidth: false
                buttonIcon: "animation"
                text: Translation.tr("Enable background animation")
                checked: Config.options.background.mediaMode.backgroundAnimation.enable
                onCheckedChanged: {
                    Config.options.background.mediaMode.backgroundAnimation.enable = checked;
                }
            }

            ConfigSpinBox {
                enabled: Config.options.background.mediaMode.backgroundAnimation.enable
                Layout.fillWidth: true
                icon: "speed"
                text: Translation.tr("Speed scale")
                value: Config.options.background.mediaMode.backgroundAnimation.speedScale
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.background.mediaMode.backgroundAnimation.speedScale = value;
                }

                MouseArea {
                    z: -1
                    id: spinBoxMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                }

                StyledToolTip {
                    extraVisibleCondition: spinBoxMouseArea.containsMouse
                    text: Translation.tr("1: very slow | 10: default | 20: 2x speed...")
                }
            }
        }
        
        ConfigSwitch {
            buttonIcon: "format_color_fill"
            text: Translation.tr("Change shell color to match album art")
            checked: Config.options.background.mediaMode.changeShellColor
            onCheckedChanged: {
                Config.options.background.mediaMode.changeShellColor = checked;
            }
        }

        ConfigSpinBox {
            Layout.fillWidth: true
            icon: "opacity"
            text: Translation.tr("Background album art opacity (%)")
            value: Config.options.background.mediaMode.backgroundOpacity
            from: 0
            to: 100
            stepSize: 10
            onValueChanged: {
                Config.options.background.mediaMode.backgroundOpacity = value;
            }
        }


        ContentSubsection {
            title: Translation.tr("Text highlight style")
            ConfigSelectionArray {
                currentValue: Config.options.background.mediaMode.syllable.textHighlightStyle
                onSelected: newValue => {
                    Config.options.background.mediaMode.syllable.textHighlightStyle = newValue;
                }
                options: [
                    {   
                        displayName: Translation.tr("Vertical"),
                        icon: "vertical_distribute",
                        value: 0
                    },
                    {
                        displayName: Translation.tr("Horizontal"),
                        icon: "horizontal_distribute",
                        value: 1
                    }
                ]
            }
        }
        
    }

    ContentSection {
        icon: "widgets"
        title: Translation.tr("Desktop widgets")

        DesktopWidgetManager {}
    }

    ContentSection {
        id: settingsClock
        icon: "clock_loader_40"
        title: Translation.tr("Clock widget styling")

        // Which clock is on the desktop is decided by which widget you add,
        // so these only need to know whether that widget is placed.
        readonly property bool digitalPresent: Config.isWidgetActive("clock_digital")
        readonly property bool cookiePresent: Config.isWidgetActive("clock_cookie")


        ContentSubsection {
            visible: settingsClock.digitalPresent
            title: Translation.tr("Digital clock settings")
            tooltip: Translation.tr("Font width and roundness settings are only available for some fonts like Google Sans Flex")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "vertical_distribute"
                    text: Translation.tr("Vertical")
                    checked: Config.options.background.widgets.clock_digital.vertical
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_digital.vertical = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "animation"
                    text: Translation.tr("Animate time change")
                    checked: Config.options.background.widgets.clock_digital.animateChange
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_digital.animateChange = checked;
                    }
                }
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "date_range"
                    text: Translation.tr("Show date")
                    checked: Config.options.background.widgets.clock_digital.showDate
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_digital.showDate = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "activity_zone"
                    text: Translation.tr("Use adaptive alignment")
                    checked: Config.options.background.widgets.clock_digital.adaptiveAlignment
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_digital.adaptiveAlignment = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Aligns the date and quote to left, center or right depending on its position on the screen.")
                    }
                }
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "colors"
                    text: Translation.tr("Colorful digits")
                    checked: Config.options.background.widgets.clock_digital.colorful
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_digital.colorful = checked;
                    }
                }
                ConfigSwitch {
                    enabled: !Config.options.background.widgets.clock_digital.vertical
                    buttonIcon: "go_to_line"
                    text: Translation.tr("Show colon")
                    checked: Config.options.background.widgets.clock_digital.showColon
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_digital.showColon = checked;
                    }
                }
            }
            

            ConfigSlider {
                text: Translation.tr("Font weight")
                value: Config.options.background.widgets.clock_digital.font.weight
                usePercentTooltip: false
                buttonIcon: "format_bold"
                from: 1
                to: 1000
                stopIndicatorValues: [350]
                onValueChanged: {
                    Config.options.background.widgets.clock_digital.font.weight = value;
                }
            }

            ConfigSlider {
                text: Translation.tr("Font size")
                value: Config.options.background.widgets.clock_digital.font.size
                usePercentTooltip: false
                buttonIcon: "format_size"
                from: 50
                to: 700
                stopIndicatorValues: [90]
                onValueChanged: {
                    Config.options.background.widgets.clock_digital.font.size = value;
                }
            }

            ConfigSlider {
                text: Translation.tr("Font width")
                value: Config.options.background.widgets.clock_digital.font.width
                usePercentTooltip: false
                buttonIcon: "fit_width"
                from: 25
                to: 125
                stopIndicatorValues: [100]
                onValueChanged: {
                    Config.options.background.widgets.clock_digital.font.width = value;
                }
            }
            ConfigSlider {
                text: Translation.tr("Font roundness")
                value: Config.options.background.widgets.clock_digital.font.roundness
                usePercentTooltip: false
                buttonIcon: "line_curve"
                from: 0
                to: 100
                onValueChanged: {
                    Config.options.background.widgets.clock_digital.font.roundness = value;
                }
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Cookie clock settings")

            ConfigSpinBox {
                enabled: Config.options.background.widgets.clock_cookie.backgroundStyle !== "shape"
                icon: "add_triangle"
                text: Translation.tr("Sides")
                value: Config.options.background.widgets.clock_cookie.sides
                from: 0
                to: 40
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.clock_cookie.sides = value;
                }
            }

            ConfigSwitch {
                buttonIcon: "autoplay"
                text: Translation.tr("Constantly rotate")
                checked: Config.options.background.widgets.clock_cookie.constantlyRotate
                onCheckedChanged: {
                    Config.options.background.widgets.clock_cookie.constantlyRotate = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Makes the clock always rotate. This is extremely expensive\n(expect 50% usage on Intel UHD Graphics) and thus impractical.")
                }
            }

            ConfigRow {

                ConfigSwitch {
                    enabled: Config.options.background.widgets.clock_cookie.dialNumberStyle === "dots" || Config.options.background.widgets.clock_cookie.dialNumberStyle === "full"
                    buttonIcon: "brightness_7"
                    text: Translation.tr("Hour marks")
                    checked: Config.options.background.widgets.clock_cookie.hourMarks
                    onEnabledChanged: {
                        checked = Config.options.background.widgets.clock_cookie.hourMarks;
                    }
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_cookie.hourMarks = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Can only be turned on using the 'Dots' or 'Full' dial style for aesthetic reasons")
                    }
                }

                ConfigSwitch {
                    enabled: Config.options.background.widgets.clock_cookie.dialNumberStyle !== "numbers"
                    buttonIcon: "timer_10"
                    text: Translation.tr("Digits in the middle")
                    checked: Config.options.background.widgets.clock_cookie.timeIndicators
                    onEnabledChanged: {
                        checked = Config.options.background.widgets.clock_cookie.timeIndicators;
                    }
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_cookie.timeIndicators = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Can't be turned on when using 'Numbers' dial style for aesthetic reasons")
                    }
                }
            }

            ConfigRow {
                Layout.fillWidth: false
                
                ConfigSwitch {
                    buttonIcon: "wand_stars"
                    text: Translation.tr("Auto style the cookie clock preset")
                    checked: Config.options.background.widgets.clock_cookie.aiStyling
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_cookie.aiStyling = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Uses the preferred AI to categorize the wallpaper then picks a preset based on it.\nYou'll need to set API key on the left sidebar first.\nImages are downscaled for performance, but just to be safe,\ndo not select wallpapers with sensitive information.\nBoth AI models does the same thing, but Gemini has strict quotas.")
                    }
                }

                StyledText {
                    Layout.rightMargin: 6
                    text: Translation.tr("with")
                    opacity: Config.options.background.widgets.clock_cookie.aiStyling ? 1 : 0.4
                }

                ConfigSelectionArray {
                    enabled: Config.options.background.widgets.clock_cookie.aiStyling
                    currentValue: Config.options.background.widgets.clock_cookie.aiStylingModel
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_cookie.aiStylingModel = newValue;
                    }
                    options: [
                        {
                            displayName: "Gemini",
                            symbol: "google-gemini-symbolic",
                            value: "gemini"
                        },
                        {
                            displayName: "OpenRouter",
                            symbol: "openrouter-symbolic",
                            value: "openrouter"
                        }
                    ]
                }
            }
        }

        

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Dial style")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_cookie.dialNumberStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock_cookie.dialNumberStyle = newValue;
                    if (newValue !== "dots" && newValue !== "full") {
                        Config.options.background.widgets.clock_cookie.hourMarks = false;
                    }
                    if (newValue === "numbers") {
                        Config.options.background.widgets.clock_cookie.timeIndicators = false;
                    }
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "none"
                    },
                    {
                        displayName: Translation.tr("Dots"),
                        icon: "graph_6",
                        value: "dots"
                    },
                    {
                        displayName: Translation.tr("Full"),
                        icon: "history_toggle_off",
                        value: "full"
                    },
                    {
                        displayName: Translation.tr("Numbers"),
                        icon: "counter_1",
                        value: "numbers"
                    }
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Hour hand")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_cookie.hourHandStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock_cookie.hourHandStyle = newValue;
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "hide"
                    },
                    {
                        displayName: Translation.tr("Classic"),
                        icon: "radio",
                        value: "classic"
                    },
                    {
                        displayName: Translation.tr("Hollow"),
                        icon: "circle",
                        value: "hollow"
                    },
                    {
                        displayName: Translation.tr("Fill"),
                        icon: "eraser_size_5",
                        value: "fill"
                    },
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Minute hand")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_cookie.minuteHandStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock_cookie.minuteHandStyle = newValue;
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "hide"
                    },
                    {
                        displayName: Translation.tr("Classic"),
                        icon: "radio",
                        value: "classic"
                    },
                    {
                        displayName: Translation.tr("Thin"),
                        icon: "line_end",
                        value: "thin"
                    },
                    {
                        displayName: Translation.tr("Medium"),
                        icon: "eraser_size_2",
                        value: "medium"
                    },
                    {
                        displayName: Translation.tr("Bold"),
                        icon: "eraser_size_4",
                        value: "bold"
                    },
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Second hand")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_cookie.secondHandStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock_cookie.secondHandStyle = newValue;
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "hide"
                    },
                    {
                        displayName: Translation.tr("Classic"),
                        icon: "radio",
                        value: "classic"
                    },
                    {
                        displayName: Translation.tr("Line"),
                        icon: "line_end",
                        value: "line"
                    },
                    {
                        displayName: Translation.tr("Dot"),
                        icon: "adjust",
                        value: "dot"
                    },
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Date style")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_cookie.dateStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock_cookie.dateStyle = newValue;
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "hide"
                    },
                    {
                        displayName: Translation.tr("Bubble"),
                        icon: "bubble_chart",
                        value: "bubble"
                    },
                    {
                        displayName: Translation.tr("Border"),
                        icon: "rotate_right",
                        value: "border"
                    },
                    {
                        displayName: Translation.tr("Rect"),
                        icon: "rectangle",
                        value: "rect"
                    }
                ]
            }
        }


        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Background style")

            ConfigRow {
                spacing: 10
                ConfigSelectionArray {
                    Layout.fillWidth: false
                    currentValue: Config.options.background.widgets.clock_cookie.backgroundStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_cookie.backgroundStyle = newValue;
                    }
                    options: [
                        {
                            displayName: "",
                            icon: "block",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Sine"),
                            icon: "waves",
                            value: "sine"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Shape"),
                            icon: "shape_line",
                            value: "shape"
                        },
                    ]
                }

                RippleButtonWithShape {
                    visible: Config.options.background.widgets.clock_cookie.backgroundStyle == "shape"
                    Layout.fillWidth: false

                    shapeString: Config.options.background.widgets.clock_cookie.backgroundShape
                    implicitWidth: 60
                    extraIcon: "edit"

                    onClicked: {
                        backgroundShapeLoader.active = !backgroundShapeLoader.active;
                    }
                    StyledToolTip {
                        text: Translation.tr("Edit the material shape")
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }   
        }

        Loader { 
            id: backgroundShapeLoader
            active: false
            visible: active
            Layout.fillWidth: true
            sourceComponent: ContentSubsection {
                title: Translation.tr("Background shape")
                
                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock_cookie.backgroundShape
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_cookie.backgroundShape = newValue;
                    }
                    options: ([ 
                        "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle",
                        "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", 
                        "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", 
                        "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart" 
                    ]).map(icon => { 
                        return { 
                            displayName: "", 
                            shape: icon, 
                            value: icon 
                        } 
                    })
                }
            }
        }
        

        ContentSubsection {
            title: Translation.tr("Quote")

            ConfigSwitch {
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.background.widgets.clock_cookie.quoteEnable
                onCheckedChanged: {
                    Config.options.background.widgets.clock_cookie.quoteEnable = checked;
                }
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Quote")
                text: Config.options.background.widgets.clock_cookie.quoteText
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.background.widgets.clock_cookie.quoteText = text;
                }
            }
        }
    }

    ContentSection {
        icon: "weather_mix"
        title: Translation.tr("Widget: Weather")

    }

    ContentSection {
        icon: "music_cast"
        title: Translation.tr("Widget: Media")
        tooltip: Translation.tr("You can reset the media player by middle-clicking on the widget in case of media source errors")



        ConfigRow {
            RippleButtonWithShape {
                Layout.fillWidth: false
                shapeString: Config.options.background.widgets.media.backgroundShape
                implicitWidth: 60
                extraIcon: "edit"

                onClicked: {
                    mediaBackgroundShapeLoader.active = !mediaBackgroundShapeLoader.active;
                }
                StyledToolTip {
                    text: Translation.tr("Edit the material shape")
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        Loader { 
            id: mediaBackgroundShapeLoader
            active: false
            visible: active
            Layout.fillWidth: true
            sourceComponent: ContentSubsection {
                title: Translation.tr("Background shape")
                
                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.media.backgroundShape
                    onSelected: newValue => {
                        Config.options.background.widgets.media.backgroundShape = newValue;
                    }
                    options: ([ 
                        "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle",
                        "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", 
                        "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", 
                        "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart" 
                    ]).map(icon => { 
                        return { 
                            displayName: "", 
                            shape: icon, 
                            value: icon 
                        } 
                    })
                }
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "opacity"
                text: Translation.tr("Use album colors")
                checked: Config.options.background.widgets.media.useAlbumColors
                onCheckedChanged: {
                    Config.options.background.widgets.media.useAlbumColors = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "colors"
                text: Translation.tr("Tint art cover")
                checked: Config.options.background.widgets.media.tintArtCover
                onCheckedChanged: {
                    Config.options.background.widgets.media.tintArtCover = checked;
                }
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "block"
                text: Translation.tr("Hide all controls")
                checked: Config.options.background.widgets.media.hideAllButtons
                onCheckedChanged: {
                    Config.options.background.widgets.media.hideAllButtons = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Buttons will only be visible on hover")
                }
            }
            ConfigSwitch {
                buttonIcon: "skip_previous"
                text: Translation.tr("Show previous toggle")
                checked: Config.options.background.widgets.media.showPreviousToggle
                onCheckedChanged: {
                    Config.options.background.widgets.media.showPreviousToggle = checked;
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Glow effect")
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "backlight_high"
                    text: Translation.tr("Enable")
                    checked: Config.options.background.widgets.media.glow.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.media.glow.enable = checked;
                    }
                }
                ConfigSpinBox {
                    from: 5
                    to: 100
                    stepSize: 5
                    icon: "brightness_5"
                    text: Translation.tr("Brightness (%)")
                    value: Config.options.background.widgets.media.glow.brightness
                    onValueChanged: {
                        Config.options.background.widgets.media.glow.brightness = value;
                    }
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Visualizer")

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "bar_chart"
                    text: Translation.tr("Enable")
                    checked: Config.options.background.widgets.media.visualizer.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.media.visualizer.enable = checked;
                    }
                }
                
                ConfigSpinBox {
                    from: 0
                    to: 100
                    stepSize: 5
                    icon: "opacity"
                    text: Translation.tr("Opacity (%)")
                    value: Config.options.background.widgets.media.visualizer.opacity * 100
                    onValueChanged: {
                        Config.options.background.widgets.media.visualizer.opacity = value / 100;
                    }
                }
            }
            
            ConfigRow {
                uniform: true
                
                ConfigSpinBox {
                    from: 0
                    to: 5
                    stepSize: 1
                    icon: "rounded_corner"
                    text: Translation.tr("Smoothing")
                    value: Config.options.background.widgets.media.visualizer.smoothing
                    onValueChanged: {
                        Config.options.background.widgets.media.visualizer.smoothing = value;
                    }
                }

                ConfigSpinBox {
                    from: 0
                    to: 10
                    stepSize: 1
                    icon: "blur_on"
                    text: Translation.tr("Blur")
                    value: Config.options.background.widgets.media.visualizer.blur
                    onValueChanged: {
                        Config.options.background.widgets.media.visualizer.blur = value;
                    }
                }
            }

        }
    }
}
