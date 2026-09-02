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

    // Every wallpaper feature below configures the desktop and the lock
    // screen independently. One card each, not two: the segmented control at
    // the top picks which of the two the controls underneath are editing.
    // That choice is view state, not config - nothing about it is persisted,
    // and the lock screen mirrors the desktop until told otherwise, so the
    // common case is one card that looks exactly like it did before.
    component TargetedSection: ContentSection {
        id: section
        required property var desktopOpt
        required property var lockOpt

        property string editTarget: "desktop"
        readonly property bool editingDesktop: section.editTarget === "desktop"
        readonly property var opt: section.editingDesktop ? section.desktopOpt : section.lockOpt
        // A mirroring lock screen has nothing of its own to show, so the
        // controls below hide themselves rather than lie about what they edit.
        readonly property bool collapsed: !section.editingDesktop && section.lockOpt.sync

        ConfigSelectionArray {
            currentValue: section.editTarget
            onSelected: newValue => section.editTarget = newValue
            options: [
                { displayName: Translation.tr("Desktop"), icon: "desktop_windows", value: "desktop" },
                { displayName: Translation.tr("Lock screen"), icon: "lock", value: "lock" }
            ]
        }

        ConfigSwitch {
            visible: !section.editingDesktop
            Layout.fillWidth: true
            buttonIcon: "sync"
            text: Translation.tr("Match desktop")
            checked: section.lockOpt.sync
            onCheckedChanged: section.lockOpt.sync = checked
        }
    }

    component ShapeMaskSection: TargetedSection {
        id: shapeSection

        ConfigRow {
            visible: !shapeSection.collapsed

            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "interests"
                text: Translation.tr("Enable shape mask")
                checked: shapeSection.opt.enable
                onCheckedChanged: {
                    shapeSection.opt.enable = checked;
                    // Subject depth wants the same pixels, and only on the
                    // desktop does it have widgets to layer into.
                    if (checked && shapeSection.editingDesktop) {
                        Config.options.background.depth.desktop.enable = false;
                    }
                }
            }

            RippleButtonWithShape {
                Layout.fillWidth: false
                enabled: shapeSection.opt.enable
                shapeString: shapeSection.opt.style
                implicitWidth: 60
                extraIcon: "edit"

                onClicked: {
                    shapeStyleLoader.active = !shapeStyleLoader.active;
                }
                StyledToolTip {
                    text: Translation.tr("Edit the material shape")
                }
            }
        }

        Loader {
            id: shapeStyleLoader
            active: false
            visible: active && !shapeSection.collapsed
            Layout.fillWidth: true
            sourceComponent: ContentSubsection {
                title: Translation.tr("Background shape")

                ConfigSelectionArray {
                    currentValue: shapeSection.opt.style
                    onSelected: newValue => {
                        shapeSection.opt.style = newValue;
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
            visible: !shapeSection.collapsed && shapeSection.opt.enable

            // Reusing a text field or color picker if available. Otherwise just text field.
            ConfigTextField {
                Layout.fillWidth: true
                icon: "palette"
                text: Translation.tr("Hex Color or @colLayer0")
                inputText: shapeSection.opt.backgroundColor
                onInputTextChanged: {
                    if (shapeSection.opt.backgroundColor !== inputText) {
                        shapeSection.opt.backgroundColor = inputText;
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
                                shapeSection.opt.backgroundColor = "@" + modelData.name;
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
                value: shapeSection.opt.size * 100
                onMoved: value => shapeSection.opt.size = Math.round(value) / 100
            }
        }
    }

    ShapeMaskSection {
        icon: "category"
        title: Translation.tr("Wallpaper shape")
        tooltip: Translation.tr("Custom shape the wallpaper in Material Icons. Grays out subject depth when enabled.\nDesktop and lock screen are set separately; the lock screen matches the desktop until you turn that off.")
        desktopOpt: Config.options.background.shape.desktop
        lockOpt: Config.options.background.shape.lock
    }

    // ---- Wallpaper effects ----------------------------------------------
    // The filter list and its maths mirror what custom ROMs ship (risingOS's
    // SystemUI WallpaperUtils, inherited by Evolution X, Matrixx, Mist,
    // Lunaris, PenguinOS). Fluted glass is ours.
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

    function applyGlassPreset(glassOpt, preset) {
        for (const key in preset)
            glassOpt[key] = preset[key];
        glassOpt.enable = true;
    }

    function glassPresetActive(glassOpt, preset) {
        return glassOpt.enable && Object.keys(preset).every(key => glassOpt[key] === preset[key]);
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

    component DepthSection: TargetedSection {
        id: depthSection
        // Shape mask and subject depth both claim the same pixels, so
        // whichever shape mask covers the target being edited wins.
        readonly property bool shapeConflict: depthSection.editingDesktop
            ? Config.options.background.shape.desktop.enable
            : (Config.options.background.shape.lock.sync
                ? Config.options.background.shape.desktop.enable
                : Config.options.background.shape.lock.enable)

        enabled: !depthSection.shapeConflict
        opacity: enabled ? 1 : 0.4
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        ConfigSwitch {
            visible: !depthSection.collapsed
            buttonIcon: "filter_center_focus"
            text: Translation.tr("Layer widgets into the wallpaper")
            checked: depthSection.opt.enable
            onCheckedChanged: {
                depthSection.opt.enable = checked;
            }
        }
    }

    DepthSection {
        icon: "filter_center_focus"
        title: Translation.tr("Subject depth")
        tooltip: Translation.tr("Cuts the foreground subject out of the wallpaper and draws it back on top of the widgets, so a clock can sit behind a shoulder.\nThe cutout is found by a segmentation model that runs once per wallpaper, on the CPU, and is cached afterwards. A video wallpaper is matted frame by frame, which takes minutes rather than seconds, and the shell plays it in place of mpvpaper so the matte cannot drift from the frame.\nEach widget picks its own side from its right-click menu; behind is the default.")
        desktopOpt: Config.options.background.depth.desktop
        lockOpt: Config.options.background.depth.lock

        ContentSubsection {
            // The cutout is one shared resource, so its status is worth
            // showing whenever either context is actually using it.
            visible: WallpaperSubject.enabled
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

    component WallpaperEffectsSection: TargetedSection {
        id: fxSection

        ContentSubsection {
            visible: !fxSection.collapsed
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
                        selected: fxSection.opt.filter === modelData.value
                        // Preview the filter alone, with the adjustments off.
                        filterPreset: ({
                            filter: modelData.value,
                            saturation: 100, dim: 0, vignette: 0, grain: 0
                        })
                        onClicked: {
                            fxSection.opt.filter = modelData.value;
                        }
                    }
                }
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: fxSection.opt.filter === "posterize"
                buttonIcon: "gradient"
                text: Translation.tr("Posterize levels")
                usePercentTooltip: false
                from: 2
                to: 16
                value: fxSection.opt.posterizeLevels
                onMoved: value => fxSection.opt.posterizeLevels = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: fxSection.opt.filter === "pixelate"
                buttonIcon: "grid_on"
                text: Translation.tr("Pixel size (px)")
                usePercentTooltip: false
                from: 2
                to: 40
                value: fxSection.opt.pixelSize
                onMoved: value => fxSection.opt.pixelSize = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: fxSection.opt.filter === "sharpen"
                buttonIcon: "deblur"
                text: Translation.tr("Sharpen amount")
                usePercentTooltip: false
                from: 0
                to: 300
                value: fxSection.opt.sharpen * 100
                onMoved: value => fxSection.opt.sharpen = Math.round(value) / 100
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: fxSection.opt.filter === "chromatic"
                buttonIcon: "blur_linear"
                text: Translation.tr("Colour separation (px)")
                usePercentTooltip: false
                from: 1
                to: 40
                value: fxSection.opt.chromatic
                onMoved: value => fxSection.opt.chromatic = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: fxSection.opt.filter === "radialBlur"
                buttonIcon: "blur_circular"
                text: Translation.tr("Radial blur (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: fxSection.opt.radialBlur
                onMoved: value => fxSection.opt.radialBlur = Math.round(value)
            }
        }

        ContentSubsection {
            visible: !fxSection.collapsed
            title: Translation.tr("Blur")

            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "blur_on"
                text: Translation.tr("Blur the wallpaper")
                checked: fxSection.opt.blur.enable
                onCheckedChanged: {
                    fxSection.opt.blur.enable = checked;
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: fxSection.opt.blur.enable

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
                        selected: fxSection.opt.blur.style === modelData.value
                        previewBlur: modelData.radius < 0 ? fxSection.opt.blur.radius : modelData.radius
                        filterPreset: ({ filter: "none", saturation: 100, dim: 0, vignette: 0, grain: 0 })
                        onClicked: {
                            fxSection.opt.blur.style = modelData.value;
                        }
                    }
                }
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: fxSection.opt.blur.enable && fxSection.opt.blur.style === "custom"
                buttonIcon: "blur_on"
                text: Translation.tr("Blur radius")
                usePercentTooltip: false
                from: 1
                to: 150
                value: fxSection.opt.blur.radius
                onMoved: value => fxSection.opt.blur.radius = Math.round(value)
            }
        }

        ContentSubsection {
            visible: !fxSection.collapsed
            title: Translation.tr("Adjustments")

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "palette"
                text: Translation.tr("Saturation (%)")
                usePercentTooltip: false
                from: 50
                to: 200
                value: fxSection.opt.saturation
                onMoved: value => fxSection.opt.saturation = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "brightness_medium"
                text: Translation.tr("Dim (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: fxSection.opt.dim
                onMoved: value => fxSection.opt.dim = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "vignette"
                text: Translation.tr("Vignette (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: fxSection.opt.vignette
                onMoved: value => fxSection.opt.vignette = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "grain"
                text: Translation.tr("Film grain (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: fxSection.opt.grain
                onMoved: value => fxSection.opt.grain = Math.round(value)
            }
        }
    }

    WallpaperEffectsSection {
        icon: "auto_fix"
        title: Translation.tr("Wallpaper effects")
        tooltip: Translation.tr("Applied to the wallpaper image only - widgets, panels and the dock are untouched.\nA video wallpaper cannot be filtered.\nEach effect is a GPU pass over the whole wallpaper, so stacking several costs frames on weak hardware.")
        desktopOpt: Config.options.background.effects.desktop
        lockOpt: Config.options.background.effects.lock
    }

    component WeatherEffectsSection: TargetedSection {
        id: weatherSection

        ConfigSwitch {
            visible: !weatherSection.collapsed
            Layout.fillWidth: true
            buttonIcon: "rainy"
            text: Translation.tr("Live weather effects")
            checked: weatherSection.opt.enable
            onCheckedChanged: {
                weatherSection.opt.enable = checked;
            }
        }

        ConfigSwitch {
            Layout.fillWidth: true
            visible: !weatherSection.collapsed && weatherSection.opt.enable
            buttonIcon: "cloud_sync"
            text: Translation.tr("Follow the current weather")
            checked: weatherSection.opt.followWeather
            onCheckedChanged: {
                weatherSection.opt.followWeather = checked;
            }
        }

        ContentSubsection {
            visible: !weatherSection.collapsed && weatherSection.opt.enable && !weatherSection.opt.followWeather
            title: Translation.tr("Effect")

            ConfigSelectionArray {
                currentValue: weatherSection.opt.effect
                onSelected: newValue => {
                    weatherSection.opt.effect = newValue;
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
            visible: !weatherSection.collapsed && weatherSection.opt.enable && weatherSection.opt.followWeather
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
            visible: !weatherSection.collapsed && weatherSection.opt.enable
            title: Translation.tr("Adjustments")
            tooltip: Translation.tr("Intensity is what the conditions drive, so it becomes a readout while following the weather.\nParticle scale is not a weather property - AOSP keeps its grid fixed and varies intensity and fall speed only - so it stays yours to set for your monitor's size and how far away you sit.")

            // A readout, not a control, while the weather owns the value. The
            // binding has to be reinstated on the way in because dragging a
            // QtQuick Slider writes `value` directly and kills whatever
            // binding was on it.
            ConfigSlider {
                id: weatherIntensitySlider
                Layout.fillWidth: true
                buttonIcon: "opacity"
                text: weatherSection.opt.followWeather
                    ? Translation.tr("Intensity (%) - from weather")
                    : Translation.tr("Intensity (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: weatherSection.opt.intensity
                enabled: !weatherSection.opt.followWeather
                opacity: enabled ? 1 : 0.4
                onMoved: value => weatherSection.opt.intensity = Math.round(value)
            }

            Binding {
                target: weatherIntensitySlider
                property: "value"
                value: Math.round(Weather.liveIntensity * 100)
                when: weatherSection.opt.followWeather
            }

            // Left editable in both modes on purpose: AOSP derives its grid
            // from the display, never from the conditions, so there is nothing
            // for the weather to say here.
            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "grain"
                text: Translation.tr("Particle scale (%)")
                usePercentTooltip: false
                from: 50
                to: 200
                value: weatherSection.opt.scale
                onMoved: value => weatherSection.opt.scale = Math.round(value)
            }

            // The per-effect lookup table Android grades each effect through:
            // cold blue for rain, a grey wash for fog, a cool cast for snow.
            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "palette"
                text: Translation.tr("Colour grading")
                checked: weatherSection.opt.colorGrading
                onCheckedChanged: {
                    weatherSection.opt.colorGrading = checked;
                }
            }
        }
    }

    WeatherEffectsSection {
        icon: "rainy"
        title: Translation.tr("Weather effects")
        tooltip: Translation.tr("Android's live weather wallpaper, ported shader for shader from AOSP.\nIt draws over everything on the desktop plane - the wallpaper effects, the widgets and subject depth all sit underneath.\nUnlike the wallpaper effects, this one animates: it redraws the whole desktop every frame for as long as it is on.")
        desktopOpt: Config.options.background.weatherEffects.desktop
        lockOpt: Config.options.background.weatherEffects.lock
    }

    // Fluted glass targets on its own, separately from the other wallpaper
    // effects - it is subtle enough to want running everywhere far more
    // often than a filter is.
    component GlassSection: TargetedSection {
        id: glassSection

        ConfigSwitch {
            visible: !glassSection.collapsed
            buttonIcon: "texture"
            text: Translation.tr("Fluted glass")
            checked: glassSection.opt.enable
            onCheckedChanged: {
                glassSection.opt.enable = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Style")
            visible: !glassSection.collapsed && glassSection.opt.enable

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: page.glassPresets
                    EffectCard {
                        required property var modelData
                        label: modelData.name
                        selected: page.glassPresetActive(glassSection.opt, modelData.preset)
                        glassPreset: modelData.preset
                        filterPreset: ({ filter: "none", saturation: 100, dim: 0, vignette: 0, grain: 0 })
                        onClicked: page.applyGlassPreset(glassSection.opt, modelData.preset)
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Pattern")
            visible: !glassSection.collapsed && glassSection.opt.enable

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
                currentIndex: Math.max(0, model.findIndex(item => item.value === glassSection.opt.pattern))
                onActivated: index => {
                    glassSection.opt.pattern = model[index].value;
                }
            }

            StyledComboBox {
                Layout.fillWidth: true
                visible: glassSection.opt.pattern !== "bubble"
                buttonIcon: "line_curve"
                textRole: "displayName"
                model: [
                    { displayName: Translation.tr("Lens (round)"),   value: "lens" },
                    { displayName: Translation.tr("Prism (facets)"), value: "prism" },
                    { displayName: Translation.tr("Contour"),        value: "contour" },
                    { displayName: Translation.tr("Cascade"),        value: "cascade" },
                    { displayName: Translation.tr("Flat"),           value: "flat" }
                ]
                currentIndex: Math.max(0, model.findIndex(item => item.value === glassSection.opt.profile))
                onActivated: index => {
                    glassSection.opt.profile = model[index].value;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Shape")
            visible: !glassSection.collapsed && glassSection.opt.enable

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "straighten"
                text: Translation.tr("Flute width (px)")
                usePercentTooltip: false
                from: 4
                to: 160
                value: glassSection.opt.fluteWidth
                onMoved: value => glassSection.opt.fluteWidth = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "rotate_right"
                text: Translation.tr("Angle (deg)")
                usePercentTooltip: false
                from: 0
                to: 180
                value: glassSection.opt.angle
                onMoved: value => glassSection.opt.angle = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: glassSection.opt.pattern === "rain" || glassSection.opt.pattern === "chevron"
                buttonIcon: "waves"
                text: Translation.tr("Rib bending (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: glassSection.opt.waviness
                onMoved: value => glassSection.opt.waviness = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                visible: glassSection.opt.pattern === "lines"
                buttonIcon: "shuffle"
                text: Translation.tr("Uneven widths (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: glassSection.opt.irregularity
                onMoved: value => glassSection.opt.irregularity = Math.round(value)
            }
        }

        ContentSubsection {
            title: Translation.tr("Optics")
            visible: !glassSection.collapsed && glassSection.opt.enable

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "lens_blur"
                text: Translation.tr("Refraction (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: glassSection.opt.distortion
                onMoved: value => glassSection.opt.distortion = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "colorize"
                text: Translation.tr("Dispersion (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: glassSection.opt.dispersion
                onMoved: value => glassSection.opt.dispersion = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "motion_blur"
                text: Translation.tr("Smear along rib (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: glassSection.opt.smear
                onMoved: value => glassSection.opt.smear = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "flare"
                text: Translation.tr("Highlights (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: glassSection.opt.highlights
                onMoved: value => glassSection.opt.highlights = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "line_weight"
                text: Translation.tr("Seam shadow (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: glassSection.opt.shadows
                onMoved: value => glassSection.opt.shadows = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "unfold_more"
                text: Translation.tr("Seam bend (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: glassSection.opt.edges
                onMoved: value => glassSection.opt.edges = Math.round(value)
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "grain"
                text: Translation.tr("Frost (%)")
                usePercentTooltip: false
                from: 0
                to: 100
                value: glassSection.opt.frost
                onMoved: value => glassSection.opt.frost = Math.round(value)
            }
        }
    }

    GlassSection {
        icon: "texture"
        title: Translation.tr("Fluted glass")
        tooltip: Translation.tr("Vertical cylindrical lenses refracted through Snell's law, so the flutes compress toward their seams like real cast glass.")
        desktopOpt: Config.options.background.effects.glass.desktop
        lockOpt: Config.options.background.effects.glass.lock
    }
}

