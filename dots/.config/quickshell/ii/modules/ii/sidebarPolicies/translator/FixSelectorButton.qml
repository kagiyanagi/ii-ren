pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * What a same-language "translation" fixes. A multi-select, so the rows are
 * wrapped in an Item: ComboBox closes itself on a delegate that is a button.
 */
StyledComboBox {
    id: root

    readonly property var kinds: [
        { key: "grammar", text: Translation.tr("Grammar") },
        { key: "spelling", text: Translation.tr("Spelling") },
        { key: "punctuation", text: Translation.tr("Punctuation") },
        { key: "style", text: Translation.tr("Style") },
    ]
    readonly property var fixes: Config.options.sidebar.translator.fixes
    readonly property bool all: root.kinds.every(k => root.fixes.includes(k.key))

    function toggle(key: string): void {
        const next = key === "all" ? (root.all ? [] : root.kinds.map(k => k.key))
            : root.fixes.includes(key) ? root.fixes.filter(k => k !== key) : [...root.fixes, key];
        Config.options.sidebar.translator.fixes = next;
    }

    model: [{ key: "all", text: Translation.tr("Everything") }, ...root.kinds]
    textRole: "text"
    currentIndex: -1
    displayText: {
        const picked = root.kinds.filter(k => root.fixes.includes(k.key));
        if (root.all) return Translation.tr("Fix: Everything");
        if (picked.length === 0) return Translation.tr("Fix: Nothing");
        return Translation.tr("Fix: %1").arg(picked[0].text) + (picked.length > 1 ? ` +${picked.length - 1}` : "");
    }

    // Sits on a TextCanvas card, which is layer 2, beside the layer-3 language button.
    colBackground: Appearance.colors.colLayer3
    colBackgroundHover: Appearance.colors.colLayer3Hover
    colBackgroundActive: Appearance.colors.colLayer3Active
    buttonRadius: Appearance.rounding.small
    Layout.fillWidth: false
    // TextCanvas sizes it to the language button beside it.
    // StyledComboBox's own insets: 16 each side of the text, 8 before the indicator.
    implicitWidth: contentItem.implicitWidth + indicator.width + 40
    font.pixelSize: Appearance.font.pixelSize.small
    // ponytail: fixed floor so "Punctuation" fits; measure the rows if labels get longer.
    Component.onCompleted: popup.width = Qt.binding(() => Math.max(root.width, 180))

    delegate: Item {
        id: row
        required property var modelData
        readonly property bool checked: modelData.key === "all" ? root.all : root.fixes.includes(modelData.key)
        width: ListView.view ? ListView.view.width : root.width
        implicitHeight: 40

        RippleButton {
            anchors.fill: parent
            buttonRadius: Appearance.rounding.small
            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3)
            colBackgroundHover: Appearance.colors.colLayer3Hover
            colRipple: Appearance.colors.colLayer3Active
            onClicked: root.toggle(row.modelData.key)

            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8
                MaterialSymbol {
                    text: row.checked ? "check_box" : "check_box_outline_blank"
                    fill: row.checked ? 1 : 0
                    iconSize: Appearance.font.pixelSize.larger
                    color: row.checked ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
                }
                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData.text
                    color: Appearance.colors.colOnLayer3
                    elide: Text.ElideRight
                }
            }
        }
    }
}
