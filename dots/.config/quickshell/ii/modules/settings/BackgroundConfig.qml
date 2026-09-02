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
    
    // A video wallpaper is swapped by mpvpaper, which knows nothing about the
    // transition set here.
    readonly property bool wallpaperIsVideo: Wallpapers.isVideoFile((Config.options.background.wallpaperPath ?? "").toLowerCase())

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

            // Kept at full strength while the controls below it dim: a disabled
            // control that cannot say why it is disabled is its own kind of
            // silence, and this one is only off because of the wallpaper that
            // happens to be set right now.
            StyledText {
                visible: page.wallpaperIsVideo
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("A video wallpaper is swapped straight in by mpvpaper, which cannot play a transition. This applies to image wallpapers.")
            }

            StyledComboBox {
                Layout.fillWidth: true
                enabled: !page.wallpaperIsVideo
                opacity: enabled ? 1 : 0.4
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
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
                enabled: !page.wallpaperIsVideo
                opacity: enabled ? 1 : 0.4
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
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

    ContentSection {
        icon: "category"
        title: Translation.tr("Wallpaper shape")
        tooltip: Translation.tr("Custom shape the wallpaper in Material Icons. Gray out subject depth when enabled.")

        ConfigRow {
            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "interests"
                text: Translation.tr("Enable shape mask")
                checked: Config.options.background.shape.enable
                onCheckedChanged: {
                    Config.options.background.shape.enable = checked;
                    if (checked) {
                        Config.options.background.depth.enable = false;
                    }
                }
            }

            RippleButtonWithShape {
                Layout.fillWidth: false
                enabled: Config.options.background.shape.enable
                shapeString: Config.options.background.shape.style
                implicitWidth: 60
                extraIcon: "edit"

                onClicked: {
                    wallpaperShapeShapeLoader.active = !wallpaperShapeShapeLoader.active;
                }
                StyledToolTip {
                    text: Translation.tr("Edit the material shape")
                }
            }
        }

        Loader { 
            id: wallpaperShapeShapeLoader
            active: false
            visible: active
            Layout.fillWidth: true
            sourceComponent: ContentSubsection {
                title: Translation.tr("Background shape")
                
                ConfigSelectionArray {
                    currentValue: Config.options.background.shape.style
                    onSelected: newValue => {
                        Config.options.background.shape.style = newValue;
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
            title: Translation.tr("Background color")
            visible: Config.options.background.shape.enable

            // Reusing a text field or color picker if available. Otherwise just text field.
            ConfigTextField {
                Layout.fillWidth: true
                icon: "palette"
                text: Translation.tr("Hex Color or @colLayer0")
                inputText: Config.options.background.shape.backgroundColor
                onInputTextChanged: {
                    if (Config.options.background.shape.backgroundColor !== inputText) {
                        Config.options.background.shape.backgroundColor = inputText;
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 8
                spacing: 12

                StyledText {
                    text: Translation.tr("Recommended")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    Layout.rightMargin: 8
                }

                Repeater {
                    model: [
                        { name: "colLayer0", col: Appearance.colors.colLayer0 },
                        { name: "colLayer1", col: Appearance.colors.colLayer1 },
                        { name: "colLayer2", col: Appearance.colors.colLayer2 },
                        { name: "colPrimaryContainer", col: Appearance.colors.colPrimaryContainer },
                        { name: "colSecondaryContainer", col: Appearance.colors.colSecondaryContainer },
                        { name: "colTertiaryContainer", col: Appearance.colors.colTertiaryContainer }
                    ]

                    delegate: Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: modelData.col
                        border.color: Appearance.colors.colOutlineVariant
                        border.width: 1

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Config.options.background.shape.backgroundColor = "@" + modelData.name;
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true } // spacer
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Shape size (%)")
                usePercentTooltip: false
                from: 10
                to: 150
                value: Config.options.background.shape.size * 100
                onMoved: value => Config.options.background.shape.size = Math.round(value) / 100
            }
        }
    }

    // ---- Wallpaper effects ----------------------------------------------
    // The filter list and its maths mirror what custom ROMs ship (risingOS's
    // SystemUI WallpaperUtils, inherited by Evolution X, Matrixx, Mist,
    // Lunaris, PenguinOS). Fluted glass is ours.
    readonly property var effectOpt: Config.options.background.effects
    readonly property var weatherOpt: Config.options.background.weatherEffects

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
        icon: "filter_center_focus"
        title: Translation.tr("Subject depth")
        tooltip: Translation.tr("Cuts the foreground subject out of the wallpaper and draws it back on top of the desktop widgets, so a clock can sit behind a shoulder.\nThe cutout is found by a segmentation model that runs once per wallpaper, on the CPU, and is cached afterwards. A video wallpaper is matted frame by frame, which takes minutes rather than seconds, and the shell plays it in place of mpvpaper so the matte cannot drift from the frame.\nEach widget picks its own side from its right-click menu; behind is the default.")

        enabled: !Config.options.background.shape.enable
        opacity: enabled ? 1 : 0.4
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        ConfigSwitch {
            buttonIcon: "filter_center_focus"
            text: Translation.tr("Layer widgets into the wallpaper")
            checked: Config.options.background.depth.enable
            onCheckedChanged: {
                Config.options.background.depth.enable = checked;
            }
        }

        ContentSubsection {
            visible: Config.options.background.depth.enable
            title: Translation.tr("Subject")

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    text: {
                        if (!WallpaperSubject.wallpaperUsable)
                            return Translation.tr("No wallpaper to cut a subject out of yet.");
                        if (WallpaperSubject.declined)
                            return Translation.tr("Cancelled for this wallpaper. It stays uncut - reselecting it or restarting the shell will not start it again.");
                        if (WallpaperSubject.working && WallpaperSubject.wallpaperIsVideo) {
                            if (WallpaperSubject.progressTotal === 0)
                                return Translation.tr("Reading the video…");
                            // How long this takes is set by how much the video
                            // moves, not its length: a near-still loop reuses
                            // one matte for a dozen frames, one that really
                            // moves is recut every frame. Minutes either way,
                            // so the count and the estimate are the difference
                            // between working and hung.
                            const left = WallpaperSubject.etaSeconds;
                            const when = left > 90
                                ? Translation.tr("about %1 minutes left").arg(Math.round(left / 60))
                                : Translation.tr("nearly done");
                            return Translation.tr("Matting frame %1 of %2, %3. Runs once per wallpaper at lowest priority; the desktop stays usable, and closing this window will not stop it.")
                                .arg(WallpaperSubject.progressFrames)
                                .arg(WallpaperSubject.progressTotal)
                                .arg(when);
                        }
                        if (WallpaperSubject.working)
                            return Translation.tr("Looking for the subject…");
                        if (WallpaperSubject.error.length > 0)
                            return WallpaperSubject.error;
                        if (WallpaperSubject.hasSubject && WallpaperSubject.wallpaperIsVideo)
                            return Translation.tr("Subject matted through the video, covering %1% of a typical frame. The shell plays the wallpaper itself while this is on, in place of mpvpaper.")
                                .arg(Math.round(WallpaperSubject.coverage * 100));
                        if (WallpaperSubject.hasSubject)
                            return Translation.tr("Subject found, covering %1% of the wallpaper.")
                                .arg(Math.round(WallpaperSubject.coverage * 100));
                        if (WallpaperSubject.wallpaperIsVideo)
                            return Translation.tr("Nothing stands out from the background in this video, so the widgets stay flat.");
                        return Translation.tr("No subject stands out in this wallpaper, so the widgets stay flat.");
                    }
                }

                // Shown the moment a run starts, before there is any frame
                // count to report: a bake can be minutes, and the first of them
                // are the ones you are most likely to want back.
                RippleButtonWithIcon {
                    visible: WallpaperSubject.working
                    materialIcon: "close"
                    mainText: Translation.tr("Cancel")
                    onClicked: WallpaperSubject.cancel()
                }

                // Only a failed run is worth retrying on its own. A wallpaper
                // the model simply found nothing in will find nothing again.
                RippleButtonWithIcon {
                    visible: WallpaperSubject.error.length > 0 && !WallpaperSubject.working
                    materialIcon: "refresh"
                    mainText: Translation.tr("Try again")
                    onClicked: WallpaperSubject.generate()
                }

                // The way back from a cancel, and the way to redo a cutout you
                // are not happy with.
                RippleButtonWithIcon {
                    visible: !WallpaperSubject.working
                        && (WallpaperSubject.declined || WallpaperSubject.hasSubject)
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Rebake")
                    onClicked: WallpaperSubject.rebake()
                }
            }

            // Every window watching this wallpaper reads the same status file,
            // so this fills whether or not this window is the one doing the
            // work. Wavy because it is the M3 Expressive in-progress
            // indicator, and this is very much in progress.
            StyledProgressBar {
                Layout.fillWidth: true
                visible: WallpaperSubject.working && WallpaperSubject.progressTotal > 0
                wavy: true
                from: 0
                to: Math.max(1, WallpaperSubject.progressTotal)
                value: WallpaperSubject.progressFrames
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
        icon: "rainy"
        title: Translation.tr("Weather effects")
        tooltip: Translation.tr("Android's live weather wallpaper, ported shader for shader from AOSP.\nIt draws over everything on the desktop plane - the wallpaper effects, the widgets and subject depth all sit underneath.\nUnlike the wallpaper effects, this one animates: it redraws the whole desktop every frame for as long as it is on.")

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "rainy"
            text: Translation.tr("Live weather effects")
            checked: page.weatherOpt.enable
            onCheckedChanged: {
                Config.options.background.weatherEffects.enable = checked;
            }
        }

        ConfigSwitch {
            Layout.fillWidth: true
            visible: page.weatherOpt.enable
            buttonIcon: "cloud_sync"
            text: Translation.tr("Follow the current weather")
            checked: page.weatherOpt.followWeather
            onCheckedChanged: {
                Config.options.background.weatherEffects.followWeather = checked;
            }
        }

        ContentSubsection {
            visible: page.weatherOpt.enable && !page.weatherOpt.followWeather
            title: Translation.tr("Effect")

            ConfigSelectionArray {
                currentValue: page.weatherOpt.effect
                onSelected: newValue => {
                    Config.options.background.weatherEffects.effect = newValue;
                }
                options: [
                    { displayName: Translation.tr("Rain"), icon: "rainy", value: "rain" },
                    { displayName: Translation.tr("Fog"),  icon: "foggy", value: "fog" },
                    { displayName: Translation.tr("Snow"), icon: "weather_snowy", value: "snow" },
                    { displayName: Translation.tr("Sun"),  icon: "clear_day", value: "sun" }
                ]
            }
        }

        ContentSubsection {
            visible: page.weatherOpt.enable && page.weatherOpt.followWeather
            title: Translation.tr("Right now")
            tooltip: Translation.tr("The effect follows the conditions the weather widget is fetching. Nothing draws when it is clear out.")

            StyledText {
                Layout.fillWidth: true
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                text: Weather.liveEffect === "rain" ? Translation.tr("Raining - %1").arg(Weather.data.wDesc)
                    : Weather.liveEffect === "fog" ? Translation.tr("Foggy - %1").arg(Weather.data.wDesc)
                    : Weather.liveEffect === "snow" ? Translation.tr("Snowing - %1").arg(Weather.data.wDesc)
                    : Weather.liveEffect === "sun" ? Translation.tr("Sunny - %1").arg(Weather.data.wDesc)
                    : Translation.tr("Nothing to draw - %1").arg(Weather.data.wDesc)
            }
        }

        ContentSubsection {
            visible: page.weatherOpt.enable
            title: Translation.tr("Adjustments")

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "opacity"
                text: page.weatherOpt.followWeather
                    ? Translation.tr("Intensity ceiling (%)")
                    : Translation.tr("Intensity (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: page.weatherOpt.intensity
                onMoved: value => Config.options.background.weatherEffects.intensity = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "grain"
                text: Translation.tr("Particle scale (%)")
                // AOSP picks its grid from the display width in dp, which is
                // calibrated for a phone at arm's length.
                usePercentTooltip: false
                from: 50
                to: 200
                value: page.weatherOpt.scale
                onMoved: value => Config.options.background.weatherEffects.scale = Math.round(value)
            }

            // The per-effect lookup table Android grades each effect through:
            // cold blue for rain, a grey wash for fog, a cool cast for snow.
            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "palette"
                text: Translation.tr("Colour grading")
                checked: page.weatherOpt.colorGrading
                onCheckedChanged: {
                    Config.options.background.weatherEffects.colorGrading = checked;
                }
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
        title: Translation.tr("Widget Manager")
        icon: "widgets"
        
        ShortcutBox {
            Layout.fillWidth: true
            value: Translation.tr("Desktop Widgets configuration")
            targetPageId: "widgets"
            targetSectionTitle: Translation.tr("Widget Manager")
        }
    }
}
