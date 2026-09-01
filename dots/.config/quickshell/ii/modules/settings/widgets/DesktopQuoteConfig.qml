import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Quote Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Quote Widget Settings")
        icon: "format_quote"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("quote")

            PagePlaceholder {
                anchors.fill: parent
                icon: "format_quote"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Quote Widget disabled")
                description: Translation.tr("Enable the Quote Widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("quote")

            ContentSubsectionLabel {
                text: Translation.tr("Quote Source")
            }

            ConfigSwitch {
                buttonIcon: "cloud_download"
                text: Translation.tr("Fetch random quotes from internet")
                checked: Config.options.background.widgets.quote.fetchRandom ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.quote.fetchRandom = checked;
                    if (checked && (!QuoteService.currentQuote || QuoteService.currentQuote.length === 0)) {
                        QuoteService.fetchRandomQuote();
                    }
                }
            }

            ConfigSwitch {
                visible: Config.options.background.widgets.quote.fetchRandom ?? false
                buttonIcon: "animation"
                text: Translation.tr("Anime quotes only")
                checked: Config.options.background.widgets.quote.animeOnly ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.quote.animeOnly = checked;
                }
            }

            // Online quote management card
            Rectangle {
                Layout.fillWidth: true
                visible: Config.options.background.widgets.quote.fetchRandom ?? false
                color: Appearance.colors.colLayer1
                radius: Appearance.rounding.normal
                implicitHeight: onlineContentCol.implicitHeight + 24

                ColumnLayout {
                    id: onlineContentCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (QuoteService.loading)
                                return Translation.tr("Fetching new quote from internet…");
                            if (QuoteService.currentQuote && QuoteService.currentQuote.length > 0)
                                return `"${QuoteService.currentQuote}"`;
                            if (QuoteService.lastError && QuoteService.lastError.length > 0)
                                return QuoteService.lastError;
                            return Translation.tr("No quote fetched yet");
                        }
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.italic: true
                        color: Appearance.colors.colOnLayer1
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: QuoteService.currentAuthor.length > 0
                        text: "— " + QuoteService.currentAuthor
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }

                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.normal
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive

                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialSymbol {
                                text: "refresh"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnSecondaryContainer
                                RotationAnimation on rotation {
                                    running: QuoteService.loading
                                    from: 0
                                    to: 360
                                    loops: Animation.Infinite
                                    duration: Appearance.animation.elementMoveDuration * 4
                                }
                            }

                            StyledText {
                                text: QuoteService.loading ? Translation.tr("Fetching…") : Translation.tr("Fetch new quote")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        onClicked: QuoteService.fetchRandomQuote()
                    }
                }
            }

            ConfigSlider {
                visible: Config.options.background.widgets.quote.fetchRandom ?? false
                buttonIcon: "schedule"
                text: Translation.tr("Auto-Refresh Interval")
                from: 1
                to: 24
                stepSize: 1
                value: Config.options.background.widgets.quote.updateIntervalHours || 4
                usePercentTooltip: false
                tooltipContent: `${Math.round(value)} hr${Math.round(value) > 1 ? "s" : ""}`
                onValueChanged: {
                    Config.options.background.widgets.quote.updateIntervalHours = Math.round(value);
                }
            }

            ContentSubsectionLabel {
                visible: !(Config.options.background.widgets.quote.fetchRandom ?? false)
                text: Translation.tr("Custom Quote")
            }

            ConfigTextField {
                id: quoteTextField
                visible: !(Config.options.background.widgets.quote.fetchRandom ?? false)
                Layout.fillWidth: true
                text: Translation.tr("Your quote")
                placeholderText: Translation.tr("Enter your favorite quote...")

                Component.onCompleted: {
                    quoteTextField.textField.text = Config.options.background.widgets.quote.quoteText || "";
                }

                Connections {
                    target: quoteTextField.textField
                    function onTextChanged() {
                        Config.options.background.widgets.quote.quoteText = quoteTextField.textField.text;
                    }
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Text Size")
            }

            ConfigSlider {
                buttonIcon: "format_size"
                text: Translation.tr("Quote Font Size")
                from: 10
                to: 32
                stepSize: 1
                value: Config.options.background.widgets.quote.fontSize || 16
                usePercentTooltip: false
                tooltipContent: `${Math.round(value)}px`
                onValueChanged: {
                    Config.options.background.widgets.quote.fontSize = value;
                }
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
