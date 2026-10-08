import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

Item {
    id: widgetsConfigRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    Connections {
        target: root
        function onPendingSectionHighlightChanged() {
            if (root.pendingSectionHighlight && root.pendingSectionHighlight.endsWith(".qml")) {
                widgetsConfigRoot.activeSubPage = Qt.resolvedUrl(root.pendingSectionHighlight);
                root.pendingSectionHighlight = ""; // clear after handling
            }
        }
    }

    // Every gallery card re-runs mapToItem() when this changes. Quantising the
    // scroll position keeps that off the per-pixel path: the load/unload
    // margins below are an order of magnitude larger than one step.
    readonly property int scrollStep: Math.floor(widgetsConfigRoot.contentY / 120)

    // Build all category models in one pass. Each individual filter used to
    // walk the complete registry again whenever an extension changed.
    readonly property var widgetCategories: {
        const categories = {
            Clock: [],
            Media: [],
            Weather: [],
            Date: [],
            Photo: [],
            Bluetooth: [],
            Utility: [],
            Resources: [],
            System: []
        };
        const allWidgets = WidgetsRegistry.allWidgets || [];
        for (let i = 0; i < allWidgets.length; i++) {
            const widget = allWidgets[i];
            if (widget.category === "Devices" || widget.category === "Bluetooth")
                categories.Bluetooth.push(widget);
            else if (categories[widget.category] !== undefined)
                categories[widget.category].push(widget);
        }
        return categories;
    }

    readonly property var categoriesList: [
        { id: "clock", title: Translation.tr("Clocks"), icon: "schedule", widgets: widgetCategories.Clock },
        { id: "media", title: Translation.tr("Media players"), icon: "play_circle", widgets: widgetCategories.Media },
        { id: "weather", title: Translation.tr("Weather"), icon: "cloud", widgets: widgetCategories.Weather },
        { id: "date", title: Translation.tr("Date & calendar"), icon: "calendar_today", widgets: widgetCategories.Date },
        { id: "photo", title: Translation.tr("Photo"), icon: "image", widgets: widgetCategories.Photo },
        { id: "bluetooth", title: Translation.tr("Devices & Bluetooth"), icon: "devices", widgets: widgetCategories.Bluetooth },
        { id: "utility", title: Translation.tr("Utility"), icon: "build", widgets: widgetCategories.Utility },
        { id: "system", title: Translation.tr("System"), icon: "tune", widgets: widgetCategories.System },
        { id: "resource", title: Translation.tr("Resources"), icon: "monitor_heart", widgets: widgetCategories.Resources }
    ]

    property var expandedCategories: ({
        "clock": false,
        "media": false,
        "weather": false,
        "date": false,
        "photo": false,
        "bluetooth": false,
        "utility": false,
        "system": false,
        "resource": false
    })

    function toggleCategory(catId) {
        let updated = Object.assign({}, expandedCategories);
        updated[catId] = !updated[catId];
        expandedCategories = updated;
    }

    function countActiveWidgets(categoryWidgetList) {
        if (!categoryWidgetList || categoryWidgetList.length === 0)
            return 0;
        let activeList = Config.options.background.activeWidgets || [];
        if (activeList.length === 0)
            return 0;
        let count = 0;
        for (let i = 0; i < categoryWidgetList.length; i++) {
            let wid = categoryWidgetList[i].widgetId;
            for (let j = 0; j < activeList.length; j++) {
                if (activeList[j].widgetId === wid) {
                    count++;
                    break;
                }
            }
        }
        return count;
    }

    // Rich catalog sections are opt-in. This keeps the first page pass limited
    // to the small Desktop Widgets controls and avoids starting network work.
    property bool colorSchemeActive: false

    property var _previewQueue: []
    property bool _previewStaggerActive: false

    function _enqueuePreview(card) {
        if (!card || card._previewActive || card._previewQueued || !card.previewNearViewport)
            return;

        card._previewQueued = true;
        _previewQueue.push(card);
        if (!_previewStaggerActive) {
            _previewStaggerActive = true;
            _previewStaggerTimer.start();
        }
    }

    function _removePreview(card) {
        const index = _previewQueue.indexOf(card);
        if (index >= 0)
            _previewQueue.splice(index, 1);
    }

    Timer {
        id: _previewStaggerTimer
        interval: 30
        repeat: true
        onTriggered: {
            if (widgetsConfigRoot._previewQueue.length > 0) {
                var card = widgetsConfigRoot._previewQueue.shift();
                if (card) {
                    card._previewQueued = false;
                    if (card.previewNearViewport)
                        card._previewActive = true;
                }
            } else {
                widgetsConfigRoot._previewStaggerActive = false;
                stop();
            }
        }
    }

    Timer {
        id: colorSchemeLoadTimer
        interval: 0
        repeat: false
        onTriggered: widgetsConfigRoot.colorSchemeActive = true
    }

    Component.onCompleted: {
        colorSchemeLoadTimer.start();
        if (root.pendingSectionHighlight && root.pendingSectionHighlight.endsWith(".qml")) {
            widgetsConfigRoot.activeSubPage = Qt.resolvedUrl(root.pendingSectionHighlight);
            root.pendingSectionHighlight = "";
        }
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: true
        readonly property int index: 7
        property bool register: parent.register ?? false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        // ── 1. Desktop Widgets Configuration ─────────────────────────────────
        ContentSection {
            title: Translation.tr("Desktop widgets")
            icon: "widgets"

            ConfigSwitch {
                buttonIcon: "grid_on"
                text: Translation.tr("Enable alignment grid (10px)")
                checked: Config.options.background.widgets.enableGrid ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.enableGrid = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "align_horizontal_center"
                text: Translation.tr("Enable layout snap alignment")
                checked: Config.options.background.widgets.enableSnap ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.enableSnap = checked;
                }
            }

            NoticeBox {
                color: "transparent"
                textColor: Appearance.colors.colOnLayer0
                Layout.fillWidth: true
                materialIcon: "info"
                text: Translation.tr("Hold Ctrl while dragging a widget to temporarily disable the alignment grid and snap for pixel-perfect placement")
            }

            ConfigSlider {
                buttonIcon: "photo_size_select_small"
                text: Translation.tr("Global widget scale")
                value: Config.options.background.widgets.widgetsScale ?? 1.0
                from: 0.5
                to: 2.0
                onMoved: val => {
                    Config.options.background.widgets.widgetsScale = val;
                }
            }

            ConfigSwitch {
                buttonIcon: "lock"
                text: Translation.tr("Lock widget positions")
                checked: Config.options.background.widgets.lockWidgetPositions ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.lockWidgetPositions = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "desktop_windows"
                text: Translation.tr("Show widgets only in one monitor")
                checked: Config.options.background.widgets.showOnlyOnSingleMonitor ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.showOnlyOnSingleMonitor = checked;
                }
            }

            MonitorPicker {
                visible: Config.options.background.widgets.showOnlyOnSingleMonitor ?? false
                currentValue: Config.options.background.widgets.targetMonitor ?? ""
                onSelected: newValue => {
                    Config.options.background.widgets.targetMonitor = newValue;
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.preferredHeight: item ? item.implicitHeight : 0
                active: widgetsConfigRoot.colorSchemeActive
                asynchronous: true
                sourceComponent: ContentSubsection {
                    title: Translation.tr("Widget color scheme")
                    Layout.fillWidth: true

                    // A plain card in the run, like every other row: ContentGroup
                    // paints it, so it takes the card's corners and reach. The
                    // outline it used to draw is the only one on the page.
                    Item {
                        readonly property bool wantsCard: true
                        Layout.fillWidth: true
                        implicitHeight: schemeGrid.implicitHeight + 24

                        GridLayout {
                            id: schemeGrid
                            anchors.fill: parent
                            anchors.topMargin: 12
                            anchors.bottomMargin: 12
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            columns: 3
                            rowSpacing: 8
                            columnSpacing: 8

                            Repeater {
                                model: WidgetColorScheme.availableSchemes

                                delegate: RippleButton {
                                    required property var modelData

                                    Layout.fillWidth: true
                                    implicitHeight: 64

                                    readonly property bool toggled: Config.options.background.widgets.colorScheme === modelData
                                    readonly property bool sharpMode: Config.options.appearance.sharpMode

                                    colBackground: toggled ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                                    colBackgroundHover: toggled ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                                    colRipple: toggled ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active

                                    buttonRadius: Appearance.rounding.small

                                    onClicked: Config.options.background.widgets.colorScheme = modelData

                                    StyledToolTip {
                                        text: WidgetColorScheme.schemes[modelData] ? WidgetColorScheme.schemes[modelData].name : modelData
                                    }

                                    Item {
                                        anchors.fill: parent

                                        Canvas {
                                            id: myCanvas
                                            anchors.centerIn: parent
                                            anchors.margins: 8

                                            implicitWidth: parent.height - 16
                                            implicitHeight: parent.height - 16
                                            antialiasing: true
                                            // Painted once, so a rounding-style change left
                                            // the swatches in the old shape.
                                            readonly property bool sharp: sharpMode
                                            onSharpChanged: requestPaint()

                                            onPaint: {
                                                var ctx = getContext("2d");
                                                var centerX = width / 2;
                                                var centerY = height / 2;
                                                var radius = width / 2;

                                                var primaryColor = WidgetColorScheme.getCardBgColor(modelData);
                                                var secondaryColor = WidgetColorScheme.getTextColorOnBg(modelData);
                                                var tertiaryColor = WidgetColorScheme.getAccentColor(modelData);

                                                ctx.reset();

                                                if (sharpMode) {
                                                    ctx.fillStyle = primaryColor;
                                                    ctx.fillRect(0, 0, width, centerY);

                                                    ctx.fillStyle = secondaryColor;
                                                    ctx.fillRect(centerX, centerY, centerX, centerY);

                                                    ctx.fillStyle = tertiaryColor;
                                                    ctx.fillRect(0, centerY, centerX, centerY);
                                                } else {
                                                    ctx.beginPath();
                                                    ctx.fillStyle = primaryColor;
                                                    ctx.moveTo(centerX, centerY);
                                                    ctx.arc(centerX, centerY, radius, Math.PI, 0, false);
                                                    ctx.fill();

                                                    ctx.beginPath();
                                                    ctx.fillStyle = secondaryColor;
                                                    ctx.moveTo(centerX, centerY);
                                                    ctx.arc(centerX, centerY, radius, 0, Math.PI / 2, false);
                                                    ctx.fill();

                                                    ctx.beginPath();
                                                    ctx.fillStyle = tertiaryColor;
                                                    ctx.moveTo(centerX, centerY);
                                                    ctx.arc(centerX, centerY, radius, Math.PI / 2, Math.PI, false);
                                                    ctx.fill();
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── 2. Widget Catalog (Categorized Gallery) ──────────────────────────
        ContentSection {
            title: Translation.tr("Widget catalog")
            icon: "dashboard_customize"
            tooltip: Translation.tr("Browse, preview, and configure widgets across all categories")

            // One card run, one card per category, as the rest of the page.
            ContentGroup {
                Repeater {
                    model: widgetsConfigRoot.categoriesList
                    delegate: categorySectionComponent
                }
            }
        }
    }

    // ── Category Section Component ───────────────────────────────────────────
    Component {
        id: categorySectionComponent

        // ContentGroup paints the card and hands this tile the card's corners
        // and reach; the header passes them on to its hover film (5.6). The
        // outline it used to draw, primary when open, was the page's only one:
        // open is the chevron and the tinted icon tile.
        Item {
            id: catCard
            required property var modelData
            required property int index

            readonly property bool wantsCard: true
            property real buttonRadius: Appearance.rounding.verysmall
            property real topLeftRadius: buttonRadius
            property real topRightRadius: buttonRadius
            property real bottomLeftRadius: buttonRadius
            property real bottomRightRadius: buttonRadius
            property real backgroundBleedLeft: 0
            property real backgroundBleedRight: 0

            Layout.fillWidth: true
            implicitHeight: catCol.implicitHeight

            readonly property string catId: modelData.id
            readonly property var catWidgets: modelData.widgets || []
            readonly property bool isExpanded: widgetsConfigRoot.expandedCategories[catId] ?? false
            readonly property int activeCount: widgetsConfigRoot.countActiveWidgets(catWidgets)

            ColumnLayout {
                id: catCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                spacing: 0

                RippleButton {
                    id: headerBtn
                    Layout.fillWidth: true
                    implicitHeight: 52
                    topLeftRadius: catCard.topLeftRadius
                    topRightRadius: catCard.topRightRadius
                    bottomLeftRadius: catCard.isExpanded ? Appearance.rounding.verysmall : catCard.bottomLeftRadius
                    bottomRightRadius: catCard.isExpanded ? Appearance.rounding.verysmall : catCard.bottomRightRadius
                    backgroundBleedLeft: catCard.backgroundBleedLeft
                    backgroundBleedRight: catCard.backgroundBleedRight
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: widgetsConfigRoot.toggleCategory(catCard.catId)

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 8
                            rightMargin: 8
                        }
                        spacing: 12

                        Rectangle {
                            implicitWidth: 32
                            implicitHeight: 32
                            radius: Appearance.rounding.small
                            color: catCard.isExpanded ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: catCard.modelData.icon
                                iconSize: Appearance.font.pixelSize.normal
                                color: catCard.isExpanded ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: catCard.modelData.title
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }

                        // Active count badge
                        Rectangle {
                            visible: catCard.activeCount > 0
                            implicitWidth: activeBadgeRow.implicitWidth + 12
                            implicitHeight: 22
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colPrimaryContainer

                            RowLayout {
                                id: activeBadgeRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: "check"
                                    iconSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnPrimaryContainer
                                }
                                StyledText {
                                    text: catCard.activeCount + " " + Translation.tr("active")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnPrimaryContainer
                                }
                            }
                        }

                        // Total count chip
                        StyledText {
                            text: catCard.catWidgets.length + " " + Translation.tr("widgets")
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colSubtext
                        }

                        MaterialSymbol {
                            text: "keyboard_arrow_down"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnLayer1
                            rotation: catCard.isExpanded ? 180 : 0
                            // A rotation is spatial: elementMove, like every other
                            // chevron in the shell. It was on the fast effects spec.
                            Behavior on rotation {
                                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                            }
                        }
                    }
                }

                // It snapped open and shut. Revealer grows it on the spatial spec
                // and collapses it on the exit one; the Loader stays up until the
                // collapse has finished, or it would empty the card first.
                Revealer {
                    id: catReveal
                    Layout.fillWidth: true
                    vertical: true
                    reveal: catCard.isExpanded && catLoader.status === Loader.Ready

                    Loader {
                        id: catLoader
                        x: 12
                        y: 12
                        width: catReveal.width - 24
                        // 12 above and 4 below, which is what the card had.
                        height: (item?.implicitHeight ?? 0) + 4
                        active: catCard.isExpanded || catReveal.visible
                        asynchronous: true
                        sourceComponent: Flow {
                            id: flowContainer
                            Layout.fillWidth: true
                            spacing: 12

                            readonly property int minColWidth: 200
                            readonly property int columns: Math.max(1, Math.floor((width + spacing) / (minColWidth + spacing)))
                            readonly property real cardWidth: Math.floor((width - (columns - 1) * spacing) / columns)

                            Repeater {
                                model: catCard.catWidgets
                                delegate: widgetCardComponent
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Widget Card Component ────────────────────────────────────────────────
    Component {
        id: widgetCardComponent

        Item {
            id: cardItem
            width: parent && parent.cardWidth ? parent.cardWidth : 220
            implicitHeight: cardBackground.implicitHeight

            property bool _previewActive: false
            property bool _previewQueued: false

            // How far outside the viewport this card sits, in pixels; 0 while
            // any part of it is on screen. One mapToItem() feeds both the load
            // and the unload decision.
            readonly property real viewportDistance: {
                widgetsConfigRoot.scrollStep;
                widgetsConfigRoot.width;
                widgetsConfigRoot.height;
                cardItem.x;
                cardItem.y;
                cardItem.height;

                if (!cardItem.visible || widgetsConfigRoot.height <= 0)
                    return Number.MAX_VALUE;

                const point = cardItem.mapToItem(widgetsConfigRoot, 0, 0);
                if (point.y > widgetsConfigRoot.height)
                    return point.y - widgetsConfigRoot.height;
                if (point.y + cardItem.height < 0)
                    return -(point.y + cardItem.height);
                return 0;
            }

            readonly property real previewLoadMargin: Math.max(cardItem.height, widgetsConfigRoot.height * 0.25)
            readonly property bool previewNearViewport: cardItem.viewportDistance < cardItem.previewLoadMargin
            readonly property bool previewFarFromViewport: cardItem.viewportDistance > widgetsConfigRoot.height * 1.5

            function requestPreviewIfVisible() {
                if (previewNearViewport)
                    widgetsConfigRoot._enqueuePreview(cardItem);
            }

            function releasePreview() {
                widgetsConfigRoot._removePreview(cardItem);
                cardItem._previewQueued = false;
                cardItem._previewActive = false;
            }

            Component.onCompleted: Qt.callLater(requestPreviewIfVisible)
            Component.onDestruction: widgetsConfigRoot._removePreview(cardItem)
            onPreviewNearViewportChanged: requestPreviewIfVisible()
            onPreviewFarFromViewportChanged: {
                if (cardItem.previewFarFromViewport)
                    cardItem.releasePreview();
            }

            readonly property var widgetData: modelData
            readonly property var _activeWidgets: Config.options.background.activeWidgets
            readonly property bool isActive: {
                let list = _activeWidgets || [];
                for (let i = 0; i < list.length; i++) {
                    if (list[i].widgetId === widgetData.widgetId)
                        return true;
                }
                return false;
            }
            readonly property string currentLockBehavior: {
                let list = _activeWidgets || [];
                for (let i = 0; i < list.length; i++) {
                    if (list[i].widgetId === widgetData.widgetId)
                        return list[i].lockBehavior || "hide";
                }
                return "hide";
            }

            Rectangle {
                id: cardBackground
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                implicitHeight: mainColumn.implicitHeight + 16
                color: cardMouseArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                radius: Appearance.rounding.large
                border.color: cardItem.isActive ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                border.width: cardItem.isActive ? 2 : 1

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                Behavior on border.color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MouseArea {
                    id: cardMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                }

                ColumnLayout {
                    id: mainColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 8
                    }
                    spacing: 8

                    // Preview container with fallback watermark
                    Item {
                        id: previewContainer
                        Layout.fillWidth: true
                        Layout.preferredHeight: 140
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            color: Appearance.colors.colLayer0
                            radius: Appearance.rounding.normal
                            border.color: Appearance.colors.colLayer0Border
                            border.width: 1

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                opacity: (!widgetPreviewLoader.item || widgetPreviewLoader.status !== Loader.Ready) ? 0.6 : 0.2

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: cardItem.widgetData.icon || "widgets"
                                    iconSize: Appearance.font.pixelSize.hugeass * 2
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: cardItem.widgetData.name
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    visible: !widgetPreviewLoader.item
                                }
                            }
                        }

                        Item {
                            id: previewScaler
                            width: widgetPreviewLoader.item ? Math.max(100, widgetPreviewLoader.item.implicitWidth || widgetPreviewLoader.item.width) : 200
                            height: widgetPreviewLoader.item ? Math.max(100, widgetPreviewLoader.item.implicitHeight || widgetPreviewLoader.item.height) : 200
                            scale: Math.min((previewContainer.width - 12) / width, (previewContainer.height - 12) / height)
                            transformOrigin: Item.Center
                            anchors.centerIn: parent

                            Loader {
                                id: widgetPreviewLoader
                                anchors.fill: parent
                                active: cardItem._previewActive
                                asynchronous: true
                                source: cardItem._previewActive ? cardItem.widgetData.qmlPath : ""

                                Binding { target: widgetPreviewLoader.item; property: "isPreview"; value: true }
                                Binding { target: widgetPreviewLoader.item; property: "screenWidth"; value: 1920 }
                                Binding { target: widgetPreviewLoader.item; property: "screenHeight"; value: 1080 }
                                Binding { target: widgetPreviewLoader.item; property: "scaledScreenWidth"; value: 1920 }
                                Binding { target: widgetPreviewLoader.item; property: "scaledScreenHeight"; value: 1080 }
                                Binding { target: widgetPreviewLoader.item; property: "wallpaperScale"; value: 1.0 }
                                Binding { target: widgetPreviewLoader.item; property: "styleOverride"; value: cardItem.widgetData.styleOverride || "" }
                            }
                        }

                        // Active status badge
                        Rectangle {
                            visible: cardItem.isActive
                            anchors {
                                top: parent.top
                                right: parent.right
                                margins: 6
                            }
                            implicitWidth: activeBadgeInner.implicitWidth + 10
                            implicitHeight: 20
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colPrimary

                            RowLayout {
                                id: activeBadgeInner
                                anchors.centerIn: parent
                                spacing: 2
                                MaterialSymbol {
                                    text: "check"
                                    iconSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnPrimary
                                }
                                StyledText {
                                    text: Translation.tr("Active")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }

                    // Title & Settings Button
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        spacing: 6

                        StyledText {
                            Layout.fillWidth: true
                            text: cardItem.widgetData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                        }

                        RippleButton {
                            visible: cardItem.widgetData.configPage !== undefined && cardItem.widgetData.configPage !== ""
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            colRipple: Appearance.colors.colSecondaryContainerActive
                            onClicked: {
                                widgetsConfigRoot.activeSubPage = Qt.resolvedUrl(cardItem.widgetData.configPage);
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "settings"
                                iconSize: Appearance.font.pixelSize.smallie
                                color: Appearance.colors.colOnSecondaryContainer
                            }

                            StyledToolTip {
                                text: Translation.tr("Configure widget")
                            }
                        }
                    }

                    // Primary Add/Remove Action Button
                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        colBackground: cardItem.isActive ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
                        colBackgroundHover: cardItem.isActive ? Appearance.colors.colErrorContainerHover : Appearance.colors.colPrimaryContainerHover
                        colRipple: cardItem.isActive ? Appearance.colors.colErrorContainerActive : Appearance.colors.colPrimaryContainerActive
                        onClicked: {
                            if (cardItem.isActive) {
                                Config.removeWidgetFromDesktop(cardItem.widgetData.widgetId);
                            } else {
                                Config.addWidgetToDesktop(cardItem.widgetData.widgetId);
                            }
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: cardItem.isActive ? "delete" : "add"
                                iconSize: Appearance.font.pixelSize.normal
                                color: cardItem.isActive ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                            }
                            StyledText {
                                text: cardItem.isActive ? Translation.tr("Remove from desktop") : Translation.tr("Add to desktop")
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                font.weight: Font.DemiBold
                                color: cardItem.isActive ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }

                    // Lock Behavior Segmented Controls (Visible when active)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 4
                        visible: cardItem.isActive

                        Repeater {
                            model: [
                                {
                                    value: "hide",
                                    icon: "visibility_off",
                                    tooltip: Translation.tr("Hidden on lock")
                                },
                                {
                                    value: "keep",
                                    icon: "visibility",
                                    tooltip: Translation.tr("Show on lock")
                                },
                                {
                                    value: "center",
                                    icon: "center_focus_strong",
                                    tooltip: Translation.tr("Center on lock")
                                },
                                {
                                    value: "lockOnly",
                                    icon: "lock",
                                    tooltip: Translation.tr("Lock screen only")
                                }
                            ]

                            delegate: RippleButton {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 28
                                buttonRadius: Appearance.rounding.small
                                readonly property bool isCurrent: cardItem.currentLockBehavior === modelData.value

                                colBackground: isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                                colBackgroundHover: isCurrent ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
                                colRipple: isCurrent ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer1Active
                                onClicked: {
                                    Config.setWidgetLockBehavior(cardItem.widgetData.widgetId, modelData.value);
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    iconSize: Appearance.font.pixelSize.smallie
                                    color: isCurrent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                }

                                StyledToolTip {
                                    text: modelData.tooltip
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
