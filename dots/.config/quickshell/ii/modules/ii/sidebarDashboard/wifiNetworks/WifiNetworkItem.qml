import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs.services.network
import QtQuick
import QtQuick.Layouts

// A tap joins the network, or opens its password field when it is secured and
// NetworkManager has no profile for it, as in Android's Internet dialog. The
// status line is the Bluetooth dialog's.
DialogListItem {
    id: root
    required property WifiAccessPoint wifiNetwork
    property bool showPassword: false

    readonly property bool connected: wifiNetwork?.active ?? false
    readonly property bool connecting: Network.wifiConnectTarget === wifiNetwork
    readonly property bool askingPassword: wifiNetwork?.askingPassword ?? false
    readonly property string failure: wifiNetwork?.failure ?? ""
    readonly property bool saved: Network.savedWifiSsids.includes(wifiNetwork?.ssid ?? "")
    // WPA needs 8 characters; a WEP key can be 5 or 13, which NM checks itself.
    readonly property int minPasswordLength: (wifiNetwork?.security ?? "").includes("WPA") ? 8 : 1
    // A tap on any other row would do nothing, so it must not look accepted.
    readonly property bool tappable: !connected && !Network.wifiConnecting && !askingPassword

    // `active` takes the hover film and the pointing hand away as well.
    active: !tappable
    rippleEnabled: tappable
    onClicked: if (tappable) Network.connectToWifiNetwork(wifiNetwork)

    function submit() {
        if (passwordField.text.length < root.minPasswordLength)
            return;
        Network.connectToWifiNetwork(root.wifiNetwork, passwordField.text);
    }

    contentItem: ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 0

        RowLayout {
            spacing: 10

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                property int strength: root.wifiNetwork?.strength ?? 0
                text: strength > 66 ? "wifi" : strength > 33 ? "wifi_2_bar" : "wifi_1_bar"
                color: root.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideRight
                    text: root.wifiNetwork?.ssid ?? Translation.tr("Unknown")
                    textFormat: Text.PlainText
                }
                StyledText {
                    visible: text !== ""
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.failure !== "" && !root.connecting ? Appearance.colors.colError : Appearance.colors.colSubtext
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    elide: Text.ElideRight
                    // What the network is doing now, then how the last attempt went,
                    // then what it is.
                    text: root.connecting ? Translation.tr("Connecting…")
                        : root.connected ? Translation.tr("Connected")
                        : root.failure === "password" ? Translation.tr("Wrong password")
                        : root.failure === "connect" ? Translation.tr("Couldn't connect")
                        : root.saved ? Translation.tr("Saved")
                        : ""
                }
            }

            MaterialSymbol {
                visible: root.wifiNetwork?.isSecure ?? false
                text: "lock"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        // Fades out before the row's height drops, rather than vanishing on the
        // collapse's first frame, as the Bluetooth row's Forget does.
        ColumnLayout { // Password prompt
            id: passwordPrompt
            property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
            Layout.topMargin: 8
            opacity: {
                passwordPrompt.fadeSpec = root.askingPassword ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
                return root.askingPassword ? 1 : 0;
            }
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation {
                    duration: passwordPrompt.fadeSpec.duration
                    easing.type: passwordPrompt.fadeSpec.type
                    easing.bezierCurve: passwordPrompt.fadeSpec.bezierCurve
                }
            }
            onVisibleChanged: {
                passwordField.text = "";
                root.showPassword = false;
                if (visible)
                    passwordField.forceActiveFocus();
            }

            MaterialTextField {
                id: passwordField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Password")
                echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData
                rightPadding: revealButton.width + 12
                onAccepted: root.submit()

                // The hotspot dialog's trailing icon, centred on the outline rather
                // than the control, which reserves the floating label's room above it.
                RippleButton {
                    id: revealButton
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.background.verticalCenter
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    // The row paints no film while it asks (it is `active`), so this
                    // comes off layer 3 like DialogButton.
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3)
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    colStateLayer: Appearance.colors.colOnLayer3
                    onClicked: root.showPassword = !root.showPassword
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurfaceVariant
                        text: root.showPassword ? "visibility_off" : "visibility"
                    }

                    StyledToolTip {
                        text: root.showPassword ? Translation.tr("Hide password") : Translation.tr("Show password")
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Item {
                    Layout.fillWidth: true
                }

                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.wifiNetwork.askingPassword = false
                }

                DialogButton {
                    buttonText: Translation.tr("Connect")
                    enabled: passwordField.text.length >= root.minPasswordLength
                    onClicked: root.submit()
                }
            }
        }

        ColumnLayout { // Public wifi login page
            Layout.topMargin: 8
            visible: root.connected && !(root.wifiNetwork?.isSecure ?? true)

            RowLayout {
                DialogButton {
                    Layout.fillWidth: true
                    buttonText: Translation.tr("Open network portal")
                    colBackground: Appearance.colors.colLayer4
                    colBackgroundHover: Appearance.colors.colLayer4Hover
                    colRipple: Appearance.colors.colLayer4Active
                    onClicked: {
                        Network.openPublicWifiPortal()
                        GlobalStates.sidebarRightOpen = false
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
