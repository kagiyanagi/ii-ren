#!/usr/bin/env bash

# apply-icon-theme.sh
# Applies and synchronizes icon packs across KDE (Dolphin, kdeglobals) and GTK (gsettings).

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
KDE_MYC_CONF="$XDG_CONFIG_HOME/kde-material-you-colors/config.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

light_theme=""
dark_theme=""
target_theme=""
mode=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --theme)
            target_theme="$2"
            shift 2
            ;;
        --light)
            light_theme="$2"
            shift 2
            ;;
        --dark)
            dark_theme="$2"
            shift 2
            ;;
        --mode)
            mode="$2"
            shift 2
            ;;
        --sync)
            shift
            ;;
        *)
            # Positional argument treated as target theme
            target_theme="$1"
            shift
            ;;
    esac
done

# Read existing themes from kde-material-you-colors config if not provided
if [[ -f "$KDE_MYC_CONF" ]]; then
    existing_light=$(awk -F'=' '/^[[:space:]]*iconslight[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); print $2}' "$KDE_MYC_CONF")
    existing_dark=$(awk -F'=' '/^[[:space:]]*iconsdark[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); print $2}' "$KDE_MYC_CONF")
fi

light_theme="${light_theme:-${existing_light:-breeze-plus}}"
dark_theme="${dark_theme:-${existing_dark:-breeze-plus-dark}}"

# Detect current mode if not specified
if [[ -z "$mode" ]]; then
    current_scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
    if [[ "$current_scheme" == "prefer-dark" ]]; then
        mode="dark"
    else
        mode="light"
    fi
fi

# Determine target theme
if [[ -z "$target_theme" ]]; then
    if [[ "$mode" == "dark" ]]; then
        target_theme="$dark_theme"
    else
        target_theme="$light_theme"
    fi
fi

# Function to update or add key in config file
update_conf_key() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    [[ ! -f "$file" ]] && return
    
    if grep -q "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
        sed -i "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
    elif grep -q "\[CUSTOM\]" "$file"; then
        sed -i "/\[CUSTOM\]/a ${key} = ${value}" "$file"
    else
        echo -e "\n[CUSTOM]\n${key} = ${value}" >> "$file"
    fi
}

# Auto-recolor non-native themes to match system wallpaper color
resolve_and_recolor_theme() {
    local theme="$1"
    [[ -z "$theme" ]] && return

    # Breeze family has native dynamic support built-in
    if [[ "$theme" =~ ^[Bb]reeze ]]; then
        echo "$theme"
        return
    fi

    local base_name="${theme%-Dynamic}"
    local recolor_bin=""
    if [ -x "$SCRIPT_DIR/../icons/recolor-icon-theme" ]; then
        recolor_bin="$SCRIPT_DIR/../icons/recolor-icon-theme"
    elif [ -x "$HOME/.local/bin/recolor-icon-theme" ]; then
        recolor_bin="$HOME/.local/bin/recolor-icon-theme"
    fi

    if [ -n "$recolor_bin" ]; then
        "$recolor_bin" "$base_name" >/dev/null 2>&1
        if [ -d "$HOME/.local/share/icons/${base_name}-Dynamic" ]; then
            echo "${base_name}-Dynamic"
            return
        fi
    fi

    echo "$theme"
}

effective_target=$(resolve_and_recolor_theme "$target_theme")
effective_light=$(resolve_and_recolor_theme "$light_theme")
effective_dark=$(resolve_and_recolor_theme "$dark_theme")

# Persist to kde-material-you-colors configuration
if [[ -n "$effective_light" ]]; then
    update_conf_key "$KDE_MYC_CONF" "iconslight" "$effective_light"
fi
if [[ -n "$effective_dark" ]]; then
    update_conf_key "$KDE_MYC_CONF" "iconsdark" "$effective_dark"
fi

# Apply to KDE (Dolphin and Qt apps)
if command -v kwriteconfig6 &>/dev/null; then
    kwriteconfig6 --file kdeglobals --group Icons --key Theme "$effective_target"
fi

# Apply to GNOME / GTK
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface icon-theme "$effective_target" 2>/dev/null || true
fi

# Notify KDE applications (KIconLoader in Dolphin, etc.)
if command -v qdbus6 &>/dev/null; then
    qdbus6 org.kde.KGlobalSettings /KGlobalSettings org.kde.KGlobalSettings.notifyChange 2 0 2>/dev/null || true
fi

echo "Applied icon theme: $effective_target (light: $effective_light, dark: $effective_dark, mode: $mode)"
