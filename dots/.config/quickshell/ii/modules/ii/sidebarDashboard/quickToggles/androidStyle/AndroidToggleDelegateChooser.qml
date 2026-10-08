pragma ComponentBehavior: Bound
import qs.modules.common.widgets
import QtQuick

// One entry per toggle type. Everything a tile needs beyond its own data --
// cell size, edit mode, which page it is on -- it reads back off this chooser,
// so an entry stays down to the type, its data and where a long-press goes.
DelegateChooser {
    id: root
    property var panel: null
    property var gridRef: null
    property int pageIndex: 0
    property bool isUnused: false
    signal openAudioOutputDialog
    signal openAudioInputDialog
    signal openBluetoothDialog
    signal openNightLightDialog
    signal openComfortViewDialog
    signal openReadingModeDialog
    signal openAntiFlashbangDialog
    signal openWifiDialog
    signal openHotspotDialog
    signal openDnsDialog
    signal openVpnDialog
    signal openIdleDialog
    signal openEditCustomToggleDialog(string toggleId)

    role: "toggleType"

    DelegateChoice {
        roleValue: "antiFlashbang"
        AndroidAntiFlashbangToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openAntiFlashbangDialog()
        }
    }

    DelegateChoice {
        roleValue: "keyboardBacklight"
        AndroidKeyboardBacklightToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "audio"
        AndroidAudioToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openAudioOutputDialog()
        }
    }

    DelegateChoice {
        roleValue: "bluetooth"
        AndroidBluetoothToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openBluetoothDialog()
        }
    }

    DelegateChoice {
        roleValue: "colorPicker"
        AndroidColorPickerToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "darkMode"
        AndroidDarkModeToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "easyEffects"
        AndroidEasyEffectsToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "gameMode"
        AndroidGameModeToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "floatingMode"
        AndroidFloatingModeToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "localSend"
        AndroidLocalSendToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "idleInhibitor"
        AndroidIdleInhibitorToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openIdleDialog()
        }
    }

    DelegateChoice {
        roleValue: "location"
        AndroidLocationToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "mic"
        AndroidMicToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openAudioInputDialog()
        }
    }

    DelegateChoice {
        roleValue: "musicRecognition"
        AndroidMusicRecognition {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "network"
        AndroidNetworkToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openWifiDialog()
        }
    }

    DelegateChoice {
        roleValue: "hotspot"
        AndroidHotspotToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openHotspotDialog()
        }
    }

    DelegateChoice {
        roleValue: "dns"
        AndroidDnsToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openDnsDialog()
        }
    }

    DelegateChoice {
        roleValue: "vpn"
        AndroidVpnToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openVpnDialog()
        }
    }

    DelegateChoice {
        roleValue: "nightLight"
        AndroidNightLightToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openNightLightDialog()
        }
    }

    DelegateChoice {
        roleValue: "onScreenKeyboard"
        AndroidOnScreenKeyboardToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "keypressDisplay"
        AndroidKeypressDisplayToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "powerProfile"
        AndroidPowerProfileToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "screenSnip"
        AndroidScreenSnipToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "mediaWidget"
        AndroidMediaWidgetToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "volumeSlider"
        AndroidVolumeSliderToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openAudioOutputDialog()
        }
    }

    DelegateChoice {
        roleValue: "micSlider"
        AndroidMicSliderToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openAudioInputDialog()
        }
    }

    DelegateChoice {
        roleValue: "brightnessSlider"
        AndroidBrightnessSliderToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "gammaSlider"
        AndroidGammaSliderToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }

    DelegateChoice {
        roleValue: "comfortView"
        AndroidComfortViewToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openComfortViewDialog()
        }
    }

    DelegateChoice {
        roleValue: "readingMode"
        AndroidReadingModeToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
            onOpenMenu: root.openReadingModeDialog()
        }
    }

    DelegateChoice {
        roleValue: "custom"
        AndroidCustomToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            buttonData: modelData
            chooser: root
        }
    }
}
