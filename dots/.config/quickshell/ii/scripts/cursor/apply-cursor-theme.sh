#!/usr/bin/env bash

# apply-cursor-theme.sh
# Applies cursor theme and size across Hyprland, GTK (gsettings), and Qt/KDE.

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
II_CONFIG="$XDG_CONFIG_HOME/illogical-impulse/config.json"

target_theme=""
target_size=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --theme)
            target_theme="$2"
            shift 2
            ;;
        --size)
            target_size="$2"
            shift 2
            ;;
        --sync)
            shift
            ;;
        *)
            if [[ -z "$target_theme" ]]; then
                target_theme="$1"
            elif [[ -z "$target_size" ]]; then
                target_size="$1"
            fi
            shift
            ;;
    esac
done

# If theme or size not provided, read from config.json
if [[ -z "$target_theme" || -z "$target_size" ]] && [[ -f "$II_CONFIG" ]]; then
    if command -v jq &>/dev/null; then
        conf_theme=$(jq -r '.appearance.cursor.theme // empty' "$II_CONFIG" 2>/dev/null)
        conf_size=$(jq -r '.appearance.cursor.size // empty' "$II_CONFIG" 2>/dev/null)
        target_theme="${target_theme:-$conf_theme}"
        target_size="${target_size:-$conf_size}"
    fi
fi

# Fallback to defaults or system values
if [[ -z "$target_theme" ]]; then
    if command -v gsettings &>/dev/null; then
        target_theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
    fi
    target_theme="${target_theme:-Bibata-Modern-Classic}"
fi

if [[ -z "$target_size" ]]; then
    if command -v gsettings &>/dev/null; then
        target_size=$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null)
    fi
    target_size="${target_size:-24}"
fi

# 1. Hyprland: apply dynamically and update compositor environment
if command -v hyprctl &>/dev/null; then
    hyprctl setcursor "$target_theme" "$target_size" 2>/dev/null || true
    hyprctl eval 'hl.env("XCURSOR_SIZE", "'"$target_size"'")' 2>/dev/null || true
    hyprctl eval 'hl.env("HYPRCURSOR_SIZE", "'"$target_size"'")' 2>/dev/null || true
    hyprctl eval 'hl.env("XCURSOR_THEME", "'"$target_theme"'")' 2>/dev/null || true
    hyprctl eval 'hl.env("HYPRCURSOR_THEME", "'"$target_theme"'")' 2>/dev/null || true
fi

# 2. Systemd and D-Bus activation environments
if command -v dbus-update-activation-environment &>/dev/null; then
    dbus-update-activation-environment --systemd \
        XCURSOR_SIZE="$target_size" \
        XCURSOR_THEME="$target_theme" \
        HYPRCURSOR_SIZE="$target_size" \
        HYPRCURSOR_THEME="$target_theme" 2>/dev/null || true
fi

# 3. GTK (gsettings)
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface cursor-theme "$target_theme" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-size "$target_size" 2>/dev/null || true
fi

# 4. xsettingsd (GTK/XWayland daemon)
XSETTINGSD_CONF="$XDG_CONFIG_HOME/xsettingsd/xsettingsd.conf"
if [[ -f "$XSETTINGSD_CONF" ]]; then
    if grep -q "^Gtk/CursorThemeSize " "$XSETTINGSD_CONF"; then
        sed -i "s/^Gtk\/CursorThemeSize .*/Gtk\/CursorThemeSize $target_size/" "$XSETTINGSD_CONF" 2>/dev/null || true
    else
        echo "Gtk/CursorThemeSize $target_size" >> "$XSETTINGSD_CONF"
    fi
    if grep -q "^Gtk/CursorThemeName " "$XSETTINGSD_CONF"; then
        sed -i "s/^Gtk\/CursorThemeName .*/Gtk\/CursorThemeName \"$target_theme\"/" "$XSETTINGSD_CONF" 2>/dev/null || true
    else
        echo "Gtk/CursorThemeName \"$target_theme\"" >> "$XSETTINGSD_CONF"
    fi
    killall -HUP xsettingsd 2>/dev/null || true
fi

# 5. KDE / Qt (kdeglobals & kcminputrc)
if command -v kwriteconfig6 &>/dev/null; then
    kwriteconfig6 --file kdeglobals --group Mouse --key cursorTheme "$target_theme" 2>/dev/null || true
    kwriteconfig6 --file kdeglobals --group Mouse --key cursorSize "$target_size" 2>/dev/null || true
    kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "$target_theme" 2>/dev/null || true
    kwriteconfig6 --file kcminputrc --group Mouse --key cursorSize "$target_size" 2>/dev/null || true
fi

# 6. XCursor / XWayland default index.theme
mkdir -p "$HOME/.icons/default"
cat <<EOF > "$HOME/.icons/default/index.theme"
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=$target_theme
EOF

# 7. GTK 3.0 settings.ini
if [[ -f "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" ]]; then
    if grep -q "^gtk-cursor-theme-name=" "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"; then
        sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$target_theme/" "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" 2>/dev/null || true
    else
        sed -i "/\[Settings\]/a gtk-cursor-theme-name=$target_theme" "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" 2>/dev/null || true
    fi
    if grep -q "^gtk-cursor-theme-size=" "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"; then
        sed -i "s/^gtk-cursor-theme-size=.*/gtk-cursor-theme-size=$target_size/" "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" 2>/dev/null || true
    else
        sed -i "/\[Settings\]/a gtk-cursor-theme-size=$target_size" "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" 2>/dev/null || true
    fi
fi

# 8. Xresources / xrdb
if command -v xrdb &>/dev/null; then
    echo -e "Xcursor.theme: $target_theme\nXcursor.size: $target_size" | xrdb -merge - 2>/dev/null || true
fi

echo "Applied cursor theme: $target_theme, size: $target_size"
