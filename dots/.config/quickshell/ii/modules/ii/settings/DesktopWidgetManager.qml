pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/**
 * Adds, removes and sets lock behaviour for the desktop widgets in
 * WidgetsRegistry. One instance per widget, which is what
 * Config.addWidgetToDesktop enforces, so each entry is a toggle.
 *
 * Position is set by dragging the widget on the desktop, not here.
 */
ColumnLayout {
    id: root

    spacing: 8
    Layout.fillWidth: true

    readonly property var placed: Config.options.background.activeWidgets ?? []
    readonly property var allWidgets: WidgetsRegistry.allWidgets ?? []

    readonly property var categoryIcons: ({
        "Clock": "schedule",
        "Date": "calendar_month",
        "Devices": "devices",
        "Media": "music_note",
        "Photo": "photo",
        "Resources": "memory",
        "System": "settings",
        "Utility": "build",
        "Weather": "partly_cloudy_day"
    })

    readonly property var categories: {
        let seen = [];
        for (let i = 0; i < root.allWidgets.length; i++) {
            const category = root.allWidgets[i].category;
            if (seen.indexOf(category) === -1)
                seen.push(category);
        }
        return seen;
    }

    property string selectedCategory: ""
    onCategoriesChanged: {
        if (root.categories.indexOf(root.selectedCategory) === -1)
            root.selectedCategory = root.categories[0] ?? "";
    }
    Component.onCompleted: root.selectedCategory = root.categories[0] ?? ""

    ContentSubsection {
        title: Translation.tr("On the desktop")
        visible: root.placed.length > 0
        Layout.fillWidth: true

        Repeater {
            model: root.placed

            delegate: ColumnLayout {
                id: placedRow

                required property var modelData
                readonly property var meta: WidgetsRegistry.getWidgetMetadata(placedRow.modelData.widgetId)

                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: placedRow.meta?.icon ?? "widgets"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: placedRow.meta?.name ?? placedRow.modelData.widgetId
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    RippleButtonWithShape {
                        extraIcon: "delete"
                        onClicked: Config.removeWidgetFromDesktop(placedRow.modelData.widgetId)
                        StyledToolTip { text: Translation.tr("Remove from desktop") }
                    }
                }

                ConfigRow {
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        Layout.fillWidth: false
                        currentValue: placedRow.modelData.placementStrategy ?? "free"
                        onSelected: newValue => Config.updateWidgetPlacementStrategy(placedRow.modelData.id, newValue)
                        options: [
                            {
                                displayName: Translation.tr("Draggable"),
                                icon: "drag_pan",
                                value: "free"
                            },
                            {
                                displayName: Translation.tr("Least busy"),
                                icon: "category",
                                value: "leastBusy"
                            },
                            {
                                displayName: Translation.tr("Most busy"),
                                icon: "shapes",
                                value: "mostBusy"
                            }
                        ]
                    }

                    Item { Layout.fillWidth: true }

                    ConfigSelectionArray {
                        Layout.fillWidth: false
                        currentValue: placedRow.modelData.lockBehavior ?? "hide"
                        onSelected: newValue => Config.updateWidgetLockBehavior(placedRow.modelData.id, newValue)
                        options: [
                            {
                                displayName: Translation.tr("Hide on lock"),
                                icon: "visibility_off",
                                value: "hide"
                            },
                            {
                                displayName: Translation.tr("Keep"),
                                icon: "visibility",
                                value: "keep"
                            },
                            {
                                displayName: Translation.tr("Center"),
                                icon: "filter_center_focus",
                                value: "center"
                            }
                        ]
                    }
                }
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Add a widget")
        tooltip: Translation.tr("Drag a widget on the desktop to move it. Widget-specific settings are not exposed here yet.")
        Layout.fillWidth: true

        ConfigSelectionArray {
            currentValue: root.selectedCategory
            onSelected: newValue => root.selectedCategory = newValue
            options: root.categories.map(category => ({
                displayName: category,
                icon: root.categoryIcons[category] ?? "widgets",
                value: category
            }))
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.allWidgets.filter(widget => widget.category === root.selectedCategory)

                delegate: RippleButtonWithShape {
                    id: widgetButton

                    required property var modelData
                    readonly property bool active: Config.isWidgetActive(widgetButton.modelData.widgetId)

                    mainText: widgetButton.modelData.name
                    extraIcon: widgetButton.active ? "check" : "add"
                    toggled: widgetButton.active
                    onClicked: {
                        if (widgetButton.active)
                            Config.removeWidgetFromDesktop(widgetButton.modelData.widgetId);
                        else
                            Config.addWidgetToDesktop(widgetButton.modelData.widgetId);
                    }
                    StyledToolTip { text: widgetButton.modelData.description ?? "" }
                }
            }
        }
    }
}
