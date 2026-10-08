import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Water reminder widget options")

    ContentSection {
        title: Translation.tr("Water reminder widget settings")
        icon: "water_drop"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("water_reminder")

            PagePlaceholder {
                anchors.fill: parent
                icon: "water_drop"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Water reminder widget disabled")
                description: Translation.tr("Enable the Water Reminder Widget in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("water_reminder")

            ContentSubsectionLabel {
                text: Translation.tr("Reminders")
            }

            ConfigSwitch {
                buttonIcon: "notifications_active"
                text: Translation.tr("Enable water reminders")
                checked: Config.options.background.widgets.water_reminder.enable ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.water_reminder.enable = checked;
                }
            }

            ConfigSpinBox {
                enabled: Config.options.background.widgets.water_reminder.enable ?? false
                icon: "av_timer"
                text: Translation.tr("Reminder interval (hours)")
                value: Config.options.background.widgets.water_reminder.intervalHours ?? 2
                from: 1
                to: 12
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.water_reminder.intervalHours = value;
                }
                StyledToolTip {
                    text: Translation.tr("How often to send a hydration notification while the daily goal is not reached.")
                }
            }


            ConfigSpinBox {
                icon: "flag"
                text: Translation.tr("Glasses per day")
                value: Config.options.background.widgets.water_reminder.dailyGoal ?? 8
                from: 1
                to: 12
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.water_reminder.dailyGoal = value;
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Reminder message")
            }

            ConfigTextField {
                id: reminderTextField
                Layout.fillWidth: true
                text: Translation.tr("Water reminder")
                placeholderText: Translation.tr("e.g. Time to hydrate! 💧")

                inputText: Config.options.background.widgets.water_reminder.reminderText || ""
                onInputTextChanged: Config.options.background.widgets.water_reminder.reminderText = inputText
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reset today's count")
                onClicked: WaterReminderService.resetCounter()
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
