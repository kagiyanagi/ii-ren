import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: page
    readonly property int index: 2
    property bool register: parent.register ?? false
    forceWidth: true

    ContentSection {
        icon: "volume_up"
        title: Translation.tr("Audio")

        ConfigSwitch {
            buttonIcon: "hearing"
            text: Translation.tr("Earbang protection")
            checked: Config.options.audio.protection.enable
            onCheckedChanged: {
                Config.options.audio.protection.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Prevents abrupt increments and restricts volume limit")
            }
        }
        ConfigSpinBox {
            enabled: Config.options.audio.protection.enable
            icon: "arrow_warm_up"
            text: Translation.tr("Max allowed increase")
            value: Config.options.audio.protection.maxAllowedIncrease
            from: 0
            to: 100
            stepSize: 2
            onValueChanged: {
                Config.options.audio.protection.maxAllowedIncrease = value;
            }
        }
        ConfigSpinBox {
            enabled: Config.options.audio.protection.enable
            icon: "vertical_align_top"
            text: Translation.tr("Volume limit")
            value: Config.options.audio.protection.maxAllowed
            from: 0
            to: 154 // pavucontrol allows up to 153%
            stepSize: 2
            onValueChanged: {
                Config.options.audio.protection.maxAllowed = value;
            }
        }
    }

    ContentSection {
        icon: "language"
        title: Translation.tr("Language")

        ConfigLabeledRow {
            buttonIcon: "language"
            text: Translation.tr("Interface language")
            summary: Translation.tr("Select the language for the user interface.\n\"Auto\" will use your system's locale.")
            StyledComboBox {
                id: languageSelector
                textRole: "displayName"

                model: [
                    {
                        displayName: Translation.tr("Auto (system)"),
                        value: "auto"
                    },
                    ...Translation.allAvailableLanguages.map(lang => {
                        return {
                            displayName: lang,
                            value: lang
                        };
                    })]

                currentIndex: {
                    const index = model.findIndex(item => item.value === Config.options.language.ui);
                    return index !== -1 ? index : 0;
                }

                onActivated: index => {
                    Config.options.language.ui = model[index].value;
                }
            }
        }

        ConfigLabeledRow {
            buttonIcon: "memory"
            text: Translation.tr("Screen translator engine")
            summary: Translation.tr("Engine for screen translation. Web engines require no setup.\nLocal Model (Manga) requires: pip install mokuro argostranslate\nLocal Argos (General) requires: pip install argostranslate")
            StyledComboBox {
                textRole: "displayName"

                model: [
                    {
                        displayName: Translation.tr("Lightweight (Tesseract + Google)"),
                        value: "lightweight"
                    },
                    {
                        displayName: Translation.tr("Local AI model (Mokuro MangaOCR)"),
                        value: "local_model"
                    }
                ]

                currentIndex: {
                    const index = model.findIndex(item => item.value === Config.options.language.translator.mode);
                    return index !== -1 ? index : 0;
                }

                onActivated: index => {
                    Config.options.language.translator.mode = model[index].value;
                }
            }
        }
    }

    // Each policy is a page in the left sidebar, listed in the sidebar's own
    // order. Weeb's three states are two switches: the page, then its tab. The
    // rows don't toggle themselves, so each switch keeps showing the config.
    ContentSection {
        icon: "rule"
        title: Translation.tr("Policies")

        ConfigSwitch {
            buttonIcon: "auto_awesome"
            text: Translation.tr("Hermes")
            summary: Translation.tr("Chat with your Hermes agent")
            toggles: false
            checked: Config.options.hermes.enable
            onClicked: Config.options.hermes.enable = !checked
        }
        ConfigSwitch {
            buttonIcon: "translate"
            text: Translation.tr("Translator")
            summary: Translation.tr("Translate text without leaving the desktop")
            toggles: false
            checked: Config.options.policies.translator !== 0
            onClicked: Config.options.policies.translator = checked ? 0 : 1
        }
        ConfigSwitch {
            buttonIcon: "bookmark_heart"
            text: Translation.tr("Weeb")
            summary: Translation.tr("Browse anime image boards")
            toggles: false
            checked: Config.options.policies.weeb !== 0
            onClicked: Config.options.policies.weeb = checked ? 0 : 1
        }
        ConfigSwitch {
            enabled: Config.options.policies.weeb !== 0
            buttonIcon: "ev_shadow"
            text: Translation.tr("Closet")
            summary: Translation.tr("Keep the anime page but hide its tab")
            toggles: false
            checked: Config.options.policies.weeb === 2
            onClicked: Config.options.policies.weeb = checked ? 1 : 2
        }
        ConfigSwitch {
            buttonIcon: "devices"
            text: Translation.tr("Continuity")
            summary: Translation.tr("Your phone and other devices")
            toggles: false
            checked: Config.options.policies.continuity !== 0
            onClicked: Config.options.policies.continuity = checked ? 0 : 1
        }
    }

    ContentSection {
        icon: "nest_clock_farsight_analog"
        title: Translation.tr("Time & date")

        ConfigFormatPicker {
            buttonIcon: "schedule"
            text: Translation.tr("Time format")
            formats: ["hh:mm", "h:mm ap", "h:mm AP"]
            value: Config.options.time.format
            placeholderText: Translation.tr("Custom time format (e.g. hh:mm, h:mm ap)")
            hint: Translation.tr("Custom format tokens: hh (24h), h (12h), mm (min), ss (sec), ap (am/pm), AP (AM/PM)")
            onPicked: format => {
                if (format.length === 0)
                    return;
                // hyprlock has its own 12h clock variable; keep it on the same clock.
                const hyprlock = `${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf`;
                Quickshell.execDetached(["sed", "-i", format.toLowerCase().includes("a") ? "s/\\bTIME\\b/TIME12/" : "s/\\bTIME12\\b/TIME/", hyprlock]);
                Config.options.time.format = format;
            }
        }
        ConfigSwitch {
            buttonIcon: "timer"
            text: Translation.tr("Second precision")
            summary: Translation.tr("Enable if you want clocks to show seconds accurately")
            checked: Config.options.time.secondPrecision
            onCheckedChanged: {
                Config.options.time.secondPrecision = checked;
            }
        }
        ConfigFormatPicker {
            buttonIcon: "calendar_today"
            text: Translation.tr("Date format")
            formats: ["ddd dd/MM", "ddd MM/dd", "dddd, MMMM dd", "yyyy-MM-dd"]
            value: Config.options.time.dateFormat
            placeholderText: Translation.tr("Custom date format (e.g. ddd, dd/MM)")
            hint: Translation.tr("Custom format tokens: ddd (short day), dddd (full day), dd (day), MM (month), yyyy (year)")
            onPicked: format => {
                if (format.length > 0)
                    Config.options.time.dateFormat = format;
            }
        }
    }

    ContentSection {
        icon: "work_alert"
        title: Translation.tr("Work safety")

        ConfigSwitch {
            buttonIcon: "assignment"
            text: Translation.tr("Hide clipboard images copied from sussy sources")
            checked: Config.options.workSafety.enable.clipboard
            onCheckedChanged: {
                Config.options.workSafety.enable.clipboard = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "wallpaper"
            text: Translation.tr("Hide sussy/anime wallpapers")
            checked: Config.options.workSafety.enable.wallpaper
            onCheckedChanged: {
                Config.options.workSafety.enable.wallpaper = checked;
            }
        }
    }

    ContentSection {
        id: autostartSection

        icon: "rocket_launch"
        title: Translation.tr("Autostart")

        // A working copy, deliberately not a binding on Config: every edit writes
        // back to Config, and a binding would then reset this list, destroy the
        // Repeater delegates and take the field being edited with them.
        // ponytail: the trade is that an external edit to config.json needs the
        // settings window reopened to show up.
        property var entries: []

        Component.onCompleted: autostartSection.entries = autostartSection.snapshot()

        function snapshot() {
            return (Config.options.hyprland.autostartApps.apps ?? []).map(app => ({
                        cmd: app.cmd ?? "",
                        workspace: app.workspace ?? 0,
                        delay: app.delay ?? 0
                    }));
        }

        function commit() {
            // list<var> cannot be mutated in place, so Config always gets a fresh
            // list. That is also what makes the change persist.
            Config.options.hyprland.autostartApps.apps = autostartSection.entries.map(entry => ({
                        cmd: entry.cmd,
                        workspace: entry.workspace,
                        delay: entry.delay
                    }));
        }

        // Mutates in place on purpose: reassigning entries would reset the model.
        function setField(index, key, value) {
            if (autostartSection.entries[index]?.[key] === value)
                return;
            autostartSection.entries[index][key] = value;
            autostartSection.commit();
        }

        function addEntry() {
            autostartSection.entries = [...autostartSection.entries, {
                    cmd: "",
                    workspace: 0,
                    delay: 0
                }];
            autostartSection.commit();
        }

        function removeEntry(index) {
            const list = [...autostartSection.entries];
            list.splice(index, 1);
            autostartSection.entries = list;
            autostartSection.commit();
        }

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Launch these apps at login")
            checked: Config.options.hyprland.autostartApps.enable
            onCheckedChanged: {
                Config.options.hyprland.autostartApps.enable = checked;
            }
        }

        Repeater {
            model: autostartSection.entries

            delegate: ConfigRow {
                id: entryRow

                required property var modelData
                required property int index

                // Signal handlers fire while the delegate is still being built,
                // when a spin box still reads 0 and the text field is still empty.
                // Writing then would clobber the stored entry with those defaults.
                property bool ready: false
                Component.onCompleted: entryRow.ready = true

                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                uniform: false
                spacing: 8

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Command")
                    text: entryRow.modelData.cmd ?? ""
                    onEditingFinished: {
                        if (entryRow.ready)
                            autostartSection.setField(entryRow.index, "cmd", text);
                    }
                }

                // Bare spinners with an icon, not ConfigSpinBox: that one is a
                // whole settings row (label + spinner, fillWidth hardcoded), so
                // several of them in one row collapse on top of each other.
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "workspaces"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext

                    // StyledToolTip shows itself whenever the parent has no
                    // "hovered" property, and a MaterialSymbol is a Text, so the
                    // handler is what keeps the tooltip off screen until hover.
                    HoverHandler {
                        id: workspaceIconHover
                    }

                    StyledToolTip {
                        extraVisibleCondition: workspaceIconHover.hovered
                        text: Translation.tr("Workspace to open on. 0 leaves it wherever it lands.")
                    }
                }

                StyledSpinBox {
                    Layout.alignment: Qt.AlignVCenter
                    value: entryRow.modelData.workspace ?? 0
                    from: 0
                    to: 30
                    stepSize: 1
                    onValueChanged: {
                        if (entryRow.ready)
                            autostartSection.setField(entryRow.index, "workspace", value);
                    }
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "timer"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext

                    HoverHandler {
                        id: delayIconHover
                    }

                    StyledToolTip {
                        extraVisibleCondition: delayIconHover.hovered
                        text: Translation.tr("Seconds to wait before starting the next app.")
                    }
                }

                StyledSpinBox {
                    Layout.alignment: Qt.AlignVCenter
                    value: entryRow.modelData.delay ?? 0
                    from: 0
                    to: 120
                    stepSize: 1
                    onValueChanged: {
                        if (entryRow.ready)
                            autostartSection.setField(entryRow.index, "delay", value);
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: implicitWidth / 2
                    onClicked: autostartSection.removeEntry(entryRow.index)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "delete"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledToolTip {
                        text: Translation.tr("Remove")
                    }
                }
            }
        }

        ConfigRow {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            uniform: false
            spacing: 8

            // They were bare-text RippleButtons with no fill, which read as
            // labels rather than the two actions of the section.
            RippleButtonWithIcon {
                materialIcon: "add"
                mainText: Translation.tr("Add app")
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: autostartSection.addEntry()
            }

            RippleButtonWithIcon {
                materialIcon: "play_arrow"
                mainText: Translation.tr("Run now")
                enabled: autostartSection.entries.length > 0
                onClicked: Autostart.launch()
            }
        }
    }
}
