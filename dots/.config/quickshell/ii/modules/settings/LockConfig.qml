import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: lockConfigRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage
    property bool register: parent.register ?? false

    // Lets the settings search (and II_SETTINGS_HIGHLIGHT) land straight on a
    // sub-page instead of only on a section of this one.
    Connections {
        target: root
        function onPendingSectionHighlightChanged() {
            if (root.pendingSectionHighlight && root.pendingSectionHighlight.endsWith(".qml")) {
                lockConfigRoot.activeSubPage = Qt.resolvedUrl(root.pendingSectionHighlight);
                root.pendingSectionHighlight = "";
            }
        }
    }

    Component.onCompleted: {
        if (root.pendingSectionHighlight && root.pendingSectionHighlight.endsWith(".qml")) {
            lockConfigRoot.activeSubPage = Qt.resolvedUrl(root.pendingSectionHighlight);
            root.pendingSectionHighlight = "";
        }
    }

    ContentPage {
        id: page
        readonly property int index: 10
        property bool register: lockConfigRoot.register
        anchors.fill: parent
        forceWidth: true

        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

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
        }

        // These three style the shell's own lock surface. With Hyprlock on it never
        // shows, so they are greyed out rather than left looking live. The switches
        // take `enabled`, not the section, so the header's info icon still hovers.
        ContentSection {
            icon: "palette"
            title: Translation.tr("Appearance")
            tooltip: Translation.tr("These style the built-in lock screen, so they do nothing while Hyprlock is used")

            ConfigSwitch {
                buttonIcon: "text_fields"
                enabled: !Config.options.lock.useHyprlock
                text: Translation.tr("Show locked text")
                checked: Config.options.lock.showLockedText
                onCheckedChanged: {
                    Config.options.lock.showLockedText = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "category"
                enabled: !Config.options.lock.useHyprlock
                text: Translation.tr("Material shape characters")
                checked: Config.options.lock.materialShapeChars
                onCheckedChanged: {
                    Config.options.lock.materialShapeChars = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "bolt"
                enabled: !Config.options.lock.useHyprlock
                text: Translation.tr("Show charging info")
                checked: Config.options.lock.showChargingInfo
                onCheckedChanged: {
                    Config.options.lock.showChargingInfo = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "push_pin"
                enabled: !Config.options.lock.useHyprlock
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
            stringMap: [Translation.tr("Fingerprint"), Translation.tr("Biometrics"), Translation.tr("fprintd")]

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

            ConfigNavRow {
                buttonIcon: "fingerprint"
                text: Translation.tr("Fingerprint")
                summary: {
                    if (!Fingerprint.installed)
                        return Translation.tr("fprintd is not installed");
                    if (!Config.options.lock.security.fingerprint.enable)
                        return Translation.tr("Off");
                    if (!Fingerprint.enrolledLoaded)
                        return Translation.tr("Checking…");
                    if (Fingerprint.enrolled.length === 0)
                        return Translation.tr("No fingerprints added");
                    return Translation.tr("%1 added").arg(Fingerprint.enrolled.length);
                }
                onClicked: lockConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/FingerprintConfig.qml")
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
