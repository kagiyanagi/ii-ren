import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarPolicies
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects

Item {
    id: root
    property var responseData
    property var tagInputField

    property string previewDownloadPath
    property string downloadPath
    property string nsfwPath

    property real availableWidth: parent.width
    property real rowTooShortThreshold: 190
    property real imageSpacing: 4
    property real responsePadding: 4

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: columnLayout.implicitHeight + root.responsePadding * 2

    // Assigned rather than bound: a bound width re-laid out every row on every
    // frame of a sidebar resize. The timer below picks the new width up once.
    Component.onCompleted: availableWidth = parent.width

    Connections {
        target: parent
        function onWidthChanged() {
            updateWidthTimer.restart()
        }
    }

    Timer {
        id: updateWidthTimer
        interval: 100
        onTriggered: {
            availableWidth = parent.width
        }
    }

    // Justified rows: keep adding images to a row while it stays at least
    // rowTooShortThreshold tall, and size the row so it fills the width exactly.
    readonly property var rows: {
        const width = root.availableWidth - root.responsePadding * 2;
        const heightOf = (aspect, count) => (width - root.imageSpacing * (count - 1)) / aspect;
        let rows = [], row = [], aspect = 0;
        for (const image of root.responseData.images) {
            if (row.length > 0 && heightOf(aspect + image.aspect_ratio, row.length + 1) < root.rowTooShortThreshold) {
                rows.push({ height: heightOf(aspect, row.length), images: row });
                row = [];
                aspect = 0;
            }
            row.push(image);
            aspect += image.aspect_ratio;
        }
        if (row.length > 0)
            rows.push({ height: heightOf(aspect, row.length), images: row });
        return rows;
    }

    ColumnLayout {
        id: columnLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: responsePadding
        spacing: 8

        RowLayout { // Header
            Rectangle { // Provider name
                color: Appearance.colors.colSecondaryContainer
                radius: Appearance.rounding.small
                implicitWidth: providerName.implicitWidth + 12 * 2
                implicitHeight: Math.max(providerName.implicitHeight + 4 * 2, 32)
                Layout.alignment: Qt.AlignVCenter

                StyledText {
                    id: providerName
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.m3colors.m3onSecondaryContainer
                    text: Booru.providers[root.responseData.provider].name
                }
            }
            Item { Layout.fillWidth: true }
            StyledText { // Page number
                visible: root.responseData.page != "" && root.responseData.page > 0
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: 8
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Page %1").arg(root.responseData.page)
            }
        }

        StyledFlickable { // Tag strip. The chips round themselves; clip holds the strip
            visible: root.responseData.tags.length > 0
            Layout.fillWidth: true
            implicitHeight: tagRowLayout.implicitHeight
            contentWidth: tagRowLayout.implicitWidth
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            RowLayout {
                id: tagRowLayout

                Repeater {
                    model: root.responseData.tags

                    ApiCommandButton {
                        Layout.fillWidth: false
                        buttonText: modelData
                        onClicked: {
                            if (root.tagInputField.text.length !== 0) root.tagInputField.text += " "
                            root.tagInputField.text += modelData
                        }
                    }
                }
            }
        }

        StyledText { // Message
            Layout.fillWidth: true
            visible: root.responseData.message.length > 0
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            text: root.responseData.message
            wrapMode: Text.WordWrap
            Layout.margins: responsePadding
            textFormat: Text.MarkdownText
            onLinkActivated: (link) => {
                Qt.openUrlExternally(link)
                GlobalStates.sidebarLeftOpen = false
            }
            PointingHandLinkHover {}
        }

        Item { // Image grid
            visible: root.rows.length > 0
            Layout.fillWidth: true
            implicitHeight: tiles.implicitHeight

            // One mask for the whole grid, drawn from the same rows as the tiles,
            // so every tile is rounded for the price of one layer (DESIGN.md 8).
            // Plain Column/Row on both sides so the two land on the same pixels.
            Column {
                id: tiles
                width: parent.width
                spacing: root.imageSpacing
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: tileMask
                }

                Repeater {
                    model: root.rows
                    delegate: Row {
                        id: imageRow
                        required property var modelData
                        spacing: root.imageSpacing

                        Repeater {
                            model: imageRow.modelData.images
                            delegate: BooruImage {
                                id: tile
                                required property var modelData
                                imageData: modelData
                                rowHeight: imageRow.modelData.height
                                menuShown: menu.shown
                                // Download manually to reduce redundant requests or make sure downloading works
                                manualDownload: ["danbooru", "waifu.im", "t.alcy.cc"].includes(root.responseData.provider)
                                previewDownloadPath: root.previewDownloadPath
                                onMenuRequested: (x, y) => menu.open(tile, x, y)
                            }
                        }
                    }
                }
            }

            Column {
                id: tileMask
                visible: false
                width: tiles.width
                height: tiles.height
                spacing: root.imageSpacing

                Repeater {
                    model: root.rows
                    delegate: Row {
                        id: maskRow
                        required property var modelData
                        spacing: root.imageSpacing

                        Repeater {
                            model: maskRow.modelData.images
                            delegate: Rectangle {
                                required property var modelData
                                width: maskRow.modelData.height * modelData.aspect_ratio
                                height: maskRow.modelData.height
                                radius: Appearance.rounding.small
                            }
                        }
                    }
                }
            }
        }

        RippleButton { // Next page button
            visible: root.responseData.page != "" && root.responseData.page > 0

            Layout.alignment: Qt.AlignRight
            implicitHeight: 30
            leftPadding: 12
            rightPadding: 8

            onClicked: {
                tagInputField.text = `${responseData.tags.join(" ")} ${parseInt(root.responseData.page) + 1}`
                tagInputField.accept()
            }

            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSurfaceContainerHighest
            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
            colRipple: Appearance.colors.colSurfaceContainerHighestActive

            contentItem: RowLayout {
                spacing: 4
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Next page")
                    color: Appearance.m3colors.m3onSurface
                }
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.m3colors.m3onSurface
                    text: "chevron_right"
                }
            }
        }
    }

    // One menu for every tile in this response. It is drawn from the window's
    // content item so neither the list's clip nor the next response covers it,
    // and it grows out of the click on a zero-size pivot (DESIGN.md 2.6, 9).
    Item {
        id: menu
        property var image: null // Kept through the exit so the rows do not empty
        property string fileName
        property bool shown: false
        // The list's rect in the host's coordinates. The window is wider than the
        // panel it draws, so its own edges are no bound for the card.
        property rect bounds

        width: parent?.width ?? 0
        height: parent?.height ?? 0
        visible: shown || pivot.visible

        function open(tile, x, y): void {
            // Set here, never as a binding: CalendarPopup found that reparenting
            // while Quickshell rebuilds the window on a sidebar open segfaults.
            const host = tile.QsWindow?.contentItem;
            if (!host)
                return;
            menu.parent = host;
            menu.image = tile.imageData;
            menu.fileName = tile.fileName;
            const view = root.ListView.view ?? root.parent;
            menu.bounds = host.mapFromItem(view, 0, 0, view.width, view.height);
            const point = host.mapFromItem(tile, x, y);
            pivot.x = point.x;
            pivot.y = point.y;
            menu.shown = true;
            card.forceActiveFocus();
            motion.open();
        }

        function close(): void {
            if (!menu.shown)
                return;
            menu.shown = false;
            motion.close();
            root.tagInputField?.forceActiveFocus();
        }

        function openExternally(url): void {
            menu.close();
            Hyprland.dispatch("hl.config({cursor = {no_warps = true}})");
            Qt.openUrlExternally(url);
            Hyprland.dispatch("hl.config({cursor = {no_warps = false}})");
        }

        Connections {
            target: GlobalStates
            function onPoliciesPanelOpenChanged() {
                if (!GlobalStates.policiesPanelOpen)
                    menu.close();
            }
        }

        MouseArea { // Any press outside dismisses; a wheel dismisses and still scrolls
            anchors.fill: parent
            enabled: menu.shown
            acceptedButtons: Qt.AllButtons
            onPressed: menu.close()
            onWheel: wheel => {
                menu.close();
                wheel.accepted = false;
            }
        }

        Item {
            id: pivot
            opacity: 0
            scale: Appearance.animationCurves.arrowPopupScale
            visible: opacity > 0

            ArrowPopupMotion {
                id: motion
                target: pivot
                onClosed: menu.image = null
            }

            StyledRectangularShadow {
                target: card
            }

            Rectangle {
                id: card
                readonly property real gutter: Appearance.sizes.elevationMargin

                // Right of and below the pointer when it fits, else the other side;
                // then clamped inside the list. The side is chosen from where the
                // pointer is, never from where the clamp put the card.
                x: {
                    const left = menu.bounds.x + gutter - pivot.x, right = menu.bounds.x + menu.bounds.width - gutter - width - pivot.x;
                    return Math.max(left, Math.min(right >= 0 ? 0 : -width, right));
                }
                y: {
                    const top = menu.bounds.y + gutter - pivot.y, bottom = menu.bounds.y + menu.bounds.height - gutter - height - pivot.y;
                    return Math.max(top, Math.min(bottom >= 0 ? 0 : -height, bottom));
                }
                // Inset as DockContextMenuBase is, so a square row's hover stays inside the corners
                implicitWidth: menuColumn.implicitWidth + 8 * 2
                implicitHeight: menuColumn.implicitHeight + 8 * 2
                radius: Appearance.rounding.normal
                // Floats over the sidebar rather than sitting on a layer, so the
                // palette colour at full alpha, as CalendarPopup does.
                readonly property color base: Appearance.m3colors.m3surfaceContainerHigh
                color: Qt.rgba(base.r, base.g, base.b, 1)

                Keys.onEscapePressed: menu.close()

                ColumnLayout {
                    id: menuColumn
                    anchors.centerIn: parent
                    spacing: 0

                    MenuButton {
                        Layout.fillWidth: true
                        buttonText: Translation.tr("Open file link")
                        onClicked: menu.openExternally(menu.image.file_url)
                    }
                    MenuButton {
                        visible: (menu.image?.source ?? "").length > 0
                        Layout.fillWidth: true
                        buttonText: Translation.tr("Go to source (%1)").arg(StringUtils.getDomain(menu.image?.source ?? ""))
                        onClicked: menu.openExternally(menu.image.source)
                    }
                    MenuButton {
                        Layout.fillWidth: true
                        buttonText: Translation.tr("Download")
                        onClicked: {
                            menu.close();
                            const targetPath = menu.image.is_nsfw ? root.nsfwPath : root.downloadPath;
                            // Arguments, not interpolation: the URL and name come from a remote API.
                            Quickshell.execDetached(["bash", "-c", 'mkdir -p "$1" && curl -fsSL "$2" -o "$1/$3" && notify-send "$4" "$1/$3" -a Shell',
                                "_", targetPath, menu.image.file_url, menu.fileName, Translation.tr("Download complete")]);
                        }
                    }
                }
            }
        }
    }
}
