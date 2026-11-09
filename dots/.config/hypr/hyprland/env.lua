local home_dir = os.getenv("HOME")

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Applications
-- Started without a login environment (greetd, a TTY on NixOS) there is no
-- XDG_DATA_DIRS to append, and "$XDG_DATA_DIRS" stayed in as literal text: then
-- the Nix profiles, where everything Home Manager installed lives, go in instead.
-- Hyprland keeps what hl.env sets, so a reload reads back last load's value: prepended
-- blindly, every reload added these four again (13 copies in a day, each one rescanned
-- by the shell whenever an app folder changed), and the login environment often has
-- them already. Each directory is kept once, so any number of reloads give one value.
local data_dirs = { home_dir .. "/.local/share/flatpak/exports/share", "/var/lib/flatpak/exports/share", "/usr/local/share", "/usr/share" }
local inherited = os.getenv("XDG_DATA_DIRS") or ""
if inherited == "" then
    for _, dir in ipairs({ home_dir .. "/.nix-profile/share", "/etc/profiles/per-user/" .. (os.getenv("USER") or "") .. "/share", "/run/current-system/sw/share" }) do
        if is_file_exists(dir) then table.insert(data_dirs, dir) end
    end
else
    for dir in inherited:gmatch("[^:]+") do table.insert(data_dirs, (dir:gsub("(.)/+$", "%1"))) end
end
local seen, unique = {}, {}
for _, dir in ipairs(data_dirs) do
    if not seen[dir] then
        seen[dir] = true
        table.insert(unique, dir)
    end
end
hl.env("XDG_DATA_DIRS", table.concat(unique, ":"))

-- Themes
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XDG_MENU_PREFIX", "plasma-")

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")
