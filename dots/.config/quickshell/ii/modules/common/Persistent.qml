pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property alias states: persistentStatesJsonAdapter
    property string fileDir: Directories.state
    property string fileName: "states.json"
    property string filePath: `${root.fileDir}/${root.fileName}`

    property bool ready: false
    property string previousHyprlandInstanceSignature: ""
    property bool isNewHyprlandInstance: previousHyprlandInstanceSignature !== states.hyprlandInstanceSignature

    onReadyChanged: {
        root.previousHyprlandInstanceSignature = root.states.hyprlandInstanceSignature
        root.states.hyprlandInstanceSignature = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    }

    Timer {
        id: fileReloadTimer
        interval: 100
        repeat: false
        onTriggered: {
            persistentStatesFileView.reload()
        }
    }

    Timer {
        id: fileWriteTimer
        interval: 100
        repeat: false
        onTriggered: {
            persistentStatesFileView.writeAdapter()
        }
    }

    FileView {
        id: persistentStatesFileView
        path: root.filePath

        watchChanges: true
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: fileWriteTimer.restart()
        onLoaded: root.ready = true
        onLoadFailed: error => {
            console.log("Failed to load persistent states file:", error);
            if (error == FileViewError.FileNotFound) {
                fileWriteTimer.restart();
            }
        }

        adapter: JsonAdapter {
            id: persistentStatesJsonAdapter

            property string hyprlandInstanceSignature: ""

            property JsonObject hermes: JsonObject {
                // Applied to each new session with `--session`, so the sidebar's
                // model never overwrites what the hermes CLI starts on.
                property string model: ""
                property string provider: ""
                // A connection id from the Hermes desktop app's connections.json.
                property string gateway: "local"
            }

            property JsonObject water: JsonObject {
                property int glassesDrunk: 0
                property string lastDate: ""
                property real lastNotify: 0
            }
            property JsonObject background: JsonObject {
                property bool widgetsMigrated: false
                property bool lockBehaviorMigrated: false
            }

            property JsonObject cheatsheet: JsonObject {
                property int tabIndex: 0
            }

            property JsonObject sidebar: JsonObject {
                property JsonObject policies: JsonObject {
                    property int tab: 0
                }
                property JsonObject bottomGroup: JsonObject {
                    property bool collapsed: false
                    property int tab: 0
                }
                // Ids of the custom quick toggles last clicked on (services/CustomToggles.qml).
                property list<string> activeCustomToggles: []
            }

            property JsonObject booru: JsonObject {
                property bool allowNsfw: false
                property string provider: "yandere"
            }

            property JsonObject hyprland: JsonObject {
                property string layout: "dwindle"
                property bool floatingMode: false
                // Classes whose windows get a floating-mode bar, so an app's bar is on its
                // first frame from its second launch on, reboots included.
                property list<string> floatingBarClasses: []
            }

            property JsonObject lock: JsonObject {
                // Whether the session is locked *right now*, not whether it
                // should be. A session lock outlives the process holding it, so
                // a shell that restarts under its own lock has to take it back,
                // and nothing in Hyprland's IPC will tell it that it must.
                // LockScreen.qml has the whole story.
                property bool locked: false
            }

            property JsonObject idle: JsonObject {
                property bool inhibit: false
                property string sessionId: ""
                // The last duration picked, in minutes; 0 is until turned off.
                property int minutes: 0
                // When the running one ends, epoch ms; 0 is never.
                property real until: 0
                // Processes it stays awake for, as Idle.anchors has them.
                property list<var> anchors: []
            }

            property JsonObject overlay: JsonObject {
                property list<string> open: ["crosshair", "recorder", "media", "volumeMixer", "resources"]
                property JsonObject assist: OverlayState { x: 1200; y: 120; width: 480; height: 420 }
                property JsonObject crosshair: OverlayState { clickthrough: true; x: 827; y: 441; width: 250; height: 100 }
                property JsonObject media: OverlayState { clickthrough: true; x: 827; y: 441; width: 250; height: 100 }
                property JsonObject floatingImage: OverlayState { x: 1650; y: 390; width: 0; height: 0 }
                property JsonObject fpsLimiter: OverlayState { x: 1570; y: 615; width: 280; height: 80 }
                property JsonObject recorder: OverlayState { x: 80; y: 80; width: 350; height: 130 }
                property JsonObject resources: OverlayState { property int tabIndex: 0; clickthrough: true; x: 1500; y: 770; width: 350; height: 200 }
                property JsonObject volumeMixer: OverlayState { property int tabIndex: 0; x: 80; y: 280; width: 350; height: 600 }
                property JsonObject notes: OverlayState { property int tabIndex: 0; clickthrough: true; x: 1400; y: 42; width: 460; height: 330 }
            }

            property JsonObject screenRecord: JsonObject {
                property bool active: false
                property bool paused: false
                property int seconds: 0
            }

            property JsonObject settings: JsonObject {
                property JsonObject fonts: JsonObject {
                    property string main: "Google Sans Flex"
                    property string numbers: "Google Sans Flex"
                    property string title: "Google Sans Flex"
                    property string iconNerd: "Maple Mono NF"
                    property string monospace: "Maple Mono NF"
                    property string reading: "Readex Pro"
                    property string expressive: "Space Grotesk" 
                }
            }

            property JsonObject timer: JsonObject {
                property JsonObject pomodoro: JsonObject {
                    property bool running: false
                    property int start: 0
                }
                property JsonObject stopwatch: JsonObject {
                    property bool running: false
                    // In 10ms ticks since the epoch, which passed int's range in 1970.
                    property real start: 0
                    property list<var> laps: []
                }
            }
            property JsonObject media: JsonObject {
                // Four numbers rather than a rect: JsonAdapter cannot serialize a
                // QRectF, so a stored rect comes back as null and warns on every
                // start.
                property real popupX: 0
                property real popupY: 0
                property real popupWidth: 0
                property real popupHeight: 0
            }

            property list<var> alarms: []

            property JsonObject wallpaper: JsonObject {
                property list<string> favourites: []
            }

            // Per-wallpaper fit, zoom, pan and custom subject, keyed by path;
            // wallpaperFraming.js reads and writes it. A wallpaper still at the
            // defaults has no entry. Rebuilt whole on every change, since
            // JsonAdapter only notices a new value.
            //
            // It belongs in `wallpaper` above and has to live out here: JsonAdapter
            // deserializes a `var` by reading and writing it on the adapter rather
            // than on the JsonObject that holds it, so one nested anywhere below
            // this level writes into the wrong object and crashes the shell on
            // every load of this file.
            property var wallpaperFraming: ({})
        }
    }
}
