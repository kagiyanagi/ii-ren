import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

/**
 * One grid tile: the picture is the tile, its name under it (the Android 16
 * wallpaper picker, with names because this one browses folders).
 *
 * It paints no layer of its own. The picture's corners are cut by the one
 * OpacityMask on the grid, which is drawn from `cardRect` -- so the card's
 * geometry lives here and the grid's mask reads the same numbers.
 */
MouseArea {
    id: root
    required property var fileModelData
    property bool isDirectory: fileModelData.fileIsDir
    property bool isVideo: Wallpapers.isVideoFile(fileModelData.fileName.toLowerCase())
    property bool isApi: fileModelData.isApi || false
    property bool useThumbnail: (Images.isValidImageByName(fileModelData.fileName) || root.isVideo) && !root.isApi

    property bool current: false // the applied wallpaper
    property bool ringed: false // keyboard focus, or the tile the options toolbar acts on
    // Set by the grid, whose mask cuts the card's corners from the same numbers.
    required property real inset
    required property real labelGap
    required property real labelHeight
    readonly property rect cardRect: Qt.rect(inset, inset, width - inset * 2, height - inset * 2 - labelGap - labelHeight)

    signal activated
    signal moreOptionsRequested(var modelData)

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: event => {
        if (event.button === Qt.LeftButton)
            root.activated();
        else
            root.moreOptionsRequested(fileModelData);
    }

    Rectangle {
        id: card
        x: root.cardRect.x
        y: root.cardRect.y
        width: root.cardRect.width
        height: root.cardRect.height
        radius: Appearance.rounding.normal
        // Stands in for the picture until its thumbnail fades in; a folder has none.
        color: root.useThumbnail || root.isApi ? Appearance.colors.colLayer1 : "transparent"

        Loader {
            anchors.fill: parent
            active: root.useThumbnail
            sourceComponent: ThumbnailImage {
                id: thumbnailImage
                generateThumbnail: false
                sourcePath: root.fileModelData.filePath
                cache: false
                fillMode: Image.PreserveAspectCrop

                Connections {
                    target: Wallpapers
                    function onThumbnailGenerated(directory) {
                        if (thumbnailImage.status !== Image.Error) return;
                        if (FileUtils.parentDirectory(thumbnailImage.sourcePath) !== FileUtils.trimFileProtocol(directory)) return;
                        thumbnailImage.source = "";
                        thumbnailImage.source = thumbnailImage.thumbnailPath;
                    }
                    function onThumbnailGeneratedFile(filePath) {
                        if (thumbnailImage.status !== Image.Error) return;
                        if (Qt.resolvedUrl(thumbnailImage.sourcePath) !== Qt.resolvedUrl(filePath)) return;
                        thumbnailImage.source = "";
                        thumbnailImage.source = thumbnailImage.thumbnailPath;
                    }
                }
            }
        }

        Loader {
            anchors.fill: parent
            active: root.isApi
            sourceComponent: StyledImage {
                source: root.fileModelData.filePath
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: card.width
                sourceSize.height: card.height
            }
        }

        Loader {
            anchors.fill: parent
            active: !root.useThumbnail && !root.isApi
            sourceComponent: DirectoryIcon {
                fileModelData: root.fileModelData
            }
        }

        MaterialSymbol {
            visible: root.isVideo && root.useThumbnail
            anchors {
                top: parent.top
                left: parent.left
                margins: 8
            }
            text: "video_library"
            color: Appearance.colors.colPrimary
            iconSize: Appearance.font.pixelSize.large
            fill: 1
        }

        StateOverlay {
            anchors.fill: parent
            radius: card.radius
            hover: root.containsMouse
            press: root.pressed
        }

        // A film alone vanishes over a photo. 3dp is the M3 focus indicator.
        Rectangle {
            anchors.fill: parent
            radius: card.radius
            color: "transparent"
            border.width: 3
            border.color: Appearance.colors.colPrimary
            opacity: root.ringed ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Loader {
            active: root.containsMouse && !root.isDirectory
            anchors {
                top: parent.top
                right: parent.right
                margins: 8
            }
            sourceComponent: RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.moreOptionsRequested(root.fileModelData)

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "more_vert"
                    color: Appearance.colors.colOnSecondaryContainer
                    iconSize: Appearance.font.pixelSize.large
                }
            }
        }
    }

    Row {
        anchors {
            top: card.bottom
            topMargin: root.labelGap
            horizontalCenter: parent.horizontalCenter
        }
        height: root.labelHeight
        width: Math.min(implicitWidth, card.width)
        spacing: 4

        MaterialSymbol {
            id: currentMark
            visible: root.current
            anchors.verticalCenter: parent.verticalCenter
            text: "check_circle"
            fill: 1
            color: Appearance.colors.colPrimary
            iconSize: Appearance.font.pixelSize.small
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, card.width - (currentMark.visible ? currentMark.width + 4 : 0))
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
            text: root.fileModelData.fileName
        }
    }
}
