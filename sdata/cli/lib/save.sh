#!/usr/bin/env bash

# Command: iiren save
# The reverse of an install: pulls the settings you edit outside the repo -
# through the Settings GUI and in ~/.config/hypr/custom - back into dots/, so
# `git diff` shows what you changed and you can commit it.
echo -e "${BLUE}Saving live settings into the repo...${NC}"

REPO="${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
CHANGED=0

save_file() {
    local src="$1" dest="$2"
    [ -f "$src" ] || return 0
    mkdir -p "$(dirname "$dest")"
    if cmp -s "$src" "$dest"; then return 0; fi
    cp "$src" "$dest"
    echo -e "${GREEN}  ✓ ${dest#"$REPO"/}${NC}"
    CHANGED=$((CHANGED + 1))
}

# The repo is public and installs onto other people's machines. Anything that
# still names this machine or its owner after de-personalising - a home path, an
# email, a Bluetooth address - stops the save instead of being committed.
LEAK_RE="/home/[^/\"']+|[A-Za-z0-9._+-]+(@|%40)[A-Za-z0-9-]+\.[A-Za-z.]{2,}|([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}"
leaks() {
    grep -nE "$LEAK_RE" "$1" | grep -v 'noreply' && return 0
    return 1
}

# Same as save_file, but de-personalises the copy that lands in the repo. Keys
# that only mean something on this machine are dropped, so a fresh install gets
# Config.qml's default for them: the wallpaper and photos, the weather city,
# calendar feeds (a private iCal url is a password), Bluetooth devices, the last
# VPN, the to-do file, the UI language, and which apps are pinned. Your home
# directory goes back to "~" so the rest installs as the next person's paths.
save_config() {
    local src="$1" dest="$2" tmp
    [ -f "$src" ] || return 0
    tmp="$(mktemp)"
    jq --indent 4 'del(
            .background.wallpaperPath, .background.thumbnailPath, .background.depth.declined,
            .bar.weather.city, .calendar.icsUrls, .bluetooth.fastPair.ignoredDevices,
            .networking.vpn.last, .todo.filePath, .language.ui,
            .dock.pinnedApps, .dock.pinnedFiles, .dock.folders, .tray.pinnedItems,
            .launcher.pinnedApps, .sidebar.booru.gelbooru, .update.scriptPath)
        | walk(if type == "object" then del(.imagePath, .cachedRandomQuote, .cachedRandomAuthor) else . end)' \
        "$src" | sed -e "s|\"$HOME/|\"~/|g" -e "s|\"file://$HOME/|\"file://~/|g" > "$tmp"
    if leaks "$tmp"; then
        echo -e "${RED}  ✗ ${dest#"$REPO"/} not saved: the lines above are personal. Drop that key in save.sh.${NC}"
    else
        save_file "$tmp" "$dest"
    fi
    rm -f "$tmp"
    [ -f "$dest" ] && chmod 644 "$dest" || true
}

save_config "$HOME/.config/illogical-impulse/config.json" \
            "$REPO/dots/.config/illogical-impulse/config.json"

# private.lua is for what only this machine has - its own apps, paths, scripts.
# Hyprland loads it after the other custom files; it never reaches the repo.
for f in "$HOME"/.config/hypr/custom/*.lua; do
    [ -e "$f" ] || continue
    [ "$(basename "$f")" = private.lua ] && continue
    if leaks "$f"; then
        echo -e "${RED}  ✗ $f not saved: move the lines above into custom/private.lua.${NC}"
        continue
    fi
    save_file "$f" "$REPO/dots/.config/hypr/custom/$(basename "$f")"
done

if [ "$CHANGED" -eq 0 ]; then
    echo -e "${GREEN}✓ Nothing changed - the repo already matches your live setup.${NC}"
else
    echo ""
    echo -e "${GREEN}✓ $CHANGED file(s) updated. Review and commit:${NC}"
    echo -e "${BLUE}    cd $REPO && git diff${NC}"
fi
