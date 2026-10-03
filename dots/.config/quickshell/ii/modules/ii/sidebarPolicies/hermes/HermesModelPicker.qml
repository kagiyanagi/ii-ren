pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * Model selection, opened from the composer's model chip: every model of every
 * provider in one searchable list, fed by the agent's own inventory
 * (`model.options`) rather than a hardcoded list -- so a provider the user
 * configures in Hermes shows up here without a shell change.
 *
 * Picking applies with `--session` (see HermesService.setModel): the sidebar
 * remembers the choice itself and re-applies it to each new session, so it never
 * rewrites the model the `hermes` CLI starts on.
 */
HermesPopover {
    id: root

    opensUp: true
    cardWidth: 320

    property string query: ""

    // concat, not flatMap: the list arrives as a QML sequence, which has no flatMap.
    readonly property var allModels: [].concat(...(HermesService.providers ?? []).map(provider => (provider.models ?? []).map(model => ({
        key: `${provider.slug}/${model}`,
        name: model,
        slug: provider.slug,
        providerName: provider.name ?? provider.slug,
        reasoning: provider.capabilities?.[model]?.reasoning ?? false
    }))))

    readonly property var rows: {
        const q = root.query.trim().toLowerCase();
        return q.length === 0 ? root.allModels : root.allModels.filter(row => `${row.name} ${row.providerName}`.toLowerCase().includes(q));
    }

    function pick(row: var): void {
        if (!row)
            return;
        HermesService.setModel(row.name, row.slug, false);
        root.close();
    }

    function openFrom(opener: Item): void {
        if (root.shown) {
            root.close();
            return;
        }
        root.open(opener);
        searchField.forceActiveFocus();
        // Opens on the model in use, not the top of a long list.
        listView.currentIndex = Math.max(0, root.rows.findIndex(row => row.name === HermesService.currentModel));
        listView.positionViewAtIndex(listView.currentIndex, ListView.Center);
    }

    onShownChanged: {
        if (!root.shown)
            searchField.text = "";
    }

    ToolbarTextField {
        id: searchField
        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: 40
        leftPadding: 40
        colBackground: Appearance.colors.colLayer2
        placeholderText: Translation.tr("Search models")
        onTextChanged: {
            root.query = text;
            listView.currentIndex = 0;
        }
        Keys.onDownPressed: listView.incrementCurrentIndex()
        Keys.onUpPressed: listView.decrementCurrentIndex()
        Keys.onReturnPressed: root.pick(root.rows[listView.currentIndex])
        Keys.onEnterPressed: root.pick(root.rows[listView.currentIndex])
        // Esc clears a filter before it closes the card.
        Keys.onEscapePressed: {
            if (text.length > 0)
                text = "";
            else
                root.close();
        }

        MaterialSymbol {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "search"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colSubtext
        }
    }

    StyledListView {
        id: listView
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 320)
        visible: root.rows.length > 0
        clip: true
        spacing: 2
        model: root.rows

        delegate: RippleButton {
            id: modelRow
            required property var modelData
            required property int index

            readonly property bool selected: modelRow.modelData.name === HermesService.currentModel && [modelRow.modelData.slug, modelRow.modelData.providerName].includes(HermesService.currentProvider)
            readonly property color onColor: modelRow.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

            width: listView.width
            implicitHeight: rowContent.implicitHeight + 8 * 2
            buttonRadius: Appearance.rounding.normal

            colBackground: modelRow.selected ? Appearance.colors.colSecondaryContainer : (modelRow.ListView.isCurrentItem && searchField.text.length > 0 ? ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.92) : "transparent")
            // Same films over the opaque card as HermesApprovalModeMenu's rows (3.1).
            colBackgroundHover: modelRow.selected ? Appearance.colors.colSecondaryContainerHover : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.92)
            colRipple: ColorUtils.transparentize(modelRow.onColor, 0.9)
            colStateLayer: modelRow.onColor

            releaseAction: () => root.pick(modelRow.modelData)

            contentItem: RowLayout {
                id: rowContent
                spacing: 12

                MaterialSymbol {
                    Layout.leftMargin: 12
                    Layout.alignment: Qt.AlignVCenter
                    text: modelRow.modelData.reasoning ? "neurology" : "auto_awesome"
                    iconSize: Appearance.font.pixelSize.normal
                    fill: modelRow.selected ? 1 : 0
                    color: modelRow.onColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: modelRow.onColor
                        text: modelRow.modelData.name
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: modelRow.modelData.providerName
                    }
                }

                MaterialSymbol {
                    Layout.rightMargin: 12
                    Layout.alignment: Qt.AlignVCenter
                    visible: modelRow.selected
                    text: "check"
                    iconSize: Appearance.font.pixelSize.normal
                    color: modelRow.onColor
                }
            }
        }
    }

    StyledText { // Empty: still loading, or the filter matched nothing
        Layout.fillWidth: true
        Layout.topMargin: 8
        Layout.bottomMargin: 8
        visible: root.rows.length === 0
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
        // Loading is said as loading, not as an empty inventory (TASTE 3.5).
        text: root.allModels.length > 0 ? Translation.tr("Nothing matching “%1”").arg(root.query)
            : HermesService.providersLoading ? Translation.tr("Loading models…")
            : Translation.tr("No models available")
    }
}
