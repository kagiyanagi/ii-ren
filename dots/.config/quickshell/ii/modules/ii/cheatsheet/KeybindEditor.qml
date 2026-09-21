pragma ComponentBehavior: Bound

import "keybind_keys.js" as KeybindKeys
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Add one keybind to `~/.config/hypr/custom/keybinds.lua`.
 *
 * The combination is **captured**, not typed: the field listens for a real key
 * press and writes down the name Hyprland uses for it. Typing "SUPER + SHIFT +
 * K" by hand is where the spelling goes wrong -- `Slash` vs `/`, `Page_Up` vs
 * `PageUp` -- and the result is a line that parses and silently never fires.
 */
WindowDialog {
    id: root

    backgroundWidth: 520

    property string combo: ""
    property string action: "exec_cmd"
    property string command: ""
    property string globalName: ""
    property string description: ""
    property bool capturing: false

    readonly property var parsedCombo: root.combo.length > 0 ? UserKeybinds.parseCombo(root.combo) : null
    readonly property string argument: root.action === "exec_cmd" ? root.command : root.globalName
    readonly property bool valid: root.parsedCombo !== null && root.argument.trim().length > 0

    // What this combination is already bound to, if anything. Hyprland lets two
    // binds share a combination and simply runs both, so this is a warning
    // rather than a block -- but it is the difference between "my new bind does
    // not work" and "it works, and so does the old one".
    readonly property var conflict: {
        if (root.parsedCombo === null)
            return null;
        for (const bind of HyprlandKeybinds.keybinds) {
            if (bind.modmask === root.parsedCombo.modmask
                && String(bind.key).toLowerCase() === root.parsedCombo.key.toLowerCase())
                return bind;
        }
        return null;
    }

    function reset() {
        root.combo = "";
        root.action = "exec_cmd";
        root.command = "";
        root.globalName = "";
        root.description = "";
        root.capturing = false;
    }

    function save() {
        if (!root.valid)
            return;
        // Categories in this sheet are the text before the first colon, so a
        // bind the user adds lands under its own heading instead of falling into
        // "Uncategorized".
        const described = root.description.trim().length > 0
            ? (root.description.indexOf(":") === -1
                ? Translation.tr("Custom") + ": " + root.description.trim()
                : root.description.trim())
            : "";
        if (UserKeybinds.add(root.combo, root.action, root.argument.trim(), described))
            root.dismiss();
    }

    onShowChanged: if (root.show) {
        UserKeybinds.loadGlobals();
        root.reset();
        captureButton.forceActiveFocus();
    }

    WindowDialogTitle {
        text: Translation.tr("Add a keybind")
    }

    // Everything below is a direct child of the dialog's own column, so it all
    // shares the one 16px inset. Wrapping these in ContentSubsection -- which is
    // a settings-page widget and adds 8 of its own on each side -- left the
    // title at 16, the section labels at 31 and the fields at 25, which reads as
    // four different left edges stacked down the dialog.
    WindowDialogSectionHeader {
        text: Translation.tr("Combination")
    }

    RippleButton {
        id: captureButton
        Layout.fillWidth: true
        implicitHeight: 64
        buttonRadius: Appearance.rounding.normal
        colBackground: Appearance.colors.colLayer2
        toggled: root.capturing
        onClicked: root.capturing = !root.capturing

        // The capture itself. Escape leaves capture rather than being bound --
        // it is the key someone presses to get out of a mode, and a dialog that
        // swallows it is a trap.
        Keys.onPressed: event => {
            if (!root.capturing)
                return;
            event.accepted = true;
            if (event.key === Qt.Key_Escape) {
                root.capturing = false;
                return;
            }
            const captured = KeybindKeys.combo(event.key, event.text, event.modifiers);
            if (captured === null)
                return; // a bare modifier: keep waiting for a real key
            root.combo = captured;
            root.capturing = false;
        }

        contentItem: ColumnLayout {
            spacing: 4
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: root.capturing ? Translation.tr("Press any combination · Escape to stop")
                    : root.combo.length > 0 ? Translation.tr("Click to capture again")
                    : Translation.tr("Click, then press the combination")
            }
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                visible: root.combo.length > 0
                Repeater {
                    model: root.combo.split(" + ")
                    delegate: KeyboardKey {
                        required property string modelData
                        key: modelData
                        pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.conflict !== null
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colOnLayer1
        text: root.conflict
            ? Translation.tr("Already bound to “%1”. Hyprland will run both.")
                .arg(root.conflict.description || root.conflict.dispatcher)
            : ""
    }

    WindowDialogSectionHeader {
        text: Translation.tr("Action")
    }

    ButtonGroup {
        Layout.fillWidth: true
        GroupButton {
            Layout.fillWidth: false
            toggled: root.action === "exec_cmd"
            buttonText: Translation.tr("Run a command")
            releaseAction: () => root.action = "exec_cmd"
        }
        GroupButton {
            Layout.fillWidth: false
            toggled: root.action === "global"
            buttonText: Translation.tr("Shell action")
            releaseAction: () => root.action = "global"
        }
    }

    MaterialTextField {
        Layout.fillWidth: true
        visible: root.action === "exec_cmd"
        placeholderText: Translation.tr("kitty, firefox, ~/bin/thing …")
        text: root.command
        onTextChanged: root.command = text
    }

    // The real list, read from `hyprctl globalshortcuts`, so it cannot drift
    // from what the shell has actually registered. Searchable because there are
    // forty-odd of them.
    StyledComboBoxSearch {
        id: globalPicker
        Layout.fillWidth: true
        visible: root.action === "global"
        buttonIcon: "bolt"
        textRole: "displayName"
        model: UserKeybinds.globalShortcuts.map(shortcut => ({
            name: shortcut.name,
            displayName: shortcut.description.length > 0
                ? `${shortcut.description}  ·  ${shortcut.name}`
                : shortcut.name
        }))
        onCurrentIndexChanged: root.globalName = globalPicker.model[globalPicker.currentIndex]?.name ?? ""
    }

    WindowDialogSectionHeader {
        text: Translation.tr("Description")
    }

    MaterialTextField {
        Layout.fillWidth: true
        placeholderText: Translation.tr("What it does — shown in this list")
        text: root.description
        onTextChanged: root.description = text
    }

    WindowDialogButtonRow {
        Item { Layout.fillWidth: true } // pushes the pair to the right edge (9)

        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: root.dismiss()
        }
        DialogButton {
            buttonText: Translation.tr("Add")
            enabled: root.valid
            onClicked: root.save()
        }
    }
}
