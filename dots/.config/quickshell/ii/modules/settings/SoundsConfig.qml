import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.utils

/*
 * Every sound the shell makes, in the shape of Android's Sound & vibration page:
 * one switch for all of them, the volume and the theme they come from, then each
 * moment on its own row with a play button. A theme is an XDG sound theme, so
 * anything in ~/.local/share/sounds shows up here; one that lacks a sound
 * inherits it, and the row says where it really comes from.
 */
ContentPage {
    id: page
    readonly property int index: 3
    property bool register: parent.register ?? false
    forceWidth: true

    readonly property var opts: Config.options.sounds

    // Row icons, in SoundService.events order; the theme cards' strip reuses them.
    readonly property var icons: ({
        notifications: "notifications",
        alarm: "alarm",
        pomodoro: "timer",
        session: "login",
        lock: "lock",
        volumeChange: "volume_up",
        screenshot: "screenshot_region",
        recording: "screen_record",
        authFailed: "password",
        charging: "power",
        battery: "battery_alert",
        devices: "devices_other"
    })
    readonly property var categories: Object.keys(SoundService.events)

    // Where the row's sound comes from, after what sets it off.
    function summary(category, when) {
        const custom = page.opts.custom[category] ?? "";
        if (SoundService.previewFailed === category)
            return Translation.tr("Couldn't play this sound");
        if (filePicker.missing && page.pickingFor === category)
            return Translation.tr("Choosing a file needs kdialog or zenity, and neither is installed");
        if (custom !== "")
            return `${when}  ·  ${FileUtils.fileNameForPath(custom)}`;
        const url = SoundService.urlFor(category);
        if (url === "")
            return SoundService.indexReady ? `${when}  ·  ${Translation.tr("Not in this theme")}` : when;
        const theme = SoundService.themeOf(url);
        return theme && theme.id !== page.opts.theme ? `${when}  ·  ${Translation.tr("From %1").arg(theme.name)}` : when;
    }

    // Whether a theme has the category's sound itself, not by inheritance.
    function themeHas(theme, category) {
        return SoundService.themeOf(SoundService.resolve(SoundService.events[category], theme.id))?.id === theme.id;
    }

    function previewTheme(theme) {
        SoundService.preview(`theme:${theme.id}`, SoundService.resolve([theme.example, ...SoundService.events.notifications].filter(Boolean), theme.id));
    }

    property string pickingFor: ""
    FilePickerProcess {
        id: filePicker
        label: "Sounds"
        patterns: ["*.ogg", "*.oga", "*.opus", "*.wav", "*.mp3", "*.flac"]
        onPicked: path => Config.options.sounds.custom[page.pickingFor] = path
    }

    // How far along a preview is. In on default effects, out on the exit spec,
    // assigned inside the binding that drives the fade (DESIGN.md 2.9).
    component PlayRing: CircularProgress {
        id: ring
        required property bool playing
        property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
        value: playing ? SoundService.previewProgress : 0
        colPrimary: Appearance.colors.colPrimary
        colSecondary: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 1)
        opacity: {
            ring.fadeSpec = ring.playing ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
            return ring.playing ? 1 : 0;
        }
        Behavior on opacity {
            NumberAnimation {
                duration: ring.fadeSpec.duration
                easing.type: ring.fadeSpec.type
                easing.bezierCurve: ring.fadeSpec.bezierCurve
            }
        }
    }

    // The 0.08 hover film over whatever the button sits on: these buttons sit on
    // colSurfaceContainerHigh cards, which have no Hover token of their own.
    // RippleButton's own overlay already does focus and press.
    component HoverFilm: StateOverlay {
        anchors.fill: parent
        radius: parent.buttonRadius
        hover: parent.hovered
        contentColor: parent.colStateLayer
    }

    // Plays the row's sound; the ring around it is how far along it is.
    component PlayButton: RippleButton {
        id: playButton
        required property string category
        readonly property string url: SoundService.urlFor(category)
        readonly property bool playing: SoundService.previewing === category

        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        enabled: url !== ""
        // Dimmed for its own reason only: inside a disabled row it would be 0.4 twice (TASTE 3.6).
        opacity: url === "" ? 0.4 : 1
        colBackground: playing ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 1)
        colBackgroundHover: colBackground
        colRipple: Appearance.colors.colSecondaryContainer
        colStateLayer: Appearance.colors.colOnSecondaryContainer

        HoverFilm {}
        onClicked: playing ? SoundService.stopPreview() : SoundService.preview(category, url)

        contentItem: Item {
            PlayRing {
                anchors.centerIn: parent
                implicitSize: playButton.implicitWidth
                playing: playButton.playing
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: playButton.playing ? "stop" : "play_arrow"
                iconSize: Appearance.font.pixelSize.larger
                fill: playButton.playing ? 1 : 0
                color: Appearance.colors.colOnSecondaryContainer
                Behavior on fill {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        StyledToolTip {
            text: playButton.playing ? Translation.tr("Stop") : Translation.tr("Play")
        }
    }

    // A file of the user's own in place of the theme's, and back again.
    component FileButton: RippleButton {
        id: fileButton
        required property string category
        readonly property bool custom: (page.opts.custom[category] ?? "") !== ""

        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        opacity: 1 // the row it sits in does the dimming
        colBackground: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 1)
        colBackgroundHover: colBackground
        colRipple: Appearance.colors.colSecondaryContainer
        colStateLayer: Appearance.colors.colOnSecondaryContainer

        HoverFilm {}
        onClicked: {
            if (custom) {
                Config.options.sounds.custom[category] = "";
                return;
            }
            page.pickingFor = category;
            filePicker.pick();
        }

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: fileButton.custom ? "restart_alt" : "audio_file"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSecondaryContainer
        }

        StyledToolTip {
            text: fileButton.custom ? Translation.tr("Use the theme's sound") : Translation.tr("Choose a sound file")
        }
    }

    // Android's main switch bar: the page's one loud thing, and the whole bar is
    // the switch. It bleeds as ContentGroup's cards do, to meet the same edges.
    Item {
        Layout.fillWidth: true
        implicitHeight: mainSwitch.implicitHeight

        RippleButton {
            id: mainSwitch
            readonly property bool soundsOn: page.opts.enable
            x: -8
            width: parent.width + 16
            implicitHeight: mainSwitchRow.implicitHeight + 16 * 2
            leftPadding: 24
            rightPadding: 16
            buttonRadius: Appearance.rounding.full
            colBackground: soundsOn ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
            colBackgroundHover: soundsOn ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
            colRipple: soundsOn ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
            colStateLayer: soundsOn ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
            onClicked: Config.options.sounds.enable = !Config.options.sounds.enable

            contentItem: RowLayout {
                id: mainSwitchRow
                spacing: 12

                // One line in both states, so nothing below moves when it is flipped.
                // That alarms still ring is the Alarms row's to say.
                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: Translation.tr("Use system sounds")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: mainSwitch.soundsOn ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                }
                StyledSwitch {
                    checkable: false
                    checked: mainSwitch.soundsOn
                    down: mainSwitch.down
                    focusPolicy: Qt.NoFocus
                    onClicked: mainSwitch.clicked()
                }
            }
        }
    }

    ContentSection {
        icon: "graphic_eq"
        title: Translation.tr("Sound")
        tooltip: Translation.tr("The volume is a share of the output volume, and alarms follow it too")

        // The effects volume, wavy like the media player's seek bar. Like Android's
        // squiggle it lies flat at rest and waves while something plays: here,
        // whatever this page is previewing.
        ConfigSlider {
            readonly property bool playing: SoundService.previewing !== ""
            buttonIcon: page.opts.volume === 0 ? "volume_off" : page.opts.volume < 50 ? "volume_down" : "volume_up"
            text: Translation.tr("Volume")
            configuration: StyledSlider.Configuration.Wavy
            animateWave: playing
            waveAmplitudeMultiplier: playing ? 0.5 : 0
            from: 0
            to: 100
            stepSize: 1
            value: page.opts.volume
            // Android plays the stream's own sound at the new level; a
            // notification is the one long enough to judge by.
            function hear() {
                SoundService.preview("notifications", SoundService.urlFor("notifications"));
            }
            onMoved: value => {
                Config.options.sounds.volume = Math.round(value);
                if (!pressed)
                    hear(); // the wheel and the arrow keys, one step at a time
            }
            onPressedChanged: if (!pressed) hear()
        }

        // The themes, as cards: picking one plays its example. Under each name, the
        // row icons of the sounds it has of its own; the rest it inherits.
        Item {
            Layout.fillWidth: true
            Layout.topMargin: 8
            implicitHeight: themeGrid.implicitHeight

            GridLayout {
                id: themeGrid
                x: -8
                width: parent.width + 16
                columns: 2
                uniformCellWidths: true
                rowSpacing: 8
                columnSpacing: 8

                Repeater {
                    model: SoundService.themes

                    RippleButton {
                        id: themeCard
                        required property var modelData
                        readonly property bool selected: modelData.id === page.opts.theme
                        readonly property bool playing: SoundService.previewing === `theme:${modelData.id}`

                        Layout.fillWidth: true
                        implicitHeight: cardRow.implicitHeight + 16 * 2
                        padding: 16
                        buttonRadius: Appearance.rounding.large
                        colBackground: selected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: colBackground
                        colRipple: selected ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colSurfaceContainerHighest
                        colStateLayer: selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                        onClicked: {
                            Config.options.sounds.theme = modelData.id;
                            page.previewTheme(modelData);
                        }

                        HoverFilm {}

                        contentItem: RowLayout {
                            id: cardRow
                            spacing: 12

                            // Selection is a shape: circle at rest, cookie when picked.
                            Item {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: 40
                                implicitHeight: 40
                                MaterialShapeWrappedMaterialSymbol {
                                    anchors.centerIn: parent
                                    implicitSize: 40
                                    shape: themeCard.selected ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.Circle
                                    color: themeCard.selected ? Appearance.colors.colSecondary : Appearance.colors.colSurfaceContainerHighest
                                    colSymbol: themeCard.selected ? Appearance.colors.colOnSecondary : Appearance.colors.colOnSurfaceVariant
                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                    text: themeCard.playing ? "graphic_eq" : themeCard.selected ? "check" : "music_note"
                                    iconSize: Appearance.font.pixelSize.larger
                                }
                                PlayRing {
                                    anchors.centerIn: parent
                                    implicitSize: 48
                                    playing: themeCard.playing
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: themeCard.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.family: Appearance.font.family.title
                                    color: themeCard.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    elide: Text.ElideRight
                                    text: themeCard.modelData.comment
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                                Row {
                                    Layout.topMargin: 4
                                    spacing: 4
                                    Repeater {
                                        model: page.categories
                                        MaterialSymbol {
                                            required property string modelData
                                            readonly property bool own: page.themeHas(themeCard.modelData, modelData)
                                            text: page.icons[modelData]
                                            iconSize: Appearance.font.pixelSize.small
                                            fill: own ? 1 : 0
                                            // design-ok: an absent glyph, as recessive as a chart's gridline, not a divider
                                            color: own ? (themeCard.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant) : Appearance.colors.colOutlineVariant
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            wrapMode: Text.WordWrap
            text: SoundService.themesFailed ? Translation.tr("Couldn't read the sound themes, so only FreeDesktop's sounds play")
                : SoundService.themes.length === 0 ? Translation.tr("Looking for sound themes…")
                : Translation.tr("Filled icons are sounds a theme has of its own; it borrows the rest. More themes go in ~/.local/share/sounds.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        icon: "notifications_active"
        title: Translation.tr("Alerts")

        ConfigSwitch {
            buttonIcon: page.icons.notifications
            text: Translation.tr("Notifications")
            summary: page.summary("notifications", Translation.tr("When one arrives, unless Do Not Disturb is on"))
            enabled: page.opts.enable
            checked: page.opts.notifications
            onCheckedChanged: Config.options.sounds.notifications = checked
            trailing: [
                FileButton { category: "notifications" },
                PlayButton { category: "notifications" }
            ]
        }
        // Not dimmed with the main switch: the alarm loop ignores it.
        ConfigSwitch {
            buttonIcon: page.icons.alarm
            text: Translation.tr("Alarms")
            summary: page.summary("alarm", Translation.tr("Rings until dismissed, even with system sounds off"))
            checked: page.opts.alarm
            onCheckedChanged: Config.options.sounds.alarm = checked
            trailing: [
                FileButton { category: "alarm" },
                PlayButton { category: "alarm" }
            ]
        }
        ConfigSwitch {
            buttonIcon: page.icons.pomodoro
            text: Translation.tr("Timer")
            summary: page.summary("pomodoro", Translation.tr("When a focus timer runs out"))
            enabled: page.opts.enable
            checked: page.opts.pomodoro
            onCheckedChanged: Config.options.sounds.pomodoro = checked
            trailing: [
                FileButton { category: "pomodoro" },
                PlayButton { category: "pomodoro" }
            ]
        }

        // Android Clock's "Gradually increase volume", as chips.
        ContentSubsection {
            title: Translation.tr("Gradually increase alarm volume")
            enabled: page.opts.alarm

            ConfigSelectionArray {
                currentValue: page.opts.alarmFadeIn ? page.opts.alarmFadeInSeconds : 0
                onSelected: newValue => {
                    Config.options.sounds.alarmFadeIn = newValue > 0;
                    if (newValue > 0)
                        Config.options.sounds.alarmFadeInSeconds = newValue;
                }
                options: [
                    { displayName: Translation.tr("Off"), value: 0 },
                    { displayName: Translation.tr("10 s"), value: 10 },
                    { displayName: Translation.tr("30 s"), value: 30 },
                    { displayName: Translation.tr("1 min"), value: 60 }
                ]
            }
        }
    }

    ContentSection {
        icon: "desktop_windows"
        title: Translation.tr("System")

        ConfigSwitch {
            buttonIcon: page.icons.session
            text: Translation.tr("Startup")
            summary: page.summary("session", Translation.tr("Once, when you log in"))
            enabled: page.opts.enable
            checked: page.opts.session
            onCheckedChanged: Config.options.sounds.session = checked
            trailing: PlayButton { category: "session" }
        }
        ConfigSwitch {
            buttonIcon: page.icons.lock
            text: Translation.tr("Screen lock")
            summary: page.summary("lock", Translation.tr("When the screen locks and unlocks"))
            enabled: page.opts.enable
            checked: page.opts.lock
            onCheckedChanged: Config.options.sounds.lock = checked
            trailing: PlayButton { category: "lock" }
        }
        ConfigSwitch {
            buttonIcon: page.icons.volumeChange
            text: Translation.tr("Volume changes")
            summary: page.summary("volumeChange", Translation.tr("A tick at the new level"))
            enabled: page.opts.enable
            checked: page.opts.volumeChange
            onCheckedChanged: Config.options.sounds.volumeChange = checked
            trailing: PlayButton { category: "volumeChange" }
        }
        ConfigSwitch {
            buttonIcon: page.icons.screenshot
            text: Translation.tr("Screenshots")
            summary: page.summary("screenshot", Translation.tr("When a screenshot is copied or saved"))
            enabled: page.opts.enable
            checked: page.opts.screenshot
            onCheckedChanged: Config.options.sounds.screenshot = checked
            trailing: PlayButton { category: "screenshot" }
        }
        ConfigSwitch {
            buttonIcon: page.icons.recording
            text: Translation.tr("Screen recording")
            summary: page.summary("recording", Translation.tr("When a recording starts and stops"))
            enabled: page.opts.enable
            checked: page.opts.recording
            onCheckedChanged: Config.options.sounds.recording = checked
            trailing: PlayButton { category: "recording" }
        }
        ConfigSwitch {
            buttonIcon: page.icons.authFailed
            text: Translation.tr("Wrong password")
            summary: page.summary("authFailed", Translation.tr("On the lock screen and in password prompts"))
            enabled: page.opts.enable
            checked: page.opts.authFailed
            onCheckedChanged: Config.options.sounds.authFailed = checked
            trailing: PlayButton { category: "authFailed" }
        }
    }

    ContentSection {
        icon: "power"
        title: Translation.tr("Power and devices")

        ConfigSwitch {
            visible: UPower.displayDevice.isLaptopBattery
            buttonIcon: page.icons.charging
            text: Translation.tr("Charging")
            summary: page.summary("charging", Translation.tr("When the charger is plugged in or out"))
            enabled: page.opts.enable
            checked: page.opts.charging
            onCheckedChanged: Config.options.sounds.charging = checked
            trailing: PlayButton { category: "charging" }
        }
        ConfigSwitch {
            visible: UPower.displayDevice.isLaptopBattery
            buttonIcon: page.icons.battery
            text: Translation.tr("Battery warnings")
            summary: page.summary("battery", Translation.tr("When the battery is low, critical or full"))
            enabled: page.opts.enable
            checked: page.opts.battery
            onCheckedChanged: Config.options.sounds.battery = checked
            trailing: PlayButton { category: "battery" }
        }
        ConfigSwitch {
            buttonIcon: page.icons.devices
            text: Translation.tr("Devices")
            summary: page.summary("devices", Translation.tr("When a Bluetooth or USB device connects or disconnects"))
            enabled: page.opts.enable
            checked: page.opts.devices
            onCheckedChanged: Config.options.sounds.devices = checked
            trailing: PlayButton { category: "devices" }
        }
    }
}
