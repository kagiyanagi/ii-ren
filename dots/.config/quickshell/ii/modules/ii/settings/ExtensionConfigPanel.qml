import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// An extension's configSchema as the settings app's own rows. Every row gets
// its key and entry at creation, so nothing reads a half-wired binding: the
// Loader this replaced set them in onLoaded, and every row wrote its value
// back to plugins.json as they arrived.
//
// The rows sit in their own ContentGroup run, one tone above the extension's
// card: a ConfigTextField has no outline and is recognisable as a field only by
// its card, and the group hands every row's hover film the card's corners.
ContentGroup {
    id: root
    required property string extensionId
    required property var schema

    cardColor: Appearance.colors.colSurfaceContainerHighest
    // Concentric with the extension card, which is inset 8 from these.
    outerRadius: Appearance.rounding.normal

    function valueOf(key, entry, fallback) {
        return ExtensionManager.extensionConfigs?.[root.extensionId]?.[key] ?? entry?.default ?? fallback
    }
    // Writes only a real change, so a row settling on its stored value does not
    // rewrite the file.
    function write(key, entry, value) {
        if (root.valueOf(key, entry, undefined) === value) return
        ExtensionManager.setExtensionConfig(root.extensionId, key, value)
    }

    Repeater {
        model: Object.keys(root.schema ?? {})
            .map(key => ({ key: key, entry: root.schema[key], type: root.schema[key]?.type ?? "" }))
            .filter(item => ["bool", "int", "float", "slider", "enum", "string"].includes(item.type))

        delegate: DelegateChooser {
            role: "type"

            DelegateChoice {
                roleValue: "bool"
                ConfigSwitch {
                    id: toggle
                    required property var modelData
                    buttonIcon: modelData.entry.icon ?? ""
                    text: modelData.entry.label ?? modelData.key
                    checked: root.valueOf(modelData.key, modelData.entry, false)
                    onCheckedChanged: root.write(modelData.key, modelData.entry, checked)
                    // A click assigns `checked` and drops the binding; a reset
                    // has to put the stored value back by hand.
                    Connections {
                        target: ExtensionManager
                        function onExtensionConfigsChanged() {
                            toggle.checked = root.valueOf(toggle.modelData.key, toggle.modelData.entry, false)
                        }
                    }
                }
            }

            DelegateChoice {
                roleValue: "int"
                ConfigSpinBox {
                    id: spin
                    required property var modelData
                    icon: modelData.entry.icon ?? ""
                    text: modelData.entry.label ?? modelData.key
                    from: modelData.entry.min ?? 0
                    to: modelData.entry.max ?? 999999
                    stepSize: modelData.entry.stepSize ?? 1
                    // SpinBox clamps on assignment, and `to` defaults to 99: if
                    // this ran before `to` landed, 150 came back as 99. Reading
                    // the bounds re-runs it once they have.
                    value: { from; to; return root.valueOf(modelData.key, modelData.entry, 0) }
                    // Only after creation, for the same reason: a change while
                    // the bounds are still defaults is not the user's.
                    property bool ready: false
                    Component.onCompleted: ready = true
                    onValueChanged: if (ready) root.write(modelData.key, modelData.entry, value)
                    Connections {
                        target: ExtensionManager
                        function onExtensionConfigsChanged() {
                            spin.value = root.valueOf(spin.modelData.key, spin.modelData.entry, 0)
                        }
                    }
                }
            }

            DelegateChoice {
                roleValue: "float"
                SliderRow {}
            }
            DelegateChoice {
                roleValue: "slider"
                SliderRow {}
            }

            DelegateChoice {
                roleValue: "enum"
                ConfigSelectionRow {
                    required property var modelData
                    buttonIcon: modelData.entry.icon ?? ""
                    text: modelData.entry.label ?? modelData.key
                    options: modelData.entry.options ?? []
                    currentValue: root.valueOf(modelData.key, modelData.entry, "")
                    onSelected: newValue => root.write(modelData.key, modelData.entry, newValue)
                }
            }

            DelegateChoice {
                roleValue: "string"
                ConfigTextField {
                    id: field
                    required property var modelData
                    icon: modelData.entry.icon ?? ""
                    text: modelData.entry.label ?? modelData.key
                    inputText: root.valueOf(modelData.key, modelData.entry, "")
                    // On commit, not per keystroke: each write reloads the
                    // file, and the reload would reset the text under the caret.
                    onEditingFinished: root.write(modelData.key, modelData.entry, inputText)
                    Connections {
                        target: ExtensionManager
                        function onExtensionConfigsChanged() {
                            field.inputText = root.valueOf(field.modelData.key, field.modelData.entry, "")
                        }
                    }
                }
            }
        }
    }

    component SliderRow: ConfigSlider {
        id: slider
        required property var modelData
        buttonIcon: modelData.entry.icon ?? ""
        text: modelData.entry.label ?? modelData.key
        from: modelData.entry.from ?? modelData.entry.min ?? 0
        to: modelData.entry.to ?? modelData.entry.max ?? 100
        value: { from; to; return root.valueOf(modelData.key, modelData.entry, 0) }
        // valueChanged fires on every frame of the settle animation.
        onMoved: v => root.write(modelData.key, modelData.entry, v)
        Connections {
            target: ExtensionManager
            function onExtensionConfigsChanged() {
                slider.value = root.valueOf(slider.modelData.key, slider.modelData.entry, 0)
            }
        }
    }
}
