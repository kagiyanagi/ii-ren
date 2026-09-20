pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Docker section for ExpressiveResourcesPopup.
 * Material 3 Expressive design — no borders, no plain number grids,
 * uses chips, mini arc gauges, sparkline-style bars and ripple buttons.
 */
Item {
    id: root
    implicitWidth: 380
    implicitHeight: mainCol.implicitHeight

    // Uptime tick force-reactive update
    property int uptimeUpdateTick: 0
    Timer {
        interval: 1000
        running: root.visible && DockerService.dockerRunning
        repeat: true
        onTriggered: root.uptimeUpdateTick++
    }

    // ── Helpers ──────────────────────────────────────────────────────────
    // `tick` is unused in the body and required in the signature: it is what makes
    // the binding re-run every second, and passing it beats the comma expression
    // that used to smuggle the same dependency into the caller.
    function uptimeShort(startedAt, tick) {
        if (!startedAt || startedAt === "0001-01-01T00:00:00Z")
            return "—";
        const ms = Date.now() - new Date(startedAt).getTime();
        if (ms < 0)
            return "—";
        const s = Math.floor(ms / 1000);
        if (s < 60)
            return s + "s";
        if (s < 3600)
            return Math.floor(s / 60) + "m";
        return Math.floor(s / 3600) + "h";
    }

    // ── Layout ────────────────────────────────────────────────────────────
    ColumnLayout {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        // ── Header row ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Docker icon + label block
            RowLayout {
                spacing: 10

                CustomIcon {
                    source: "docker.svg"
                    implicitWidth: 36
                    implicitHeight: 36
                    colorize: true
                    color: Appearance.colors.colOnLayer1
                }

                ColumnLayout {
                    spacing: 0
                    StyledText {
                        text: "Docker"
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: DockerService.dockerAvailable ? DockerService.runningCount + " running" : (DockerService.dockerRunning ? "loading..." : "stopped")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                        opacity: 0.6
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            // Total Docker RAM usage pill
            Rectangle {
                visible: DockerService.dockerRunning && DockerService.totalMemoryMb > 0
                radius: Appearance.rounding.full
                color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.12)
                implicitHeight: 32
                implicitWidth: ramPillRow.implicitWidth + 24

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: ramPillRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: "memory"
                        iconSize: 14
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: DockerService.totalMemoryMb >= 1024 ? (DockerService.totalMemoryMb / 1024).toFixed(1) + " GB" : Math.round(DockerService.totalMemoryMb) + " MB"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            // Service on/off toggle pill
            RippleButton {
                id: serviceToggle
                implicitWidth: serviceToggleRow.implicitWidth + 24
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: DockerService.dockerRunning ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                colBackgroundHover: DockerService.dockerRunning ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover
                // Without this, RippleButton defaults pressed to the hover colour and
                // the button has three states, not four (DESIGN.md 3.1).
                colBackgroundActive: DockerService.dockerRunning ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive
                onClicked: DockerService.toggleDockerService(!DockerService.dockerRunning)

                Behavior on colBackground {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                RowLayout {
                    id: serviceToggleRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: DockerService.dockerRunning ? "power_settings_new" : "power_off"
                        iconSize: 14
                        color: DockerService.dockerRunning ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        text: DockerService.dockerRunning ? "On" : "Off"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: DockerService.dockerRunning ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnSurfaceVariant
                    }
                }
            }
        }

        // ── Loading state ──────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: 80
            visible: DockerService.isLoading

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                MaterialLoadingIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    implicitSize: 32
                    loading: DockerService.isLoading
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Fetching container states..."
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.6
                }
            }
        }

        // ── Empty / unavailable state ──────────────────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: 88
            visible: !DockerService.isLoading && (!DockerService.dockerAvailable || DockerService.containers.length === 0)

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHigh

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    MaterialShape {
                        shapeString: "Cookie6Sided"
                        implicitSize: 40
                        color: DockerService.dockerRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colErrorContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: DockerService.dockerRunning ? "deployed_code" : "cloud_off"
                            iconSize: 22
                            color: DockerService.dockerRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnErrorContainer
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: DockerService.dockerRunning ? "No active containers" : "Docker service offline"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            text: DockerService.dockerRunning ? "Spin up some containers to manage them here." : "Click the power button to start the system daemon."
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.5
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // ── Scrollable Container cards area (Extreme Conditions safe) ────────
        /*
         * StyledListView brings the scrollbar, the wheel handler and the
         * add/remove transitions a container list needs; the hand-rolled
         * ScrollBar and HoverHandler here had neither an enter nor an exit for a
         * row appearing (DESIGN.md 2.5, 9 *List*).
         */
        StyledListView {
            id: containersListView

            // The row height, said once. It was spelled out three times and again
            // as the 196 they multiply out to, which is how the three drift apart.
            readonly property int rowHeight: 60
            readonly property int maxRows: 3

            visible: !DockerService.isLoading && DockerService.dockerAvailable && DockerService.containers.length > 0
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            clip: true
            spacing: 8

            implicitHeight: {
                const rows = Math.min(DockerService.containers.length, containersListView.maxRows);
                return rows > 0 ? rows * containersListView.rowHeight + (rows - 1) * containersListView.spacing : 0;
            }

            model: DockerService.containers

            delegate: ContainerCard {
                required property var modelData
                width: containersListView.width
                rowHeight: containersListView.rowHeight
                containerData: modelData
            }

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
        }
    }

    // ── Container card component ───────────────────────────────────────────
    component ContainerCard: Item {
        id: card
        property var containerData: null
        property bool actionPanelOpen: false
        property int rowHeight: 60

        implicitWidth: parent ? parent.width : 360
        implicitHeight: card.rowHeight

        /*
         * A running card is filled colPrimary, so the chips on it have no
         * container token to sit on: they are an on-primary film, with the
         * StateTokens hover (+0.08) and pressed (+0.10) films over it
         * (DESIGN.md 3.1). A stopped card is neutral and its chips take the
         * layer above the card's own (DESIGN.md 6.1) -- which is what the ten
         * hand-mixed `Qt.rgba(colOnLayer1, 0.07|0.08|0.12|0.15|0.38)` calls
         * spread through this card were each approximating on their own.
         */
        readonly property bool onPrimary: card.containerData?.isRunning ?? false
        readonly property color chipColor: card.onPrimary ? ColorUtils.applyAlpha(Appearance.m3colors.m3onPrimary, 0.12) : Appearance.colors.colSurfaceContainerHighest
        readonly property color chipHover: card.onPrimary ? ColorUtils.applyAlpha(Appearance.m3colors.m3onPrimary, 0.20) : Appearance.colors.colSurfaceContainerHighestHover
        readonly property color chipActive: card.onPrimary ? ColorUtils.applyAlpha(Appearance.m3colors.m3onPrimary, 0.22) : Appearance.colors.colSurfaceContainerHighestActive
        readonly property color chipText: card.onPrimary ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnSurfaceVariant
        readonly property color cardText: card.onPrimary ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1

        // ── List of action items for this container ────────────────────────
        property var allActionItems: {
            let items = [];
            // Collapse Button (arrow back)
            items.push({
                icon: "arrow_back",
                isCollapse: true,
                tooltip: "Collapse actions",
                color: Appearance.colors.colOnSurfaceVariant,
                execute: () => {
                    card.actionPanelOpen = false;
                }
            });
            if (card.containerData?.isRunning) {
                // Stop Container
                items.push({
                    icon: "stop",
                    tooltip: "Stop container",
                    color: Appearance.colors.colError,
                    execute: () => {
                        DockerService.containerAction(card.containerData.id, "stop");
                    }
                });
                // Shell
                items.push({
                    icon: "terminal",
                    isSecondaryContainer: true,
                    tooltip: "Open shell",
                    color: Appearance.colors.colOnSecondaryContainer,
                    execute: () => {
                        DockerService.openShell(card.containerData.id);
                    }
                });
            } else {
                // Start Container
                items.push({
                    icon: "play_arrow",
                    tooltip: "Start container",
                    color: Appearance.colors.colSuccess,
                    execute: () => {
                        DockerService.containerAction(card.containerData.id, "start");
                    }
                });
            }
            // Logs
            items.push({
                icon: "description",
                isSecondaryContainer: true,
                tooltip: "Open logs",
                color: Appearance.colors.colOnSecondaryContainer,
                execute: () => {
                    DockerService.openLogs(card.containerData.id);
                }
            });
            if (card.containerData?.ports?.length > 0) {
                items.push({
                    icon: "open_in_new",
                    isSecondaryContainer: true,
                    tooltip: "Open in browser (http://localhost:" + card.containerData.ports[0].hostPort + ")",
                    color: Appearance.colors.colOnSecondaryContainer,
                    execute: () => {
                        DockerService.openInBrowser(card.containerData.ports[0].hostPort);
                    }
                });
            }
            if (card.containerData?.isRunning) {
                // RAM Gauge quick button (moved to the end)
                items.push({
                    isRamGauge: true,
                    tooltip: "RAM: " + (card.containerData?.memMb >= 1024 ? (card.containerData.memMb / 1024).toFixed(2) + " GB" : (card.containerData?.memMb ?? 0).toFixed(1) + " MB"),
                    memMb: card.containerData?.memMb ?? 0,
                    execute: () => {}
                });
            }
            return items;
        }

        Item {
            id: cardWrapper
            anchors.fill: parent
            clip: true

            Row {
                id: slideRow
                anchors.fill: parent
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter

                // ── Main Card ────────────────────────────────────────────────
                Rectangle {
                    id: itemRect
                    width: card.actionPanelOpen ? 184 : cardWrapper.width
                    height: card.rowHeight
                    radius: Appearance.rounding.large
                    anchors.verticalCenter: parent.verticalCenter
                    color: card.onPrimary ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh

                    Behavior on width {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    // Click whole card to collapse when open
                    MouseArea {
                        anchors.fill: parent
                        visible: card.actionPanelOpen
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.actionPanelOpen = false
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 6

                        // Container Icon Chip - Uses official Docker icon for visual premium excellence!
                        MaterialShape {
                            shapeString: "Cookie9Sided"
                            implicitSize: 32
                            color: card.onPrimary ? Appearance.colors.colPrimaryContainer : card.chipColor

                            CustomIcon {
                                anchors.centerIn: parent
                                source: "docker.svg"
                                width: 16
                                height: 16
                                colorize: true
                                color: card.onPrimary ? Appearance.colors.colOnPrimaryContainer : card.chipText
                            }
                        }

                        // Text Content Column
                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true

                            RowLayout {
                                spacing: 4

                                StyledText {
                                    text: card.containerData?.name ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: card.cardText
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                // Uptime pill (hidden when action panel is open)
                                Rectangle {
                                    visible: (card.containerData?.isRunning ?? false) && !card.actionPanelOpen
                                    radius: Appearance.rounding.full
                                    color: card.chipColor
                                    implicitHeight: 16
                                    implicitWidth: uptimeTextRow.implicitWidth + 8

                                    RowLayout {
                                        id: uptimeTextRow
                                        anchors.centerIn: parent
                                        spacing: 2
                                        MaterialSymbol {
                                            text: "schedule"
                                            iconSize: 8
                                            color: card.chipText
                                        }
                                        StyledText {
                                            text: root.uptimeShort(card.containerData?.startedAt, root.uptimeUpdateTick)
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            color: card.chipText
                                        }
                                    }
                                }
                            }

                            // Sub-Chips row (hidden when action panel is open)
                            RowLayout {
                                spacing: 4
                                visible: !card.actionPanelOpen

                                // Image name chip
                                Rectangle {
                                    radius: Appearance.rounding.full
                                    color: card.chipColor
                                    implicitHeight: 16
                                    implicitWidth: imageText.implicitWidth + 10
                                    Layout.maximumWidth: 88

                                    StyledText {
                                        id: imageText
                                        anchors.centerIn: parent
                                        text: card.containerData?.image ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: card.chipText
                                        elide: Text.ElideRight
                                        width: parent.width - 10
                                    }
                                }

                                // Port chip
                                Repeater {
                                    model: (card.containerData?.ports ?? []).slice(0, 2)

                                    // Was a bare MouseArea rendering hover and nothing
                                    // else; RippleButton carries all four states and the
                                    // cursor (DESIGN.md 3.1). Ripple off: at chip size
                                    // there is no room for one to read.
                                    delegate: RippleButton {
                                        id: portChip
                                        required property var modelData

                                        implicitHeight: 16
                                        implicitWidth: portChipText.implicitWidth + 12
                                        buttonRadius: Appearance.rounding.full
                                        rippleEnabled: false
                                        colBackground: card.chipColor
                                        colBackgroundHover: card.chipHover
                                        colBackgroundActive: card.chipActive
                                        onClicked: DockerService.openInBrowser(portChip.modelData.hostPort)

                                        StyledText {
                                            id: portChipText
                                            anchors.centerIn: parent
                                            text: portChip.modelData.hostPort
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.Bold
                                            color: card.chipText
                                        }

                                        StyledToolTip {
                                            text: "Open http://localhost:" + portChip.modelData.hostPort + " in browser"
                                        }
                                    }
                                }
                            }
                        }

                        // Right-Arrow Button to open panel (only when NOT open)
                        RippleButton {
                            visible: !card.actionPanelOpen
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: card.chipColor
                            colBackgroundHover: card.chipHover
                            colBackgroundActive: card.chipActive
                            onClicked: card.actionPanelOpen = true

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_forward"
                                iconSize: 16
                                color: card.chipText
                            }

                            StyledToolTip {
                                text: "Manage actions"
                            }
                        }
                    }
                }

                // ── Circular Action Buttons Scrollable Drawer ────────────────
                Flickable {
                    id: actionsFlickable
                    visible: card.actionPanelOpen || itemRect.width < cardWrapper.width
                    height: card.rowHeight
                    width: Math.max(0, cardWrapper.width - itemRect.width - slideRow.spacing)
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    contentWidth: buttonsRow.implicitWidth
                    flickableDirection: Flickable.HorizontalFlick

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: wheel => {
                            var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                            actionsFlickable.contentX = Math.max(0, Math.min(actionsFlickable.contentWidth - actionsFlickable.width, actionsFlickable.contentX - delta * 0.5));
                            wheel.accepted = true;
                        }
                    }

                    Row {
                        id: buttonsRow
                        spacing: 8
                        height: card.rowHeight
                        anchors.verticalCenter: parent.verticalCenter

                        Repeater {
                            model: card.allActionItems

                            delegate: RippleButton {
                                id: actionButton
                                required property var modelData

                                implicitWidth: card.rowHeight
                                implicitHeight: card.rowHeight
                                anchors.verticalCenter: parent.verticalCenter
                                buttonRadius: Appearance.rounding.full

                                /*
                                 * Each kind takes the hover and pressed siblings of the
                                 * layer it actually paints (DESIGN.md 6.1). Before this
                                 * the secondary-container buttons -- shell, logs, open in
                                 * browser -- had hover set to their own rest colour and so
                                 * rendered no hover at all, and none of the four had a
                                 * pressed colour, which RippleButton then defaults to the
                                 * hover one.
                                 */
                                colBackground: actionButton.modelData.isCollapse ? Appearance.colors.colSurfaceContainerHighest : (actionButton.modelData.isRamGauge ? Appearance.colors.colTertiaryContainer : (actionButton.modelData.isSecondaryContainer ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary))
                                colBackgroundHover: actionButton.modelData.isCollapse ? Appearance.colors.colSurfaceContainerHighestHover : (actionButton.modelData.isRamGauge ? Appearance.colors.colTertiaryContainerHover : (actionButton.modelData.isSecondaryContainer ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colPrimaryHover))
                                colBackgroundActive: actionButton.modelData.isCollapse ? Appearance.colors.colSurfaceContainerHighestActive : (actionButton.modelData.isRamGauge ? Appearance.colors.colTertiaryContainerActive : (actionButton.modelData.isSecondaryContainer ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colPrimaryActive))

                                onClicked: actionButton.modelData.execute()

                                // Material symbol for generic actions
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: !actionButton.modelData.isRamGauge
                                    text: actionButton.modelData.icon || ""
                                    iconSize: 24
                                    color: actionButton.modelData.isCollapse ? Appearance.colors.colOnSurface : (actionButton.modelData.isSecondaryContainer ? Appearance.colors.colOnSecondaryContainer : Appearance.m3colors.m3onPrimary)
                                }

                                // Custom circular RAM Usage Gauge quick button
                                Loader {
                                    anchors.centerIn: parent
                                    active: actionButton.modelData.isRamGauge || false
                                    visible: active
                                    sourceComponent: ClippedFilledCircularProgress {
                                        id: ramGaugeProgress
                                        implicitSize: card.rowHeight
                                        lineWidth: 4
                                        value: {
                                            const totalSysMb = (ResourceUsage.memoryTotal || 16777216) / 1024;
                                            return Math.min(1.0, Math.max(0.005, (actionButton.modelData.memMb || 0) / totalSysMb));
                                        }
                                        colPrimary: Appearance.colors.colTertiary
                                        colSecondary: ColorUtils.applyAlpha(Appearance.colors.colTertiary, 0.15)
                                        accountForLightBleeding: false

                                        Item {
                                            anchors.centerIn: parent
                                            width: ramGaugeProgress.implicitSize
                                            height: ramGaugeProgress.implicitSize

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: {
                                                    const m = actionButton.modelData.memMb || 0;
                                                    if (m < 0.1)
                                                        return Math.round(m * 1024) + "K";
                                                    if (m < 1.0)
                                                        return (m * 1024).toFixed(0) + "K";
                                                    if (m < 10.0)
                                                        return m.toFixed(1) + "M";
                                                    return Math.round(m) + "M";
                                                }
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.Bold
                                                color: Appearance.colors.colOnTertiaryContainer
                                            }
                                        }
                                    }
                                }

                                // Tooltips for all quick actions to describe behavior
                                StyledToolTip {
                                    text: actionButton.modelData.tooltip || ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
