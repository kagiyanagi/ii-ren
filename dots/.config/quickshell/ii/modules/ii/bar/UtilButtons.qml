import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Item {
    id: root
    property bool vertical: false
    // Material style: tonal circles in the group pill (CircleUtilButton). Each
    // paints 4 in from its own 32px target, so no spacing or edge goes round
    // them -- 4 to the pill's ends, 8 between.
    readonly property bool material: Config.options.bar.barGroupStyle === 3 && !root.vertical
    readonly property int edge: root.material ? 0 : 4
    implicitWidth: gridLayout.implicitWidth + root.edge * 2
    implicitHeight: gridLayout.implicitHeight + 8

    // Implicit size is spatial, so it takes the resize spec, not the effects one
    // a colour fade uses (the motion table, 2.3). Not in Material style: a button
    // opening under the pointer already animates its own width, and chasing it
    // here would leave the pill a step behind its contents.
    Behavior on implicitWidth {
        enabled: !root.material
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    component UtilButton: CircleUtilButton {
        material: root.material
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        rows: root.vertical ? -1 : 1

        rowSpacing: 4
        columnSpacing: root.edge
        anchors.centerIn: parent

        Loader {
            active: Config.options.bar.utilButtons.showScreenSnip
            visible: active
            sourceComponent: UtilButton {
                iconName: "screenshot_region"
                iconFill: 1
                onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"])
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showScreenRecord
            visible: active
            sourceComponent: UtilButton {
                active: Persistent.states.screenRecord.active
                iconName: active ? "stop" : "videocam"
                iconFill: 1
                onClicked: Quickshell.execDetached([Directories.recordScriptPath])
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showColorPicker
            visible: active
            sourceComponent: UtilButton {
                iconName: "colorize"
                iconFill: 1
                onClicked: Quickshell.execDetached(["hyprpicker", "-a"])
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showKeyboardToggle
            visible: active
            sourceComponent: UtilButton {
                active: GlobalStates.oskOpen
                iconName: "keyboard"
                onClicked: GlobalStates.oskOpen = !GlobalStates.oskOpen
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showKeyboardBacklight && KeyboardBacklight.available
            visible: active
            sourceComponent: UtilButton {
                iconName: KeyboardBacklight.currentValue > 0 ? "keyboard_full" : "keyboard_off"
                iconFill: KeyboardBacklight.currentValue > 0 ? 1 : 0
                onClicked: KeyboardBacklight.cycle()
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showMicToggle
            visible: active
            sourceComponent: UtilButton {
                iconName: Pipewire.defaultAudioSource?.audio?.muted ? "mic_off" : "mic"
                onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_SOURCE@", "toggle"])
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showDarkModeToggle
            visible: active
            sourceComponent: UtilButton {
                iconName: Appearance.m3colors.darkmode ? "light_mode" : "dark_mode"
                onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", Appearance.m3colors.darkmode ? "light" : "dark", "--noswitch"])
            }
        }

        Loader {
            active: Config.options.bar.utilButtons.showPerformanceProfileToggle
            visible: active
            sourceComponent: UtilButton {
                iconName: switch (PowerProfiles.profile) {
                    case PowerProfile.PowerSaver: return "energy_savings_leaf"
                    case PowerProfile.Balanced: return "airwave"
                    case PowerProfile.Performance: return "local_fire_department"
                }
                onClicked: {
                    if (!PowerProfiles.hasPerformanceProfile) {
                        PowerProfiles.profile = PowerProfiles.profile == PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced
                        return
                    }
                    switch (PowerProfiles.profile) {
                        case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced; break
                        case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance; break
                        case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver; break
                    }
                }
            }
        }
    }
}
