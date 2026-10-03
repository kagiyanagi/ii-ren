import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// Android's Private DNS as the audio dialog's device list: a tap on a provider
// commits it. Custom opens a field under its row instead, which Enter applies.
WindowDialog {
    id: root
    // The sidebar dialogs' fixed height, so the field opening scrolls the body
    // rather than re-centring the card under the pointer.
    backgroundHeight: Math.round(root.height * 0.6)

    Component.onCompleted: Dns.refresh()

    readonly property var last: Config.options.networking.dns
    // A provider picked from Automatic takes the encryption last chosen.
    readonly property bool wantEncrypted: Dns.provider === "auto" ? last.encrypted : Dns.encrypted
    property bool customOpen: Dns.provider === "custom"
    property bool customRejected: false
    // As NetworkManager has them, "#hostname" and all.
    readonly property string currentServers: Dns.link ? [...Dns.link.v4, ...Dns.link.v6].join(", ") : ""
    readonly property var parsed: Dns.parse(customField.text)
    readonly property bool customValid: parsed.bad.length === 0 && parsed.v4.length + parsed.v6.length > 0

    readonly property var options: [
        { id: "auto", icon: "router", name: Translation.tr("Automatic"), note: Translation.tr("From the network") },
        ...Dns.providers.map(p => ({ id: p.id, icon: "dns", name: p.name, note: `${Translation.tr(p.note)} · ${p.v4[0]}` })),
        { id: "custom", icon: "edit", name: Translation.tr("Custom"),
          note: Dns.provider === "custom" ? Dns.servers : Translation.tr("Your own servers") }
    ]

    readonly property string status: {
        if (!Dns.available) return Translation.tr("Connect to Wi-Fi or Ethernet to set its DNS");
        if (Dns.busy) return Translation.tr("Applying…");
        if (Dns.failed) return Translation.tr("Couldn't change DNS");
        return Translation.tr("For %1").arg(Dns.link.name);
    }

    function commit(choice): bool {
        if (!Dns.apply(choice)) return false;
        if (choice.provider !== "auto") {
            root.last.provider = choice.provider;
            root.last.encrypted = choice.encrypted;
            if (choice.custom !== undefined) root.last.custom = choice.custom;
        }
        return true;
    }

    function pick(id: string): void {
        if (Dns.busy) return;
        if (id === "custom") {
            root.customOpen = true;
            customField.forceActiveFocus();
            return;
        }
        root.customOpen = false;
        root.commit({ provider: id, encrypted: root.wantEncrypted });
    }

    function saveCustom(): void {
        if (Dns.busy || !root.customValid) return;
        // Valid text a connection cannot use: IPv6 servers with IPv6 off.
        root.customRejected = !root.commit({ provider: "custom", custom: customField.text.trim(), encrypted: root.wantEncrypted });
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        WindowDialogTitle {
            text: Translation.tr("DNS")
        }
        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Dns.failed && !Dns.busy ? Appearance.colors.colError : Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: root.status
        }
    }

    StyledFlickable {
        id: flick
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        // The field opens under the last row, below the fold at 1080p: its bottom
        // is followed as it grows. A jump to the final spot was clamped, since the
        // content had not grown to it yet.
        onContentHeightChanged: {
            if (!root.customOpen || !customField.activeFocus) return;
            const bottom = providerCard.y + customRevealer.y + customRevealer.implicitHeight;
            if (bottom > contentY + height) contentY = bottom - height;
        }

        ColumnLayout {
            id: body
            width: parent.width
            spacing: 12
            enabled: Dns.available

            DialogCard {
                id: providerCard
                Repeater {
                    model: root.options
                    delegate: DialogListItem {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool selected: Dns.provider === modelData.id
                        readonly property bool isLast: index === root.options.length - 1
                        Layout.fillWidth: true
                        // A second tap on the provider in use does nothing; Custom reopens its field.
                        active: selected && modelData.id !== "custom"
                        topLeftRadius: index === 0 ? Appearance.rounding.large : 0
                        topRightRadius: topLeftRadius
                        bottomLeftRadius: isLast && !root.customOpen ? Appearance.rounding.large : 0
                        bottomRightRadius: bottomLeftRadius
                        onClicked: root.pick(modelData.id)

                        contentItem: RowLayout {
                            spacing: 10
                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.larger
                                text: row.modelData.icon
                                color: row.selected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                StyledText {
                                    Layout.fillWidth: true
                                    color: row.selected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                    elide: Text.ElideRight
                                    text: row.modelData.name
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: row.modelData.note
                                }
                            }
                            // Colour alone is not enough: a greyscale wallpaper makes
                            // colPrimary a shade off the other rows. Faded, not hidden,
                            // so the text keeps its width.
                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.larger
                                text: "check"
                                color: Appearance.colors.colPrimary
                                opacity: row.selected ? 1 : 0
                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                            }
                        }
                    }
                }

                Revealer {
                    id: customRevealer
                    vertical: true
                    reveal: root.customOpen
                    Layout.fillWidth: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 4

                        MaterialTextField {
                            id: customField
                            Layout.fillWidth: true
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            Layout.topMargin: 4
                            text: Dns.provider === "custom" ? root.currentServers : root.last.custom
                            placeholderText: Translation.tr("e.g. 1.1.1.1, 9.9.9.9")
                            rightPadding: saveButton.width + 12
                            onTextEdited: root.customRejected = false
                            onAccepted: root.saveCustom()

                            // The hotspot password field's trailing icon, here the field's Enter.
                            RippleButton {
                                id: saveButton
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.background.verticalCenter
                                implicitWidth: 40
                                implicitHeight: 40
                                buttonRadius: Appearance.rounding.full
                                enabled: root.customValid && !Dns.busy
                                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3)
                                colBackgroundHover: Appearance.colors.colLayer3Hover
                                colRipple: Appearance.colors.colLayer3Active
                                colStateLayer: Appearance.colors.colOnLayer3
                                onClicked: root.saveCustom()
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colPrimary
                                    text: "check"
                                }
                                StyledToolTip {
                                    text: Translation.tr("Save")
                                }
                            }
                        }

                        // M3 supporting text: the format first, the problem once there is one.
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 32
                            Layout.rightMargin: 16
                            Layout.bottomMargin: 12
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            readonly property bool bad: root.parsed.bad.length > 0 || root.customRejected
                            color: bad ? Appearance.colors.colError : Appearance.colors.colSubtext
                            text: root.parsed.bad.length > 0 ? Translation.tr("Not an IP address: %1").arg(root.parsed.bad[0])
                                : root.customRejected ? Translation.tr("This network has no IPv4 or IPv6 for these servers")
                                : Translation.tr("Separate with commas. Add #hostname to a server to encrypt it")
                        }
                    }
                }
            }

            // The Wi-Fi and hotspot dialogs' switch row: the row owns the state,
            // and the switch never toggles itself.
            DialogCard {
                DialogListItem {
                    id: encryptRow
                    Layout.fillWidth: true
                    buttonRadius: Appearance.rounding.large
                    enabled: Dns.provider !== "auto"
                    onClicked: {
                        if (Dns.busy) return;
                        root.commit({ provider: Dns.provider, custom: Dns.provider === "custom" ? root.currentServers : undefined, encrypted: !Dns.encrypted });
                    }

                    contentItem: RowLayout {
                        spacing: 10
                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.larger
                            text: "lock"
                            color: Dns.encrypted ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                color: Appearance.colors.colOnSurfaceVariant
                                elide: Text.ElideRight
                                text: Translation.tr("Encrypted DNS")
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                                text: Dns.provider === "auto" ? Translation.tr("Pick a provider to encrypt")
                                    : Dns.encrypted ? Translation.tr("Over TLS, never falls back to plain")
                                    : Translation.tr("Sent unencrypted")
                            }
                        }
                        StyledSwitch {
                            checkable: false
                            checked: Dns.encrypted
                            down: encryptRow.down
                            focusPolicy: Qt.NoFocus
                            opacity: 1 // the row already dims to 0.4 when disabled (3.1)
                            onClicked: encryptRow.clicked()
                        }
                    }
                }
            }
        }
    }

    WindowDialogButtonRow {
        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
