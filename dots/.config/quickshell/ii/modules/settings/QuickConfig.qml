import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: page
    readonly property int index: 0
    property bool register: parent.register ?? false
    forceWidth: true

    property bool allowHeavyLoad: false
    property ListModel favouritesCarouselModel: ListModel {}

    function refreshFavouritesCarousel() {
        favouritesCarouselModel.clear()

        let favs = [...Persistent.states.wallpaper.favourites]
        const currentWallpaper = Config.options.background.wallpaperPath
        const currentIndex = favs.indexOf(currentWallpaper)

        if (favs.length === 0) return
        if (currentIndex !== -1) {
            const elementsBefore = favs.slice(0, currentIndex)
            const elementsFromCurrent = favs.slice(currentIndex)
            favs = elementsFromCurrent.concat(elementsBefore)
        } else if (currentWallpaper !== "") {
            favs.unshift(currentWallpaper)
        }

        for (let i = 0; i < favs.length; i++) {
            const path = favs[i]
            const fileName = path.split('/').pop()

            const name = (path === currentWallpaper && currentIndex === -1) ? "current-wallpaper" : fileName
            favouritesCarouselModel.append({ filePath: path, fileName: name })
        }
    }

    Component.onCompleted: Qt.callLater(() => {
        page.allowHeavyLoad = true
        page.refreshFavouritesCarousel()
    })

    Connections {
        target: Persistent.states.wallpaper
        function onFavouritesChanged() {
            page.refreshFavouritesCarousel()
        }
    }

    component SmallLightDarkPreferenceButton: RippleButton {
        id: smallLightDarkPreferenceButton
        required property bool dark
        property color colText: enabled ? toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2 : Appearance.colors.colOnLayer3
        padding: 4
        Layout.fillWidth: true
        toggled: Appearance.m3colors.darkmode === dark
        colBackground: Appearance.colors.colLayer2
        onClicked: {
            Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${dark ? "dark" : "light"} --noswitch`]);
        }
        StyledToolTip {
            extraVisibleCondition: !smallLightDarkPreferenceButton.enabled
            text: Translation.tr("Custom color scheme has been selected")
        }
        contentItem: Item {
            anchors.centerIn: parent
            RowLayout {
                anchors.centerIn: parent
                spacing: 10
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 30
                    text: dark ? "dark_mode" : "light_mode"
                    fill: toggled ? 1 : 0
                    color: smallLightDarkPreferenceButton.colText
                }
                StyledText {
                    visible: !carouselWrapper.expanded
                    Layout.alignment: Qt.AlignHCenter
                    text: dark ? Translation.tr("Dark") : Translation.tr("Light")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: smallLightDarkPreferenceButton.colText
                }
            }
        }
    }

    // Wallpaper selection
    ContentSection {
        icon: "format_paint"
        title: Translation.tr("Wallpaper & Colors")
        tooltip: Translation.tr("Favourite your wallpapers from wallpaper selector for them to be visible in the carousel")
        Layout.fillWidth: true

        RowLayout {
            Layout.fillWidth: true

            Item {
                id: carouselWrapper
                // Widens while a card is held, so the pressed wallpaper has room.
                // A size, so the spatial spec; it was two hand-timed 450ms
                // OutCubic animations started from the carousel's handlers.
                property bool widened: false
                implicitWidth: widened ? 450 : 360
                implicitHeight: 220

                readonly property bool expanded: implicitWidth > 400

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                Carousel {
                    id: favouritesCarousel
                    implicitWidth: parent.implicitWidth
                    implicitHeight: parent.implicitHeight

                    showBadges: true
                    showOpenningAnimation: true

                    leftPadding: 0
                    rightPadding: 0
                    topPadding: 0
                    bottomPadding: 0

                    model: page.favouritesCarouselModel
                    visible: page.favouritesCarouselModel.count > 0
                    onItemClicked: (index, modelData) => {
                        carouselWrapper.widened = false
                        favouritesCarousel.currentIndex = 0
                        favouritesCarousel.snapToIndex(0)
                        Wallpapers.select(modelData.filePath)
                    }

                    onPressedAny: () => {
                        carouselWrapper.widened = true
                    }

                    delegate: Item {
                        id: carouselItem
                        required property var modelData
                        required property int index

                        ThumbnailImage {
                            anchors.fill: parent
                            sourcePath: carouselItem.modelData.filePath
                            fillMode: Image.PreserveAspectCrop
                            generateThumbnail: true

                            // fix for resolution. Was `(512,512)`, the JS comma
                            // operator: that is 512, which QSize refuses.
                            thumbnailSizeName: Images.thumbnailSizeNameForDimensions(512, 512)
                            sourceSize: Qt.size(512, 512)
                        }
                    }
                }

                Timer {
                    // The model fills a moment after the page opens, so the placeholder
                    // waits rather than flashing over a carousel about to appear.
                    interval: 200
                    running: true
                    onTriggered: emptyFavourites.canBeVisible = true
                }

                // The wallpaper selector's own empty favourites, so the same empty
                // list reads the same in both places.
                PagePlaceholder {
                    id: emptyFavourites
                    property bool canBeVisible: false
                    shown: page.favouritesCarouselModel.count === 0 && canBeVisible
                    icon: "favorite"
                    title: Translation.tr("No favourites yet")
                    description: Translation.tr("Right-click one in the wallpaper selector and tap the heart")
                    descriptionHorizontalAlignment: Text.AlignHCenter
                }
            }

            ColumnLayout {
                Layout.fillHeight: true
                Layout.fillWidth: true

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    uniformCellSizes: true

                    SmallLightDarkPreferenceButton {
                        Layout.preferredHeight: 60
                        dark: false
                        enabled: Config.options.appearance.palette.type.startsWith("scheme")
                    }
                    SmallLightDarkPreferenceButton {
                        Layout.preferredHeight: 60
                        dark: true
                        enabled: Config.options.appearance.palette.type.startsWith("scheme")
                    }
                }

                Item {
                    id: colorGridItem
                    z: 1
                    Layout.fillHeight: true
                    Layout.fillWidth: true

                    StyledFlickable {
                        id: flickable
                        anchors.fill: parent
                        contentHeight: contentLayout.implicitHeight
                        contentWidth: width
                        clip: true

                        ColumnLayout {
                            id: contentLayout
                            width: flickable.width

                            Repeater {
                                model: [
                                    { customTheme: false, builtInTheme: false },
                                    { customTheme: false, builtInTheme: true },
                                    { customTheme: true, builtInTheme: false }
                                ]

                                delegate: ColorPreviewGrid {
                                    columns: carouselWrapper.expanded ? 2 : 3
                                    customTheme: modelData.customTheme
                                    builtInTheme: modelData.builtInTheme
                                }
                            }
                        }
                    }
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "ev_shadow"
            text: Translation.tr("Transparency")
            checked: Config.options.appearance.transparency.enable
            onCheckedChanged: {
                Config.options.appearance.transparency.enable = checked;
            }
        }
    }

    // One section, named after the sidebar dialog that holds the same three
    // effects. They were three sections pulled together with -25 margins.
    ContentSection {
        icon: "visibility"
        title: Translation.tr("Eye protection")

        ContentSubsection {
            title: Translation.tr("Night light")
            tooltip: Translation.tr("Times are 24-hour, HH:mm")

            ConfigSwitch {
                buttonIcon: "nightlight"
                text: Translation.tr("Automatic night light")
                checked: Config.options.light.night.automatic
                onCheckedChanged: {
                    Config.options.light.night.automatic = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "night_sight_auto"
                text: Translation.tr("Automatic dark mode")
                checked: Config.options.light.night.automaticDarkMode
                onCheckedChanged: {
                    Config.options.light.night.automaticDarkMode = checked;
                }
            }
            ConfigRow {
                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("From (HH:mm)")
                    text: Config.options.light.night.from
                    onEditingFinished: {
                        if (/^([01]?\d|2[0-3]):[0-5]\d$/.test(text.trim()))
                            Config.options.light.night.from = text.trim();
                    }
                }
                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Until (HH:mm)")
                    text: Config.options.light.night.to
                    onEditingFinished: {
                        if (/^([01]?\d|2[0-3]):[0-5]\d$/.test(text.trim()))
                            Config.options.light.night.to = text.trim();
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Comfort View")
            tooltip: Translation.tr("Soften screen colors, reduce OLED saturation and glare")

            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Enable Comfort View")
                checked: HyprlandComfortView.manualEnable
                onCheckedChanged: {
                    if (checked !== HyprlandComfortView.manualEnable)
                        HyprlandComfortView.toggleManual(checked);
                }
            }
            ConfigSwitch {
                buttonIcon: "auto_mode"
                text: Translation.tr("Dynamic automatic mode")
                checked: HyprlandComfortView.automatic
                onCheckedChanged: {
                    if (checked !== HyprlandComfortView.automatic)
                        HyprlandComfortView.toggleAutomatic(checked);
                }
            }
            ConfigSpinBox {
                icon: "tune"
                text: Translation.tr("Effect intensity (%)")
                value: HyprlandComfortView.intensity
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    if (value !== HyprlandComfortView.intensity)
                        HyprlandComfortView.setIntensity(value);
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Reading Mode")
            tooltip: Translation.tr("Grayscale monochrome display mode for long-term reading comfort")

            ConfigSwitch {
                buttonIcon: "menu_book"
                text: Translation.tr("Enable Reading Mode")
                checked: HyprlandReadingMode.manualEnable
                onCheckedChanged: {
                    if (checked !== HyprlandReadingMode.manualEnable)
                        HyprlandReadingMode.toggleManual(checked);
                }
            }
            ConfigSwitch {
                buttonIcon: "auto_mode"
                text: Translation.tr("Dynamic automatic mode")
                checked: HyprlandReadingMode.automatic
                onCheckedChanged: {
                    if (checked !== HyprlandReadingMode.automatic)
                        HyprlandReadingMode.toggleAutomatic(checked);
                }
            }
            ConfigSwitch {
                buttonIcon: "history_edu"
                text: Translation.tr("Paper warmth tone")
                checked: HyprlandReadingMode.paperTone
                onCheckedChanged: {
                    if (checked !== HyprlandReadingMode.paperTone)
                        HyprlandReadingMode.togglePaperTone(checked);
                }
            }
            ConfigSpinBox {
                icon: "tune"
                text: Translation.tr("Grayscale intensity (%)")
                value: HyprlandReadingMode.intensity
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    if (value !== HyprlandReadingMode.intensity)
                        HyprlandReadingMode.setIntensity(value);
                }
            }
        }
    }

    ContentSection {
        icon: "screenshot_monitor"
        title: Translation.tr("Bar & screen")

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Bar position")
                Layout.fillWidth: true
                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = (newValue & 2) !== 0;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Top"),
                            icon: "arrow_upward",
                            value: 0 // bottom: false, vertical: false
                        },
                        {
                            displayName: Translation.tr("Left"),
                            icon: "arrow_back",
                            value: 2 // bottom: false, vertical: true
                        },
                        {
                            displayName: Translation.tr("Bottom"),
                            icon: "arrow_downward",
                            value: 1 // bottom: true, vertical: false
                        },
                        {
                            displayName: Translation.tr("Right"),
                            icon: "arrow_forward",
                            value: 3 // bottom: true, vertical: true
                        }
                    ]
                }
            }
            ContentSubsection {
                title: Translation.tr("Bar style")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => {
                        Config.options.bar.cornerStyle = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Hug"),
                            icon: "line_curve",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Float"),
                            icon: "page_header",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "toolbar",
                            value: 2
                        }
                    ]
                }
            }
        }

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Screen round corner")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.appearance.fakeScreenRounding
                    onSelected: newValue => {
                        Config.options.appearance.fakeScreenRounding = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Not fullscreen"),
                            icon: "fullscreen_exit",
                            value: 2
                        },
                        {
                            displayName: Translation.tr("Wrapped"),
                            icon: "capture",
                            value: 3
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Rounding style")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.appearance.sharpMode
                    onSelected: newValue => {
                        Config.options.appearance.sharpMode = newValue;
                        HyprlandSettings.setRounding(newValue ? 0 : Config.options.appearance.defaultBorderRadius);
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "rounded_corner",
                            value: false
                        },
                        {
                            displayName: Translation.tr("Sharp"),
                            icon: "square",
                            value: true
                        }
                    ]
                }
            }
        }

        ConfigSpinBox {
            visible: Config.options.appearance.fakeScreenRounding === 3
            icon: "line_weight"
            text: Translation.tr("Wrapped frame thickness")
            value: Config.options.appearance.wrappedFrameThickness
            from: 5
            to: 25
            stepSize: 1
            onValueChanged: {
                Config.options.appearance.wrappedFrameThickness = value;
            }
        }

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Bar background style")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.bar.barBackgroundStyle
                    onSelected: newValue => {
                        Config.options.bar.barBackgroundStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Visible"),
                            icon: "visibility",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Adaptive"),
                            icon: "masked_transitions",
                            value: 2
                        },
                        {
                            displayName: Translation.tr("Transparent"),
                            icon: "opacity",
                            value: 0
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Hyprland layout")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: {
                        if (Persistent.states.hyprland.layout !== "scrolling") return "default"
                        else return "scrolling"
                    }
                    onSelected: newValue => {
                        if (newValue === "scrolling") {
                            HyprlandSettings.setLayout("scrolling")
                        } else {
                            const defaultLayout = Config.options.hyprland.defaultHyprlandLayout
                            HyprlandSettings.setLayout(defaultLayout)
                        }
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "mobile_layout",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Scrolling"),
                            icon: "view_carousel",
                            value: "scrolling"
                        }
                    ]
                }
            }
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        text: Translation.tr('Not all options are available in this app. You should also check the config file by hitting the "Config file" button on the topleft corner or opening ~/.config/illogical-impulse/config.json manually.')

        RippleButtonWithIcon {
            id: copyPathButton
            property bool justCopied: false
            buttonRadius: Appearance.rounding.small
            materialIcon: justCopied ? "check" : "content_copy"
            mainText: justCopied ? Translation.tr("Path copied") : Translation.tr("Copy path")
            onClicked: {
                copyPathButton.justCopied = true
                Quickshell.clipboardText = FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                revertTextTimer.restart();
            }
            colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive

            Timer {
                id: revertTextTimer
                interval: 1500
                onTriggered: {
                    copyPathButton.justCopied = false
                }
            }
        }
    }
}
