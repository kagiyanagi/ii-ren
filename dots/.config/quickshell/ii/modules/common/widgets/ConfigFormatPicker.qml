import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Picks a Qt date/time format. Each preset chip is labelled with what it
 * renders, not with its tokens, and a Custom chip folds open a field for any
 * other format, its rendering shown as the field's suffix and the tokens as
 * its supporting text. The field only exists while the value is custom, so it
 * never repeats the selected chip.
 */
ConfigSelectionRow {
    id: root
    property list<string> formats
    property string value
    property string placeholderText
    property string hint
    signal picked(string format)

    // A fixed instant, not now: 31/12 cannot be read as 12/31, 13:05 cannot be
    // read as either clock, and the chips keep their width as the clock ticks.
    readonly property date sample: new Date(new Date().getFullYear(), 11, 31, 13, 5, 9)
    property bool editing: false
    readonly property bool custom: editing || !formats.includes(value)

    function render(format: string): string {
        return Qt.locale().toString(root.sample, format);
    }

    // -1 marks the Custom chip; no format string equals it.
    currentValue: root.custom ? -1 : root.value
    options: [
        ...root.formats.map(format => ({
                    displayName: root.render(format),
                    value: format
                })),
        {
            displayName: Translation.tr("Custom"),
            icon: "edit",
            value: -1
        }
    ]
    onSelected: newValue => {
        root.editing = newValue === -1;
        if (root.editing) {
            field.forceActiveFocus();
            return;
        }
        // A field still holding focus would commit its text over this
        // pick whenever it finally lost it; settle it first.
        field.focus = false;
        root.picked(newValue);
    }

    Revealer {
        Layout.fillWidth: true
        vertical: true
        reveal: root.custom

        ColumnLayout {
            width: parent.width
            spacing: 4

            MaterialTextField {
                id: field
                Layout.fillWidth: true
                rightPadding: suffix.implicitWidth + 32
                placeholderText: root.placeholderText
                text: root.value
                onEditingFinished: {
                    root.editing = false;
                    // Leaving the field untouched is not a change (TASTE 3.2).
                    if (text.trim() !== root.value)
                        root.picked(text.trim());
                    text = Qt.binding(() => root.value);
                }

                StyledText {
                    id: suffix
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: field.text.trim().length > 0 ? root.render(field.text.trim()) : ""
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                visible: root.hint.length > 0
                wrapMode: Text.Wrap
                text: root.hint
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}
