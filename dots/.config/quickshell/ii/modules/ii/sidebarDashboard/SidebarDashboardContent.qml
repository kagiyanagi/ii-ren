import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland

import qs.modules.ii.sidebarDashboard.quickToggles
import qs.modules.ii.sidebarDashboard.quickToggles.classicStyle

import qs.modules.ii.sidebarDashboard.bluetoothDevices
import qs.modules.ii.sidebarDashboard.nightLight
import qs.modules.ii.sidebarDashboard.volumeMixer
import qs.modules.ii.sidebarDashboard.wifiNetworks
import qs.modules.ii.sidebarDashboard.hotspot
import qs.modules.ii.sidebarDashboard.dns
import qs.modules.ii.sidebarDashboard.vpn
import qs.modules.ii.sidebarDashboard.idle

Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10
    property string settingsQmlPath: Quickshell.shellPath("settings.qml")
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showComfortViewDialog: false
    property bool showReadingModeDialog: false
    property bool showAntiFlashbangDialog: false
    property bool showWifiDialog: false
    property bool showHotspotDialog: false
    property bool showDnsDialog: false
    property bool showVpnDialog: false
    property bool showIdleDialog: false
    property string customToggleDialogId: ""
    property bool showCustomToggleDialog: false
    property bool editMode: false
    readonly property bool anyDialogOpen: showAudioOutputDialog || showAudioInputDialog || showBluetoothDialog || showNightLightDialog || showComfortViewDialog || showReadingModeDialog || showAntiFlashbangDialog || showWifiDialog || showHotspotDialog || showDnsDialog || showVpnDialog || showIdleDialog || showCustomToggleDialog

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false;
                root.showHotspotDialog = false;
                root.showDnsDialog = false;
                root.showVpnDialog = false;
                root.showIdleDialog = false;
                root.showCustomToggleDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
                root.showNightLightDialog = false;
                root.showComfortViewDialog = false;
                root.showReadingModeDialog = false;
                root.showAntiFlashbangDialog = false;
            }
        }
        // The media popup's audio-device pill. Nothing read this, so the pill
        // opened the sidebar and stopped there.
        function onRequestVolumeDialogChanged() {
            if (!GlobalStates.requestVolumeDialog) return;
            GlobalStates.requestVolumeDialog = false;
            root.showAudioOutputDialog = true;
        }
    }

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    StyledRectangularShadow {
        target: sidebarRightBackground
    }
    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding

            SystemButtonRow {
                Layout.fillHeight: false
                Layout.fillWidth: true
                Layout.topMargin: 5
                Layout.bottomMargin: 0
            }

            Loader {
                id: slidersLoader
                Layout.fillWidth: true
                visible: active
                active: {
                    const configQuickSliders = Config.options.sidebar.quickSliders
                    if (!configQuickSliders.enable) return false
                    if (!configQuickSliders.showMic && !configQuickSliders.showVolume && !configQuickSliders.showBrightness && !configQuickSliders.showGamma) return false;
                    // The android panel carries sliders as grid tiles instead.
                    return Config.options.sidebar.quickToggles.style !== "android";
                }
                sourceComponent: QuickSliders {}
            }

            LoaderedQuickPanelImplementation {
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {}
            }

            LoaderedQuickPanelImplementation {
                styleName: "android"
                sourceComponent: AndroidQuickPanel {
                    editMode: root.editMode
                }
            }

            // Editing hands the panel the sidebar's spare height, so the
            // drawer of unplaced toggles has somewhere to go.
            CenterWidgetGroup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.fillWidth: true
                visible: !root.editMode
                enabled: !root.anyDialogOpen
            }

            BottomWidgetGroup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            // No adapter: the dialog says so, and there is nothing to switch on.
            if (!Bluetooth.defaultAdapter)
                return;
            if (!shown) {
                Bluetooth.defaultAdapter.discovering = false;
            } else {
                Bluetooth.defaultAdapter.enabled = true;
                Bluetooth.defaultAdapter.discovering = true;
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {
            effect: "nightLight"
        }
    }

    ToggleDialog {
        shownPropertyString: "showComfortViewDialog"
        dialog: NightLightDialog {
            effect: "comfortView"
        }
    }

    ToggleDialog {
        shownPropertyString: "showReadingModeDialog"
        dialog: NightLightDialog {
            effect: "readingMode"
        }
    }

    ToggleDialog {
        shownPropertyString: "showAntiFlashbangDialog"
        dialog: NightLightDialog {
            effect: "antiFlashbang"
        }
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) return;
            Network.enableWifi();
            Network.rescanWifi();
        }
    }

    ToggleDialog {
        shownPropertyString: "showHotspotDialog"
        dialog: HotspotDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showDnsDialog"
        dialog: DnsDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showVpnDialog"
        dialog: VpnDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showIdleDialog"
        dialog: IdleDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showCustomToggleDialog"
        dialog: CustomToggleDialog {
            toggleId: root.customToggleDialogId
        }
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        // The dialog follows its flag both ways. Closing the sidebar only cleared
        // the flag, so the dialog stayed shown and covered the next one opened.
        onShownChanged: {
            if (!shown) {
                if (item) item.show = false;
            } else if (active) {
                item.show = true;
                item.forceActiveFocus();
            } else {
                active = true;
            }
        }
        // Not bound to `shown`: unloading on close would cut the exit short.
        active: false
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (!toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString]) toggleDialogLoader.active = false;
            }
        }
    }

    component LoaderedQuickPanelImplementation: Loader {
        id: quickPanelImplLoader
        required property string styleName
        Layout.alignment: item?.Layout.alignment ?? Qt.AlignHCenter
        Layout.fillWidth: item?.Layout.fillWidth ?? false
        Layout.fillHeight: root.editMode && quickPanelImplLoader.styleName === "android"
        visible: active
        active: Config.options.sidebar.quickToggles.style === styleName
        Connections {
            target: quickPanelImplLoader.item
            function onOpenAudioOutputDialog() {
                root.showAudioOutputDialog = true;
            }
            function onOpenAudioInputDialog() {
                root.showAudioInputDialog = true;
            }
            function onOpenBluetoothDialog() {
                root.showBluetoothDialog = true;
            }
            function onOpenNightLightDialog() {
                root.showNightLightDialog = true;
            }
            function onOpenComfortViewDialog() {
                root.showComfortViewDialog = true;
            }
            function onOpenReadingModeDialog() {
                root.showReadingModeDialog = true;
            }
            function onOpenAntiFlashbangDialog() {
                root.showAntiFlashbangDialog = true;
            }
            function onOpenWifiDialog() {
                root.showWifiDialog = true;
            }
            function onOpenHotspotDialog() {
                root.showHotspotDialog = true;
            }
            function onOpenDnsDialog() {
                root.showDnsDialog = true;
            }
            function onOpenVpnDialog() {
                root.showVpnDialog = true;
            }
            function onOpenIdleDialog() {
                root.showIdleDialog = true;
            }
            function onOpenEditCustomToggleDialog(toggleId) {
                root.customToggleDialogId = toggleId;
                root.showCustomToggleDialog = true;
            }
            function onOpenNewCustomToggleDialog() {
                root.customToggleDialogId = "";
                root.showCustomToggleDialog = true;
            }
        }
    }

    component SystemButtonRow: Item {
        implicitHeight: Math.max(uptimeContainer.implicitHeight, systemButtonsRow.implicitHeight)

        Rectangle {
            id: uptimeContainer
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            color: Appearance.colors.colLayer1
            readonly property int fullRadius: Config.options.appearance.sharpMode ? Appearance.rounding.full : height / 2
            radius: fullRadius
            implicitWidth: uptimeRow.implicitWidth + 20
            implicitHeight: uptimeRow.implicitHeight + 8
            
            Row {
                id: uptimeRow
                anchors.centerIn: parent
                spacing: 8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: Config.options.appearance.sharpMode ? Appearance.rounding.full : height / 2
                    color: Appearance.colors.colLayer2
                    CustomIcon {
                        anchors.centerIn: parent
                        width: 19
                        height: 19
                        source: SystemInfo.distroIcon
                        colorize: true
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledImage { // Configured icon or user avatar, covers the distro icon when one loads
                        id: uptimeAvatar
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        // Its own fallback chain: StyledImage assigns source
                        // imperatively, which would kill the binding to the setting.
                        property list<string> candidates: Config.options.sidebar.uptimeIcon.length > 0 ? [Config.options.sidebar.uptimeIcon.replace(/^~\//, `${Directories.home}/`)] : [Directories.userAvatarPathAccountsService, Directories.userAvatarPathRicersAndWeirdSystems, Directories.userAvatarPathRicersAndWeirdSystems2]
                        property int candidateIndex: 0
                        onCandidatesChanged: candidateIndex = 0
                        source: candidates[candidateIndex] ?? ""
                        onStatusChanged: if (status === Image.Error && candidateIndex < candidates.length - 1)
                            candidateIndex++
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Circle {
                                diameter: uptimeAvatar.height
                            }
                        }
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                    text: Translation.tr("Uptime: %1").arg(DateTime.uptime)
                }
            }
        }

        ButtonGroup {
            id: systemButtonsRow
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Appearance.colors.colLayer1
            padding: 4

            QuickToggleButton {
                iconFill: 1
                toggled: root.editMode
                visible: Config.options.sidebar.quickToggles.style === "android"
                buttonIcon: "edit"
                onClicked: root.editMode = !root.editMode
                StyledToolTip {
                    text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nDrag to move, drag a handle to resize\nClick a tile to remove it, one below to add") : "")
                }
            }
            QuickToggleButton {
                iconFill: 1
                toggled: false
                buttonIcon: "settings"
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    Quickshell.execDetached(["qs", "-p", root.settingsQmlPath]);
                }
                StyledToolTip {
                    text: Translation.tr("Settings")
                }
            }
            QuickToggleButton {
                iconFill: 1
                id: updateButton
                toggled: confirm
                property bool confirm: false
                buttonIcon: confirm ? "check" : "download"
                Timer {
                    id: confirmTimer
                    interval: 2000
                    onTriggered: {
                        confirmTimer.stop();
                        updateButton.confirm = false
                    }
                }
                onClicked: {
                    if (confirm) {
                        Quickshell.execDetached([Directories.cliPath, "update", "--no-confirm", "--no-backup"]);
                        GlobalStates.sidebarRightOpen = false;
                    } else {
                        confirm = true
                        confirmTimer.start()
                    }
                    
                }
                StyledToolTip {
                    alternativeVisibleCondition: updateButton.confirm
                    text: updateButton.confirm ?
                        Translation.tr("Click again to confirm update") :
                        Translation.tr("Update ii-ren, make sure you have the iiren CLI installed")
                }
            }
            QuickToggleButton {
                iconFill: 1
                toggled: false
                buttonIcon: "power_settings_new"
                onClicked: {
                    GlobalStates.sessionOpen = true;
                }
                StyledToolTip {
                    text: Translation.tr("Session")
                }
            }
        }
    }
}
