import QtQuick
import qs.modules.common

Rectangle {
    id: root

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    signal openAudioOutputDialog()
    signal openAudioInputDialog()
    signal openBluetoothDialog()
    signal openNightLightDialog()
    signal openComfortViewDialog()
    signal openReadingModeDialog()
    signal openAntiFlashbangDialog()
    signal openWifiDialog()
    signal openHotspotDialog()
    signal openDnsDialog()
    signal openIdleDialog()
    signal openVpnDialog()
    signal openEditCustomToggleDialog(string toggleId)
    signal openNewCustomToggleDialog()
}
