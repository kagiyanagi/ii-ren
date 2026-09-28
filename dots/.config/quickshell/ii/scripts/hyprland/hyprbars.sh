#!/usr/bin/env bash
# Makes hyprbars (hyprwm/hyprland-plugins) loaded in the running Hyprland: floating
# mode's title bars are drawn by it, inside the compositor, so they move, open and
# close in the same frame as their window. FloatingMode.qml runs this; exit 0 means
# the plugin is loaded, anything else and the shell draws its own bars instead.
#
# A plugin is built against one exact Hyprland, so the build is keyed on the running
# Hyprland's commit and redone after an update. hyprpm.toml pins the plugin commit
# for each release; a Hyprland newer than the last pin tries the plugins' head, and
# a mismatched build is refused by the plugin's own version check, never loaded.
#
# hyprbars.patch lets a title drag bring a maximized window out under the pointer
# first (floatingMode.lua, before_drag). It is part of the key too. If it no longer
# applies to the pinned plugin, the plugin is built without it: bars still work, and a
# maximized window is dragged at its full size.
set -euo pipefail

loaded() { hyprctl plugin list 2>/dev/null | grep -q "Plugin hyprbars"; }

out="${XDG_DATA_HOME:-$HOME/.local/share}/ii-ren/hyprbars"
src="${XDG_CACHE_HOME:-$HOME/.cache}/ii-ren/hyprland-plugins"
patch="$(dirname "$(readlink -f "$0")")/hyprbars.patch"
commit=$(hyprctl version -j | jq -r .commit)
key="$commit $(sha1sum < "$patch" | cut -c1-12)"
fresh=$([[ -f $out/hyprbars.so && $(cat "$out/built-for" 2>/dev/null) == "$key" ]] && echo 1 || true)

loaded && [[ $fresh ]] && exit 0

if [[ ! $fresh ]]; then
    if [[ -d $src/.git ]]; then
        git -C "$src" fetch -q origin
    else
        git clone -q https://github.com/hyprwm/hyprland-plugins "$src"
    fi
    pin=$(git -C "$src" show origin/HEAD:hyprpm.toml | grep -F "\"$commit\"" | sed -E 's/.*", "([0-9a-f]+)".*/\1/' || true)
    git -C "$src" checkout -q -f --detach "${pin:-origin/HEAD}"
    git -C "$src" apply "$patch" 2>/dev/null || echo "hyprbars.sh: $patch does not apply; building without it" >&2
    rm -f "$src/hyprbars/hyprbars.so" # make trusts its timestamp over a checkout's
    make -C "$src/hyprbars" all >/dev/null 2>&1
    git -C "$src" checkout -q -- .
    mkdir -p "$out"
    # By rename, never over the file: the running compositor has the old one mapped, and
    # writing into a mapped library takes the session down with it.
    cp "$src/hyprbars/hyprbars.so" "$out/hyprbars.so.new"
    mv -f "$out/hyprbars.so.new" "$out/hyprbars.so"
    echo "$key" > "$out/built-for"
fi

# An older build still loaded goes first. Unloading clears its buttons and the effect its
# rules name; the shell declares both again once the flags that say they are there are gone.
if loaded; then
    hyprctl plugin unload "$out/hyprbars.so" >/dev/null
    hyprctl eval "ii_fm_buttons, ii_fm_bars_untagged, ii_fm_bars_tiled = nil, nil, nil" >/dev/null
fi
hyprctl plugin load "$out/hyprbars.so" >/dev/null
loaded
