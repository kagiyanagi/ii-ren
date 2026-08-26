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
    readonly property int index: 1
    property bool register: parent.register ?? false
    forceWidth: true  
  
    Process {  
        id: translationProc  
        property string locale: ""  
        command: [Directories.aiTranslationScriptPath, translationProc.locale]  
    }  
  
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
        ConfigRow {  
            enabled: Config.options.audio.protection.enable  
            ConfigSpinBox {  
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
    }  
  
    ContentSection {  
        icon: "battery_android_full"  
        title: Translation.tr("Battery")  
  
        ConfigRow {  
            uniform: true  
            ConfigSpinBox {  
                icon: "warning"  
                text: Translation.tr("Low warning")  
                value: Config.options.battery.low  
                from: 0  
                to: 100  
                stepSize: 5  
                onValueChanged: {  
                    Config.options.battery.low = value;  
                }  
            }  
            ConfigSpinBox {  
                icon: "dangerous"  
                text: Translation.tr("Critical warning")  
                value: Config.options.battery.critical  
                from: 0  
                to: 100  
                stepSize: 5  
                onValueChanged: {  
                    Config.options.battery.critical = value;  
                }  
            }  
        }  
        ConfigRow {  
            uniform: false  
            Layout.fillWidth: false  
            ConfigSwitch {  
                buttonIcon: "pause"  
                text: Translation.tr("Automatic suspend")  
                checked: Config.options.battery.automaticSuspend  
                onCheckedChanged: {  
                    Config.options.battery.automaticSuspend = checked;  
                }  
                StyledToolTip {  
                    text: Translation.tr("Automatically suspends the system when battery is low")  
                }  
            }  
            ConfigSpinBox {  
                enabled: Config.options.battery.automaticSuspend  
                text: Translation.tr("at")  
                value: Config.options.battery.suspend  
                from: 0  
                to: 100  
                stepSize: 5  
                onValueChanged: {  
                    Config.options.battery.suspend = value;  
                }  
            }  
        }  
        ConfigRow {  
            uniform: true  
            ConfigSpinBox {  
                icon: "charger"  
                text: Translation.tr("Full warning")  
                value: Config.options.battery.full  
                from: 0  
                to: 101  
                stepSize: 5  
                onValueChanged: {  
                    Config.options.battery.full = value;  
                }  
            }  
        }  
    }  
  
    ContentSection {  
        icon: "language"  
        title: Translation.tr("Language")  
  
        ContentSubsection {  
            title: Translation.tr("Interface Language")  
            tooltip: Translation.tr("Select the language for the user interface.\n\"Auto\" will use your system's locale.")  
  
            StyledComboBox {  
                id: languageSelector  
                buttonIcon: "language"  
                textRole: "displayName"  
  
                model: [  
                    {  
                        displayName: Translation.tr("Auto (System)"),  
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
        ContentSubsection {  
            title: Translation.tr("Generate translation with Gemini")  
            tooltip: Translation.tr("You'll need to enter your Gemini API key first.\nType /key on the sidebar for instructions.")  
  
            ConfigRow {  
                MaterialTextArea {  
                    id: localeInput  
                    Layout.fillWidth: true  
                    placeholderText: Translation.tr("Locale code, e.g. fr_FR, de_DE, zh_CN...")  
                    text: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui  
                }  
                RippleButtonWithIcon {  
                    id: generateTranslationBtn  
                    Layout.fillHeight: true  
                    nerdIcon: ""  
                    enabled: !translationProc.running || (translationProc.locale !== localeInput.text.trim())  
                    mainText: enabled ? Translation.tr("Generate\nTypically takes 2 minutes") : Translation.tr("Generating...\nDon't close this window!")  
                    onClicked: {  
                        translationProc.locale = localeInput.text.trim();  
                        translationProc.running = false;  
                        translationProc.running = true;  
                    }  
                }  
            }  
        }  
    } 

    ContentSection {
        icon: "rule"
        title: Translation.tr("Policies")

        ConfigRow {
            Layout.fillHeight: false

            ContentSubsection {
                title: Translation.tr("AI")
                Layout.fillWidth: true

                ConfigSelectionArray {  
                    currentValue: Config.options.policies.ai  
                    onSelected: newValue => {  
                        Config.options.policies.ai = newValue;  
                    }  
                    options: [  
                        {  
                            displayName: Translation.tr("No"),  
                            icon: "close",  
                            value: 0  
                        },  
                        {  
                            displayName: Translation.tr("Yes"),  
                            icon: "check",  
                            value: 1  
                        },  
                        {  
                            displayName: Translation.tr("Local only"),  
                            icon: "sync_saved_locally",  
                            value: 2  
                        }  
                    ]  
                } 
            }

            ContentSubsection {
                title: Translation.tr("Weeb")
                Layout.fillWidth: false

                ConfigSelectionArray {  
                    currentValue: Config.options.policies.weeb  
                    onSelected: newValue => {  
                        Config.options.policies.weeb = newValue;  
                    }  
                    options: [  
                        {  
                            displayName: Translation.tr("No"),  
                            icon: "close",  
                            value: 0  
                        },  
                        {  
                            displayName: Translation.tr("Yes"),  
                            icon: "check",  
                            value: 1  
                        },  
                        {  
                            displayName: Translation.tr("Closet"),  
                            icon: "ev_shadow",  
                            value: 2  
                        }  
                    ]  
                }
            }
        }

        ConfigRow {
            Layout.fillHeight: false

            ContentSubsection {
                title: Translation.tr("Continuity")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.policies.continuity
                    onSelected: newValue => {
                        Config.options.policies.continuity = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: 1
                        }
                    ]
                }
            }
        }

        ConfigRow {
            Layout.fillHeight: false

            ContentSubsection {
                title: Translation.tr("Translator")
                Layout.fillWidth: false

                ConfigSelectionArray {  
                    currentValue: Config.options.policies.translator  
                    onSelected: newValue => {  
                        Config.options.policies.translator = newValue;  
                    }  
                    options: [  
                        {  
                            displayName: Translation.tr("No"),  
                            icon: "close",  
                            value: 0  
                        },  
                        {  
                            displayName: Translation.tr("Yes"),  
                            icon: "check",  
                            value: 1  
                        }  
                    ]  
                }
            }
        }
        
    }
  
    ContentSection {  
        icon: "notification_sound"  
        title: Translation.tr("Sounds")  
        ConfigRow {  
            uniform: true  
            ConfigSwitch {  
                buttonIcon: "battery_android_full"  
                text: Translation.tr("Battery")  
                checked: Config.options.sounds.battery  
                onCheckedChanged: {  
                    Config.options.sounds.battery = checked;  
                }  
            }  
            ConfigSwitch {  
                buttonIcon: "av_timer"  
                text: Translation.tr("Pomodoro")  
                checked: Config.options.sounds.pomodoro  
                onCheckedChanged: {  
                    Config.options.sounds.pomodoro = checked;  
                }  
            }  
        }  
    }  
  
    ContentSection {  
        icon: "nest_clock_farsight_analog"  
        title: Translation.tr("Time")  
  
        ConfigSwitch {  
            buttonIcon: "pace"  
            text: Translation.tr("Second precision")  
            checked: Config.options.time.secondPrecision  
            onCheckedChanged: {  
                Config.options.time.secondPrecision = checked;  
            }  
            StyledToolTip {  
                text: Translation.tr("Enable if you want clocks to show seconds accurately")  
            }  
        }  
  
        ContentSubsection {  
            title: Translation.tr("Format")  
            tooltip: ""  
  
            ConfigSelectionArray {  
                currentValue: Config.options.time.format  
                onSelected: newValue => {  
                    if (newValue === "hh:mm") {  
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME12\\b/TIME/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);  
                    } else {  
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME\\b/TIME12/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);  
                    }  
  
                    Config.options.time.format = newValue;  
                }  
                options: [  
                    {  
                        displayName: Translation.tr("24h"),  
                        value: "hh:mm"  
                    },  
                    {  
                        displayName: Translation.tr("12h am/pm"),  
                        value: "h:mm ap"  
                    },  
                    {  
                        displayName: Translation.tr("12h AM/PM"),  
                        value: "h:mm AP"  
                    },  
                ]  
            }  
        }  
    }  

    ContentSection {
        icon: "calendar_month"
        title: Translation.tr("Date")

        ContentSubsection {
            title: Translation.tr("Format")
            tooltip: Translation.tr("Changes the date format in the bar")

            ConfigSelectionArray {
                currentValue: Config.options.time.dateFormat
                onSelected: newValue => {
                    Config.options.time.dateFormat = newValue;  
                }
                options: [
                    {
                        displayName: Translation.tr("Date First dd/MM"),
                        value: "ddd dd/MM"
                    },
                    {
                        displayName: Translation.tr("Month First MM/dd"),
                        value: "ddd MM/dd"
                    }
                ]
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

            RippleButton {
                buttonText: Translation.tr("Add app")
                onClicked: autostartSection.addEntry()
            }

            RippleButton {
                buttonText: Translation.tr("Run now")
                enabled: autostartSection.entries.length > 0
                onClicked: Autostart.launch()
            }
        }
    }
}
