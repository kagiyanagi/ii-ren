import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("At a Glance widget options")

    ContentSection {
        title: Translation.tr("At a Glance widget settings")
        icon: "dashboard"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("at_a_glance")

            PagePlaceholder {
                anchors.fill: parent
                icon: "dashboard"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("At a Glance widget disabled")
                description: Translation.tr("Enable the At a Glance Widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 4
            visible: Config.isWidgetActive("at_a_glance")

            // ── Layout & Size ───────────────────────────────────────────────
            ContentSubsectionLabel {
                text: Translation.tr("Layout & size")
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget scale")
                value: Config.options.background.widgets.at_a_glance.widgetSize ?? 100
                from: 50; to: 200; stepSize: 10
                onValueChanged: Config.options.background.widgets.at_a_glance.widgetSize = value
            }

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.at_a_glance.widthCells ?? 3
                options: [
                    { displayName: Translation.tr("2x1 compact"), icon: "view_week", value: 2 },
                    { displayName: Translation.tr("3x1 full"), icon: "view_column", value: 3 }
                ]
                onSelected: value => Config.options.background.widgets.at_a_glance.widthCells = value
            }

            ConfigSwitch {
                buttonIcon: "view_stream"
                text: Translation.tr("Dual-column mode (display 2 targets)")
                checked: Config.options.background.widgets.at_a_glance.dualColumnMode ?? false
                onCheckedChanged: Config.options.background.widgets.at_a_glance.dualColumnMode = checked
            }

            // ── Context Sources ──────────────────────────────────────────────
            ContentSubsectionLabel {
                text: Translation.tr("Smart context sources")
            }

            ConfigSwitch {
                buttonIcon: "music_note"
                text: Translation.tr("Use media context")
                checked: Config.options.background.widgets.at_a_glance.enableMedia ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableMedia = checked
            }

            ConfigSwitch {
                buttonIcon: "event"
                text: Translation.tr("Use calendar context")
                checked: Config.options.background.widgets.at_a_glance.enableCalendar ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableCalendar = checked
            }

            ConfigSwitch {
                buttonIcon: "task_alt"
                text: Translation.tr("Use to-do context")
                checked: Config.options.background.widgets.at_a_glance.enableTodo ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableTodo = checked
            }

            ConfigSwitch {
                buttonIcon: "share"
                text: Translation.tr("Use LocalSend context")
                checked: Config.options.background.widgets.at_a_glance.enableLocalSend ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableLocalSend = checked
            }

            ConfigSwitch {
                buttonIcon: "smartphone"
                text: Translation.tr("Use KDE Connect context")
                checked: Config.options.background.widgets.at_a_glance.enableKdeConnect ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableKdeConnect = checked
            }

            ConfigSwitch {
                buttonIcon: "cloud"
                text: Translation.tr("Show weather info")
                checked: Config.options.background.widgets.at_a_glance.enableWeather ?? true
                onCheckedChanged: Config.options.background.widgets.at_a_glance.enableWeather = checked
            }

            // ── Context Windows ──────────────────────────────────────────────
            ContentSubsectionLabel {
                text: Translation.tr("Context Windows")
            }

            ConfigSpinBox {
                icon: "event_upcoming"
                text: Translation.tr("Calendar window (minutes)")
                value: Config.options.background.widgets.at_a_glance.calendarWindowMinutes ?? 60
                from: 0
                to: 720
                stepSize: 15
                onValueChanged: Config.options.background.widgets.at_a_glance.calendarWindowMinutes = value
            }
        }
    }
}
