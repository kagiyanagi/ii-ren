import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings for Hermes: first the shell's own block (Config.options.hermes),
 * then the agent itself -- ~/.hermes/config.yaml, reached through the
 * gateway's config.get/config.set RPC. The two stay separate stores; they
 * share a page so the user has one place to look.
 */
ContentPage {
    id: page
    // This page's slot in settings.qml's `pages`; search navigates by it.
    // tools/check-settings-search.py keeps the two in step.
    readonly property int index: 12
    property bool register: parent.register ?? false
    forceWidth: true

    property bool loaded: false
    property var failedKeys: ({})
    // Set while a fetched value is being written into a bound control, so
    // that assignment doesn't look like a user edit and echo straight back
    // out to setConfig.
    property bool _applyingFetch: false

    property string personality: ""
    property string prompt: ""
    property string reasoning: ""
    property bool fastEnabled: false
    property string busyMode: "queue"
    property string detailsMode: "collapsed"
    property string thinkingMode: "collapsed"
    property string theme: "auto"
    property bool densityOn: true

    property string profileHome: ""
    property string providerText: ""
    property string projectText: ""

    // Non-null arms the remove-confirmation dialog for that vault item.
    property var removeTarget: null

    // A key the backend would not answer shows this instead of a blank or
    // "undefined" control, so one dead key never looks like the whole page
    // failed to load.
    component UnavailableHint: StyledText {
        property string configKey: ""
        visible: page.failedKeys[configKey] === true
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colSubtext
        text: Translation.tr("Could not read this from the agent.")
    }

    // A password source's row: the switch that enables it, plus its
    // unlock/lock affordance when the source needs a master password.
    component VaultSourceRow: ColumnLayout {
        id: sourceRow
        required property var source
        readonly property bool wantsCard: true
        readonly property bool installed: sourceRow.source?.installed !== false
        readonly property bool needsUnlock: sourceRow.source?.needs_unlock ?? false
        readonly property bool unlocked: sourceRow.source?.unlocked ?? false
        property string unlockError: ""

        function submitUnlock(): void {
            const password = pwField.text;
            if (password.length === 0)
                return;
            HermesService.unlockVaultSource(sourceRow.source.name, password, (ok, message) => {
                sourceRow.unlockError = ok ? "" : (message.length > 0 ? message : Translation.tr("Could not unlock"));
            });
            // Cleared the instant the call is made -- never held longer than
            // it takes to hand off, never logged, never read back by anything else.
            pwField.text = "";
        }

        Layout.fillWidth: true
        spacing: 4

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: sourceRow.unlocked || !sourceRow.needsUnlock ? "lock_open" : "lock"
            text: (sourceRow.source.display_name ?? "").length > 0 ? sourceRow.source.display_name : (sourceRow.source.name ?? "")
            enabled: sourceRow.installed
            checked: sourceRow.source.enabled ?? false
            // The handler also fires while the row is built and on every vault
            // refresh, which wrote each source's own state straight back.
            onCheckedChanged: {
                if (checked !== (sourceRow.source.enabled ?? false))
                    HermesService.setVaultSource(sourceRow.source.name, checked);
            }
        }

        StyledText {
            visible: !sourceRow.installed
            Layout.fillWidth: true
            Layout.leftMargin: 12
            text: Translation.tr("Not installed")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        RowLayout {
            visible: sourceRow.installed && sourceRow.needsUnlock && sourceRow.unlocked
            Layout.fillWidth: true
            Layout.leftMargin: 12
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Unlocked")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            RippleButtonWithIcon {
                Layout.fillWidth: false
                materialIcon: "lock"
                mainText: Translation.tr("Lock")
                onClicked: HermesService.lockVaultSource(sourceRow.source.name)
            }
        }

        RowLayout {
            visible: sourceRow.installed && sourceRow.needsUnlock && !sourceRow.unlocked
            Layout.fillWidth: true
            Layout.leftMargin: 12
            spacing: 8

            MaterialTextField {
                id: pwField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholderText: Translation.tr("Master password")
                Keys.onReturnPressed: sourceRow.submitUnlock()
            }
            RippleButtonWithIcon {
                Layout.fillWidth: false
                materialIcon: "lock_open"
                mainText: Translation.tr("Unlock")
                onClicked: sourceRow.submitUnlock()
            }
        }

        StyledText {
            visible: sourceRow.unlockError.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 12
            wrapMode: Text.Wrap
            text: sourceRow.unlockError
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    // One saved item -- label and identifiers only, never a stored secret.
    component VaultItemRow: RowLayout {
        id: itemRow
        required property var item
        signal removeRequested
        readonly property bool wantsCard: true

        Layout.fillWidth: true
        spacing: 10

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: page.vaultKindIcon(itemRow.item?.kind ?? "")
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: (itemRow.item?.label ?? "").length > 0 ? itemRow.item.label : Translation.tr("Untitled")
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                visible: text.length > 0
                text: [(itemRow.item?.origin ?? "").toString(), (itemRow.item?.identifier ?? "").toString()].filter(part => part.length > 0).join("  ·  ")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }

        RippleButton {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 32
            implicitHeight: 32
            buttonRadius: Appearance.rounding.small
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colErrorContainerHover
            releaseAction: () => itemRow.removeRequested()

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "delete"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
            }
            StyledToolTip {
                text: Translation.tr("Remove from vault")
            }
        }
    }

    // One kind of saved item ("login" | "payment" | "address"), grouped
    // under its own label and hidden entirely when there is nothing of that
    // kind saved.
    component VaultKindSection: ContentSubsection {
        id: kindSection
        required property string kind
        readonly property var items: (HermesService.vaultItems ?? []).filter(entry => (entry?.kind ?? "") === kindSection.kind)

        visible: kindSection.items.length > 0

        Repeater {
            model: kindSection.items
            delegate: VaultItemRow {
                required property var modelData
                item: modelData
                onRemoveRequested: page.removeTarget = modelData
            }
        }
    }

    // getConfig's reply shape varies by key: most answer {value}, others use
    // their own field name. `value` wins when present, otherwise the first
    // fallback field that is actually a string; anything else (missing key,
    // wrong-shaped reply) comes back null and the caller marks it unavailable.
    function extractText(result, fallbackFields) {
        if (result === null || result === undefined)
            return null;
        if (typeof result === "string")
            return result;
        if (typeof result.value === "string")
            return result.value;
        for (let i = 0; i < fallbackFields.length; i++) {
            const field = result[fallbackFields[i]];
            if (typeof field === "string")
                return field;
        }
        return null;
    }

    function fetchText(key, fallbackFields, applyFn) {
        HermesService.getConfig(key, result => {
            const text = page.extractText(result, fallbackFields);
            page.failedKeys = Object.assign({}, page.failedKeys, ({ [key]: text === null }));
            if (text === null)
                return;
            page._applyingFetch = true;
            applyFn(text);
            page._applyingFetch = false;
        });
    }

    // Writes through the gateway, then re-reads the key so the control ends
    // up showing whatever the backend actually accepted (it normalises).
    function setAndReload(key, value, fallbackFields, applyFn) {
        HermesService.setConfig(key, value, () => {
            page.fetchText(key, fallbackFields, applyFn);
        });
    }

    // ── Account & vault ──────────────────────────────────────────────────
    //
    // Vault data is metadata only -- HermesService.vaultItems never carries a
    // password, so there is nothing secret here to protect except the master
    // password field itself, which is cleared the instant it is sent.

    readonly property var billing: HermesService.billing

    readonly property string billingNotice: {
        const account = page.billing;
        if (!account)
            return Translation.tr("Couldn't check billing status right now.");
        if ((account.error ?? "").length > 0)
            return account.error.toString();
        if (account.logged_in === false)
            return Translation.tr("Not signed in.");
        return "";
    }

    // Renders whatever billing.state hands back beyond the fields it always
    // carries -- the shape past those is not guaranteed, so a scalar field
    // gets a row and a nested one is skipped rather than guessed at.
    readonly property var billingRows: {
        const account = page.billing;
        if (!account)
            return [];
        const skip = ["ok", "logged_in", "error", "free_tier"];
        const out = [];
        for (const key of Object.keys(account)) {
            if (skip.includes(key))
                continue;
            const value = account[key];
            if (value === null || value === undefined || typeof value === "object")
                continue;
            out.push({
                label: page.humanizeKey(key),
                value: value.toString()
            });
        }
        return out;
    }

    function humanizeKey(key: string): string {
        const spaced = key.replace(/_/g, " ");
        return spaced.length > 0 ? spaced.charAt(0).toUpperCase() + spaced.slice(1) : spaced;
    }

    function vaultKindIcon(kind: string): string {
        switch (kind) {
        case "login":
            return "key";
        case "payment":
            return "credit_card";
        case "address":
            return "home_pin";
        default:
            return "inventory_2";
        }
    }

    function refreshAll() {
        page.loaded = true;
        page.fetchText("personality", ["personality", "name", "display"], v => page.personality = v);
        page.fetchText("prompt", ["prompt"], v => page.prompt = v);
        page.fetchText("reasoning", ["reasoning", "effort"], v => page.reasoning = v);
        page.fetchText("fast", ["fast", "enabled"], v => page.fastEnabled = (v === "on" || v === "true"));
        page.fetchText("busy", [], v => page.busyMode = v);
        page.fetchText("details_mode", [], v => page.detailsMode = v);
        page.fetchText("thinking_mode", [], v => page.thinkingMode = v);
        page.fetchText("theme", [], v => page.theme = v);
        page.fetchText("density", [], v => page.densityOn = (v === "on"));
        page.fetchText("provider", ["provider", "name", "display"], v => page.providerText = v);
        page.fetchText("project", ["project", "name", "path", "display"], v => page.projectText = v);

        HermesService.getConfig("profile", result => {
            const home = (result && typeof result.home === "string") ? result.home : null;
            page.failedKeys = Object.assign({}, page.failedKeys, ({ profile: home === null }));
            if (home !== null)
                page.profileHome = home;
        });

        HermesService.refreshBilling();
        HermesService.refreshVault();
    }

    Component.onCompleted: {
        if (HermesService.ready)
            page.refreshAll();
    }

    Connections {
        target: HermesService
        function onReadyChanged() {
            if (HermesService.ready && !page.loaded)
                page.refreshAll();
        }
    }

    // The shell's own Hermes options (Config.options.hermes). They used to be a
    // "Hermes" section on Services, so Settings had two places by that name;
    // they come first and stay up while the gateway is down, since none of
    // them needs it.
    ContentSection {
        icon: "auto_awesome"
        title: Translation.tr("In the sidebar")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Show Hermes in the sidebar")
            checked: Config.options.hermes.enable
            onCheckedChanged: {
                Config.options.hermes.enable = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "construction"
            text: Translation.tr("Show what tools the agent runs")
            checked: Config.options.hermes.showToolCalls
            onCheckedChanged: {
                Config.options.hermes.showToolCalls = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "pending"
            text: Translation.tr("Show what it is doing while it works")
            checked: Config.options.hermes.showStatusLine
            onCheckedChanged: {
                Config.options.hermes.showStatusLine = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Notify when a reply lands and the tab isn't visible")
            checked: Config.options.hermes.notifyWhenAway
            onCheckedChanged: {
                Config.options.hermes.notifyWhenAway = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Dictate with")

            ConfigSelectionArray {
                currentValue: Config.options.hermes.sttEngine
                onSelected: newValue => {
                    Config.options.hermes.sttEngine = newValue;
                }
                options: [
                    { displayName: Translation.tr("Hermes' provider"), value: "hermes" },
                    { displayName: Translation.tr("This machine"), value: "local" }
                ]
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Config.options.hermes.sttEngine === "local"
                    ? Translation.tr("Transcribed here with whisper.cpp. Nothing is uploaded.")
                    : Translation.tr("Transcribed by whichever provider Hermes is set to — its `stt.provider`, shared with the agent's own voice mode. Falls back to this machine when Hermes isn't installed.")
            }
        }

        ContentSubsection {
            title: Translation.tr("Dictation accuracy on this machine")

            ConfigSelectionArray {
                currentValue: Config.options.hermes.sttQuality
                onSelected: newValue => {
                    Config.options.hermes.sttQuality = newValue;
                }
                options: [
                    { displayName: Translation.tr("Fast"), value: "fast" },
                    { displayName: Translation.tr("Balanced"), value: "balanced" },
                    { displayName: Translation.tr("Accurate"), value: "accurate" },
                    { displayName: Translation.tr("Best"), value: "best" }
                ]
            }
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("Everything below this section belongs to the agent itself and is read from it. Models, providers, tools and approvals are set with the picker in the sidebar or Hermes' own slash commands.")
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        visible: !HermesService.ready
        materialIcon: "cloud_off"
        text: Translation.tr("Hermes isn't connected right now. These settings live on the agent itself, so they will show up here once the gateway starts.")
    }

    ContentSection {
        visible: HermesService.ready
        icon: "psychology"
        title: Translation.tr("Behaviour")

        ContentSubsection {
            title: Translation.tr("Persona")
            tooltip: Translation.tr("Who the agent is, in its own words.")

            MaterialTextField {
                id: personalityField
                Layout.fillWidth: true
                placeholderText: Translation.tr("e.g. terse, mostly silent")
                text: page.personality
                onEditingFinished: {
                    if (text !== page.personality)
                        page.setAndReload("personality", text, ["personality", "name", "display"], v => {
                            page.personality = v;
                            personalityField.text = v;
                        });
                }
            }
            UnavailableHint { configKey: "personality" }
        }

        ContentSubsection {
            title: Translation.tr("System prompt")
            tooltip: Translation.tr("Replaces the agent's default instructions for every session.")

            MaterialTextArea {
                id: promptField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Custom system prompt")
                text: page.prompt
                wrapMode: TextEdit.Wrap
            }

            ConfigRow {
                Layout.fillWidth: true
                spacing: 8

                RippleButtonWithIcon {
                    materialIcon: "save"
                    mainText: Translation.tr("Save prompt")
                    onClicked: {
                        page.setAndReload("prompt", promptField.text, ["prompt"], v => {
                            page.prompt = v;
                            promptField.text = v;
                        });
                    }
                }
                RippleButtonWithIcon {
                    materialIcon: "backspace"
                    mainText: Translation.tr("Clear")
                    onClicked: {
                        page.setAndReload("prompt", "clear", ["prompt"], v => {
                            page.prompt = v;
                            promptField.text = v;
                        });
                    }
                    StyledToolTip {
                        text: Translation.tr("Removes the custom prompt -- back to the agent's own default.")
                    }
                }
            }
            UnavailableHint { configKey: "prompt" }
        }

        ContentSubsection {
            title: Translation.tr("Reasoning effort")

            MaterialTextField {
                id: reasoningField
                Layout.fillWidth: true
                placeholderText: Translation.tr("e.g. low, medium, high")
                text: page.reasoning
                onEditingFinished: {
                    if (text !== page.reasoning)
                        page.setAndReload("reasoning", text, ["reasoning", "effort"], v => {
                            page.reasoning = v;
                            reasoningField.text = v;
                        });
                }
            }
            UnavailableHint { configKey: "reasoning" }
        }

        ConfigSwitch {
            buttonIcon: "bolt"
            text: Translation.tr("Fast mode")
            checked: page.fastEnabled
            onCheckedChanged: {
                if (!page._applyingFetch)
                    page.setAndReload("fast", checked ? "on" : "off", ["fast", "enabled"], v => page.fastEnabled = (v === "on" || v === "true"));
            }
        }
        UnavailableHint { configKey: "fast" }

        ContentSubsection {
            title: Translation.tr("While you type and it's already working")

            ConfigSelectionArray {
                currentValue: page.busyMode
                onSelected: newValue => page.setAndReload("busy", newValue, [], v => page.busyMode = v)
                options: [
                    { displayName: Translation.tr("Queue"), icon: "playlist_add", value: "queue" },
                    { displayName: Translation.tr("Steer"), icon: "alt_route", value: "steer" },
                    { displayName: Translation.tr("Interrupt"), icon: "stop_circle", value: "interrupt" }
                ]
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: page.busyMode === "steer"
                    ? Translation.tr("Feeds what you type into the run in progress, without waiting.")
                    : page.busyMode === "interrupt"
                        ? Translation.tr("Drops what it's doing and starts on what you typed.")
                        : Translation.tr("Waits for the current turn to finish, then sends what you typed.")
            }
            UnavailableHint { configKey: "busy" }
        }
    }

    ContentSection {
        visible: HermesService.ready
        icon: "view_agenda"
        title: Translation.tr("Display")

        ContentSubsection {
            title: Translation.tr("Tool detail")

            ConfigSelectionArray {
                currentValue: page.detailsMode
                onSelected: newValue => page.setAndReload("details_mode", newValue, [], v => page.detailsMode = v)
                options: [
                    { displayName: Translation.tr("Collapsed"), icon: "unfold_less", value: "collapsed" },
                    { displayName: Translation.tr("Expanded"), icon: "unfold_more", value: "expanded" }
                ]
            }
            UnavailableHint { configKey: "details_mode" }
        }

        ContentSubsection {
            title: Translation.tr("Thinking")

            ConfigSelectionArray {
                currentValue: page.thinkingMode
                onSelected: newValue => page.setAndReload("thinking_mode", newValue, [], v => page.thinkingMode = v)
                options: [
                    { displayName: Translation.tr("Collapsed"), icon: "unfold_less", value: "collapsed" },
                    { displayName: Translation.tr("Truncated"), icon: "short_text", value: "truncated" },
                    { displayName: Translation.tr("Full"), icon: "notes", value: "full" }
                ]
            }
            UnavailableHint { configKey: "thinking_mode" }
        }

        ContentSubsection {
            title: Translation.tr("Theme")

            ConfigSelectionArray {
                currentValue: page.theme
                onSelected: newValue => page.setAndReload("theme", newValue, [], v => page.theme = v)
                options: [
                    { displayName: Translation.tr("Auto"), icon: "brightness_auto", value: "auto" },
                    { displayName: Translation.tr("Light"), icon: "light_mode", value: "light" },
                    { displayName: Translation.tr("Dark"), icon: "dark_mode", value: "dark" }
                ]
            }
            UnavailableHint { configKey: "theme" }
        }

        ConfigSwitch {
            buttonIcon: "density_medium"
            text: Translation.tr("Compact density")
            checked: page.densityOn
            onCheckedChanged: {
                if (!page._applyingFetch)
                    page.setAndReload("density", checked ? "on" : "off", [], v => page.densityOn = (v === "on"));
            }
        }
        UnavailableHint { configKey: "density" }
    }

    ContentSection {
        visible: HermesService.ready
        icon: "info"
        title: Translation.tr("Agent info")

        // Read-only here, so a subsection of the agent's facts rather than a
        // section of its own with nothing to operate.
        ContentSubsection {
            title: Translation.tr("Approvals")
            tooltip: Translation.tr("Set from the sidebar's own approvals picker, not here.")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: HermesService.approvalMode.length > 0 ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                text: HermesService.approvalMode.length > 0 ? HermesService.approvalMode : Translation.tr("Unavailable")
            }
        }

        ContentSubsection {
            title: Translation.tr("Profile home")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: page.failedKeys["profile"] === true ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                text: page.profileHome.length > 0 ? page.profileHome : Translation.tr("Unavailable")
            }
        }

        ContentSubsection {
            title: Translation.tr("Provider")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: page.failedKeys["provider"] === true ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                text: page.providerText.length > 0 ? page.providerText : Translation.tr("Unavailable")
            }
        }

        ContentSubsection {
            title: Translation.tr("Project")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: page.failedKeys["project"] === true ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                text: page.projectText.length > 0 ? page.projectText : Translation.tr("Unavailable")
            }
        }
    }

    ContentSection {
        visible: HermesService.ready
        icon: "account_circle"
        title: Translation.tr("Account")

        RippleButtonWithIcon {
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh")
            onClicked: HermesService.refreshBilling()
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: page.billingNotice.length > 0
            materialIcon: "info"
            text: page.billingNotice
        }

        StyledText {
            visible: (page.billing?.free_tier ?? false) === true
            text: Translation.tr("Free tier")
            color: Appearance.colors.colPrimary
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
        }

        Repeater {
            model: page.billingRows
            delegate: ContentSubsection {
                id: billingRow
                required property var modelData
                title: billingRow.modelData.label

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colOnLayer1
                    text: billingRow.modelData.value
                }
            }
        }
    }

    ContentSection {
        visible: HermesService.ready
        icon: "shield_lock"
        title: Translation.tr("Credential vault")

        RippleButtonWithIcon {
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh")
            onClicked: HermesService.refreshVault()
        }

        ContentSubsection {
            title: Translation.tr("Password sources")

            StyledText {
                visible: (HermesService.vaultSources ?? []).length === 0
                Layout.fillWidth: true
                text: Translation.tr("No password sources configured.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            Repeater {
                model: HermesService.vaultSources ?? []
                delegate: VaultSourceRow {
                    required property var modelData
                    source: modelData
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Saved items")

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "verified_user"
                text: Translation.tr("Only labels and identifiers show here. Passwords stay in the vault and never pass through this panel.")
            }

            StyledText {
                visible: (HermesService.vaultItems ?? []).length === 0
                Layout.fillWidth: true
                text: Translation.tr("Nothing saved yet.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            VaultKindSection {
                kind: "login"
                title: Translation.tr("Logins")
            }
            VaultKindSection {
                kind: "payment"
                title: Translation.tr("Payment methods")
            }
            VaultKindSection {
                kind: "address"
                title: Translation.tr("Addresses")
            }
        }
    }

    // Latched: the Loader stays up until the dialog has finished collapsing.
    // It used to be `active: removeTarget !== null`, which destroyed the dialog
    // on the frame Cancel or Remove cleared the target, so it never played its
    // exit. Reparented onto `page` (not left in ContentPage's own scrolling
    // column) so it overlays the whole viewport rather than becoming another
    // section row.
    property bool removeDialogActive: false
    onRemoveTargetChanged: if (page.removeTarget !== null) page.removeDialogActive = true

    Loader {
        id: removeVaultItemDialogLoader
        parent: page
        anchors.fill: parent
        z: 100
        active: page.removeDialogActive

        sourceComponent: WindowDialog {
            id: removeDialog
            // Label, else origin, else a neutral noun -- a vault row is allowed
            // to carry none of them. Copied once, so the exit does not play on
            // "this item" after the target is cleared.
            property string itemName

            // Created shut and opened a turn later, so onShowChanged runs and
            // the dialog enters instead of appearing at full size.
            show: false
            Component.onCompleted: {
                const target = page.removeTarget;
                removeDialog.itemName = (target?.label ?? "").length > 0 ? target.label
                    : (target?.origin ?? "").length > 0 ? target.origin
                    : Translation.tr("this item");
                removeDialog.show = Qt.binding(() => page.removeTarget !== null);
                removeDialog.forceActiveFocus();
            }
            onVisibleChanged: if (!visible && !show) page.removeDialogActive = false

            WindowDialogTitle {
                text: Translation.tr("Remove saved item?")
            }
            WindowDialogParagraph {
                text: Translation.tr("“%1” will be removed from the vault. This cannot be undone.").arg(removeDialog.itemName)
            }
            WindowDialogButtonRow {
                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: page.removeTarget = null
                }
                Item {
                    Layout.fillWidth: true
                }
                DialogButton {
                    buttonText: Translation.tr("Remove")
                    colEnabled: Appearance.colors.colError
                    onClicked: {
                        HermesService.removeVaultItem(page.removeTarget?.id ?? "");
                        page.removeTarget = null;
                    }
                }
            }

            onDismiss: page.removeTarget = null
        }
    }
}
