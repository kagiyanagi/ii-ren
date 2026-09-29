import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool vertical: false
    readonly property bool autoHide: Config.options.bar.networkSpeed.autoHide ?? true
    readonly property int threshold: 125 // 1 Kbps = 1000 bits/s = 125 bytes/s
    readonly property bool hasActivity: {
        if (displayMode === 1) {
            return NetworkUsage.networkDownloadSpeed >= threshold;
        } else if (displayMode === 2) {
            return NetworkUsage.networkUploadSpeed >= threshold;
        } else if (displayMode === 3) {
            return NetworkUsage.networkDownloadSpeed >= threshold || NetworkUsage.networkUploadSpeed >= threshold;
        } else {
            return (NetworkUsage.networkDownloadSpeed + NetworkUsage.networkUploadSpeed) >= threshold;
        }
    }
    property bool showWidget: true

    visible: autoHide ? showWidget : true
    implicitWidth: visible ? (vertical ? Appearance.sizes.verticalBarWidth : networkLayout.implicitWidth + 6 + (displayMode === 4 ? 16 : 0)) : 0
    implicitHeight: visible ? (vertical ? (displayMode === 4 ? singleLineText.implicitHeight + 20 : networkLayout.implicitHeight + 6) : Appearance.sizes.barHeight) : 0

    // Auto-hide delay timer (10 seconds grace period to prevent layour flickering)
    Timer {
        id: hideTimer
        interval: 10000
        running: autoHide && !hasActivity
        repeat: false
        onTriggered: {
            showWidget = false;
        }
    }

    // `visible` stays a binding. updateVisibility() used to assign root.visible
    // from three handlers and Component.onCompleted, which destroyed the binding
    // above on the first call -- after that the widget's visibility was whatever
    // the last imperative write left, and autoHide stopped tracking showWidget.
    // The bar cell still has to be told, because a zero-width child leaves the
    // group's padding behind.
    onVisibleChanged: {
        if (typeof rootItem !== "undefined")
            rootItem.visible = root.visible;
    }

    onHasActivityChanged: {
        if (!hasActivity) return;
        hideTimer.stop();
        showWidget = true;
    }

    onAutoHideChanged: {
        if (autoHide) return;
        hideTimer.stop();
        showWidget = true;
    }

    // The vertical bar has no room for a speed readout, so it shows the icon
    // mode -- by *rendering* it, not by writing it into the user's config. The
    // old onVerticalChanged/Component.onCompleted pair overwrote the stored
    // displayMode the moment a vertical bar loaded and never put it back.
    readonly property int displayMode: root.vertical ? 4 : (Config.options.bar.networkSpeed.displayMode ?? 0)
    readonly property bool showIcons: Config.options.bar.networkSpeed.showIcons
    readonly property int iconPosition: Config.options.bar.networkSpeed.iconPosition

    Component.onCompleted: NetworkUsage.activeInstances++
    Component.onDestruction: NetworkUsage.activeInstances--

    function formatSpeed(bytesPerSecond) {
        var bits = bytesPerSecond * 8;
        var suffix = "bps";

        if (bits < 1000) {
            return bits.toFixed(0) + " " + suffix;
        } else if (bits < 1000000) {
            return (bits / 1000).toFixed(1) + " K" + suffix;
        } else if (bits < 1000000000) {
            return (bits / 1000000).toFixed(1) + " M" + suffix;
        } else {
            return (bits / 1000000000).toFixed(1) + " G" + suffix;
        }
    }

    function applyIcon(speedText, iconSymbol) {
        if (!showIcons) return speedText;
        return iconPosition === 0 ? iconSymbol + " " + speedText : speedText + " " + iconSymbol;
    }

    function getDisplayText() {
        var downloadSpeed = NetworkUsage.networkDownloadSpeed;
        var uploadSpeed = NetworkUsage.networkUploadSpeed;
        var totalSpeed = downloadSpeed + uploadSpeed;

        switch (displayMode) {
        case 0: return applyIcon(formatSpeed(totalSpeed), "↓↑");
        case 1: return applyIcon(formatSpeed(downloadSpeed), "↓");
        case 2: return applyIcon(formatSpeed(uploadSpeed), "↑");
        case 3: return "";
        case 4: return "↓↑";
        default: return formatSpeed(totalSpeed);
        }
    }

    RowLayout {
        id: networkLayout
        anchors.centerIn: parent
        spacing: 6

        // Modes 0, 1, 2, 4 (Single Line/Icon Only)
        Item {
            visible: [0, 1, 2, 4].includes(displayMode)
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: singleLineText.implicitWidth
            implicitHeight: singleLineText.implicitHeight
            StyledText {
                id: singleLineText
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                text: getDisplayText()
            }
        }

        // Mode 3 (Side by Side)
        GridLayout {
            visible: displayMode === 3
            columns: 2
            rowSpacing: 4
            columnSpacing: 4

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                text: applyIcon(formatSpeed(NetworkUsage.networkDownloadSpeed), "↓")
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                text: applyIcon(formatSpeed(NetworkUsage.networkUploadSpeed), "↑")
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // Right-click cycles the display mode, so it is a clickable surface (3.4).
        cursorShape: root.vertical ? Qt.ArrowCursor : Qt.PointingHandCursor

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                if (!Config.options.bar.tooltips.clickToShow) Session.barClick("networkSpeed");
            } else {
                if (root.vertical) return;

                var nextMode = (displayMode + 1) % 5;
                Config.options.bar.networkSpeed.displayMode = nextMode;
            }
        }
    }

    NetworkSpeedPopup {
        hoverTarget: mouseArea
    }
}
