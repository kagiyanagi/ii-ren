local home_dir = os.getenv("HOME")

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Applications
-- Started without a login environment (greetd, a TTY on NixOS) there is no
-- XDG_DATA_DIRS to append, and "$XDG_DATA_DIRS" stayed in as literal text: then
-- the Nix profiles, where everything Home Manager installed lives, go in instead.
local inherited = os.getenv("XDG_DATA_DIRS") or ""
if inherited == "" then
    for _, dir in ipairs({ home_dir .. "/.nix-profile/share", "/etc/profiles/per-user/" .. (os.getenv("USER") or "") .. "/share", "/run/current-system/sw/share" }) do
        if is_file_exists(dir) then inherited = inherited .. ":" .. dir end
    end
else
    inherited = ":" .. inherited
end
hl.env("XDG_DATA_DIRS", home_dir .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share" .. inherited)

-- Themes
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XDG_MENU_PREFIX", "plasma-")

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")
