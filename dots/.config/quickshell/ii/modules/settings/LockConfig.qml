import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    readonly property int index: 12
    property bool register: parent.register ?? false
    forceWidth: true

    ContentSection {
        icon: "lock"
        title: Translation.tr("Lock Screen")

        ConfigSwitch {
            buttonIcon: "lock"
            text: Translation.tr("Use Hyprlock")
            checked: Config.options.lock.useHyprlock
            onCheckedChanged: {
                Config.options.lock.useHyprlock = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "rocket_launch"
            text: Translation.tr("Launch on startup")
            checked: Config.options.lock.launchOnStartup
            onCheckedChanged: {
                Config.options.lock.launchOnStartup = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "text_fields"
            text: Translation.tr("Show locked text")
            checked: Config.options.lock.showLockedText
            onCheckedChanged: {
                Config.options.lock.showLockedText = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "category"
            text: Translation.tr("Material shape characters")
            checked: Config.options.lock.materialShapeChars
            onCheckedChanged: {
                Config.options.lock.materialShapeChars = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "push_pin"
            text: Translation.tr("Lock widget size and position")
            checked: Config.options.lock.lockWidgetPositions
            onCheckedChanged: {
                Config.options.lock.lockWidgetPositions = checked;
            }
        }
    }

    ContentSection {
        icon: "security"
        title: Translation.tr("Security")

        ConfigSwitch {
            buttonIcon: "key"
            text: Translation.tr("Unlock keyring")
            checked: Config.options.lock.security.unlockKeyring
            onCheckedChanged: {
                Config.options.lock.security.unlockKeyring = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Require password to power off")
            checked: Config.options.lock.security.requirePasswordToPower
            onCheckedChanged: {
                Config.options.lock.security.requirePasswordToPower = checked;
            }
        }
    }
}
