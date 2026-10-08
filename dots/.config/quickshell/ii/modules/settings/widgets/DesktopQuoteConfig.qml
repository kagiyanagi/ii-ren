import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Quote widget options")

    ContentSection {
        title: Translation.tr("Quote widget settings")
        icon: "format_quote"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("quote")

            PagePlaceholder {
                anchors.fill: parent
                icon: "format_quote"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Quote widget disabled")
                description: Translation.tr("Enable the Quote Widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("quote")

            ContentSubsectionLabel {
                text: Translation.tr("Quote source")
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

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        // Disabled while fetching: the 0.4 state plus the label
                        // is the whole loading affordance, which is why the
                        // spinning icon this replaced is not missed.
                        enabled: !QuoteService.loading
                        materialIcon: "refresh"
                        mainText: QuoteService.loading ? Translation.tr("Fetching…") : Translation.tr("Fetch new quote")
                        onClicked: QuoteService.fetchRandomQuote()
                    }
                }
            }

            ConfigSlider {
                visible: Config.options.background.widgets.quote.fetchRandom ?? false
                buttonIcon: "schedule"
                text: Translation.tr("Auto-refresh interval")
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
                text: Translation.tr("Custom quote")
            }

            ConfigTextField {
                id: quoteTextField
                visible: !(Config.options.background.widgets.quote.fetchRandom ?? false)
                Layout.fillWidth: true
                text: Translation.tr("Your quote")
                placeholderText: Translation.tr("Your favorite quote")

                inputText: Config.options.background.widgets.quote.quoteText || ""
                onInputTextChanged: Config.options.background.widgets.quote.quoteText = inputText
            }

            ContentSubsectionLabel {
                text: Translation.tr("Text size")
            }

            ConfigSlider {
                buttonIcon: "format_size"
                text: Translation.tr("Quote font size")
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
