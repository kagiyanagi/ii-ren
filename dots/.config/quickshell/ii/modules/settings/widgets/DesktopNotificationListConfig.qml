import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var conf: Config.options.background.widgets.notification_list

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
            text: Translation.tr("Notification List Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Notification List")
        icon: "notifications"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("notification_list")

            PagePlaceholder {
                anchors.fill: parent
                icon: "notifications"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Notification list disabled")
                description: Translation.tr("Enable the Notification List in Desktop Widgets settings to use this page. Set its lock screen behaviour to Keep or Lock screen only to get it on the lock screen.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("notification_list")

            ContentSubsectionLabel {
                text: Translation.tr("View")
            }

            ConfigSelectionArray {
                currentValue: root.conf.view
                options: [
                    {
                        "displayName": Translation.tr("Full list"),
                        "value": "full"
                    },
                    {
                        "displayName": Translation.tr("Compact"),
                        "value": "compact"
                    }
                ]
                onSelected: newValue => {
                    root.conf.view = newValue;
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.topMargin: 4
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Compact is Android 16's default: one notification in full, the rest reduced to icons underneath. Click the icons to expand.")
            }

            ContentSubsectionLabel {
                text: Translation.tr("Size")
            }

            ConfigSlider {
                buttonIcon: "width"
                text: Translation.tr("Width")
                value: root.conf.width ?? 400
                from: 240
                to: 720
                stepSize: 20
                usePercentTooltip: false
                onValueChanged: {
                    root.conf.width = value;
                }
            }

            ConfigSlider {
                buttonIcon: "layers"
                text: Translation.tr("Cards before the icon row")
                value: root.conf.maxCards ?? 4
                from: 1
                to: 8
                stepSize: 1
                usePercentTooltip: false
                onValueChanged: {
                    root.conf.maxCards = value;
                }
            }

            ConfigSlider {
                buttonIcon: "format_size"
                text: Translation.tr("Text size")
                value: root.conf.fontScale ?? 100
                from: 80
                to: 140
                stepSize: 5
                onValueChanged: {
                    root.conf.fontScale = value;
                }
            }

            ConfigSlider {
                buttonIcon: "opacity"
                text: Translation.tr("Card opacity")
                value: root.conf.backgroundOpacity ?? 100
                from: 20
                to: 100
                stepSize: 5
                onValueChanged: {
                    root.conf.backgroundOpacity = value;
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Lock screen")
            }

            ConfigSelectionArray {
                currentValue: root.conf.privacy
                options: [
                    {
                        "displayName": Translation.tr("Show content"),
                        "value": "show"
                    },
                    {
                        "displayName": Translation.tr("Hide content"),
                        "value": "hideContent"
                    },
                    {
                        "displayName": Translation.tr("Hide all"),
                        "value": "hideAll"
                    }
                ]
                onSelected: newValue => {
                    root.conf.privacy = newValue;
                }
            }

            ConfigSwitch {
                buttonIcon: "history"
                text: Translation.tr("Only notifications since locking")
                checked: root.conf.onlySinceLock ?? false
                onCheckedChanged: {
                    root.conf.onlySinceLock = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "visibility_off"
                text: Translation.tr("Hide when there is nothing to show")
                checked: root.conf.hideWhenEmpty ?? true
                onCheckedChanged: {
                    root.conf.hideWhenEmpty = checked;
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Hiding an empty stack applies on the lock screen only - on the desktop a placeholder stays, or there would be nothing left to grab and move.")
            }

            ContentSubsectionLabel {
                text: Translation.tr("Interaction")
            }

            ConfigSwitch {
                buttonIcon: "swipe"
                text: Translation.tr("Swipe sideways to dismiss")
                checked: root.conf.dismissOnSwipe ?? true
                onCheckedChanged: {
                    root.conf.dismissOnSwipe = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "touch_app"
                text: Translation.tr("Show action buttons when expanded")
                checked: root.conf.showActions ?? true
                onCheckedChanged: {
                    root.conf.showActions = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "more_horiz"
                text: Translation.tr("Icon row for the overflow")
                checked: root.conf.showShelf ?? true
                onCheckedChanged: {
                    root.conf.showShelf = checked;
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Clicking a card")
            }

            ConfigSelectionArray {
                currentValue: root.conf.bodyAction
                options: [
                    {
                        "displayName": Translation.tr("Expand"),
                        "value": "expand"
                    },
                    {
                        "displayName": Translation.tr("Run first action"),
                        "value": "invoke"
                    }
                ]
                onSelected: newValue => {
                    root.conf.bodyAction = newValue;
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("What gets listed")
            }

            ConfigSwitch {
                buttonIcon: "notifications_paused"
                text: Translation.tr("Include low urgency notifications")
                checked: root.conf.showLowUrgency ?? true
                onCheckedChanged: {
                    root.conf.showLowUrgency = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("Skip transient notifications")
                checked: root.conf.skipTransient ?? true
                onCheckedChanged: {
                    root.conf.skipTransient = checked;
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Drag the list sideways to dismiss, up or down to move the widget. Click a card or its chevron to expand it, middle-click to dismiss it. On the lock screen this works whether or not widget positions are frozen.")
            }
        }
    }
}
