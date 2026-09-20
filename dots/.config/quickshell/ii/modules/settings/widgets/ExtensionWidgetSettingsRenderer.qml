pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets
import qs.services

// ExtensionWidgetSettingsRenderer — renders a third-party configSchema with the
// same rows a first-party page is built from, so an extension's options are
// indistinguishable from the shell's own. The root is a ContentGroup, which is
// what ContentSection puts its own rows in: it draws the card run behind them
// and hands each row the corners and the bleed the card actually has. The rows
// therefore carry no radii, no first/last plumbing and no background of their
// own — the three that did were setting `isFirst`/`isLast`/`textField`, none of
// which exist on these widgets any more, and a missing property is fatal at
// load, so this whole page rendered nothing.
// Reads/writes via WidgetExtensionManager.
ContentGroup {
    id: root

    property string extId: ""
    property var schema: ({})

    readonly property var schemaKeys: Object.keys(root.schema || {})

    Repeater {
        model: root.schemaKeys.map(function (k) {
            return Object.assign({
                _key: k
            }, root.schema[k]);
        })

        delegate: Item {
            id: controlItem
            Layout.fillWidth: true

            required property var modelData
            required property int index

            readonly property string cfgKey: modelData._key || ""
            readonly property string cfgType: modelData.type || "string"
            readonly property string cfgLabel: modelData.label || modelData._key || ""

            // An enum is a labelled chip group and brings its own card with it;
            // the other four are plain rows and take the group's.
            readonly property bool wantsCard: controlItem.cfgType !== "enum"

            implicitHeight: {
                if (controlItem.cfgType === "bool")
                    return boolControl.implicitHeight;
                if (controlItem.cfgType === "int")
                    return intControl.implicitHeight;
                if (controlItem.cfgType === "slider" || controlItem.cfgType === "float")
                    return sliderControl.implicitHeight;
                if (controlItem.cfgType === "enum")
                    return enumControl.implicitHeight;
                return stringControl.implicitHeight;
            }

            property var cfgValue: WidgetExtensionManager.getWidgetConfig(root.extId, controlItem.cfgKey, modelData.default ?? null)

            function save(v) {
                WidgetExtensionManager.setWidgetConfig(root.extId, controlItem.cfgKey, v);
            }

            // 1. bool
            ConfigSwitch {
                id: boolControl
                anchors.fill: parent
                visible: controlItem.cfgType === "bool"
                text: controlItem.cfgLabel
                checked: controlItem.cfgValue ?? (controlItem.modelData.default ?? false)
                onCheckedChanged: controlItem.save(checked)
            }

            // 2. int — EXTENSIONS.md documents a spin box for this type, and a
            // stepped integer in a named range is what one is for.
            ConfigSpinBox {
                id: intControl
                anchors.fill: parent
                visible: controlItem.cfgType === "int"
                text: controlItem.cfgLabel
                // Every control in this delegate is built, not just the visible
                // one, so an unguarded value binding reads the *string* key's
                // value into an int and Qt says so at runtime and nowhere else.
                value: controlItem.cfgType === "int" ? (controlItem.cfgValue ?? (controlItem.modelData.default ?? 0)) : 0
                from: controlItem.modelData.min ?? 0
                to: controlItem.modelData.max ?? 100
                stepSize: 1
                onValueChanged: controlItem.save(value)
            }

            // 3. slider / float
            ConfigSlider {
                id: sliderControl
                anchors.fill: parent
                visible: controlItem.cfgType === "slider" || controlItem.cfgType === "float"
                text: controlItem.cfgLabel
                value: sliderControl.visible ? (controlItem.cfgValue ?? (controlItem.modelData.default ?? 0)) : 0
                from: controlItem.modelData.min ?? 0
                to: controlItem.modelData.max ?? 100
                stepSize: controlItem.cfgType === "float" ? 0.1 : 0.0
                usePercentTooltip: false
                // The drag, not every write: onValueChanged also fires for the
                // binding above, so saving there wrote the value back at itself.
                onMoved: v => controlItem.save(v)
            }

            // 4. enum — label above, chips below, the same shape QuickConfig and
            // ServicesConfig give every first-party selection.
            ContentSubsection {
                id: enumControl
                anchors.fill: parent
                visible: controlItem.cfgType === "enum"
                title: controlItem.cfgLabel

                ConfigSelectionArray {
                    currentValue: controlItem.cfgValue ?? (controlItem.modelData.default ?? "")
                    onSelected: v => controlItem.save(v)
                    options: {
                        const vals = controlItem.modelData.values || [];
                        return vals.map(function (v) {
                            return {
                                displayName: v,
                                value: v
                            };
                        });
                    }
                }
            }

            // 5. string
            ConfigTextField {
                id: stringControl
                anchors.fill: parent
                visible: controlItem.cfgType === "string"
                text: controlItem.cfgLabel
                inputText: controlItem.cfgValue ?? (controlItem.modelData.default ?? "")
                placeholderText: controlItem.modelData.placeholder || ""
                onInputTextChanged: controlItem.save(inputText)
            }
        }
    }
}
