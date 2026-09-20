pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Community widgets, fetched from GitHub by topic.
 *
 * Four states, and none of them is a spinner over a greyed page — the grid
 * keeps its shape and the cards fill in:
 *   loading  discoverLoading -> the indeterminate bar under the header, plus
 *            three pending cards the real ones land on top of
 *   empty    fetched, nothing carries the topic -> PagePlaceholder
 *   offline  discoverError -> PagePlaceholder saying so, with the error, and
 *            pointing at Refresh; the grid is empty either way, so the
 *            difference between "nothing there" and "could not look" is the
 *            only thing the surface has to say
 *   busy     installing -> that card's button says so and the rest go disabled
 */
ColumnLayout {
    id: root

    // 5.3: sections in a panel sit 12–16 apart.
    spacing: 12

    readonly property bool offline: WidgetExtensionManager.discoverError !== ""
    readonly property bool noResults: WidgetExtensionManager.communityWidgets.length === 0

    // Which card's Install button was pressed. The manager's `loading` is
    // global, so without this every card in the grid said "Installing…" at once.
    property string installingId: ""

    // Auto-fetch only after this lazy section has been materialized. A Timer
    // is canceled automatically if the section is collapsed immediately.
    Timer {
        id: discoverKickoffTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (root.noResults && !WidgetExtensionManager.discoverLoading && !root.offline) {
                WidgetExtensionManager.discoverWidgets();
            }
        }
    }

    Component.onCompleted: discoverKickoffTimer.start()

    // A card with nothing in it yet. Same width, colour, radius, margins and
    // spacing as a real one, and its blanks stand at the sizes the real rows
    // are, so the grid does not change shape when the results land. No shimmer:
    // the bar above says the fetch is running, and a pulse per card is motion
    // in a repeated delegate for nothing.
    component PendingCard: Rectangle {
        implicitWidth: 240
        implicitHeight: pendingCardCol.implicitHeight + 24
        color: Appearance.colors.colLayer2Base
        radius: Appearance.rounding.large

        ColumnLayout {
            id: pendingCardCol
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 12
            }
            spacing: 6

            PendingBar {
                Layout.preferredWidth: pendingCardCol.width * 0.7
                implicitHeight: Appearance.font.pixelSize.large
            }
            PendingBar {
                Layout.preferredWidth: pendingCardCol.width * 0.4
            }
            PendingBar {
                Layout.fillWidth: true
            }
            PendingBar {
                Layout.preferredWidth: pendingCardCol.width * 0.85
            }
            PendingBar {
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: 32
                radius: Appearance.rounding.full
            }
        }
    }

    // One blank standing in for a line of text. colLayer3 is the layer above the
    // card it sits on (6.1).
    component PendingBar: Rectangle {
        implicitHeight: Appearance.font.pixelSize.small
        radius: Appearance.rounding.unsharpenmore
        color: Appearance.colors.colLayer3
    }

    // Header row: status + refresh
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            // The error itself belongs to the offline placeholder below, which
            // is the only thing on the surface when it happens.
            text: WidgetExtensionManager.discoverLoading ? Translation.tr("Fetching community widgets from GitHub…") : Translation.tr("%1 widget(s) found on GitHub").arg(WidgetExtensionManager.communityWidgets.length)
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.small
            elide: Text.ElideRight
        }

        RippleButtonWithIcon {
            implicitHeight: 32
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            colText: Appearance.colors.colOnSecondaryContainer
            materialIcon: WidgetExtensionManager.discoverLoading ? "hourglass_top" : "refresh"
            mainText: WidgetExtensionManager.discoverLoading ? Translation.tr("Refreshing…") : Translation.tr("Refresh")
            enabled: !WidgetExtensionManager.discoverLoading
            onClicked: WidgetExtensionManager.discoverWidgets()
        }
    }

    // The fetch has no knowable duration, which is the one case 9 allows this.
    StyledIndeterminateProgressBar {
        Layout.fillWidth: true
        visible: WidgetExtensionManager.discoverLoading
    }

    // Community widget grid
    Flow {
        id: communityFlow
        Layout.fillWidth: true
        spacing: 12

        Repeater {
            model: WidgetExtensionManager.communityWidgets

            delegate: Rectangle {
                id: communityCard
                required property var modelData
                required property int index

                readonly property string extId: {
                    const name = communityCard.modelData.fullName || communityCard.modelData.name || "";
                    return name.split("/").pop().replace(/[^a-zA-Z0-9_\-]/g, "-");
                }
                readonly property bool alreadyInstalled: WidgetExtensionManager.installedWidgets[communityCard.extId] !== undefined
                readonly property bool installing: WidgetExtensionManager.loading && root.installingId === communityCard.extId

                width: 240
                implicitHeight: communityCardCol.implicitHeight + 24
                color: Appearance.colors.colLayer2Base
                radius: Appearance.rounding.large

                ColumnLayout {
                    id: communityCardCol
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: 12
                    }
                    spacing: 6

                    // Repo name + stars
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "extension"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: communityCard.modelData.name || ""
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                        }

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "star"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colTertiary
                        }

                        StyledText {
                            text: communityCard.modelData.stars || "0"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.family: Appearance.font.family.numbers
                            color: Appearance.colors.colTertiary
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "@" + (communityCard.modelData.author || "")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: communityCard.modelData.description || Translation.tr("No description")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: communityCard.alreadyInstalled ? Appearance.colors.colSurfaceContainerLow : Appearance.colors.colPrimaryContainer
                        colBackgroundHover: communityCard.alreadyInstalled ? Appearance.colors.colSurfaceContainerLow : Appearance.colors.colPrimaryContainerHover
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        colText: communityCard.alreadyInstalled ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOnPrimaryContainer
                        materialIcon: communityCard.alreadyInstalled ? "check_circle" : "download"
                        mainText: communityCard.alreadyInstalled ? Translation.tr("Installed") : communityCard.installing ? Translation.tr("Installing…") : Translation.tr("Install")
                        enabled: !communityCard.alreadyInstalled && !WidgetExtensionManager.loading
                        onClicked: {
                            if (communityCard.alreadyInstalled)
                                return;
                            root.installingId = communityCard.extId;
                            WidgetExtensionManager.installWidget(communityCard.modelData.cloneUrl);
                        }
                    }
                }
            }
        }

        // Loading: three cards' worth of the shape that is coming.
        Repeater {
            model: WidgetExtensionManager.discoverLoading && root.noResults ? 3 : 0
            delegate: PendingCard {}
        }
    }

    // Empty, or offline. Both leave the grid with nothing in it, so the
    // placeholder is the surface, and only the wording differs.
    Item {
        Layout.fillWidth: true
        implicitHeight: Appearance.sizes.pagePlaceholderHeight
        visible: root.noResults && !WidgetExtensionManager.discoverLoading

        PagePlaceholder {
            anchors.fill: parent
            icon: root.offline ? "cloud_off" : "travel_explore"
            shape: MaterialShape.Shape.Circle
            title: root.offline ? Translation.tr("Can't reach GitHub") : Translation.tr("No community widgets found")
            description: root.offline ? Translation.tr("%1 — check your connection and press Refresh.").arg(WidgetExtensionManager.discoverError) : Translation.tr("Nothing on GitHub carries the widget topic yet. Press Refresh to look again.")
        }
    }
}
