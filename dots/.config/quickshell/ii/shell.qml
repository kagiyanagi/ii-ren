//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Qt 6.11 defaults to its native PipeWire audio backend, whose QAudioContext thread
// segfaults the shell inside libpipewire-module-protocol-native when sounds play.
// Its PulseAudio backend (through pipewire-pulse) does not.
//@ pragma Env QT_AUDIO_BACKEND=pulseaudio

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "services"
import "panelFamilies"

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    

    // Stuff for every panel family
    ReloadPopup {}

    Component.onCompleted: {
        // Quickshell restarts a crashed shell with __QUICKSHELL_CRASH_* set and never clears
        // them, so every qs it spawns (settings, ipc calls) boots a second whole shell instead.
        if (Quickshell.env("__QUICKSHELL_CRASH_DUMP_PID")) {
            Quickshell.execDetached(["env", "-u", "__QUICKSHELL_CRASH_INFO_FD", "-u", "__QUICKSHELL_CRASH_DUMP_PID",
                "-u", "__QUICKSHELL_CRASH_SIGNAL", "qs", "-p", Quickshell.shellPath("shell.qml")])
            Qt.callLater(Qt.quit) // quit is not wired up until the root finishes loading
            return
        }
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        HyprlandComfortView.load()
        HyprlandReadingMode.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        Wallpapers.load()
        Autostart.load()
        Updates.load()
        HermesService.load()
        SoundService.load()
        if (Config.ready) root.activeFamily = Config.options.panelFamily
    }


    // Panel families
    property list<string> families: ["ii", "waffle"]
    // Loaders read only this latch, never panelFamily itself: on a switch the
    // outgoing family must unload before the incoming one loads, since both
    // declare IpcHandlers on the same targets. A binding on panelFamily and a
    // handler on its change signal run in no defined order.
    property string activeFamily: ""

    Timer {
        id: familySwitchTimer
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        onTriggered: root.activeFamily = Config.options.panelFamily
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) root.activeFamily = Config.options.panelFamily
        }
    }

    Connections {
        target: Config.options
        function onPanelFamilyChanged() {
            // Not loaded yet, or the load itself notifying: nothing to switch.
            if (root.activeFamily === "" || root.activeFamily === Config.options.panelFamily) return
            root.activeFamily = ""
            familySwitchTimer.restart()
        }
    }

    function cyclePanelFamily() {
        const currentIndex = families.indexOf(Config.options.panelFamily)
        const nextIndex = (currentIndex + 1) % families.length
        Config.options.panelFamily = families[nextIndex]
    }

    component PanelFamilyLoader: LazyLoader {
        required property string identifier
        property bool extraCondition: true
        active: root.activeFamily === identifier && extraCondition
    }
    
    PanelFamilyLoader {
        identifier: "ii"
        component: IllogicalImpulseFamily {}
    }

    PanelFamilyLoader {
        identifier: "waffle"
        component: WaffleFamily {}
    }


    // Shortcuts
    IpcHandler {
        target: "panelFamily"

        function cycle(): void {
            root.cyclePanelFamily()
        }
    }

    GlobalShortcut {
        name: "panelFamilyCycle"
        description: "Cycles panel family"

        onPressed: root.cyclePanelFamily()
    }
}
