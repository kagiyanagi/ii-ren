import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page;
    readonly property int index: 5
    property bool register: parent.register ?? false
    forceWidth: true

    ContentSection {
        icon: "neurology"
        title: Translation.tr("AI")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("System prompt")
            text: Config.options.ai.systemPrompt
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Qt.callLater(() => {
                    Config.options.ai.systemPrompt = text;
                });
            }
        }
    }

    ContentSection {
        icon: "electrical_services"
        title: Translation.tr("Conduit")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Show Conduit in the sidebar")
            checked: Config.options.conduit.enable
            onCheckedChanged: {
                Config.options.conduit.enable = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "construction"
            text: Translation.tr("Tools (run unattended in the working directory)")
            checked: Config.options.conduit.enableTools
            onCheckedChanged: {
                Config.options.conduit.enableTools = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "smart_toy"
            text: Translation.tr("Desktop control (the agent can see the screen, click and type)")
            checked: Config.options.conduit.desktopControl
            enabled: Config.options.conduit.enableTools
            onCheckedChanged: {
                Config.options.conduit.desktopControl = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Notify when a reply lands and the tab isn't visible")
            checked: Config.options.conduit.notifyWhenAway
            onCheckedChanged: {
                Config.options.conduit.notifyWhenAway = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "history"
            text: Translation.tr("Restore the last chat on restart")
            checked: Config.options.conduit.restoreOnRestart
            onCheckedChanged: {
                Config.options.conduit.restoreOnRestart = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Permissions")

            ConfigSelectionArray {
                currentValue: Config.options.conduit.permissionMode
                onSelected: newValue => {
                    Config.options.conduit.permissionMode = newValue;
                }
                options: [
                    { displayName: Translation.tr("Bypass"), value: "bypassPermissions" },
                    { displayName: Translation.tr("Edits"), value: "acceptEdits" },
                    { displayName: Translation.tr("No ask"), value: "dontAsk" },
                    { displayName: Translation.tr("Plan"), value: "plan" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Voice accuracy")

            ConfigSelectionArray {
                currentValue: Config.options.conduit.sttQuality
                onSelected: newValue => {
                    Config.options.conduit.sttQuality = newValue;
                }
                options: [
                    { displayName: Translation.tr("Fast"), value: "fast" },
                    { displayName: Translation.tr("Balanced"), value: "balanced" },
                    { displayName: Translation.tr("Accurate"), value: "accurate" },
                    { displayName: Translation.tr("Best"), value: "best" }
                ]
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Working directory (empty: home). Tools cannot reach outside it.")
            text: Config.options.conduit.workingDir
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Qt.callLater(() => {
                    Config.options.conduit.workingDir = text.trim();
                });
            }
        }
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Denied tools, comma-separated (claude only)")
            text: Config.options.conduit.disallowedTools
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Qt.callLater(() => {
                    Config.options.conduit.disallowedTools = text.trim();
                });
            }
        }
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("System prompt")
            text: Config.options.conduit.systemPrompt
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Qt.callLater(() => {
                    Config.options.conduit.systemPrompt = text;
                });
            }
        }
    }

    ContentSection {
        icon: "calendar_month"
        title: Translation.tr("Calendar")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("iCal feed URLs, one per line (Google Calendar → Settings → Secret address in iCal format)")
            text: (Config.options.calendar.icsUrls || []).join("\n")
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Qt.callLater(() => {
                    Config.options.calendar.icsUrls = text.split("\n").map(s => s.trim()).filter(s => s.length > 0);
                });
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

        ContentSubsection {
            title: Translation.tr("Popup corner")

            ConfigSelectionArray {
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

        RippleButtonWithIcon {
            visible: Config.options.bluetooth.fastPair.ignoredDevices.length > 0
            materialIcon: "playlist_remove"
            mainText: Translation.tr("Clear %1 ignored device(s)").arg(Config.options.bluetooth.fastPair.ignoredDevices.length)
            onClicked: {
                Config.options.bluetooth.fastPair.ignoredDevices = [];
            }
        }
    }

    ContentSection {
        icon: "album"
        title: Translation.tr("Media")

        ContentSubsection {
            title: Translation.tr("Prioritized player")
            tooltip: Translation.tr("Automatically sets the active player to a newly detected player if its identifier matches the value specified in the priority player property so you dont have to manually set the active player")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Desktop entry name (e.g. spotify, google-chrome)")
                text: Config.options.media.priorityPlayer
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
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
        title: Translation.tr("Music Recognition")

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

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("User agent (for services that require it)")
            text: Config.options.networking.userAgent
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.networking.userAgent = text;
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
                text: Translation.tr("Disabling this will prevent the API from being called, but already cached lyrics will still be available.")
            }
        }


        ConfigRow {
            uniform: true

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
    }

    ContentSection {
        icon: "screen_record"
        title: Translation.tr("Screen recording")

        ContentSubsection {
            title: Translation.tr("Video codec")
            tooltip: Translation.tr("The GPU ones encode without eating the CPU, but need a render device set below.")

            StyledComboBox {
                buttonIcon: "movie"
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

        ContentSubsection {
            title: Translation.tr("Quality")
            tooltip: Translation.tr("CRF: lower looks better and takes more space. 0 leaves the codec's own default alone.")

            ConfigRow {
                uniform: true

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
        }

        ContentSubsection {
            title: Translation.tr("File format")
            tooltip: Translation.tr("MP4 plays anywhere. MKV survives a crash mid-recording. WebM wants VP9.")

            StyledComboBox {
                buttonIcon: "folder_zip"
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

        ContentSubsection {
            title: Translation.tr("Pixel format")
            tooltip: Translation.tr("yuv420p plays everywhere. The others keep text sharper but few players take them.")

            StyledComboBox {
                buttonIcon: "palette"
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
            title: Translation.tr("Audio")
            tooltip: Translation.tr("\"Follow the shortcut\" records sound only when the recording was started with the sound keybind.")

            ConfigSelectionArray {
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

            StyledComboBox {
                enabled: Config.options.screenRecord.audioMode !== "off"
                buttonIcon: "graphic_eq"
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

            // Without tracking them the nodes have no readable name yet
            PwObjectTracker {
                objects: [...Audio.outputDevices, ...Audio.inputDevices]
            }
        }

        ContentSubsection {
            title: Translation.tr("Audio codec")
            tooltip: Translation.tr("Only used when recording with sound.")

            StyledComboBox {
                buttonIcon: "music_note"
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

        ContentSubsection {
            title: Translation.tr("GPU render device")
            tooltip: Translation.tr("Needed by the VAAPI codecs, ignored by the rest. Pick another one if you have two GPUs.")

            StyledComboBox {
                buttonIcon: "memory"
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

        ContentSubsection {
            title: Translation.tr("Advanced")

            MaterialTextArea {
                id: extraArgsField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Extra wf-recorder arguments")
                text: Config.options.screenRecord.extraArgs
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.screenRecord.extraArgs = text;
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
        icon: "file_open"
        title: Translation.tr("Save paths")
        
        MaterialTextArea {
            id: recordingPathField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Video Recording Path")
            text: Config.options.screenRecord.savePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.screenRecord.savePath = text;
            }
        }
        
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Screenshot Path (leave empty to just copy)")
            text: Config.options.screenSnip.savePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.screenSnip.savePath = text;
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("To-do list file (Markdown checklist)")
            text: Config.options.todo.filePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.todo.filePath = text;
            }
            StyledToolTip {
                text: Translation.tr("Point this at a note in a vault to edit the same list there.\nOnly \"- [ ]\" lines are touched; the rest of the note is left alone.")
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
            text: Translation.tr("Auto-start server")
            checked: Config.options.localsend.autoStart
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.autoStart = checked;
            }
            StyledToolTip {
                text: Translation.tr("Automatically start LocalSend server when shell starts")
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
                text: Translation.tr("Show notifications for incoming transfers and completed downloads")
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Download path")
            text: Config.options.localsend.downloadPath
            wrapMode: TextEdit.Wrap
            enabled: LocalSend.available
            onTextChanged: {
                Config.options.localsend.downloadPath = text;
            }
        }
    }

    ContentSection {
        icon: "search"
        title: Translation.tr("Search")

        ContentSubsection {
            title: Translation.tr("Prefixes")
            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Action")
                    text: Config.options.search.prefix.action
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.action = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Clipboard")
                    text: Config.options.search.prefix.clipboard
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.clipboard = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Emojis")
                    text: Config.options.search.prefix.emojis
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.emojis = text;
                    }
                }
            }

            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Math")
                    text: Config.options.search.prefix.math
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.math = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Shell command")
                    text: Config.options.search.prefix.shellCommand
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.shellCommand = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Web search")
                    text: Config.options.search.prefix.webSearch
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.webSearch = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("File search")
                    text: Config.options.search.prefix.fileSearch
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.fileSearch = text;
                    }
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Web search")
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Base URL")
                text: Config.options.search.engineBaseUrl
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.search.engineBaseUrl = text;
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("File search")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search directory")
                text: Config.options.search.fileSearchDirectory
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.search.fileSearchDirectory = text;
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

    // There's no update indicator in ii for now so we shouldn't show this yet
    // ContentSection {
    //     icon: "deployed_code_update"
    //     title: Translation.tr("System updates (Arch only)")

    //     ConfigSwitch {
    //         text: Translation.tr("Enable update checks")
    //         checked: Config.options.updates.enableCheck
    //         onCheckedChanged: {
    //             Config.options.updates.enableCheck = checked;
    //         }
    //     }

    //     ConfigSpinBox {
    //         icon: "av_timer"
    //         text: Translation.tr("Check interval (mins)")
    //         value: Config.options.updates.checkInterval
    //         from: 60
    //         to: 1440
    //         stepSize: 60
    //         onValueChanged: {
    //             Config.options.updates.checkInterval = value;
    //         }
    //     }
    // }

    ContentSection {
        icon: "weather_mix"
        title: Translation.tr("Weather")
        ConfigRow {
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
        }
        ConfigRow {
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
        }
        
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("City name")
            text: Config.options.bar.weather.city
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.bar.weather.city = text;
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
