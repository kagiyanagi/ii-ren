import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Keyboard light")
    icon: KeyboardBacklight.currentValue > 0 ? "keyboard_full" : "keyboard_off"
    toggled: KeyboardBacklight.currentValue > 0
    available: KeyboardBacklight.available
    statusText: KeyboardBacklight.maxValue > 1 ? `${KeyboardBacklight.currentValue}/${KeyboardBacklight.maxValue}` : (KeyboardBacklight.currentValue > 0 ? Translation.tr("On") : Translation.tr("Off"))

    mainAction: () => KeyboardBacklight.cycle()
    tooltipText: Translation.tr("Click to cycle keyboard backlight")
}
