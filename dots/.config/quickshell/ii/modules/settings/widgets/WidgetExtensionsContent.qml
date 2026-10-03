pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Installed extensions: the list, and the field that adds to it.
 *
 * Four states, and none of them is a spinner over a greyed page — the list
 * keeps its shape and the rows fill in:
 *   loading  registry not read yet (up to ~2s on a machine with no
 *            widget_extensions.json) -> one pending card, same shape as a real one
 *   empty    read, nothing installed -> PagePlaceholder
 *   offline  install or update failed, network included -> NoticeBox, which is
 *            the shell's failure surface and hides itself when there is no error
 *   busy     an install in flight -> the Install button says so and a pending
 *            card for the thing being installed joins the end of the list
 */
ColumnLayout {
    id: root
    signal extensionConfigRequested(string extId)

    // 5.3: sections in a panel sit 12–16 apart. ColumnLayout's own default is 5,
    // which is off the grid.
    spacing: 12

    readonly property var installedIds: {
        if (!WidgetExtensionManager.ready)
            return [];
        return Object.keys(WidgetExtensionManager.installedWidgets);
    }

    // What the Install button was last pointed at. Only read while the manager
    // is busy, so it never needs clearing.
    property string pendingInstall: ""

    function install(target: string): void {
        const trimmed = (target ?? "").trim();
        if (trimmed.length === 0 || WidgetExtensionManager.loading)
            return;
        root.pendingInstall = trimmed;
        WidgetExtensionManager.installWidget(trimmed);
        extInstallInput.text = "";
    }

    // A card with nothing in it yet: the registry loading, or an install in
    // flight. Same width, colour and radius as a real extension card, so the
    // list does not change shape when one arrives.
    component PendingCard: Rectangle {
        id: pendingCard
        property string label: ""

        Layout.fillWidth: true
        implicitHeight: pendingCardCol.implicitHeight + 24
        color: Appearance.colors.colLayer2
        radius: Appearance.rounding.large

        ColumnLayout {
            id: pendingCardCol
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 12
            }
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: pendingCard.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideMiddle
            }

            StyledIndeterminateProgressBar {
                Layout.fillWidth: true
            }
        }
    }

    // Icon-only action on a card. RippleButton carries all four states and the
    // pointing hand; the tooltip reads the button's own `hovered`.
    component CardIconButton: RippleButton {
        id: cardIconButton
        property string materialIcon: ""
        property string tooltipText: ""
        property color colIcon: Appearance.colors.colOnSecondaryContainer

        // 9's icon-button recipe: square, full radius, no padding (Controls'
        // Basic style would otherwise leave the symbol 16px to draw 20 in), and
        // 3.4's 32px minimum hit area.
        implicitWidth: 32
        implicitHeight: 32
        padding: 0
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        colStateLayer: cardIconButton.colIcon

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: cardIconButton.materialIcon
            iconSize: Appearance.font.pixelSize.larger
            color: cardIconButton.colIcon
        }

        StyledToolTip {
            text: cardIconButton.tooltipText
        }
    }

    // Install input row
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        ToolbarTextField {
            id: extInstallInput
            Layout.fillWidth: true
            implicitHeight: 40
            placeholderText: Translation.tr("GitHub URL or local absolute path")
            font.pixelSize: Appearance.font.pixelSize.normal
            // 3.7: Enter accepts a text field.
            onAccepted: root.install(extInstallInput.text)
        }

        RippleButtonWithIcon {
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive
            colText: Appearance.colors.colOnPrimaryContainer
            materialIcon: WidgetExtensionManager.loading ? "hourglass_top" : "download"
            mainText: WidgetExtensionManager.loading ? Translation.tr("Installing...") : Translation.tr("Install")
            enabled: !WidgetExtensionManager.loading && extInstallInput.text.trim().length > 0
            onClicked: root.install(extInstallInput.text)
        }
    }

    // Failure notice — install and update both report here, network failures
    // included. NoticeBox hides itself while the text is empty.
    NoticeBox {
        materialIcon: "error"
        text: WidgetExtensionManager.lastError
    }

    // The list
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: root.installedIds.map(function (k) {
                return Object.assign({
                    _extId: k
                }, WidgetExtensionManager.installedWidgets[k]);
            })

            delegate: Rectangle {
                id: extCard
                Layout.fillWidth: true
                implicitHeight: extCardCol.implicitHeight + 24
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.large

                required property var modelData
                required property int index

                readonly property string extId: modelData._extId || ""
                readonly property bool isEnabled: modelData.enabled ?? true
                readonly property var wj: modelData.widgetJson || ({})
                readonly property var activeEntry: {
                    const list = Config.options.background.activeWidgets || [];
                    for (let i = 0; i < list.length; i++) {
                        if (list[i].widgetId === "ext:" + extCard.extId)
                            return list[i];
                    }
                    return null;
                }
                readonly property bool isWidgetActive: extCard.activeEntry !== null
                readonly property string lockBehavior: extCard.activeEntry?.lockBehavior || "hide"

                ColumnLayout {
                    id: extCardCol
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: 12
                    }
                    spacing: 8

                    // Header: icon + name + toggle
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: extCard.wj.icon || "extension"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: extCard.modelData.name || extCard.extId
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer2
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    const parts = [];
                                    if (extCard.modelData.author)
                                        parts.push("@" + extCard.modelData.author);
                                    if (extCard.modelData.version)
                                        parts.push("v" + extCard.modelData.version);
                                    if (extCard.modelData.isLocal)
                                        parts.push(Translation.tr("local"));
                                    return parts.join(" · ");
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                                visible: text !== ""
                                elide: Text.ElideRight
                            }
                        }

                        StyledSwitch {
                            Layout.alignment: Qt.AlignVCenter
                            checked: extCard.isEnabled
                            onToggled: WidgetExtensionManager.toggleWidget(extCard.extId, checked)
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: extCard.modelData.description || ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                        wrapMode: Text.WordWrap
                        visible: text !== ""
                    }

                    // Actions
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        // Add to / remove from the desktop
                        RippleButtonWithIcon {
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: extCard.isWidgetActive ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
                            colBackgroundHover: extCard.isWidgetActive ? Appearance.colors.colErrorContainerHover : Appearance.colors.colPrimaryContainerHover
                            colRipple: extCard.isWidgetActive ? Appearance.colors.colErrorContainerActive : Appearance.colors.colPrimaryContainerActive
                            colText: extCard.isWidgetActive ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                            materialIcon: extCard.isWidgetActive ? "delete" : "add"
                            mainText: extCard.isWidgetActive ? Translation.tr("Remove") : Translation.tr("Add to desktop")
                            // A disabled control is 0.4 and still there (3.1);
                            // RippleButton applies that itself.
                            enabled: extCard.isEnabled
                            onClicked: {
                                if (extCard.isWidgetActive)
                                    Config.removeWidgetFromDesktop("ext:" + extCard.extId);
                                else
                                    Config.addWidgetToDesktop("ext:" + extCard.extId);
                            }
                        }

                        CardIconButton {
                            materialIcon: "settings"
                            tooltipText: Translation.tr("Widget settings")
                            visible: Object.keys(extCard.wj.configSchema || {}).length > 0
                            onClicked: root.extensionConfigRequested(extCard.extId)
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        CardIconButton {
                            materialIcon: "refresh"
                            tooltipText: Translation.tr("Reload widget")
                            visible: extCard.modelData.isLocal ?? false
                            colBackground: Appearance.colors.colTertiaryContainer
                            colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                            colRipple: Appearance.colors.colTertiaryContainerActive
                            colIcon: Appearance.colors.colOnTertiaryContainer
                            onClicked: WidgetExtensionManager.reloadLocalWidget(extCard.extId)
                        }

                        CardIconButton {
                            materialIcon: "system_update_alt"
                            tooltipText: Translation.tr("Update widget")
                            visible: !(extCard.modelData.isLocal ?? false)
                            colBackground: Appearance.colors.colTertiaryContainer
                            colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                            colRipple: Appearance.colors.colTertiaryContainerActive
                            colIcon: Appearance.colors.colOnTertiaryContainer
                            enabled: !WidgetExtensionManager.loading
                            onClicked: WidgetExtensionManager.updateWidget(extCard.extId)
                        }

                        CardIconButton {
                            materialIcon: "delete"
                            tooltipText: Translation.tr("Uninstall widget")
                            colBackground: Appearance.colors.colErrorContainer
                            colBackgroundHover: Appearance.colors.colErrorContainerHover
                            colRipple: Appearance.colors.colErrorContainerActive
                            colIcon: Appearance.colors.colOnErrorContainer
                            onClicked: WidgetExtensionManager.uninstallWidget(extCard.extId)
                        }
                    }

                    // Lock behaviour — only applies while the widget is on the
                    // desktop, so the whole group goes when it is not.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: extCard.isWidgetActive
                        spacing: 4

                        StyledText {
                            text: Translation.tr("On the lock screen")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        ConfigSelectionArray {
                            currentValue: extCard.lockBehavior
                            onSelected: newValue => Config.setWidgetLockBehavior("ext:" + extCard.extId, newValue)
                            options: [
                                {
                                    displayName: Translation.tr("Hide"),
                                    icon: "visibility_off",
                                    value: "hide"
                                },
                                {
                                    displayName: Translation.tr("Show"),
                                    icon: "visibility",
                                    value: "keep"
                                },
                                {
                                    displayName: Translation.tr("Centre"),
                                    icon: "center_focus_strong",
                                    value: "center"
                                },
                                {
                                    displayName: Translation.tr("Lock only"),
                                    icon: "lock",
                                    value: "lockOnly"
                                }
                            ]
                        }
                    }
                }
            }
        }

        // Loading: the registry is still being read.
        PendingCard {
            visible: !WidgetExtensionManager.ready
            label: Translation.tr("Reading installed extensions…")
        }

        // Install in flight: the row for it is already in the list.
        PendingCard {
            visible: WidgetExtensionManager.loading && root.pendingInstall !== ""
            label: Translation.tr("Installing %1…").arg(root.pendingInstall)
        }
    }

    // Empty: read, and nothing installed.
    Item {
        Layout.fillWidth: true
        implicitHeight: Appearance.sizes.pagePlaceholderHeight
        visible: WidgetExtensionManager.ready && root.installedIds.length === 0 && !WidgetExtensionManager.loading

        PagePlaceholder {
            anchors.fill: parent
            icon: "extension_off"
            shape: MaterialShape.Shape.Circle
            title: Translation.tr("No extensions installed")
            description: Translation.tr("Paste a GitHub URL or a local absolute path above to install one.")
        }
    }
}
