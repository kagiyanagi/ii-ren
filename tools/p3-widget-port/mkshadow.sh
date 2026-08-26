#!/usr/bin/env bash
# Build a qmllint shadow tree for the shell: real qmldir files + symlinked sources.
# Quickshell auto-registers directory modules and injects a synthetic `qs`; qmllint
# does neither, so it needs this.
set -euo pipefail
SRC="${1:-/home/ren/Code/ii-ren/dots/.config/quickshell/ii}"
OUT="${2:?usage: mkshadow.sh <shell-dir> <shadow-dir>}"
rm -rf "$OUT"; mkdir -p "$OUT"
cd "$SRC"
find . -type d -not -path '*/.git*' | while read -r d; do
    mkdir -p "$OUT/qs/$d"
    mod="qs$(printf '%s' "${d#.}" | tr '/' '.')"
    printf 'module %s\n\n' "$mod" > "$OUT/qs/$d/qmldir"
    for f in "$d"/*.qml; do
        [ -e "$f" ] || continue
        n=$(basename "$f" .qml)
        case "$n" in [a-z]*) continue ;; esac   # lowercase files are not types
        pre=""; grep -q '^pragma Singleton' "$f" && pre="singleton "
        printf '%s%s 1.0 %s.qml\n' "$pre" "$n" "$n" >> "$OUT/qs/$d/qmldir"
        ln -sf "$SRC/${f#./}" "$OUT/qs/$d/$n.qml"
    done
    for f in "$d"/*.js; do
        [ -e "$f" ] || continue
        ln -sf "$SRC/${f#./}" "$OUT/qs/$d/$(basename "$f")"
    done
done
