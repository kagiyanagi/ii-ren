import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    readonly property int index: 9
    property bool register: parent.register ?? false
    forceWidth: true

    ContentSection {
        icon: "calendar_month"
        title: Translation.tr("Calendar")

        ConfigLabeledRow {
            buttonIcon: "link"
            text: Translation.tr("iCal feeds")
            summary: Translation.tr("One URL per line. In Google Calendar: Settings → Secret address in iCal format.")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Feed URLs")
                text: (Config.options.calendar.icsUrls || []).join("\n")
                wrapMode: TextEdit.Wrap
                onEditingFinished: {
                    Config.options.calendar.icsUrls = text.split("\n").map(s => s.trim()).filter(s => s.length > 0);
                }
            }
        }
    }

    ContentSection {
        icon: "bluetooth_searching"
        title: Translation.tr("Fast pairing")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Offer nearby devices for pairing")
            checked: Config.options.bluetooth.fastPair.enable
            onCheckedChanged: {
                Config.options.bluetooth.fastPair.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Shows an Android-style card when an unpaired device is nearby. Keeps Bluetooth discovering whenever nothing is connected, which costs radio time and battery.")
            }
        }

        ConfigSelectionRow {
            buttonIcon: "picture_in_picture"
            text: Translation.tr("Popup corner")
            currentValue: Config.options.bluetooth.fastPair.popupCorner
            onSelected: newValue => {
                Config.options.bluetooth.fastPair.popupCorner = newValue;
            }
            options: [
                { displayName: Translation.tr("Top left"), icon: "north_west", value: "top_left" },
                { displayName: Translation.tr("Top right"), icon: "north_east", value: "top_right" },
                { displayName: Translation.tr("Bottom left"), icon: "south_west", value: "bottom_left" },
                { displayName: Translation.tr("Bottom right"), icon: "south_east", value: "bottom_right" },
            ]
        }

        ConfigSwitch {
            buttonIcon: "headphones"
            text: Translation.tr("Audio devices only")
            checked: Config.options.bluetooth.fastPair.audioOnly
            onCheckedChanged: {
                Config.options.bluetooth.fastPair.audioOnly = checked;
            }
            StyledToolTip {
                text: Translation.tr("Ignore watches, phones and anything else that is not a headset or speaker")
            }
        }

        ConfigSpinBox {
            icon: "settings_input_antenna"
            text: Translation.tr("Minimum signal strength (dBm)")
            value: Config.options.bluetooth.fastPair.rssiThreshold
            from: -95
            to: -35
            stepSize: 5
            onValueChanged: {
                Config.options.bluetooth.fastPair.rssiThreshold = value;
            }
        }

        ConfigSpinBox {
            icon: "timer"
            text: Translation.tr("Popup timeout (s)")
            value: Config.options.bluetooth.fastPair.popupTimeout
            from: 0
            to: 120
            stepSize: 5
            onValueChanged: {
                Config.options.bluetooth.fastPair.popupTimeout = value;
            }
        }

        // The mute now outlives the shell, so there has to be a way back out of
        // a six-hour one that does not involve editing config.json.
        RippleButtonWithIcon {
            visible: Config.options.bluetooth.fastPair.mutedUntil > 0
            materialIcon: "notifications_active"
            mainText: Translation.tr("Unmute pairing popups (muted until %1)").arg(Qt.formatDateTime(new Date(Config.options.bluetooth.fastPair.mutedUntil), "HH:mm"))
            onClicked: {
                Config.options.bluetooth.fastPair.mutedUntil = 0;
            }
        }

        RippleButtonWithIcon {
            visible: Config.options.bluetooth.fastPair.ignoredDevices.length > 0
            materialIcon: "playlist_remove"
            mainText: Config.options.bluetooth.fastPair.ignoredDevices.length === 1
                ? Translation.tr("Clear 1 ignored device")
                : Translation.tr("Clear %1 ignored devices").arg(Config.options.bluetooth.fastPair.ignoredDevices.length)
            onClicked: {
                Config.options.bluetooth.fastPair.ignoredDevices = [];
            }
        }
    }

    ContentSection {
        icon: "album"
        title: Translation.tr("Media")

        ConfigLabeledRow {
            buttonIcon: "star"
            text: Translation.tr("Prioritized player")
            summary: Translation.tr("A player with this name becomes the active one as soon as it appears.")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Desktop entry name, e.g. spotify")
                text: Config.options.media.priorityPlayer
                wrapMode: TextEdit.NoWrap
                onEditingFinished: {
                    if (Config.options.media.priorityPlayer !== text)
                        Config.options.media.priorityPlayer = text;
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "filter_list"
            text: Translation.tr("Filter duplicate players")
            checked: Config.options.media.filterDuplicatePlayers
            onCheckedChanged: {
                Config.options.media.filterDuplicatePlayers = checked;
            }
            StyledToolTip {
                text: Translation.tr("Attempt to remove dupes (the aggregator playerctl one and browsers' native ones when there's plasma browser integration)")
            }
        }
    }

    ContentSection {
        icon: "music_cast"
        title: Translation.tr("Music recognition")

        ConfigSpinBox {
            icon: "timer_off"
            text: Translation.tr("Total duration timeout (s)")
            value: Config.options.musicRecognition.timeout
            from: 10
            to: 100
            stepSize: 2
            onValueChanged: {
                Config.options.musicRecognition.timeout = value;
            }
        }
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (s)")
            value: Config.options.musicRecognition.interval
            from: 2
            to: 10
            stepSize: 1
            onValueChanged: {
                Config.options.musicRecognition.interval = value;
            }
        }
    }

    ContentSection {
        icon: "cell_tower"
        title: Translation.tr("Networking")

        ConfigSwitch {
            buttonIcon: "energy_savings_leaf"
            text: Translation.tr("Wi-Fi power saving switch")
            checked: Config.options.networking.wifiPowerSave.enable
            onCheckedChanged: {
                Config.options.networking.wifiPowerSave.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Shows a switch in the Wi-Fi dialog to choose between saving battery and full speed. Turning this off only hides it: the last choice stays applied.")
            }
        }

        ConfigLabeledRow {
            buttonIcon: "public"
            text: Translation.tr("User agent")
            summary: Translation.tr("Sent to services that need one.")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: ""
                text: Config.options.networking.userAgent
                wrapMode: TextEdit.Wrap
                onEditingFinished: {
                    if (Config.options.networking.userAgent !== text)
                        Config.options.networking.userAgent = text;
                }
            }
        }
    }

    ContentSection {
        icon: "memory"
        title: Translation.tr("Resources")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (ms)")
            value: Config.options.resources.updateInterval
            from: 100
            to: 10000
            stepSize: 100
            onValueChanged: {
                Config.options.resources.updateInterval = value;
            }
        }
    }

    ContentSection {
        icon: "lyrics"
        title: Translation.tr("Lyrics")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable lyrics service")
            checked: Config.options.lyricsService.enable
            onCheckedChanged: {
                Config.options.lyricsService.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Off stops the API calls and hides lyrics everywhere, cached ones included.")
            }
        }

        ConfigSwitch {
            enabled: Config.options.lyricsService.enable
            buttonIcon: "mood"
            text: Translation.tr("Enable genius lyrics service")
            checked: Config.options.lyricsService.enableGenius
            onCheckedChanged: {
                Config.options.lyricsService.enableGenius = checked;
            }
        }
        ConfigSwitch {
            enabled: Config.options.lyricsService.enable
            buttonIcon: "library_books"
            text: Translation.tr("Enable lrclib lyrics service")
            checked: Config.options.lyricsService.enableLrclib
            onCheckedChanged: {
                Config.options.lyricsService.enableLrclib = checked;
            }
        }
    }

    ContentSection {
        icon: "screen_record"
        title: Translation.tr("Screen recording")

        ConfigLabeledRow {
            buttonIcon: "movie"
            text: Translation.tr("Video codec")
            summary: Translation.tr("The GPU ones encode without eating the CPU, but need a render device set below.")
            StyledComboBox {
                textRole: "displayName"
                model: [
                    { displayName: Translation.tr("H.264 (most compatible)"), value: "libx264" },
                    { displayName: Translation.tr("H.265 (smaller files)"), value: "libx265" },
                    { displayName: Translation.tr("VP9 (for WebM)"), value: "libvpx-vp9" },
                    { displayName: Translation.tr("AV1 (slow, smallest)"), value: "libsvtav1" },
                    { displayName: Translation.tr("H.264 on GPU (VAAPI)"), value: "h264_vaapi" },
                    { displayName: Translation.tr("H.265 on GPU (VAAPI)"), value: "hevc_vaapi" }
                ]
                currentIndex: Math.max(0, model.findIndex(item => item.value === Config.options.screenRecord.codec))
                onActivated: index => {
                    Config.options.screenRecord.codec = model[index].value;
                }
            }
        }

        ConfigLabeledRow {
            buttonIcon: "memory"
            text: Translation.tr("GPU render device")
            summary: Translation.tr("Needed by the VAAPI codecs, ignored by the rest. Pick another one if you have two GPUs.")
            StyledComboBox {
                textRole: "displayName"
                model: [
                    { displayName: Translation.tr("None"), value: "" },
                    { displayName: "/dev/dri/renderD128", value: "/dev/dri/renderD128" },
                    { displayName: "/dev/dri/renderD129", value: "/dev/dri/renderD129" }
                ]
                currentIndex: Math.max(0, model.findIndex(item => item.value === Config.options.screenRecord.device))
                onActivated: index => {
                    Config.options.screenRecord.device = model[index].value;
                }
            }
        }

        ConfigLabeledRow {
            buttonIcon: "folder_zip"
            text: Translation.tr("File format")
            summary: Translation.tr("MP4 plays anywhere. MKV survives a crash mid-recording. WebM wants VP9.")
            StyledComboBox {
                textRole: "displayName"
                model: [
                    { displayName: "MP4", value: "mp4" },
                    { displayName: "MKV", value: "mkv" },
                    { displayName: "WebM", value: "webm" },
                    { displayName: "MOV", value: "mov" }
                ]
                currentIndex: Math.max(0, model.findIndex(item => item.value === Config.options.screenRecord.container))
                onActivated: index => {
                    Config.options.screenRecord.container = model[index].value;
                }
            }
        }

        ConfigLabeledRow {
            buttonIcon: "palette"
            text: Translation.tr("Pixel format")
            summary: Translation.tr("yuv420p plays everywhere. The others keep text sharper but few players take them.")
            StyledComboBox {
                textRole: "displayName"
                model: [
                    { displayName: Translation.tr("yuv420p (most compatible)"), value: "yuv420p" },
                    { displayName: Translation.tr("yuv444p (sharp text)"), value: "yuv444p" },
                    { displayName: Translation.tr("yuv420p10le (10-bit)"), value: "yuv420p10le" },
                    { displayName: "nv12", value: "nv12" }
                ]
                currentIndex: Math.max(0, model.findIndex(item => item.value === Config.options.screenRecord.pixelFormat))
                onActivated: index => {
                    Config.options.screenRecord.pixelFormat = model[index].value;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Quality")
            tooltip: Translation.tr("CRF: lower looks better and takes more space. 0 leaves the codec's own default alone.")

            ConfigSpinBox {
                icon: "60fps"
                text: Translation.tr("Framerate")
                value: Config.options.screenRecord.framerate
                from: 10
                to: 240
                stepSize: 5
                onValueChanged: {
                    Config.options.screenRecord.framerate = value;
                }
            }
            ConfigSpinBox {
                icon: "hd"
                text: Translation.tr("Quality (CRF)")
                value: Config.options.screenRecord.quality
                from: 0
                to: 51
                stepSize: 1
                onValueChanged: {
                    Config.options.screenRecord.quality = value;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Audio")

            ConfigSelectionRow {
                buttonIcon: "mic"
                text: Translation.tr("Record sound")
                summary: Translation.tr("\"Follow the shortcut\" records sound only when the recording was started with the sound keybind.")
                currentValue: Config.options.screenRecord.audioMode
                onSelected: newValue => {
                    Config.options.screenRecord.audioMode = newValue;
                }
                options: [
                    { displayName: Translation.tr("Never"), icon: "volume_off", value: "off" },
                    { displayName: Translation.tr("Follow the shortcut"), icon: "keyboard", value: "flag" },
                    { displayName: Translation.tr("Always"), icon: "volume_up", value: "always" }
                ]
            }

            ConfigLabeledRow {
                enabled: Config.options.screenRecord.audioMode !== "off"
                buttonIcon: "graphic_eq"
                text: Translation.tr("Source")

                StyledComboBox {
                    Layout.fillWidth: true
                    textRole: "displayName"
                    // Rebuilt whenever devices come and go, so a headset plugged in
                    // after the settings opened still shows up.
                    model: [
                        { displayName: Translation.tr("System audio (default output)"), value: "" },
                        { displayName: Translation.tr("Microphone (default input)"), value: "@mic" },
                        ...Audio.outputDevices.map(node => ({
                            displayName: Translation.tr("Output: %1").arg(Audio.friendlyDeviceName(node)),
                            value: `${node.name}.monitor`
                        })),
                        ...Audio.inputDevices.map(node => ({
                            displayName: Translation.tr("Mic: %1").arg(Audio.friendlyDeviceName(node)),
                            value: node.name
                        }))
                    ]
                    currentIndex: Math.max(0, model.findIndex(item => item.value === Config.options.screenRecord.audioSource))
                    onActivated: index => {
                        Config.options.screenRecord.audioSource = model[index].value;
                    }
                }
            }

            // Without tracking them the nodes have no readable name yet
            PwObjectTracker {
                objects: [...Audio.outputDevices, ...Audio.inputDevices]
            }
        

            ConfigLabeledRow {
                buttonIcon: "music_note"
                enabled: Config.options.screenRecord.audioMode !== "off"
                text: Translation.tr("Codec")
                summary: Translation.tr("Only used when recording with sound.")
                StyledComboBox {
                    textRole: "displayName"
                    model: [
                        { displayName: Translation.tr("Container default"), value: "" },
                        { displayName: "AAC", value: "aac" },
                        { displayName: "Opus", value: "libopus" },
                        { displayName: "MP3", value: "libmp3lame" },
                        { displayName: Translation.tr("FLAC (lossless)"), value: "flac" }
                    ]
                    currentIndex: Math.max(0, model.findIndex(item => item.value === Config.options.screenRecord.audioCodec))
                    onActivated: index => {
                        Config.options.screenRecord.audioCodec = model[index].value;
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Advanced")

            ConfigLabeledRow {
                buttonIcon: "terminal"
                text: Translation.tr("Extra wf-recorder arguments")

                MaterialTextArea {
                    id: extraArgsField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Arguments, e.g. --no-damage")
                    text: Config.options.screenRecord.extraArgs
                    wrapMode: TextEdit.Wrap
                    onEditingFinished: {
                        if (Config.options.screenRecord.extraArgs !== text)
                            Config.options.screenRecord.extraArgs = text;
                    }
                }
            }

            RippleButtonWithIcon {
                Layout.alignment: Qt.AlignLeft
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reset recording options")
                onClicked: {
                    Config.resetScreenRecord();
                    // Edited text fields hold their own copy, so they need telling
                    extraArgsField.text = Config.options.screenRecord.extraArgs;
                    recordingPathField.text = Config.options.screenRecord.savePath;
                }

                StyledToolTip {
                    text: Translation.tr("Puts every option on this section, save path included, back to how it shipped.")
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Keystroke display")
        icon: "keyboard"

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Shows the keys you press on top of everything, so they are captured by the recording. It can also be turned on at any time from the quick toggles.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        ConfigSwitch {
            buttonIcon: "keyboard_alt"
            text: Translation.tr("Show keystrokes while recording")
            checked: Config.options.screenRecord.keypress.showWhileRecording
            onCheckedChanged: {
                Config.options.screenRecord.keypress.showWhileRecording = checked;
            }
            StyledToolTip {
                text: Translation.tr("Applies to every new recording. Each recording can still be switched over on its own from the recording indicator.")
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: KeypressService.lastError.length > 0
            materialIcon: "error"
            text: Translation.tr("Keystrokes cannot be read: %1").arg(KeypressService.lastError)
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: KeypressService.lastError.length === 0 && !KeypressService.layoutAware
            materialIcon: "warning"
            text: Translation.tr("Key labels assume a US layout. Install python-xkbcommon to have them follow the keyboard layout you actually use.")
        }

        ConfigSelectionRow {
            buttonIcon: "picture_in_picture"
            text: Translation.tr("Position on screen")
            currentValue: Config.options.screenRecord.keypress.position
            onSelected: newValue => {
                Config.options.screenRecord.keypress.position = newValue;
            }
            options: [
                { displayName: Translation.tr("Top left"),     value: "topLeft",     icon: "north_west" },
                { displayName: Translation.tr("Top"),          value: "top",         icon: "north" },
                { displayName: Translation.tr("Top right"),    value: "topRight",    icon: "north_east" },
                { displayName: Translation.tr("Bottom left"),  value: "bottomLeft",  icon: "south_west" },
                { displayName: Translation.tr("Bottom"),       value: "bottom",      icon: "south" },
                { displayName: Translation.tr("Bottom right"), value: "bottomRight", icon: "south_east" }
            ]
        }

        ConfigSlider {
            buttonIcon: "swap_horiz"
            text: Translation.tr("Distance from the side edge")
            value: Config.options.screenRecord.keypress.marginH
            from: 0
            to: 400
            usePercentTooltip: false
            onMoved: value => {
                Config.options.screenRecord.keypress.marginH = Math.round(value);
            }
        }

        ConfigSlider {
            buttonIcon: "swap_vert"
            text: Translation.tr("Distance from the top or bottom edge")
            value: Config.options.screenRecord.keypress.marginV
            from: 0
            to: 400
            usePercentTooltip: false
            onMoved: value => {
                Config.options.screenRecord.keypress.marginV = Math.round(value);
            }
        }

        ConfigSlider {
            buttonIcon: "format_size"
            text: Translation.tr("Size")
            value: Config.options.screenRecord.keypress.scale
            from: 0.6
            to: 2.0
            usePercentTooltip: false
            onMoved: value => {
                Config.options.screenRecord.keypress.scale = Math.round(value * 10) / 10;
            }
        }

        ConfigSlider {
            buttonIcon: "timer"
            text: Translation.tr("Time on screen (ms)")
            value: Config.options.screenRecord.keypress.hideDelayMs
            from: 500
            to: 8000
            usePercentTooltip: false
            onMoved: value => {
                Config.options.screenRecord.keypress.hideDelayMs = Math.round(value);
            }
        }

        ConfigSlider {
            buttonIcon: "format_list_numbered"
            text: Translation.tr("Keys kept on screen")
            value: Config.options.screenRecord.keypress.maxKeys
            from: 1
            to: 12
            usePercentTooltip: false
            onMoved: value => {
                Config.options.screenRecord.keypress.maxKeys = Math.round(value);
            }
        }

        ConfigSwitch {
            buttonIcon: "text_fields"
            text: Translation.tr("Join typed letters into words")
            checked: Config.options.screenRecord.keypress.mergeTyping
            onCheckedChanged: {
                Config.options.screenRecord.keypress.mergeTyping = checked;
            }
            StyledToolTip {
                text: Translation.tr("Typing fills one chip instead of flooding the screen with a chip per letter. Shortcuts always get their own.")
            }
        }

        ConfigSwitch {
            buttonIcon: "keyboard_command_key"
            text: Translation.tr("Only show shortcuts")
            checked: Config.options.screenRecord.keypress.onlyShortcuts
            onCheckedChanged: {
                Config.options.screenRecord.keypress.onlyShortcuts = checked;
            }
            StyledToolTip {
                text: Translation.tr("Hides ordinary typing and reports only combinations with Ctrl, Alt or Super — useful when what you type is private.")
            }
        }

        ConfigSwitch {
            buttonIcon: "mouse"
            text: Translation.tr("Show mouse buttons")
            checked: Config.options.screenRecord.keypress.showMouseButtons
            onCheckedChanged: {
                Config.options.screenRecord.keypress.showMouseButtons = checked;
            }
        }
    }

    ContentSection {
        icon: "file_open"
        title: Translation.tr("Save paths")

        ConfigLabeledRow {
            buttonIcon: "videocam"
            text: Translation.tr("Video recordings")

            MaterialTextArea {
                id: recordingPathField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Folder")
                text: Config.options.screenRecord.savePath
                wrapMode: TextEdit.Wrap
                onEditingFinished: {
                    if (Config.options.screenRecord.savePath !== text)
                        Config.options.screenRecord.savePath = text;
                }
            }
        }

        ConfigLabeledRow {
            buttonIcon: "screenshot_region"
            text: Translation.tr("Screenshots")
            summary: Translation.tr("Leave empty to copy only.")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Folder")
                text: Config.options.screenSnip.savePath
                wrapMode: TextEdit.Wrap
                onEditingFinished: {
                    if (Config.options.screenSnip.savePath !== text)
                        Config.options.screenSnip.savePath = text;
                }
            }
        }

        ConfigLabeledRow {
            buttonIcon: "checklist"
            text: Translation.tr("To-do list")
            summary: Translation.tr("A Markdown checklist file.")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("File")
                text: Config.options.todo.filePath
                wrapMode: TextEdit.Wrap
                onEditingFinished: {
                    if (Config.options.todo.filePath !== text)
                        Config.options.todo.filePath = text;
                }
                StyledToolTip {
                    text: Translation.tr("Point this at a note in a vault to edit the same list there.\nOnly \"- [ ]\" lines are touched; the rest of the note is left alone.")
                }
            }
        }

        // Sits under the path field because the two decide the same thing
        // between them: whether a snip survives being copied. Hidden once a
        // path is set, since the shot is saved outright then.
        ConfigSwitch {
            visible: Config.options.screenSnip.savePath === ""
            buttonIcon: "screenshot_region"
            text: Translation.tr("Offer to save screenshots after taking them")
            checked: Config.options.screenSnip.showPreview
            onCheckedChanged: {
                Config.options.screenSnip.showPreview = checked;
            }
        }

        ContentSubsection {
            visible: Config.options.screenSnip.savePath === "" && Config.options.screenSnip.showPreview
            title: Translation.tr("Screenshot preview")

            ConfigSelectionArray {
                currentValue: Config.options.screenSnip.previewCorner
                onSelected: newValue => {
                    Config.options.screenSnip.previewCorner = newValue;
                }
                options: [
                    { displayName: Translation.tr("Top left"), icon: "north_west", value: "top_left" },
                    { displayName: Translation.tr("Top right"), icon: "north_east", value: "top_right" },
                    { displayName: Translation.tr("Bottom left"), icon: "south_west", value: "bottom_left" },
                    { displayName: Translation.tr("Bottom right"), icon: "south_east", value: "bottom_right" },
                ]
            }

            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Dismiss after (seconds)")
                value: Config.options.screenSnip.previewTimeout
                from: 1
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.screenSnip.previewTimeout = value;
                }
            }
        }
    }

    ContentSection {
        icon: "devices"
        title: Translation.tr("LocalSend")
        tooltip: Translation.tr("Send and receive files with any LocalSend device on the network")

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Receive files")
            checked: Config.options.localsend.autoStart
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.autoStart = checked;
            }
            StyledToolTip {
                text: Translation.tr("Same as the LocalSend tile in quick settings. Stays as you left it across restarts")
            }
        }

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Show notifications")
            checked: Config.options.localsend.showNotifications
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.showNotifications = checked;
            }
            StyledToolTip {
                text: Translation.tr("Show notifications for received files and text. Incoming requests always notify")
            }
        }

        ConfigLabeledRow {
            buttonIcon: "download"
            text: Translation.tr("Download folder")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Folder")
                text: Config.options.localsend.downloadPath
                wrapMode: TextEdit.Wrap
                enabled: LocalSend.available
                onEditingFinished: {
                    if (Config.options.localsend.downloadPath !== text)
                        Config.options.localsend.downloadPath = text;
                }
            }
        }
    }

    ContentSection {
        icon: "search"
        title: Translation.tr("Search")

        ConfigLabeledRow {
            buttonIcon: "tag"
            text: Translation.tr("Prefixes")
            summary: Translation.tr("Typed first in the launcher, each one searches only that source.")

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                uniformCellWidths: true
                columnSpacing: 4
                rowSpacing: 4

                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Action")
                    text: Config.options.search.prefix.action
                    wrapMode: TextEdit.Wrap
                    onEditingFinished: {
                        if (Config.options.search.prefix.action !== text)
                            Config.options.search.prefix.action = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Clipboard")
                    text: Config.options.search.prefix.clipboard
                    wrapMode: TextEdit.Wrap
                    onEditingFinished: {
                        if (Config.options.search.prefix.clipboard !== text)
                            Config.options.search.prefix.clipboard = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Emojis")
                    text: Config.options.search.prefix.emojis
                    wrapMode: TextEdit.Wrap
                    onEditingFinished: {
                        if (Config.options.search.prefix.emojis !== text)
                            Config.options.search.prefix.emojis = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Math")
                    text: Config.options.search.prefix.math
                    wrapMode: TextEdit.Wrap
                    onEditingFinished: {
                        if (Config.options.search.prefix.math !== text)
                            Config.options.search.prefix.math = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Shell command")
                    text: Config.options.search.prefix.shellCommand
                    wrapMode: TextEdit.Wrap
                    onEditingFinished: {
                        if (Config.options.search.prefix.shellCommand !== text)
                            Config.options.search.prefix.shellCommand = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Web search")
                    text: Config.options.search.prefix.webSearch
                    wrapMode: TextEdit.Wrap
                    onEditingFinished: {
                        if (Config.options.search.prefix.webSearch !== text)
                            Config.options.search.prefix.webSearch = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("File search")
                    text: Config.options.search.prefix.fileSearch
                    wrapMode: TextEdit.Wrap
                    onEditingFinished: {
                        if (Config.options.search.prefix.fileSearch !== text)
                            Config.options.search.prefix.fileSearch = text;
                    }
                }
            }
        }
        ConfigLabeledRow {
            buttonIcon: "travel_explore"
            text: Translation.tr("Web search")
            summary: Translation.tr("The query is added to the end.")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Base URL")
                text: Config.options.search.engineBaseUrl
                wrapMode: TextEdit.Wrap
                onEditingFinished: {
                    if (Config.options.search.engineBaseUrl !== text)
                        Config.options.search.engineBaseUrl = text;
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("File search")

            ConfigLabeledRow {
                buttonIcon: "folder_open"
                text: Translation.tr("Search directory")

                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Folder")
                    text: Config.options.search.fileSearchDirectory
                    wrapMode: TextEdit.Wrap
                    onEditingFinished: {
                        if (Config.options.search.fileSearchDirectory !== text)
                            Config.options.search.fileSearchDirectory = text;
                    }
                }
            }

            ConfigSwitch {
                buttonIcon: "hide_image"
                text: Translation.tr("Blur file search result previews")
                checked: Config.options.search.blurFileSearchResultPreviews
                onCheckedChanged: {
                    Config.options.search.blurFileSearchResultPreviews = checked;
                }
            }
        }
    }

    ContentSection {
        icon: "weather_mix"
        title: Translation.tr("Weather")
        ConfigSwitch {
            buttonIcon: "assistant_navigation"
            text: Translation.tr("Enable GPS based location")
            checked: Config.options.bar.weather.enableGPS
            onCheckedChanged: {
                Config.options.bar.weather.enableGPS = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "thermometer"
            text: Translation.tr("Fahrenheit unit")
            checked: Config.options.bar.weather.useUSCS
            onCheckedChanged: {
                Config.options.bar.weather.useUSCS = checked;
            }
            StyledToolTip {
                text: Translation.tr("It may take a few seconds to update")
            }
        }
        ConfigSwitch {
            buttonIcon: "image"
            text: Translation.tr("Dynamic weather icon")
            checked: Config.options.bar.weather.dynamicIcon ?? true
            onCheckedChanged: {
                Config.options.bar.weather.dynamicIcon = checked;
            }
            StyledToolTip {
                text: Translation.tr("Show condition icon in top bar")
            }
        }

        ConfigLabeledRow {
            buttonIcon: "location_city"
            text: Translation.tr("City")
            summary: Translation.tr("Used when GPS location is off.")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("City name")
                text: Config.options.bar.weather.city
                wrapMode: TextEdit.Wrap
                onEditingFinished: {
                    if (Config.options.bar.weather.city !== text)
                        Config.options.bar.weather.city = text;
                }
            }
        }
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (m)")
            value: Config.options.bar.weather.fetchInterval
            from: 5
            to: 50
            stepSize: 5
            onValueChanged: {
                Config.options.bar.weather.fetchInterval = value;
            }
        }
    }
}
