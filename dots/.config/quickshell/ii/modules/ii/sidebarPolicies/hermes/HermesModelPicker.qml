pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Provider and model selection, fed by the agent's own inventory (`model.options`)
 * rather than a hardcoded list -- so a provider the user configures in Hermes
 * shows up here without a shell change.
 *
 * Picking applies with `--session` (see HermesService.setModel): the sidebar
 * remembers the choice itself and re-applies it to each new session, so it never
 * rewrites the model the `hermes` CLI starts on.
 */
ColumnLayout {
    id: root

    spacing: 8

    // Providers with nothing usable behind them would just be dead rows.
    readonly property var usableProviders: (HermesService.providers ?? []).filter(provider => (provider.models?.length ?? 0) > 0)

    property string selectedSlug: ""

    readonly property var selectedProvider: root.usableProviders.find(provider => provider.slug === root.selectedSlug) ?? null

    readonly property var modelOptions: (root.selectedProvider?.models ?? []).map(model => ({
        name: model,
        icon: (root.selectedProvider?.capabilities?.[model]?.reasoning ?? false) ? "neurology" : ""
    }))

    function syncFromService(): void {
        // Prefer the provider actually running the session; fall back to the one
        // the inventory marks current, then the first usable one.
        const providers = root.usableProviders;
        if (providers.length === 0)
            return;
        const running = providers.find(provider => provider.models.includes(HermesService.currentModel));
        const current = providers.find(provider => provider.is_current);
        root.selectedSlug = (running ?? current ?? providers[0]).slug;
    }

    Component.onCompleted: root.syncFromService()

    Connections {
        target: HermesService
        function onProvidersChanged() {
            if (root.selectedSlug.length === 0)
                root.syncFromService();
        }
        function onCurrentModelChanged() {
            if (root.selectedSlug.length === 0)
                root.syncFromService();
        }
    }

    StyledComboBox {
        id: providerCombo
        Layout.fillWidth: true

        buttonIcon: "hub"
        textRole: "name"
        model: root.usableProviders
        enabled: root.usableProviders.length > 0

        currentIndex: Math.max(0, root.usableProviders.findIndex(provider => provider.slug === root.selectedSlug))

        onActivated: index => {
            const provider = root.usableProviders[index];
            if (!provider)
                return;
            root.selectedSlug = provider.slug;
            // Switching provider without naming a model would leave the session on
            // a model the new provider does not serve.
            if (provider.models.length > 0)
                HermesService.setModel(provider.models[0], provider.slug, false);
        }
    }

    StyledComboBoxSearch {
        id: modelCombo
        Layout.fillWidth: true

        buttonIcon: "auto_awesome"
        textRole: "name"
        model: root.modelOptions
        enabled: root.modelOptions.length > 0

        currentIndex: Math.max(0, root.modelOptions.findIndex(option => option.name === HermesService.currentModel))

        onActivated: index => {
            const option = root.modelOptions[index];
            if (option)
                HermesService.setModel(option.name, root.selectedSlug, false);
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: (root.selectedProvider?.warning ?? "").length > 0
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: root.selectedProvider?.warning ?? ""
    }
}
