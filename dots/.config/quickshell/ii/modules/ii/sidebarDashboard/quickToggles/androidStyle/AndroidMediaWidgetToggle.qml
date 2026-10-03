import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import "QuickToggleCatalog.js" as QuickToggleCatalog
import Quickshell.Services.Mpris
import Quickshell.Io
import "../../../mediaControls" as MediaCtrl
import "../../../bar" as Bar

Item {
    id: root

    required property int buttonIndex
    required property var buttonData
    // Where the tile sits comes from the chooser that built it, so a delegate
    // entry is just a type and its data.
    required property var chooser
    property var panel: root.chooser?.panel ?? null
    property var gridRef: root.chooser?.gridRef ?? null
    property int pageIndex: root.chooser?.pageIndex ?? 0
    property bool isUnused: root.chooser?.isUnused ?? false
    property bool editMode: root.panel?.editMode ?? false
    property real baseCellWidth: root.panel?.baseCellWidth ?? 0
    property real baseCellHeight: root.panel?.baseCellHeight ?? 0
    property real cellSpacing: root.panel?.spacing ?? 0
    property int gridColumns: root.panel?.columns ?? 4

    readonly property var catalogSize: QuickToggleCatalog.normalizeSize(root.buttonData.type, root.buttonData.sizeW, root.buttonData.sizeH, root.gridColumns)

    property bool isDragging: false
    property real dragOffsetX: 0
    property real dragOffsetY: 0

    // Bind only when geometry is present, so fixed sliders can still be owned
    // by their Column positioner.
    readonly property bool hasExplicitGeometry: root.buttonData
        && root.buttonData.layoutX !== undefined
        && root.buttonData.layoutY !== undefined
    Binding on x {
        when: root.hasExplicitGeometry
        value: Number(root.buttonData.layoutX)
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding on y {
        when: root.hasExplicitGeometry
        value: Number(root.buttonData.layoutY)
        restoreMode: Binding.RestoreBindingOrValue
    }
    z: root.isDragging ? 100 : 0

    // Spatial and reversible: the edit preview reflows on every pointer move.
    Behavior on x {
        enabled: root.hasExplicitGeometry && !root.isDragging
        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(root)
    }
    Behavior on y {
        enabled: root.hasExplicitGeometry && !root.isDragging
        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(root)
    }

    property string tooltipText: {
        var player = MprisController.activePlayer;
        if (player && player.trackTitle) {
            var artist = player.trackArtist ? player.trackArtist : Translation.tr("Unknown artist");
            return player.trackTitle + " - " + artist;
        }
        return Translation.tr("Media player");
    }

    readonly property int effectiveSizeW: root.catalogSize[0]
    readonly property int effectiveSizeH: root.catalogSize[1]

    property bool hovered: hoverHandler.hovered || (root.editMode && editableItem.containsMouse)

    HoverHandler {
        id: hoverHandler
    }

    property real baseWidth: root.baseCellWidth * root.effectiveSizeW + cellSpacing * (root.effectiveSizeW - 1)
    property real baseHeight: root.baseCellHeight * root.effectiveSizeH + cellSpacing * (root.effectiveSizeH - 1)

    implicitWidth: baseWidth
    implicitHeight: baseHeight

    // One blurred backdrop for every layout below. `hasArt` is what decides
    // whether the text on top is light or dark.
    component CoverArt: StyledImage {
        id: coverArt
        readonly property string artUrl: MprisController.artUrl
        readonly property bool isLocalArt: artUrl.startsWith("file://")
        readonly property bool hasArt: artUrl.length > 0 && !isLocalArt
        readonly property string artFilePath: hasArt ? `${Directories.coverArt}/${Qt.md5(artUrl)}` : ""
        property bool cached: false

        anchors.fill: parent
        // Only once the file is on disk: pointing at it mid-download fails the
        // load, and a failed load is not retried when the file appears.
        source: isLocalArt ? artUrl : (cached ? `file://${artFilePath}` : "")
        fillMode: Image.PreserveAspectCrop
        cache: false
        asynchronous: true
        opacity: 0.8

        onArtUrlChanged: {
            cached = false;
            if (!hasArt) return;
            coverDownloader.running = true;
        }

        Process {
            id: coverDownloader
            command: ["bash", "-c", `[ -f '${coverArt.artFilePath}' ] || (curl -4 -sSL '${coverArt.artUrl}' -o '${coverArt.artFilePath}.tmp' && mv '${coverArt.artFilePath}.tmp' '${coverArt.artFilePath}')`]
            onExited: exitCode => coverArt.cached = exitCode === 0
        }

        layer.enabled: true
        layer.effect: StyledBlurEffect {
            source: coverArt
            blurMax: 32
        }

        Rectangle {
            anchors.fill: parent
            color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.6)
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainer
        border.color: Appearance.colors.colOutlineVariant
        border.width: 1
        visible: root.isDragging
        opacity: 0.5
    }

    Item {
        id: visualButton

        x: 0
        y: 0
        
        Behavior on width {
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(visualButton)
        }
        Behavior on height {
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(visualButton)
        }

        width: root.width
        height: root.height

        scale: root.isDragging ? 1.05 : 1.0
        opacity: {
            if (root.isUnused)
                return 0.5;
            if (root.editMode && !root.isDragging)
                return 0.9;
            return 1.0;
        }
        z: root.isDragging ? 99 : 1

        transform: Translate {
            x: root.isDragging ? root.dragOffsetX : 0
            y: root.isDragging ? root.dragOffsetY : 0
        }

        Behavior on scale {
            animation: Appearance.animation.clickBounce.numberAnimation.createObject(visualButton)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }

        Loader {
            id: contentLoader
            anchors.fill: parent
            sourceComponent: {
                if (MprisController.players.length === 0) {
                    return emptyStateComp;
                }
                var w = root.effectiveSizeW || 2;
                var h = root.effectiveSizeH || 2;
                if (w >= 4) {
                    return layout4x2StandardComp;
                } else if (h === 1) {
                    return layout2x1Comp;
                } else {
                    return layout2x2Comp;
                }
            }
        }

        Component {
            id: emptyStateComp
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.large

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "music_note"
                        iconSize: 32
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: Translation.tr("No media")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        Component {
            id: layout4x2StandardComp
            MediaCtrl.AndroidMediaPopup {
                player: MprisController.activePlayer
                showShadow: false
                anchors.fill: parent
            }
        }

        Component {
            id: layout2x1Comp
            Rectangle {
                id: widgetRoot2x1
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2
                clip: true

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: widgetRoot2x1.width
                        height: widgetRoot2x1.height
                        radius: widgetRoot2x1.radius
                    }
                }

                property MprisPlayer player: MprisController.activePlayer

                CoverArt {
                    id: art2x1
                }

                RowLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        Layout.alignment: Qt.AlignVCenter
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colPrimary
                        colRipple: Appearance.colors.colPrimaryActive
                        contentItem: MaterialSymbol {
                            text: widgetRoot2x1.player?.isPlaying ? "pause" : "play_arrow"
                            color: Appearance.colors.colOnPrimary
                            fill: 1
                            iconSize: 22
                            horizontalAlignment: Text.AlignHCenter
                        }
                        onClicked: widgetRoot2x1.player?.togglePlaying()

                        StyledToolTip {
                            text: widgetRoot2x1.player?.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: widgetRoot2x1.player?.trackTitle || Translation.tr("Untitled")
                            color: art2x1.hasArt ? "white" : Appearance.colors.colOnLayer0
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: 600
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: widgetRoot2x1.player?.trackArtist || Translation.tr("Unknown artist")
                            color: art2x1.hasArt ? ColorUtils.transparentize("white", 0.3) : Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        Component {
            id: layout2x2Comp
            Rectangle {
                id: widgetRoot
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2
                clip: true

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: widgetRoot.width
                        height: widgetRoot.height
                        radius: widgetRoot.radius
                    }
                }

                property MprisPlayer player: MprisController.activePlayer

                CoverArt {
                    id: art2x2
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16

                    StyledText {
                        Layout.fillWidth: true
                        text: widgetRoot.player?.trackTitle || Translation.tr("Untitled")
                        color: art2x2.hasArt ? "white" : Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: 600
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: widgetRoot.player?.trackArtist || Translation.tr("Unknown artist")
                        color: art2x2.hasArt ? ColorUtils.transparentize("white", 0.3) : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        elide: Text.ElideRight
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            contentItem: MaterialSymbol {
                                text: "skip_previous"
                                color: art2x2.hasArt ? "white" : Appearance.colors.colOnSecondaryContainer
                                iconSize: 24
                                horizontalAlignment: Text.AlignHCenter
                            }
                            onClicked: widgetRoot.player?.previous()

                            StyledToolTip {
                                text: Translation.tr("Previous")
                            }
                        }
                        RippleButton {
                            implicitWidth: 44
                            implicitHeight: 44
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimary
                            colRipple: Appearance.colors.colPrimaryActive
                            contentItem: MaterialSymbol {
                                text: widgetRoot.player?.isPlaying ? "pause" : "play_arrow"
                                color: Appearance.colors.colOnPrimary
                                fill: 1
                                iconSize: 28
                                horizontalAlignment: Text.AlignHCenter
                            }
                            onClicked: widgetRoot.player?.togglePlaying()

                            StyledToolTip {
                                text: widgetRoot.player?.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")
                            }
                        }
                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            contentItem: MaterialSymbol {
                                text: "skip_next"
                                color: art2x2.hasArt ? "white" : Appearance.colors.colOnSecondaryContainer
                                iconSize: 24
                                horizontalAlignment: Text.AlignHCenter
                            }
                            onClicked: widgetRoot.player?.next()

                            StyledToolTip {
                                text: Translation.tr("Next")
                            }
                        }
                    }
                }
            }
        }

    }

    EditableQuickToggleItem {
        id: editableItem
        target: root
    }
}
