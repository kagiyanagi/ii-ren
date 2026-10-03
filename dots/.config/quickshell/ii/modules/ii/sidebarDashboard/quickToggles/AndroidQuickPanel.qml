import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

import qs.modules.ii.sidebarDashboard.quickToggles.androidStyle
import "androidStyle/QuickToggleCatalog.js" as QuickToggleCatalog
import "androidStyle/QuickToggleLayout.js" as QuickToggleLayout

AbstractQuickPanel {
    id: root
    property bool editMode: false
    Layout.fillWidth: true

    property int currentPage: 0

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen && editController.active)
                editController.cancel();
        }
    }

    onEditModeChanged: {
        if (!root.editMode && editController.active)
            editController.cancel();
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.editMode && editController.active
        onActivated: editController.cancel()
    }

    property real spacing: 6
    property real padding: 6
    // A row of `columns` tiles has one gap fewer than it has tiles.
    readonly property real baseCellWidth: {
        const availableWidth = root.width - (root.padding * 2) - (root.spacing * (root.columns - 1));
        return availableWidth / root.columns;
    }
    readonly property real baseCellHeight: 56

    readonly property list<string> availableToggleTypes: QuickToggleCatalog.allTypes()
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns

    // The canonical in-memory shape. The legacy `size` field is read only by
    // the catalog normalizer and is never handed to a delegate.
    readonly property list<var> pages: {
        const cfg = Config.options.sidebar.quickToggles.android;
        if (!Config.ready)
            return [[]];
        if (!cfg.pages || cfg.pages.length === 0)
            return [[]];
        return QuickToggleCatalog.normalizePages(cfg.pages, root.columns, {
            warn: function(message) { console.warn(message); }
        });
    }

    QuickToggleEditController {
        id: editController
        config: Config.options.sidebar.quickToggles.android
        persistedPages: root.pages
        columns: root.columns
    }

    property alias editController: editController

    // The persisted page arrays are the delegate model. A gesture may change
    // preview geometry, but it must never reorder/retype this model while a
    // MouseArea owns the grab.
    readonly property list<var> displayPages: root.pages

    // Same-page reorder and resize get a live packed preview. Cross-page drag
    // keeps both pages stable until release, then commits one atomic move.
    readonly property list<var> geometryPages: {
        if (!editController.active)
            return root.pages;
        if (editController.mode === "resize"
                || editController.targetPage === editController.sourcePage)
            return editController.draftPages;
        return root.pages;
    }

    readonly property list<string> allUsedIds: {
        var ids = [];
        for (var p = 0; p < root.pages.length; p++) {
            var page = root.pages[p];
            if (!page)
                continue;
            for (var i = 0; i < page.length; i++) {
                if (page[i] && page[i].id)
                    ids.push(page[i].id);
            }
        }
        return ids;
    }

    readonly property list<var> unusedToggles: {
        var items = [];
        for (var i = 0; i < availableToggleTypes.length; i++) {
            var type = availableToggleTypes[i];
            if (type === "custom")
                continue;
            if (!allUsedIds.includes(type))
                items.push(QuickToggleCatalog.item(type, type, undefined, undefined, root.columns));
        }
        var customs = CustomToggles.list;
        for (var j = 0; j < customs.length; j++) {
            var cust = customs[j];
            if (cust && cust.id && !allUsedIds.includes(cust.id))
                items.push(QuickToggleCatalog.item("custom", cust.id, undefined, undefined, root.columns));
        }
        return items;
    }

    readonly property var packedUnusedToggles: QuickToggleLayout.pack(root.unusedToggles, root.columns)
    readonly property list<var> positionedUnusedToggles: QuickToggleLayout.positionedItems(
        root.unusedToggles,
        root.packedUnusedToggles,
        root.baseCellWidth,
        root.baseCellHeight,
        root.spacing
    )

    // One packer owns both visible geometry and height. Delegates are decorated
    // by stable id below; their model order remains the persisted order.
    readonly property list<var> packedPages: {
        var result = [];
        for (var i = 0; i < geometryPages.length; i++)
            result.push(QuickToggleLayout.pack(geometryPages[i] || [], root.columns));
        return result;
    }

    readonly property list<var> positionedPages: {
        var result = [];
        for (var i = 0; i < root.pages.length; i++) {
            result.push(QuickToggleLayout.positionedItems(
                root.pages[i] || [],
                root.packedPages[i] || { rowsUsed: 0, items: [] },
                root.baseCellWidth,
                root.baseCellHeight,
                root.spacing
            ));
        }
        return result;
    }

    function pageHeight(pageIndex) {
        if (pageIndex < 0 || pageIndex >= root.pages.length)
            return baseCellHeight + 8;
        var packedPage = packedPages[pageIndex];
        var rows = packedPage ? packedPage.rowsUsed : 0;
        return Math.max(baseCellHeight, rows * (baseCellHeight + spacing) - spacing) + 8;
    }

    readonly property real currentContentHeight: pageHeight(currentPage) + (editMode ? 14 : 0)

    implicitHeight: panelContent.implicitHeight + root.padding * 2
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    function addPage() {
        if (editController.addPage())
            currentPage = editController.targetPage;
    }

    function removePage(pageIndex) {
        if (!editController.removePage(pageIndex))
            return;
        var remaining = Config.options.sidebar.quickToggles.android.pages.length;
        currentPage = Math.min(currentPage, Math.max(0, remaining - 1));
    }

    function goToPage(pageIndex) {
        if (pageIndex < 0 || pageIndex >= displayPages.length)
            return;
        currentPage = pageIndex;
    }

    // Held near an edge while dragging a tile, the panel turns the page.
    property real dragScrollEdgeThreshold: 40
    property int dragScrollPendingPage: -1

    Timer {
        id: dragScrollTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (root.dragScrollPendingPage >= 0 && root.dragScrollPendingPage < root.displayPages.length) {
                root.currentPage = root.dragScrollPendingPage;
                if (root.editController.active)
                    root.editController.setTargetPage(root.dragScrollPendingPage);
            }
            root.dragScrollPendingPage = -1;
        }
    }

    function cancelDragScroll() {
        dragScrollTimer.stop();
        dragScrollPendingPage = -1;
    }

    function handleDragScrollRequest(absX) {
        var newPage = -1;
        if (absX < dragScrollEdgeThreshold && currentPage > 0) {
            newPage = currentPage - 1;
        } else if (absX > root.width - dragScrollEdgeThreshold && currentPage < displayPages.length - 1) {
            newPage = currentPage + 1;
        }

        if (newPage >= 0 && newPage !== dragScrollPendingPage) {
            dragScrollPendingPage = newPage;
            dragScrollTimer.restart();
        } else if (newPage < 0) {
            dragScrollPendingPage = -1;
            dragScrollTimer.stop();
        }
    }

    StyledFlickable {
        id: panelScroll
        anchors {
            fill: parent
            margins: root.padding
        }
        clip: true
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        contentHeight: panelContent.implicitHeight
        interactive: contentHeight > height

        Column {
            id: panelContent
            width: panelScroll.width
            spacing: 8

            Item {
                id: flickableContainer
                width: parent.width
                // Not animated: the panel's own implicitHeight is, and a Behavior
                // here as well made that one chase a target moving every frame.
                height: root.currentContentHeight
                clip: true

                Flickable {
                    id: flickable
                    anchors.fill: parent
                    contentWidth: width * root.displayPages.length
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: !root.editMode

                    onMovementEnded: {
                        var targetPage = Math.round(contentX / width);
                        targetPage = Math.max(0, Math.min(targetPage, root.displayPages.length - 1));
                        root.currentPage = targetPage;
                        snapAnimation.to = targetPage * width;
                        snapAnimation.start();
                    }

                    MouseArea {
                        id: wheelArea
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton

                        // One gesture turns exactly one page, however far it travels:
                        // a notch's worth of scroll (120) turns it, the rest is spent
                        // until the fingers lift (ScrollEnd) or the stream goes quiet.
                        property real travelX: 0
                        property real travelY: 0
                        property bool spent: false

                        function release() {
                            travelX = 0;
                            travelY = 0;
                            spent = false;
                        }

                        Timer {
                            id: gestureQuiet
                            interval: 300
                            onTriggered: wheelArea.release()
                        }

                        onWheel: function (wheelEvent) {
                            // Always accepted, or the Flickable scrolls on it and lands
                            // wherever the swipe ran out.
                            wheelEvent.accepted = root.displayPages.length > 1;
                            if (wheelEvent.phase === Qt.ScrollEnd) {
                                gestureQuiet.stop();
                                release();
                                return;
                            }
                            gestureQuiet.restart();
                            if (spent)
                                return;
                            travelX += wheelEvent.angleDelta.x;
                            travelY += wheelEvent.angleDelta.y;
                            const travel = Math.abs(travelX) > Math.abs(travelY) ? travelX : travelY;
                            if (Math.abs(travel) < 120)
                                return;
                            spent = true;
                            root.goToPage(root.currentPage + (travel < 0 ? 1 : -1));
                        }
                    }

                    NumberAnimation {
                        id: snapAnimation
                        target: flickable
                        property: "contentX"
                        // A panel-width page turn is a curve-based surface move (2.4):
                        // decelerating, because a spatial curve would overshoot past
                        // the last page into blank space.
                        duration: Appearance.animation.elementMoveSmall.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }

                    Row {
                        height: parent.height

                        Repeater {
                            model: root.displayPages.length

                            Item {
                                id: pageContainer
                                required property int index
                                width: flickable.width
                                height: flickable.height

                                property list<var> pageToggles: root.positionedPages[index] || []

                                Item {
                                    id: pageContentCanvas
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        top: parent.top
                                    }
                                    implicitHeight: root.pageHeight(pageContainer.index)
                                    height: implicitHeight

                                    StableQuickToggleModel {
                                        id: pageToggleModel
                                        sourceValues: pageContainer.pageToggles
                                    }

                                    Repeater {
                                        model: pageToggleModel
                                        delegate: AndroidToggleDelegateChooser {
                                            isUnused: false
                                            pageIndex: pageContainer.index
                                            panel: root
                                            gridRef: pageContentCanvas

                                            onOpenAudioOutputDialog: root.openAudioOutputDialog()
                                            onOpenAudioInputDialog: root.openAudioInputDialog()
                                            onOpenBluetoothDialog: root.openBluetoothDialog()
                                            onOpenNightLightDialog: root.openNightLightDialog()
                                            onOpenComfortViewDialog: root.openComfortViewDialog()
                                            onOpenReadingModeDialog: root.openReadingModeDialog()
                                            onOpenAntiFlashbangDialog: root.openAntiFlashbangDialog()
                                            onOpenWifiDialog: root.openWifiDialog()
                                            onOpenHotspotDialog: root.openHotspotDialog()
                                            onOpenDnsDialog: root.openDnsDialog()
                                            onOpenIdleDialog: root.openIdleDialog()
                                            onOpenVpnDialog: root.openVpnDialog()
                                            onOpenEditCustomToggleDialog: toggleId => root.openEditCustomToggleDialog(toggleId)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: pageDots.implicitWidth
                implicitHeight: pageDots.implicitHeight
                visible: root.displayPages.length > 1

                Row {
                    id: pageDots
                    spacing: 6

                    Repeater {
                        model: root.displayPages.length
                        delegate: Rectangle {
                            required property int index
                            width: root.currentPage === index ? 16 : 8
                            height: 8
                            radius: height / 2
                            color: root.currentPage === index ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            opacity: root.currentPage === index ? 1.0 : 0.5

                            Behavior on width {
                                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                            }
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }
                }

                // One target over the whole row, 32px tall (DESIGN.md 3.4), turning
                // to the dot nearest the pointer. Per-dot areas could only be as
                // wide as a dot and half the 6px gap either side.
                MouseArea {
                    anchors.centerIn: parent
                    width: parent.width + 16
                    height: 32
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        const px = mapToItem(pageDots, mouse.x, 0).x;
                        let nearest = -1;
                        let distance = Infinity;
                        for (const dot of pageDots.children) {
                            if (dot.index === undefined)
                                continue;
                            const d = Math.abs(dot.x + dot.width / 2 - px);
                            if (d < distance) {
                                distance = d;
                                nearest = dot.index;
                            }
                        }
                        root.goToPage(nearest);
                    }
                }
            }

            FadeLoader {
                shown: root.editMode
                anchors {
                    left: parent.left
                    right: parent.right
                }
                sourceComponent: RowLayout {
                    spacing: 6

                    RippleButton {
                        Layout.preferredWidth: root.baseCellHeight
                        Layout.preferredHeight: root.baseCellHeight * 0.6
                        visible: root.currentPage > 0
                        buttonRadius: Appearance.rounding.full
                        buttonRadiusPressed: height / 2
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                        onClicked: root.goToPage(root.currentPage - 1)
                        contentItem: MaterialSymbol {
                            text: "chevron_left"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                            horizontalAlignment: Text.AlignHCenter
                        }

                        StyledToolTip {
                            text: Translation.tr("Previous page")
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.baseCellHeight * 0.6
                        radius: Appearance.rounding.full
                        color: "transparent"
                        border.color: Appearance.colors.colOutline
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol {
                                text: "auto_awesome_motion"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Translation.tr("Page %1 / %2").arg(root.currentPage + 1).arg(root.displayPages.length)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }

                    RippleButton {
                        Layout.preferredWidth: root.baseCellHeight
                        Layout.preferredHeight: root.baseCellHeight * 0.6
                        visible: root.currentPage < root.displayPages.length - 1
                        bottomLeftRadius: Appearance.rounding.full
                        topLeftRadius: Appearance.rounding.full
                        bottomRightRadius: Appearance.rounding.verysmall
                        topRightRadius: Appearance.rounding.verysmall
                        buttonRadiusPressed: height / 2
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                        onClicked: root.goToPage(root.currentPage + 1)
                        contentItem: MaterialSymbol {
                            text: "chevron_right"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurface
                            horizontalAlignment: Text.AlignHCenter
                        }

                        StyledToolTip {
                            text: Translation.tr("Next page")
                        }
                    }

                    // The middle of a connected group, so it takes the group's outer
                    // corner on whichever side its neighbour is hidden.
                    RippleButton {
                        Layout.preferredWidth: root.baseCellHeight
                        Layout.preferredHeight: root.baseCellHeight * 0.6
                        readonly property real groupLeftRadius: root.currentPage < root.displayPages.length - 1
                            ? Appearance.rounding.verysmall : Appearance.rounding.full
                        readonly property real groupRightRadius: root.displayPages.length > 1
                            ? Appearance.rounding.verysmall : Appearance.rounding.full
                        bottomLeftRadius: groupLeftRadius
                        topLeftRadius: groupLeftRadius
                        bottomRightRadius: groupRightRadius
                        topRightRadius: groupRightRadius
                        buttonRadiusPressed: height / 2
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        onClicked: root.addPage()
                        contentItem: MaterialSymbol {
                            text: "add"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnPrimary
                            horizontalAlignment: Text.AlignHCenter
                        }
                        StyledToolTip {
                            text: Translation.tr("Add new page")
                        }
                    }

                    RippleButton {
                        Layout.preferredWidth: root.baseCellHeight
                        Layout.preferredHeight: root.baseCellHeight * 0.6
                        visible: root.displayPages.length > 1
                        bottomLeftRadius: Appearance.rounding.verysmall
                        topLeftRadius: Appearance.rounding.verysmall
                        bottomRightRadius: Appearance.rounding.full
                        topRightRadius: Appearance.rounding.full
                        buttonRadiusPressed: height / 2
                        colBackground: Appearance.colors.colErrorContainer
                        colBackgroundHover: Appearance.colors.colErrorContainerHover
                        onClicked: root.removePage(root.currentPage)
                        contentItem: MaterialSymbol {
                            text: "delete"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnErrorContainer
                            horizontalAlignment: Text.AlignHCenter
                        }
                        StyledToolTip {
                            text: Translation.tr("Remove current page")
                        }
                    }
                }
            }

            // The drawer's header: what the tiles under it are, what a click on one
            // does, and the one way to make a tile that is not in the catalog.
            FadeLoader {
                shown: root.editMode
                anchors {
                    left: parent.left
                    right: parent.right
                }
                sourceComponent: RowLayout {
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        // With the column's 8, whitespace between the pages and the drawer.
                        Layout.topMargin: 8
                        Layout.leftMargin: 4
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Available toggles")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.unusedToggles.length > 0 ? Translation.tr("Click one to add it to this page")
                                : Translation.tr("Every toggle is on a page")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }

                    RippleButton {
                        Layout.alignment: Qt.AlignBottom
                        implicitHeight: 32
                        implicitWidth: newCustomToggleRow.implicitWidth + 24
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: root.openNewCustomToggleDialog()
                        contentItem: RowLayout {
                            id: newCustomToggleRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                text: "add"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                text: Translation.tr("Custom toggle")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                        StyledToolTip {
                            text: Translation.tr("Create a custom command toggle")
                        }
                    }
                }
            }

            // The drawer of toggles not on any page
            FadeLoader {
                shown: root.editMode
                anchors {
                    left: parent.left
                    right: parent.right
                }
                sourceComponent: Item {
                    id: unusedCanvas
                    implicitHeight: Math.max(0, root.packedUnusedToggles.rowsUsed
                        * (root.baseCellHeight + root.spacing) - root.spacing)
                    height: implicitHeight

                    StableQuickToggleModel {
                        id: unusedToggleModel
                        sourceValues: root.positionedUnusedToggles
                    }

                    Repeater {
                        model: unusedToggleModel
                        delegate: AndroidToggleDelegateChooser {
                            isUnused: true
                            pageIndex: root.currentPage
                            panel: root
                            gridRef: unusedCanvas

                            onOpenAudioOutputDialog: root.openAudioOutputDialog()
                            onOpenAudioInputDialog: root.openAudioInputDialog()
                            onOpenBluetoothDialog: root.openBluetoothDialog()
                            onOpenNightLightDialog: root.openNightLightDialog()
                            onOpenComfortViewDialog: root.openComfortViewDialog()
                            onOpenReadingModeDialog: root.openReadingModeDialog()
                            onOpenAntiFlashbangDialog: root.openAntiFlashbangDialog()
                            onOpenWifiDialog: root.openWifiDialog()
                            onOpenHotspotDialog: root.openHotspotDialog()
                            onOpenDnsDialog: root.openDnsDialog()
                            onOpenIdleDialog: root.openIdleDialog()
                            onOpenVpnDialog: root.openVpnDialog()
                            onOpenEditCustomToggleDialog: toggleId => root.openEditCustomToggleDialog(toggleId)
                        }
                    }
                }
            }
        }
    }

    onCurrentPageChanged: {
        if (!flickable.moving) {
            snapAnimation.stop();
            snapAnimation.to = currentPage * flickable.width;
            snapAnimation.start();
        }
    }

    onPagesChanged: {
        if (currentPage >= pages.length) {
            currentPage = Math.max(0, pages.length - 1);
        }
    }

}
