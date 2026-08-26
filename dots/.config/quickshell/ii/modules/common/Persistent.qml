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

            property JsonObject ai: JsonObject {
                property string provider: "google" // AI providers such as google, open router, mistral
                property string model: "gemini-2.5-flash" // The model of the ai such as 2.5-flash
                property real temperature: 0.5
            }

            property JsonObject water: JsonObject {
                property int glassesDrunk: 0
                property string lastDate: ""
                property real lastNotify: 0
            }
            property JsonObject background: JsonObject {
                property bool widgetsMigrated: false
                property bool lockBehaviorMigrated: false
                property JsonObject mediaMode: JsonObject {
                    property real userScrollOffset: 0
                }
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
            }

            property JsonObject booru: JsonObject {
                property bool allowNsfw: false
                property string provider: "yandere"
            }

            property JsonObject hyprland: JsonObject {
                property string layout: "dwindle"
            }

            property JsonObject idle: JsonObject {
                property bool inhibit: false
                property string sessionId: ""
            }

            property JsonObject overlay: JsonObject {
                property list<string> open: ["crosshair", "recorder", "media", "volumeMixer", "resources"]
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
                property int seconds: 0
            }

            property JsonObject settings: JsonObject {
                property JsonObject fonts: JsonObject {
                    property string main: "Google Sans Flex"
                    property string numbers: "Google Sans Flex"
                    property string title: "Google Sans Flex"
                    property string iconNerd: "JetBrains Mono NF"
                    property string monospace: "JetBrains Mono NF"
                    property string reading: "Readex Pro"
                    property string expressive: "Space Grotesk" 
                }
            }

            property JsonObject timer: JsonObject {
                property JsonObject pomodoro: JsonObject {
                    property bool running: false
                    property int start: 0
                    property bool isBreak: false
                    property int cycle: 0
                }
                property JsonObject stopwatch: JsonObject {
                    property bool running: false
                    property int start: 0
                    property list<var> laps: []
                }
            }
            property JsonObject media: JsonObject {
                property rect popupRect: Qt.rect(0, 0, 0, 0)
            }

            property JsonObject wallpaper: JsonObject {
                property list<string> favourites: []
            }
        }
    }
}
