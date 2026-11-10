hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )
hl.bind("SUPER + escape", hl.dsp.global("quickshell:settingsToggle"), {description = "Toggle settings"})
-- hyprland/keybinds.lua binds this to previous track, and Hyprland runs every bind on a key.
hl.unbind("SUPER + SHIFT + B")
hl.bind("SUPER + SHIFT + B", hl.dsp.global("quickshell:agentDictate"), {description = "Agent: dictate"})
