pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.functions

Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property alias options: configOptionsJsonAdapter
    property bool ready: false
    property int readWriteDelay: 75 // milliseconds
    property bool blockWrites: false

    // Kept out of the JsonObject so they are not written to the config file,
    // and so a reset can put them back without the values living in two places.
    readonly property var screenRecordDefaults: ({
        savePath: Directories.videos.replace("file://", ""), // strip "file://"
        container: "mp4", // file extension, also picks the muxer
        codec: "libx264", // any encoder ffmpeg knows, e.g. libx265, h264_vaapi
        device: "", // /dev/dri/renderD128 for the *_vaapi codecs
        framerate: 60,
        pixelFormat: "yuv420p",
        quality: 23, // crf, lower is better; 0 leaves the codec default alone
        // "off" never records sound, "always" always does, "flag" leaves it to
        // whatever started the recording (--sound).
        audioMode: "flag",
        // "" = the default output's monitor, "@mic" = the default input,
        // anything else is passed to wf-recorder as the device name.
        audioSource: "",
        audioCodec: "", // empty = whatever the muxer defaults to
        extraArgs: "" // appended to the wf-recorder command as-is
    })

    function resetScreenRecord() {
        for (const key in root.screenRecordDefaults)
            root.options.screenRecord[key] = root.screenRecordDefaults[key];
    }

    function setNestedValue(nestedKey, value) {
        let keys = nestedKey.split(".");
        let obj = root.options;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Convert value to correct type using JSON.parse when safe
        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try {
                    convertedValue = JSON.parse(trimmed);
                } catch (e) {
                    convertedValue = value;
                }
            }
        }

        obj[keys[keys.length - 1]] = convertedValue;
    }

    Timer {
        id: fileReloadTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            configFileView.reload();
        }
    }

    Timer {
        id: fileWriteTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            configFileView.writeAdapter();
        }
    }

    FileView {
        id: configFileView
        path: root.filePath
        watchChanges: true
        blockWrites: root.blockWrites
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: fileWriteTimer.restart()
        onLoaded: root.ready = true
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                writeAdapter();
            }
        }

        JsonAdapter {
            id: configOptionsJsonAdapter

            property string panelFamily: "ii" // "ii", "waffle"

            property JsonObject policies: JsonObject {
                property int ai: 1 // 0: No | 1: Yes | 2: Local
                property int weeb: 0 // 0: No | 1: Open | 2: Closet
                property int wallpapers: 1 // 0: No | 1: Yes
                property int translator: 0 // 0: No | 1: Yes
                property int continuity: 1 // 0: No | 1: Yes
            }

            property JsonObject extensions: JsonObject {
                property bool enable: true
            }

            property JsonObject localsend: JsonObject {
                property bool autoStart: true
                property string downloadPath: Directories.localSendDownloadPath.replace("file://", "")
                property bool showNotifications: true
            }

            property JsonObject todo: JsonObject {
                // A Markdown checklist, so the file doubles as a note in
                // whatever editor or vault you point this at.
                property string filePath: Directories.todoPath
            }

            property JsonObject ai: JsonObject {
                property string systemPrompt: "## Style\n- Use casual tone, don't be formal!\n- Always be brief and to the point, unless asked otherwise\n- Don't repeat the user's question\n- Be approachable: Avoid using overly complicated, domain-specific terms and provide analogies when asked to explain a concept\n\n## Context (ignore when irrelevant)\n- You are a helpful and inspiring sidebar assistant on a {DISTRO} Linux system\n- Desktop environment: {DE}\n- Current date & time: {DATETIME}\n- Focused app: {WINDOWCLASS}\n\n## Presentation\n- Use Markdown features in your response: \n  - **Bold** text to **highlight keywords** in your response\n  - **Split long information into small sections** with h2 headers and a relevant emoji at the start of it (for example `## 🐧 Linux`). Bullet points are preferred over long paragraphs, unless you're offering writing support or instructed otherwise by the user.\n- Asked to compare different options? You should firstly use a table to compare the main aspects, then elaborate or include relevant comments from online forums *after* the table. Make sure to provide a final recommendation for the user's use case!\n- Use LaTeX formatting for mathematical and scientific notations whenever appropriate. Enclose all LaTeX '$$' delimiters. NEVER generate LaTeX code in a latex block unless the user explicitly asks for it. DO NOT use LaTeX for regular documents (resumes, letters, essays, CVs, etc.).\n\nThanks!\n"
                property string tool: "functions" // search, functions, or none
                property list<var> models: [
                    // Needed entries in the object: title, value, modelProvider (only for openrouter)
                    {
                        "openrouter": [
                            {
                                title: "Gemini 2.5 Flash",
                                value: "gemini-2.5-flash",
                                modelProvider: "google"
                            },
                        ]
                    },
                    {
                        "google": []
                    }
                ]
                property list<var> otherModels: [
                    // Available api_format(s): openai, gemini, mistral
                    {
                        "name": "Mistral Medium",
                        "model": "mistral-medium-2505",
                        "icon": "mistral-symbolic",
                        "endpoint": "https://api.mistral.ai/v1/chat/completions",
                        "requires_key": true,
                        "key_id": "mistral",
                        "api_format": "mistral"
                    }
                ]
            }

            // Conduit: a Claude Code / Antigravity CLI session in the sidebar.
            property JsonObject conduit: JsonObject {
                property bool enable: true
                property string provider: "claude-cli" // claude-cli | antigravity
                property string model: "claude-sonnet-5"
                property string systemPrompt: "You are answering from a desktop shell sidebar. Keep replies concise and use markdown when it helps."
                property bool enableTools: true
                property bool desktopControl: true // Hands the agent the screen, pointer and keyboard over MCP
                property string permissionMode: "bypassPermissions" // bypassPermissions | acceptEdits | dontAsk | plan
                property string disallowedTools: ""
                property string workingDir: "" // empty: $HOME
                property string sttModel: ""
                property string sttLanguage: "en" // en | auto
                property string sttPrompt: "Terms: QML, Quickshell, Hyprland, ii-vynx, Conduit, LaTeX, extension, sidebar, attachment, transcript."
                property string sttSource: ""
                property string sttQuality: "balanced" // fast | balanced | accurate | best
                property string currentChatId: ""
                property bool notifyWhenAway: true
                property bool restoreOnRestart: false
                property string ttsVoice: ""
            }

            property JsonObject appearance: JsonObject {
                property bool extraBackgroundTint: true
                property int fakeScreenRounding: 2 // 0: None | 1: Always | 2: When not fullscreen | 3: Wrapped
                property int wrappedFrameThickness: 10
                property bool sharpMode: false
                property int defaultBorderRadius: 18
                property bool toggleWindowRounding: true // Changes Hyprland window rounding to 0 if sharpMode is true
                property JsonObject fonts: JsonObject {
                    property bool enableCustom: false
                    property string main: "Google Sans Flex"
                    property string numbers: "Google Sans Flex"
                    property string title: "Google Sans Flex"
                    property string iconNerd: "JetBrains Mono NF"
                    property string monospace: "JetBrains Mono NF"
                    property string reading: "Readex Pro"
                    property string expressive: "Space Grotesk"
                }
                property JsonObject transparency: JsonObject {
                    property bool popups: false
                    property bool enable: false
                    property bool automatic: true
                    property real backgroundTransparency: 0.11
                    property real contentTransparency: 0.57
                }
                property JsonObject wallpaperTheming: JsonObject {
                    property bool enableAppsAndShell: true
                    property bool enableQtApps: true
                    property bool enableTerminal: true
                    property JsonObject terminalGenerationProps: JsonObject {
                        property real harmony: 0.6
                        property real harmonizeThreshold: 100
                        property real termFgBoost: 0.35
                        property bool forceDarkMode: false
                    }
                }
                property JsonObject palette: JsonObject {
                    property string type: "auto" // Allowed: auto, scheme-content, scheme-expressive, scheme-fidelity, scheme-fruit-salad, scheme-monochrome, scheme-neutral, scheme-rainbow, scheme-tonal-spot
                    property string accentColor: ""
                }
                property list<string> customColorSchemes: []
            }

            property JsonObject audio: JsonObject {
                // Node names of the devices to play to / record from at once.
                // None means one plain default device, one means multi-device
                // mode with a single member, two or more get combined.
                property list<string> combinedSinks: []
                property list<string> combinedSources: []
                // Values in %
                property JsonObject protection: JsonObject {
                    // Prevent sudden bangs
                    property bool enable: false
                    property real maxAllowedIncrease: 10
                    property real maxAllowed: 99
                }
            }

            property JsonObject apps: JsonObject {
                property string bluetooth: "kcmshell6 kcm_bluetooth"
                property string changePassword: "kitty -1 --hold=yes fish -i -c 'passwd'"
                property string network: "kcmshell6 kcm_networkmanagement"
                property string manageUser: "kcmshell6 kcm_users"
                property string networkEthernet: "kcmshell6 kcm_networkmanagement"
                property string taskManager: "plasma-systemmonitor --page-name Processes"
                property string terminal: "kitty -1" // This is only for shell actions
                property string update: "kitty -1 --hold=yes fish -i -c 'pkexec pacman -Syu'"
                property string volumeMixer: `~/.config/hypr/hyprland/scripts/launch_first_available.sh "pavucontrol-qt" "pavucontrol"`
            }

            property JsonObject background: JsonObject {
                property bool enable: true // if someone wants to use an external wallpaper manager, note that its not fully tested but it should just disable background.qml from being loaded
                // Drop an image anywhere on the empty desktop to set it as the
                // wallpaper. Off leaves the drop to whatever is underneath.
                property bool dropToSetWallpaper: true
                // Files a drop cannot set as the wallpaper land on the drop
                // shelf instead, to be dragged back out somewhere else.
                property bool dropToShelf: true
                // Right-click the empty desktop for a context menu.
                property bool rightClickMenu: true
                property JsonObject widgets: JsonObject {
                    // Legacy pre-registry clock entry. Kept only so
                    // WidgetStateManager can migrate it into an instance.
                    property JsonObject clock: JsonObject {
                        property bool enable: true
                        property bool disableAnimationOnLock: false
                        property bool showOnlyWhenLocked: false
                        property string placementStrategy: "leastBusy" // "free", "leastBusy", "mostBusy"
                        property real x: 100
                        property real y: 100
                        property string style: "cookie"        // Options: "cookie", "digital"
                        property string styleLocked: "cookie"  // Options: "cookie", "digital"
                        property JsonObject cookie: JsonObject {
                            property bool aiStyling: false
                            property string aiStylingModel: "gemini" // Options "gemini", "openrouter"
                            property int sides: 14
                            property string backgroundStyle: "cookie"     // Options: "cookie", "sine", "shape"
                            property string backgroundShape: "Arch"  // Options: MaterialShape.Shape enum values as string
                            property string dialNumberStyle: "full"   // Options: "dots" , "numbers", "full" , "none"
                            property string hourHandStyle: "fill"     // Options: "classic", "fill", "hollow", "hide"
                            property string minuteHandStyle: "medium" // Options "classic", "thin", "medium", "bold", "hide"
                            property string secondHandStyle: "dot"    // Options: "dot", "line", "classic", "hide"
                            property string dateStyle: "bubble"       // Options: "border", "rect", "bubble" , "hide"
                            property bool timeIndicators: true
                            property bool hourMarks: false
                            property bool dateInClock: true
                            property bool constantlyRotate: false
                            property bool turnOffRotationOnTiledApps: false
                        }
                        property JsonObject digital: JsonObject {
                            property bool adaptiveAlignment: true
                            property bool showDate: true
                            property bool animateChange: true
                            property bool vertical: false
                            property bool colorful: false
                            property bool showColon: true
                            property JsonObject font: JsonObject {
                                property string family: "Google Sans Flex"
                                property real weight: 350
                                property real width: 100
                                property real size: 90
                                property real roundness: 0
                            }
                        }
                        property JsonObject quote: JsonObject {
                            property bool enable: false
                            property string text: ""
                        }
                    }
                    property string colorScheme: "default"
                    property bool showOnlyOnSingleMonitor: false
                    property string targetMonitor: ""
                    property JsonObject clock_cookie: JsonObject {
                        property bool enable: false
                        property bool disableAnimationOnLock: false
                        property string placementStrategy: "free"
                        property real x: 1518.98
                        property real y: 168.8
                        property bool aiStyling: false
                        property string aiStylingModel: "gemini"
                        property int sides: 14
                        property string backgroundStyle: "cookie"
                        property string backgroundShape: "Arch"
                        property string dialNumberStyle: "full"
                        property string hourHandStyle: "fill"
                        property string minuteHandStyle: "medium"
                        property string secondHandStyle: "dot"
                        property string dateStyle: "bubble"
                        property bool timeIndicators: true
                        property bool hourMarks: false
                        property bool dateInClock: true
                        property bool constantlyRotate: false
                        property bool quoteEnable: false
                        property string quoteText: ""
                    }
                    property JsonObject clock_expressive_card: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property int widgetSize: 100
                    }

                    property JsonObject clock_flex: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property int widgetSize: 100
                        property bool useAltColors: true
                    }
                    property JsonObject clock_digital: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool adaptiveAlignment: true
                        property bool showDate: true
                        property bool animateChange: true
                        property bool vertical: false
                        property bool colorful: false
                        property bool showColon: true
                        property JsonObject font: JsonObject {
                            property real weight: 350
                            property real width: 100
                            property real size: 90
                            property real roundness: 0
                        }
                        property bool quoteEnable: false
                        property string quoteText: ""
                    }
                    property JsonObject clock_nagasaki: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool monochrome: false
                    }
                    property JsonObject clock_word: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property int size: 240
                        property string backgroundStyle: "shape"
                        property string backgroundShape: "Circle"
                    }
                    property JsonObject clock_dial: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool showTicks: true
                        property bool showMinuteHand: true
                        property bool enableShadows: false
                        property bool enableInnerShadow: false
                        property string hourHandStyle: "fill"
                        property string minuteHandStyle: "medium"
                        property bool showSecondHand: false
                        property string secondHandStyle: "dot"
                        property bool showNumberRing: false
                        property bool expressiveColors: false
                    }
                    property JsonObject nagasaki_text: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property int size: 200
                    }
                    property JsonObject clock_hori: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property int widgetSize: 100
                        property bool useAltColors: false
                    }
                    property JsonObject clock_nothing: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool use24h: true
                        property bool showAmPmChip: true
                        property bool showTopLabel: true
                        property bool showDate: true
                        property bool useAccentColor: false
                    }
                    property JsonObject nothing_wheel_clock: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject media: JsonObject {
                        property bool enable: true
                        property string style: "circular" // circular, expressive
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 249.21
                        property real y: 612.92
                        property bool useAlbumColors: true
                        property bool hideAllButtons: false
                        property bool showPreviousToggle: true
                        property bool tintArtCover: false
                        property string backgroundShape: "Cookie12Sided"  // Options: MaterialShape.Shape enum values as string
                        property bool rotateAlbumArt: true
                        property bool showTimeInfo: true
                        property bool showArtist: true
                        property bool showProgressSlider: true
                        property bool dynamicAlbumColors: false
                        property JsonObject glow: JsonObject {
                            property bool enable: true
                            property real brightness: 10
                        }
                        property JsonObject visualizer: JsonObject {
                            property bool enable: false
                            property real opacity: 0.15
                            property int smoothing: 2
                            property int blur: 1
                        }
                    }
                    property JsonObject circular_media: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 249.21
                        property real y: 612.92
                        property bool useAlbumColors: true
                        property bool enableGlassReflection: true
                        property bool enableShadows: false
                        property bool showPrevButton: true
                        property bool showNextButton: true
                        property bool showDevicePill: true
                        property string progressShape: "Cookie9Sided"
                        property int widgetSize: 100
                    }
                    property JsonObject wearos_clock: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property bool useAlbumColors: true
                        property bool enableGlassReflection: true
                        property bool showDistroLogo: true
                        property bool showSunsetComplication: true
                        property bool showDigitalTimePill: true
                        property bool showBatteryPill: true
                        property bool showHourSubDial: true
                        property bool showBedtimeIcon: true
                        property bool showKdeConnect: true
                        property bool showDateComplication: true
                        property bool showMinuteHand: true
                        property bool showOuterNumbers: true
                        property bool showInnerNumbers: true
                        property bool showBezelRing: true
                        property bool enableShadows: false
                        property int widgetSize: 100
                    }
                    property JsonObject wearos_arc_clock: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property bool blackBackground: false
                        property bool enableGlassReflection: true
                        property bool enableBackgroundPattern: true
                        property string leftComplication: "weather"
                        property string rightComplication: "battery"
                        property string bottomComplication: "calendar"
                        property bool enableShadows: false
                    }
                    property JsonObject concentric_clock: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property string dialStyle: "concentric"
                        property string frameStyle: "none"
                        property bool boldFont: false
                        property bool use24h: true
                        property bool showHourText: true
                        property string hourHandStyle: "hide"
                        property string minuteHandStyle: "hide"
                        property string secondHandStyle: "hide"
                        property bool showHourMarks: false
                        property string minuteStyle: "pill_horizontal"
                        property bool showArc24h: false
                        property bool showHourSubDial: false
                        property bool showSunsetDial: false
                        property string bottomSubDialContent: "weather_temp"
                        property bool showMinuteDot: false
                        property bool quoteEnable: false
                        property string quoteText: ""
                        property int minutePillLeftMargin: 67
                        property int subdialMarginOffset: 5
                        property int dialMarginOffset: 3
                        property int hourPixelSize: 30
                        property int hourFontWeight: 600
                        property int hourFontWidth: 85
                        property int hourFontRound: 100
                        property bool useBlackBg: false
                        property bool enableGlassReflection: false
                        property bool enableShadows: false
                    }
                    property JsonObject month_clock: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property bool showMonthRing: true
                        property bool showDayRing: true
                        property bool showWeekRing: true
                        property bool showMonthPill: true
                        property bool showDayPill: true
                        property bool showWeekPill: true
                        property bool showTickMarks: true
                        property bool boldFont: true
                        property bool useBlackBg: true
                        property bool enableGlassReflection: false
                        property string hourHandStyle: "fill"
                        property string minuteHandStyle: "medium"
                        property string secondHandStyle: "line"
                    }
                    property JsonObject scallop_dot_clock: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property bool boldFont: true
                        property bool useBlackBg: false
                        property bool enableGlassReflection: false
                        property bool showHourHand: true
                        property bool showMinuteBubble: true
                        property bool showDots: true
                    }
                    property JsonObject scallop_number_clock: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property bool boldFont: true
                        property bool useBlackBg: false
                        property bool enableGlassReflection: false
                        property bool showHourHand: true
                        property bool showMinuteBubble: true
                        property bool showDots: true
                    }
                    property JsonObject circle_pointer_clock: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property bool boldFont: true
                        property bool useBlackBg: false
                        property bool enableGlassReflection: false
                        property bool showDots: true
                    }
                    property JsonObject triple_ring_clock: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property bool boldFont: true
                        property bool useBlackBg: false
                        property bool enableGlassReflection: false
                    }
                    property JsonObject photo_1x1: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property string backgroundShape: "Cookie9Sided"
                        property string imagePath: ""
                    }
                    property JsonObject android_search_bar: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property string aspectRatio: "0.5x2"
                        property string action1: "music_rec"
                        property string action2: "ai_chat"
                        property string action3: "search"
                    }
                    property JsonObject search_pill: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property string aspectRatio: "0.5x2"
                        property string action1: "ai_chat"
                        property string action2: "music_rec"
                        property string action3: "search"
                        property string aiLogo: "gemini"
                        property string outerLeftIcon: "spark"
                        property bool useMaterialSymbolForOuterLeftIcon: false
                    }
                    property JsonObject resource_cpu_pill: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property string aspectRatio: "2x0.5"
                        property bool showDetails: true
                    }
                    property JsonObject resource_ram_pill: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property string aspectRatio: "2x0.5"
                        property bool showDetails: true
                    }
                    property JsonObject resource_disk_pill: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property string aspectRatio: "2x0.5"
                        property bool showDetails: true
                    }
                    property JsonObject resource_fill_cards: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property string orientation: "horizontal"
                        property bool enableCpu: true
                        property bool enableRam: true
                        property bool enableDisk: true
                    }
                    property JsonObject grid_card_clock: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                    }
                    property JsonObject at_a_glance: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property int widgetSize: 100
                        property int widthCells: 3
                        property bool dualColumnMode: false
                        property list<string> servicePriority: ["media", "calendar", "sports", "todo", "email", "localsend", "kdeconnect", "fallback"]
                        property bool enableMedia: true
                        property bool enableCalendar: true
                        property bool enableSports: true
                        property bool enableTodo: true
                        property bool enableEmail: true
                        property bool enableLocalSend: true
                        property bool enableKdeConnect: true
                        property bool enableWeather: true
                        property int calendarWindowMinutes: 60
                        property int sportsWindowHours: 12
                        property bool showLocation: true
                        property bool showServiceLabel: false
                        property bool showSeparators: true
                        property bool animateContent: true
                    }
                    property JsonObject weather: JsonObject {
                        property bool enable: false
                        property string style: "default" // default, expressive
                        property string backgroundShape: "Cookie9Sided"
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 400
                        property real y: 100
                        property bool expressiveColors: false
                    }
                    property JsonObject weather_forecast: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: true
                    }
                    property JsonObject weather_card: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: true
                    }
                    property JsonObject weather_icon: JsonObject {
                        property bool enable: false
                        property string backgroundShape: "Cookie9Sided"
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: true
                    }
                    property JsonObject weather_pill: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: true
                    }
                    property JsonObject weather_circle: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: true
                    }
                    property JsonObject nothing_weather_circle: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject volume_mute_pill: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject wifi_pill: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject bluetooth_pill: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject mic_pill: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject dark_mode_pill: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject screen_record_pill: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject easy_effects_pill: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject nothing_ring_media: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject weather_typography: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: true
                    }
                    property JsonObject weather_hourly: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: true
                    }
                    property JsonObject date: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 100
                        property real y: 100
                        property bool expressiveColors: false
                    }
                    property JsonObject calendar_minimal: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject calendar_grid: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject calendar_agenda: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject calendar_next_event: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject calendar_pill: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject calendar_upcoming_3days: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject photo: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property string imagePath: ""
                        property bool expressiveColors: false
                    }
                    property JsonObject photo_weather_2x1: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property string imagePath: ""
                        property bool showOverlay: true
                        property bool expressiveColors: false
                    }
                    property JsonObject photo_pill_2x1: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property string imagePath: ""
                        property bool showOverlay: true
                        property bool expressiveColors: false
                    }
                    property JsonObject photo_minimal_temp_2x1: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property string imagePath: ""
                        property bool showOverlay: true
                        property bool expressiveColors: false
                    }
                    property JsonObject bluetooth_battery: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject bluetooth_headphone: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool halfSize: true
                        property bool expressiveColors: false
                    }
                    property JsonObject mobile_battery: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject bluetooth_headphone_cookie: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property string materialShape: "Cookie12Sided"
                        property bool expressiveColors: false
                    }
                    property JsonObject bluetooth_fill_cards: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject pc_battery_bars: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject pc_battery_cable: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject devices_battery_list: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject devices_battery_list_1x1: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject bluetooth_earbuds_stem: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject email_inbox: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject email_inbox_2x1: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject quote: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                        property string quoteText: ""
                        property real fontSize: 16
                    }
                    property JsonObject quick_actions: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                        property string bottomButton1: "translator"
                        property string bottomButton2: "phone"
                    }
                    property JsonObject ai_chat: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject notes_widget: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject notes_widget_2x1: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                    }
                    property JsonObject media_cd: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool dynamicAlbumColors: false
                        property bool enableShadows: false
                        property bool enableInnerShadow: false
                        property int widgetSize: 100
                    }
                    property JsonObject compact_media: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool dynamicAlbumColors: false
                        property string backgroundShape: "Rectangle"
                        property bool enableShadows: false
                        property bool enableInnerShadow: false
                        property int widgetSize: 100
                    }
                    property JsonObject water_reminder: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property bool expressiveColors: false
                        property int dailyGoal: 8
                        property int intervalHours: 2
                        property string reminderText: "Time to hydrate! 💧"
                    }
                    property bool enableInnerShadow: false
                    property bool enableShadows: false
                    property bool enableGrid: false
                    property bool enableSnap: true
                    property real widgetsScale: 1.0
                    property bool lockWidgetPositions: false
                }
                property list<var> activeWidgets: []
                property bool animateWallpaperChanges: true
                property string transitionType: "radial"
                property int wipeAngle: 0
                property string wallpaperPath: ""
                property string thumbnailPath: ""
                property bool hideWhenFullscreen: true
                // Wallpaper post-processing. Mirrors the effect set custom ROMs ship
                // (risingOS -> Evolution X, Matrixx, Mist, Lunaris, PenguinOS): two blur
                // styles, a dim level, and one filter at a time, plus a fluted-glass
                // distortion pass of our own. Every default is a no-op.
                property JsonObject effects: JsonObject {
                    // Where the effects apply, as the ROMs' effect target does.
                    property string target: "both" // "both", "desktop", "lock"

                    // "glass" and "frosted" are the ROMs' two radii, 50 and 9.
                    property JsonObject blur: JsonObject {
                        property bool enable: false
                        property string style: "glass" // "glass", "frosted", "custom"
                        property int radius: 50        // only read when style is "custom"
                    }

                    // One at a time, matching the ROMs' effect picker. Options:
                    // none, grayscale, sepia, negative, posterize, pixelate,
                    // sharpen, chromatic, radialBlur
                    property string filter: "none"
                    property int posterizeLevels: 8 // 2..16
                    property int pixelSize: 8       // px per block
                    property real sharpen: 1.0      // 1.0 = the ROMs' 3x3 kernel
                    property int chromatic: 5       // px of R/B separation
                    property int radialBlur: 5      // %, matches the ROMs' 0.05 strength

                    // These stack on top of whichever filter is picked.
                    property int saturation: 100 // 100 = untouched
                    property int dim: 0          // %
                    property int vignette: 0     // %
                    property int grain: 0        // %

                    // Fluted / reeded glass. No ROM has this one.
                    property JsonObject glass: JsonObject {
                        property bool enable: false
                        property string pattern: "lines" // lines, rain, chevron, bubble
                        property string profile: "lens"  // lens, prism, contour, cascade, flat
                        property int fluteWidth: 22      // px per flute
                        property int angle: 0            // degrees
                        property int distortion: 55      // %
                        property int dispersion: 25      // % chromatic aberration
                        property int smear: 10           // % blur along the rib
                        property int highlights: 55      // %
                        property int shadows: 35         // % seam darkening
                        property int edges: 30           // % extra bend at the seams
                        property int frost: 0            // %
                        property int irregularity: 0     // % uneven flute widths
                        property int waviness: 0         // % rib bending, for rain/chevron
                    }
                }
                property JsonObject parallax: JsonObject {
                    property bool vertical: true
                    property bool autoVertical: false
                    property bool enableWorkspace: false
                    property real workspaceZoom: 1.07 // Relative to wallpaper size
                    property bool enableSidebar: false
                    property real widgetsFactor: 1.2
                }
                property JsonObject mediaMode: JsonObject {
                    property bool togglePerMonitor: false
                    property string backgroundShape: "Square"
                    property bool enableBackgroundAnimation: true // It **may** cause nausea for someone
                    property bool changeShellColor: true // Changes the shell color to the album color
                    property int backgroundOpacity: 50 // In percent
                    property int backgroundBlurRadius: 120
                    property JsonObject backgroundAnimation: JsonObject {
                        property bool enable: true
                        property int speedScale: 10 // 1: very slow, 10: default, 20: 2x speed etc.
                    }
                    property JsonObject syllable: JsonObject {
                        property int textHighlightStyle: 0 // 0: vertical, 1: horizontal (not perfect bc its not synced in a word level, but a cool animation to have)
                    }
                }
            }

            property JsonObject bar: JsonObject {
                property JsonObject clock: JsonObject {
                    property bool showSeconds: false
                }
                property JsonObject activeWindow: JsonObject {
                    property bool fixedSize: false
                }

                property JsonObject autoHide: JsonObject {
                    property bool enable: false
                    property int hoverRegionWidth: 2
                    property bool pushWindows: false
                    property JsonObject showWhenPressingSuper: JsonObject {
                        property bool enable: true
                        property int delay: 140
                    }
                }

                property bool bottom: false // Instead of top
                property int cornerStyle: 0 // 0: Hug | 1: Float | 2: Plain rectangle
                property real cornerRadius: 18
                property bool floatStyleShadow: true // Show shadow behind bar when cornerStyle == 1 (Float)
                property int barGroupStyle: 0 // 0: Pills | 1: Island (opaque) | 2: Transparent (or maybe line-separated in the future)
                property string topLeftIcon: "spark" // Options: "distro" or any icon name in ~/.config/quickshell/ii/assets/icons
                property int barBackgroundStyle: 1 // 0: Transparent | 1: Visible | 2: Adaptive
                property bool verbose: true
                property bool vertical: false

                property JsonObject mediaPlayer: JsonObject {
                    property bool useFixedSize: false
                    property int customSize: 250
                    property int maxSize: 400
                    property JsonObject artwork: JsonObject {
                        property bool enable: false
                    }
                    property JsonObject lyrics: JsonObject {
                        property bool enable: false
                        property int customSize: 400
                        property string style: "scroller" // Options: scroller, static
                        property bool useGradientMask: true
                    }
                }

                property JsonObject resources: JsonObject {
                    property int memoryWarningThreshold: 95
                    property bool alwaysShowSwap: false
                    // Off: the Containers block is not wanted in the resources
                    // hover popup. Set both this and resources.enableDocker to
                    // true to bring it back - there is no settings toggle.
                    property bool showDocker: false
                    property int swapWarningThreshold: 85
                    property int cpuWarningThreshold: 90
                }
                property list<string> screenList: [] // List of names, like "eDP-1", find out with 'hyprctl monitors' command

                property JsonObject timers: JsonObject {
                    property bool showPomodoro: true
                    property bool showStopwatch: true
                }
                property JsonObject utilButtons: JsonObject {
                    property bool showScreenSnip: true
                    property bool showColorPicker: false
                    property bool showMicToggle: false
                    property bool showKeyboardToggle: true
                    property bool showKeyboardBacklight: true
                    property bool showDarkModeToggle: true
                    property bool showPerformanceProfileToggle: false
                    property bool showScreenRecord: false
                }
                property JsonObject workspaces: JsonObject {
                    property bool monochromeIcons: true
                    property int shown: 10
                    property bool showAppIcons: true
                    property bool alwaysShowNumbers: false
                    property int showNumberDelay: 300 // milliseconds
                    property list<string> numberMap: ["1", "2"] // Characters to show instead of numbers on workspace indicator
                    property bool useWorkspaceMap: true
                    property list<var> workspaceMap: [0, 10]
                    property int maxWindowCount: 1 // Maximum windows to show in one workspace
                    property bool useNerdFont: false
                    property int activeIndicatorOpacity: 100 // 0-100
                    property bool dynamicWorkspaces: false
                }
                property JsonObject weather: JsonObject {
                    property bool enable: false
                    property bool enableGPS: true // gps based location
                    property string city: "" // When 'enableGPS' is false
                    property bool useUSCS: false // Instead of metric (SI) units
                    property int fetchInterval: 10 // minutes
                    property bool dynamicIcon: true // Use dynamic weather condition icon
                }
                property JsonObject indicators: JsonObject {
                    property JsonObject notifications: JsonObject {
                        property bool showUnreadCount: false
                    }
                    property JsonObject record: JsonObject {
                        property bool minimal: false
                    }
                    property JsonObject privacy: JsonObject {
                        property bool microphone: true
                        property bool camera: true
                        property bool screen: true
                        property bool location: true
                    }
                }
                property JsonObject layouts: JsonObject {
                    // Only storing id and layout-specific flags (visible, centered)
                    // Component display info (icon, title) comes from BarComponentRegistry
                    property list<var> left: [
                        {
                            id: "policies_panel_button"
                        },
                        {
                            id: "active_window"
                        }
                    ]
                    property list<var> center: [
                        {
                            id: "music_player"
                        },
                        {
                            id: "workspaces",
                            centered: true
                        },
                        {
                            id: "system_monitor"
                        }
                    ]
                    property list<var> right: [
                        {
                            id: "privacy_indicator"
                        },
                        {
                            id: "record_indicator"
                        },
                        {
                            id: "weather"
                        },
                        {
                            id: "clock"
                        },
                        {
                            id: "system_tray"
                        },
                        {
                            id: "dashboard_panel_button"
                        }
                    ]
                }
                property JsonObject tooltips: JsonObject {
                    property bool enablePopups: true
                    property int closeDelay: 50
                    property bool clickToShow: false
                    property bool compactPopups: false
                    property bool showSwap: false
                }
                property JsonObject sizes: JsonObject {
                    property int height: 40 // horizontal mode
                    property int width: 46 // vertical mode
                }

                property JsonObject networkSpeed: JsonObject {
                    property int displayMode: 0 // 0: total, 1: download, 2: upload, 3: both, 4: icon
                    property bool showIcons: true
                    property int iconPosition: 0 // 0: Left, 1: Right
                    property int updateInterval: 1000 // ms
                    property bool autoHide: true
                }
            }

            property JsonObject battery: JsonObject {
                property int low: 20
                property int critical: 5
                property int full: 101
                property bool automaticSuspend: true
                property int suspend: 3
            }

            // Per-device artwork for the bluetooth toggle and dialog, as
            // [{ mac, image }]. `image` names a file in <shellConfig>/bluetooth_images.
            property list<var> bluetoothDeviceImages: []

            property JsonObject bluetooth: JsonObject {
                // Android-style popup offering nearby unpaired devices.
                // Off by default: it keeps the adapter discovering whenever
                // nothing is connected, which costs radio time and battery.
                property JsonObject fastPair: JsonObject {
                    property bool enable: false
                    property string popupCorner: "top_right"
                    property int rssiThreshold: -65 // dBm; higher means the device must be closer
                    property bool audioOnly: true // Only offer headsets, earbuds and speakers
                    property int popupTimeout: 20 // Seconds before the popup snoozes itself; 0 to never
                    property int snoozeSeconds: 300 // How long a dismissed device stays quiet
                    property list<string> ignoredDevices: [] // Addresses to never offer again
                }
            }

            property JsonObject calendar: JsonObject {
                property string locale: "en-GB"
                // Google Calendar: Settings → your calendar → "Secret address in iCal format"
                property list<string> icsUrls: []
            }

            property JsonObject cheatsheet: JsonObject {
                // Use a nerdfont to see the icons
                // 0: 󰖳  | 1: 󰌽 | 2: 󰘳 | 3:  | 4: 󰨡
                // 5:  | 6:  | 7: 󰣇 | 8:  | 9: 
                // 10:  | 11:  | 12:  | 13:  | 14: 󱄛
                property string superKey: ""
                property bool useMacSymbol: false
                property bool splitButtons: false
                property bool useMouseSymbol: false
                property bool useFnSymbol: false
                property JsonObject fontSize: JsonObject {
                    property int key: Appearance.font.pixelSize.smaller
                    property int comment: Appearance.font.pixelSize.smaller
                }
            }

            property JsonObject clipboard: JsonObject {
                property JsonObject copyToast: JsonObject {
                    property bool enable: true
                    // Same values as screenSnip.previewCorner: top_left, top_right,
                    // bottom_left, bottom_right. Android puts it bottom left.
                    property string corner: "bottom_left"
                    // Seconds, like every other dismissal in here. SystemUI's
                    // ClipboardOverlayController uses 6. 0 keeps it up until clicked.
                    property int dismissAfter: 6
                }
            }

            property JsonObject conflictKiller: JsonObject {
                property bool autoKillNotificationDaemons: false
                property bool autoKillTrays: false
            }

            property JsonObject crosshair: JsonObject {
                // Valorant crosshair format. Use https://www.vcrdb.net/builder
                property string code: "0;P;d;1;0l;10;0o;2;1b;0"
            }

            property JsonObject altTab: JsonObject {
                property bool enable: true
                // Hyprland warps the pointer to the newly focused window unless
                // cursor:no_warps is set; we flip it only while the switcher is up.
                property bool keepCursorInPlace: true
                property bool currentWorkspaceOnly: false
            }

            property JsonObject dock: JsonObject {
                property bool enable: false
                property bool isolateMonitors: false
                property bool monochromeIcons: true
                property bool dimInactiveIcons: false
                property real height: 60
                property bool showAppsButtonBackground: true
                property real itemSpacing: 0
                property real sectionSpacing: 0
                property string separatorStyle: "Line"
                property real cornerRadius: -1
                property real paddingHorizontal: 0
                property real paddingVertical: 0
                property real hoverRegionHeight: 2
                property bool pinnedOnStartup: false
                property bool enablePreview: true
                property bool revealOnEmptyWorkspace: true
                property bool enableMediaWidget: false
                // Media popup: hover to peek, or click to keep it up
                property bool mediaPopupOnHover: false
                // The desktop media widget shows on an empty workspace too
                property bool hideMediaOnEmptyWorkspace: false
                property string position: "bottom"
                // Sit flush against the screen edge, squaring off the two
                // corners that touch it, instead of floating with a gap.
                property bool attachToEdge: false
                property string appsButtonShape: "Pill"
                property string pinButtonShape: ""
                property bool showPinButton: true
                property bool showAppsButton: true
                property list<string> pinnedApps: ["org.kde.dolphin", "kitty",]
                property list<string> ignoredAppRegexes: []
                property list<string> pinnedFiles: []
                // App folders: [{ name: "Tools", apps: ["firefox", "kitty"] }]
                property list<var> folders: []
            }

            property JsonObject hyprland: JsonObject {
                property string defaultHyprlandLayout: "dwindle" // Options: dwindle, monocle, master // It's best to not use scrolling
                // Apps launched once per login. Each entry is
                // { cmd: string, workspace: int, delay: int (seconds) }.
                property JsonObject autostartApps: JsonObject {
                    property bool enable: false
                    property list<var> apps: []
                }
            }

            property JsonObject interactions: JsonObject {
                property JsonObject scrolling: JsonObject {
                    property bool fasterTouchpadScroll: false // Enable faster scrolling with touchpad
                    property int mouseScrollDeltaThreshold: 120 // delta >= this then it gets detected as mouse scroll rather than touchpad
                    property int mouseScrollFactor: 120
                    property int touchpadScrollFactor: 450
                }
                property JsonObject deadPixelWorkaround: JsonObject { // Hyprland leaves out 1 pixel on the right for interactions
                    property bool enable: false
                }
            }

            property JsonObject language: JsonObject {
                property string ui: "en_US" // UI language. "auto" for system locale, or specific language code like "zh_CN", "en_US"
                property JsonObject translator: JsonObject {
                    property string engine: "auto" // Run `trans -list-engines` for available engines. auto should use google
                    property string targetLanguage: "auto" // Run `trans -list-all` for available languages
                    property string sourceLanguage: "auto"
                }
            }

            property JsonObject launcher: JsonObject {
                property list<string> pinnedApps: ["org.kde.dolphin", "kitty", "cmake-gui"]
            }

            property JsonObject light: JsonObject {
                property JsonObject night: JsonObject {
                    property bool automatic: true
                    property bool automaticDarkMode: false // Switch dark/light theme on the same schedule
                    property string from: "19:00" // Format: "HH:mm", 24-hour time
                    property string to: "06:30"   // Format: "HH:mm", 24-hour time
                    property int colorTemperature: 5000
                }
                property JsonObject antiFlashbang: JsonObject {
                    property bool enable: false
                }
                property JsonObject comfortView: JsonObject {
                    property bool enable: false
                    property bool automatic: false
                    property int intensity: 50
                }
                property JsonObject readingMode: JsonObject {
                    property bool enable: false
                    property bool automatic: false
                    property int intensity: 100
                    property bool paperTone: false
                }
            }

            property JsonObject lock: JsonObject {
                property bool useHyprlock: false
                property bool launchOnStartup: false
                property JsonObject blur: JsonObject {
                    property bool enable: true
                    property real radius: 100
                    property real extraZoom: 1.1
                }
                property bool centerClock: true
                property bool showLockedText: true
                property JsonObject security: JsonObject {
                    property bool unlockKeyring: true
                    property bool requirePasswordToPower: false
                }
                property bool materialShapeChars: true
            }

            property JsonObject media: JsonObject {
                // Attempt to remove dupes (the aggregator playerctl one and browsers' native ones when there's plasma browser integration)
                property bool filterDuplicatePlayers: true

                // Automatically sets the active player to a newly detected player if its identifier matches the value specified in the priorityPlayer property like "spotify" or "google-chrome"
                // This comparison uses the desktopEntry property of MprisPlayer (which is the name of the app casting the media)
                property string priorityPlayer: ""
            }

            property JsonObject networking: JsonObject {
                property string userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
            }

            property JsonObject notifications: JsonObject {
                property int timeout: 7000
                // Phone notifications relayed by KDE Connect live on the
                // Continuity page; turn this on to get them here as well.
                property bool phoneOnDesktop: false
                // Android-like notification cooldown: suppress rapid notifications from the same app
                property bool cooldown: true
                property JsonObject monitor: JsonObject {
                    property bool enable: false
                    property string name: "" // Name of the monitor to show notifications on, like "eDP-1". Find out with 'hyprctl monitors' command
                }
            }

            property JsonObject osd: JsonObject {
                property bool enable: true
                property string style: "minimalist"
                property string position: "right"
                // AOSP volume dialog height: 2 * background_margin + 2 * button_size
                // + 2 * components_spacing + volume_dialog_slider_height (254).
                property int height: 418
                property int timeout: 3000
                property bool showValues: false
                property bool hideWhenFullscreen: true

                // Per-indicator popups. Turning one off keeps that OSD from showing
                // on its own; the master `enable` switch above still wins over all.
                property JsonObject indicators: JsonObject {
                    property bool volume: true
                    property bool brightness: true
                    property bool keyboardBrightness: true
                    property bool playerVolume: true
                    property bool gamma: true
                }
                
                property JsonObject material: JsonObject {
                    property bool minimal: false
                    property bool shapedValues: true
                    property bool circledShapes: false
                    property bool rotateShape: false
                }
            }

            property JsonObject languageSwitcher: JsonObject {
                property bool enable: false
            }

            property JsonObject osk: JsonObject {
                property string layout: "qwerty_full"
                property bool pinnedOnStartup: false
            }

            property JsonObject overlay: JsonObject {
                property bool openingZoomAnimation: true
                property bool darkenScreen: true
                property real clickthroughOpacity: 0.8
                property JsonObject floatingImage: JsonObject {
                    property string imageSource: "https://media.tenor.com/H5U5bJzj3oAAAAAi/kukuru.gif"
                    property real scale: 0.5
                }
                property JsonObject notes: JsonObject {
                    property bool showTabs: true
                    property bool allowEditingIcon: true
                }
                property JsonObject media: JsonObject {
                    property int backgroundOpacityPercentage: 100
                    property bool useGradientMask: true
                    property bool showSlider: true
                    property int lyricSize: Appearance.font.pixelSize.larger
                }
            }

            property JsonObject overview: JsonObject {
                property bool enable: true
                property real scale: 0.18 // Relative to screen size
                property real rows: 3
                property real columns: 1
                property bool orderRightLeft: false
                property bool orderBottomUp: false
                property bool showIcons: true
                property bool centerIcons: true
                property bool useWorkspaceMap: true
                property list<var> workspaceMap: [0, 10]
                property bool showOpeningAnimation: true

                property JsonObject scrollingStyle: JsonObject {

                    property int dimPercentage: 50 // 0-75
                    property string backgroundStyle: "blur" // Options: transparent, blur, dim
                    property string zoomStyle: "in"         // Options: in, out
                }
            }

            property JsonObject regionSelector: JsonObject {
                property bool showOnlyOnFocusedMonitor: false
                property JsonObject targetRegions: JsonObject {
                    property bool windows: true
                    property bool layers: false
                    property bool content: true
                    property bool showLabel: false
                    property real opacity: 0.3
                    property real contentRegionOpacity: 0.8
                    property int selectionPadding: 5
                }
                property JsonObject rect: JsonObject {
                    property bool showAimLines: true
                }
                property JsonObject circle: JsonObject {
                    property int strokeWidth: 6
                    property int padding: 10
                }
                property JsonObject annotation: JsonObject {
                    property bool useSatty: false
                }
            }

            property JsonObject resources: JsonObject {
                // Off with bar.resources.showDocker: with nothing rendering the
                // containers there is no reason to keep a `docker events` watcher
                // and a 60s `docker ps` poll running.
                property bool enableDocker: false
                property string gpuPreference: "auto"
                property int gpuInterval: 3000
                property int diskInterval: 30000
                property string diskMount: "/"
                property int updateInterval: 3000
                property int historyLength: 60
            }

            property JsonObject lyricsService: JsonObject {
                property bool enable: true
                property bool enableGenius: true
                property bool enableLrclib: true
            }

            property JsonObject tray: JsonObject {
                property bool monochromeIcons: true
                property bool showItemId: false
                property bool invertPinnedItems: true // Makes the below a whitelist for the tray and blacklist for the pinned area
                property list<var> pinnedItems: ["Fcitx"]
                property bool filterPassive: true
            }

            property JsonObject update: JsonObject {
                property string scriptPath: ""
                property string scriptFlags: "--no-backup --no-confirm"
            }

            property JsonObject musicRecognition: JsonObject {
                property int timeout: 16
                property int interval: 4
            }

            property JsonObject search: JsonObject {
                property int nonAppResultDelay: 30 // This prevents lagging when typing
                property string engineBaseUrl: "https://www.google.com/search?q="
                property list<string> excludedSites: ["quora.com", "facebook.com"]
                property string fileSearchDirectory: "/home"
                property bool blurFileSearchResultPreviews: false
                property JsonObject prefix: JsonObject {
                    property bool showDefaultActionsWithoutPrefix: true
                    property string action: "/"
                    property string app: ">"
                    property string clipboard: ";"
                    property string fileSearch: ","
                    property string emojis: ":"
                    property string math: "="
                    property string shellCommand: "$"
                    property string webSearch: "?"
                }
                property JsonObject imageSearch: JsonObject {
                    property string imageSearchEngineBaseUrl: "https://lens.google.com/uploadbyurl?url="
                    property bool useCircleSelection: false
                }
            }

            property JsonObject sidebar: JsonObject {
                property string position: "default"
                property string uptimeIcon: "" // Image for the uptime pill; empty = user avatar, falling back to the distro logo
                property bool keepRightSidebarLoaded: true
                property bool keepLeftSidebarLoaded: true
                property JsonObject translator: JsonObject {
                    property bool enable: false
                    property int delay: 300 // Delay before sending request. Reduces (potential) rate limits and lag.
                }
                property JsonObject ai: JsonObject {
                    property bool textFadeIn: false
                    property bool showProviderAndModelButtons: true
                }
                property JsonObject booru: JsonObject {
                    property bool allowNsfw: false
                    property string defaultProvider: "yandere"
                    property int limit: 20
                    property JsonObject zerochan: JsonObject {
                        property string username: "[unset]"
                    }
                }
                property JsonObject cornerOpen: JsonObject {
                    property bool enable: false
                    property bool bottom: false
                    property bool valueScroll: true
                    property bool clickless: false
                    property int cornerRegionWidth: 250
                    property int cornerRegionHeight: 5
                    property bool visualize: false
                    property bool clicklessCornerEnd: true
                    property int clicklessCornerVerticalOffset: 1
                }

                property JsonObject quickToggles: JsonObject {
                    property string style: "android" // Options: classic, android
                    property bool useThreeWaySliders: true
                    property JsonObject android: JsonObject {
                        property int columns: 4
                        property int layoutVersion: 2
                        // One entry per page, each a packed list of tiles. The
                        // panel's edit mode owns this: drag to reorder, drag the
                        // handles to resize, chevrons to page.
                        property list<var> pages: [
                            [
                                { "id": "brightnessSlider", "type": "brightnessSlider", "sizeW": 4, "sizeH": 1 },
                                { "id": "volumeSlider", "type": "volumeSlider", "sizeW": 4, "sizeH": 1 },
                                { "id": "network", "type": "network", "sizeW": 2, "sizeH": 1 },
                                { "id": "bluetooth", "type": "bluetooth", "sizeW": 2, "sizeH": 1 },
                                { "id": "mic", "type": "mic", "sizeW": 2, "sizeH": 1 },
                                { "id": "audio", "type": "audio", "sizeW": 2, "sizeH": 1 },
                                { "id": "nightLight", "type": "nightLight", "sizeW": 2, "sizeH": 1 },
                                { "id": "darkMode", "type": "darkMode", "sizeW": 2, "sizeH": 1 }
                            ]
                        ]
                    }
                }

                // The standalone slider row above the quick toggles. Only the
                // classic style draws it - the android panel carries sliders as
                // grid tiles you can move and resize like any other.
                property JsonObject quickSliders: JsonObject {
                    property bool enable: true
                    property bool showMic: true
                    property bool showGamma: true
                    property bool showVolume: true
                    property bool showBrightness: false // gamma setting also works for brightness
                }
            }

            property JsonObject screenRecord: JsonObject {
                property string savePath: root.screenRecordDefaults.savePath
                property string container: root.screenRecordDefaults.container
                property string codec: root.screenRecordDefaults.codec
                property string device: root.screenRecordDefaults.device
                property int framerate: root.screenRecordDefaults.framerate
                property string pixelFormat: root.screenRecordDefaults.pixelFormat
                property int quality: root.screenRecordDefaults.quality
                property string audioMode: root.screenRecordDefaults.audioMode
                property string audioSource: root.screenRecordDefaults.audioSource
                property string audioCodec: root.screenRecordDefaults.audioCodec
                property string extraArgs: root.screenRecordDefaults.extraArgs
            }

            property JsonObject screenSnip: JsonObject {
                property string savePath: "" // only copy to clipboard when empty
                // Android-style card after a snip, offering to save, edit or
                // delete the shot that was just copied. Only ever shown when
                // savePath is empty - with a save path set the crop is already
                // on disk under a name of the user's choosing.
                property bool showPreview: true
                // Corner the preview card slides in at: "top_left", "top_right",
                // "bottom_left" or "bottom_right".
                property string previewCorner: "bottom_left"
                // Seconds the card waits before discarding itself. Hovering it
                // holds it open regardless.
                property int previewTimeout: 2
            }

            property JsonObject sounds: JsonObject {
                property bool enable: true
                property int volume: 100
                property bool alarm: true
                property bool alarmFadeIn: false
                property int alarmFadeInSeconds: 30
                property JsonObject custom: JsonObject {
                    property string alarm: ""
                    property string battery: ""
                }
                property bool battery: false
                property bool pomodoro: false
                property string theme: "freedesktop"
            }

            property JsonObject time: JsonObject {
                property list<var> worldClocks: []
                property JsonObject alarms: JsonObject {
                    property bool useFullscreenPopup: false
                    property bool showAnalogClock: true
                    property bool showWorldClocks: true
                    property bool showAlarmsSection: true
                }
                // https://doc.qt.io/qt-6/qtime.html#toString
                property string format: "hh:mm"
                property string shortDateFormat: "dd/MM"
                property string longDateFormat: "dd/MM/yyyy"
                property string dateWithYearFormat: "dd/MM/yyyy"
                property string dateFormat: "ddd, dd/MM"
                property int firstDayOfWeek: 0 // 0: Monday, 1: Tuesday, 2: Wednesday, 3: Thursday, 4: Friday, 5: Saturday, 6: Sunday

                property JsonObject pomodoro: JsonObject {
                    property int focus: 1500
                }
                property bool secondPrecision: false
            }

            property JsonObject updates: JsonObject {
                property bool enableCheck: true
                property int checkInterval: 120 // minutes
                property int adviseUpdateThreshold: 75 // packages
                property int stronglyAdviseUpdateThreshold: 200 // packages
            }

            property JsonObject wallpaperSelector: JsonObject {
                property bool useSystemFileDialog: false
                property list<var> directories: [
                    {
                        "icon": "wallpaper",
                        "name": "Wallpapers",
                        "path": `${Directories.pictures}/Wallpapers`
                    }
                ]
            }

            property JsonObject windows: JsonObject {
                property bool showTitlebar: true // Client-side decoration for shell apps
                property bool centerTitle: true
            }

            property JsonObject hacks: JsonObject {
                property int arbitraryRaceConditionDelay: 20 // milliseconds
            }

            property JsonObject workSafety: JsonObject {
                property JsonObject enable: JsonObject {
                    property bool wallpaper: false
                    property bool clipboard: false
                }
                property JsonObject triggerCondition: JsonObject {
                    property list<string> networkNameKeywords: ["airport", "cafe", "college", "company", "eduroam", "free", "guest", "public", "school", "university"]
                    property list<string> fileKeywords: ["anime", "booru", "ecchi", "hentai", "yande.re", "konachan", "breast", "nipples", "pussy", "nsfw", "spoiler", "girl"]
                    property list<string> linkKeywords: ["hentai", "porn", "sukebei", "hitomi.la", "rule34", "gelbooru", "fanbox", "dlsite"]
                }
            }

            property JsonObject waffles: JsonObject {
                property JsonObject bar: JsonObject {
                    property bool bottom: true
                    property bool leftAlignApps: false
                }
                property JsonObject actionCenter: JsonObject {
                    property list<string> toggles: ["network", "hotspot", "bluetooth", "easyEffects", "powerProfile", "idleInhibitor", "nightLight", "comfortView", "readingMode", "darkMode", "antiFlashbang", "cloudflareWarp", "mic", "musicRecognition", "notifications", "onScreenKeyboard", "gameMode", "screenSnip", "colorPicker"]
                }
                property JsonObject calendar: JsonObject {
                    property bool force2CharDayOfWeek: true
                }
            }
        }
    }

    function isWidgetActive(widgetId) {
        let list = root.options.background.activeWidgets || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i].widgetId === widgetId)
                return true;
        }
        return false;
    }

    function getWidgetLockBehavior(widgetId) {
        let list = root.options.background.activeWidgets || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i].widgetId === widgetId)
                return list[i].lockBehavior || "hide";
        }
        return "hide";
    }

    function setWidgetLockBehavior(widgetId, newLockBehavior) {
        let cloned = JSON.parse(JSON.stringify(root.options.background.activeWidgets || []));
        for (let i = 0; i < cloned.length; i++) {
            if (cloned[i].widgetId === widgetId) {
                cloned[i].lockBehavior = newLockBehavior;
                root.options.background.activeWidgets = cloned;
                return;
            }
        }
    }

    function addWidgetToDesktop(widgetId, defaultX, defaultY) {
        let cloned = JSON.parse(JSON.stringify(root.options.background.activeWidgets || []));
        for (let i = 0; i < cloned.length; i++) {
            if (cloned[i].widgetId === widgetId)
                return;
        }

        let startX = defaultX !== undefined ? defaultX : 200;
        let startY = defaultY !== undefined ? defaultY : 200;

        if (defaultX === undefined && defaultY === undefined) {
            let offset = 0;
            while (true) {
                let collision = false;
                for (let i = 0; i < cloned.length; i++) {
                    if (Math.abs(cloned[i].x - (startX + offset)) < 30 && Math.abs(cloned[i].y - (startY + offset)) < 30) {
                        collision = true;
                        break;
                    }
                }
                if (!collision) {
                    startX += offset;
                    startY += offset;
                    break;
                }
                offset += 80;
            }
        }

        let instanceId = "widget_" + widgetId + "_" + Date.now();
        cloned.push({
            "id": instanceId,
            "widgetId": widgetId,
            "x": startX,
            "y": startY,
            "placementStrategy": "free",
            "lockBehavior": "hide"
        });
        root.options.background.activeWidgets = cloned;
    }

    function removeWidgetFromDesktop(widgetId) {
        let cloned = JSON.parse(JSON.stringify(root.options.background.activeWidgets || []));
        let indexToRemove = -1;
        for (let i = 0; i < cloned.length; i++) {
            if (cloned[i].widgetId === widgetId) {
                indexToRemove = i;
                break;
            }
        }
        if (indexToRemove !== -1) {
            cloned.splice(indexToRemove, 1);
            root.options.background.activeWidgets = cloned;
        }
    }

    function updateWidgetPosition(instanceId, newX, newY) {
        let cloned = JSON.parse(JSON.stringify(root.options.background.activeWidgets || []));
        let found = false;
        for (let i = 0; i < cloned.length; i++) {
            if (cloned[i].id === instanceId) {
                cloned[i].x = newX;
                cloned[i].y = newY;
                found = true;
                break;
            }
        }
        if (found) {
            root.options.background.activeWidgets = cloned;
        }
    }

    function updateWidgetPlacementStrategy(instanceId, newStrategy) {
        let cloned = JSON.parse(JSON.stringify(root.options.background.activeWidgets || []));
        let found = false;
        for (let i = 0; i < cloned.length; i++) {
            if (cloned[i].id === instanceId) {
                cloned[i].placementStrategy = newStrategy;
                found = true;
                break;
            }
        }
        if (found) {
            root.options.background.activeWidgets = cloned;
        }
    }

    function updateWidgetLockBehavior(instanceId, newLockBehavior) {
        let cloned = JSON.parse(JSON.stringify(root.options.background.activeWidgets || []));
        let found = false;
        for (let i = 0; i < cloned.length; i++) {
            if (cloned[i].id === instanceId) {
                cloned[i].lockBehavior = newLockBehavior;
                found = true;
                break;
            }
        }
        if (found) {
            root.options.background.activeWidgets = cloned;
        }
    }

    function osdIndicatorEnabled(indicatorId): bool {
        if (!root.ready || !root.options.osd)
            return true;
        if (!root.options.osd.enable)
            return false;
        const indicators = root.options.osd.indicators;
        if (!indicators)
            return true;
        switch (indicatorId) {
        case "volume":
            return indicators.volume;
        case "brightness":
            return indicators.brightness;
        case "keyboardBrightness":
            return indicators.keyboardBrightness;
        case "playerVolume":
            return indicators.playerVolume;
        case "gamma":
            return indicators.gamma;
        }
        return true;
    }

    function migrateWidgetLockBehavior() {
        // Same trap as the widget migration: an unloaded Persistent reports "not migrated yet".
        if (!Persistent.ready || Persistent.states.background.lockBehaviorMigrated)
            return;
        let cloned = JSON.parse(JSON.stringify(root.options.background.activeWidgets || []));
        let changed = false;
        for (let i = 0; i < cloned.length; i++) {
            if (!cloned[i].lockBehavior) {
                cloned[i].lockBehavior = "hide";
                changed = true;
            }
        }
        if (changed) {
            root.options.background.activeWidgets = cloned;
        }
        Persistent.states.background.lockBehaviorMigrated = true;
    }
}
