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
        readonly property int index: 12
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

            // Metrics copied from ConfigSwitch so this sits flush with the
            // rows above it instead of reading as a different kind of control.
            RippleButton {
                id: fingerprintEntry

                Layout.fillWidth: true
                leftPadding: 8
                rightPadding: 8
                implicitHeight: contentItem.implicitHeight + 12 * 2
                buttonRadius: Appearance.rounding.verysmall
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)

                onClicked: lockConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/FingerprintConfig.qml")

                SearchHandler {
                    searchString: Translation.tr("Fingerprint")
                }

                contentItem: RowLayout {
                    spacing: 10

                    MaterialSymbol {
                        text: "fingerprint"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: Translation.tr("Fingerprint")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSecondaryContainer
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: {
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
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    MaterialSymbol {
                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
