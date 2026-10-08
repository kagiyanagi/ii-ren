#!/usr/bin/env bash
# Walk the wallpaper effects for a screen recording: each one alone, then in
# combos, then each kind through a lock and unlock.
#
#   tools/showcase.sh          # a scene every 6s
#   tools/showcase.sh 10       # a scene every 10s
#   tools/showcase.sh step     # Enter moves to the next scene
#
# Asks for the login password once and types it into the lock screen with
# ydotool; it is never written anywhere. Effects are switched by editing
# config.json, which the shell watches; the original file is put back on exit,
# Ctrl+C included. Subject depth needs a baked cutout for the wallpaper: if it
# has none, the first depth scene starts the bake instead of showing it.
set -euo pipefail

CFG="$HOME/.config/illogical-impulse/config.json"
BACKUP="$(mktemp /tmp/ii-showcase-XXXXXX.json)"
TMP="$(mktemp /tmp/ii-showcase-XXXXXX.json)"
MODE="${1:-6}"

PW="${IIREN_PW:-}"
[[ -n $PW ]] || { read -rsp "Login password (for unlocking): " PW; echo; }
cp "$CFG" "$BACKUP"
# cat > rather than mv: keeps the inode the shell's file watch is on.
trap 'cat "$BACKUP" > "$CFG"; rm -f "$BACKUP" "$TMP"; echo; echo "config restored"' EXIT

set_cfg() { jq "$1" "$CFG" > "$TMP" && cat "$TMP" > "$CFG"; }
ipc() { qs -c ii ipc call "$@" >/dev/null; }

wait_scene() {
    if [[ $MODE == step ]]; then read -rp "  [Enter] next " _; else sleep "$MODE"; fi
}

scene() {  # scene "title" 'jq filter'
    echo "▸ $1"
    set_cfg "$OFF | $2"
    wait_scene
}

lock_cycle() {  # lock_cycle "title" 'jq filter'
    echo "▸ lock: $1"
    set_cfg "$OFF | $2"
    sleep 1
    ipc lock activate
    sleep 4
    ipc chargingRipple play bottomRight
    sleep 4
    ydotool type --key-delay 40 "$PW"
    ydotool key 28:1 28:0   # Enter
    sleep 4                 # unlock ripple + workspace rise
}

# Everything off, and the lock screen mirroring the desktop.
OFF='.background.effects.desktop.blur.enable = false
   | .background.effects.desktop.filter = "none"
   | .background.effects.desktop.saturation = 100
   | .background.effects.desktop.dim = 0
   | .background.effects.desktop.vignette = 0
   | .background.effects.desktop.grain = 0
   | .background.effects.lock.sync = true
   | .background.effects.glass.desktop.enable = false
   | .background.effects.glass.lock.sync = true
   | .background.weatherEffects.desktop.enable = false
   | .background.weatherEffects.desktop.followWeather = false
   | .background.weatherEffects.lock.sync = true
   | .background.depth.desktop.enable = false
   | .background.depth.lock.sync = true'

W='.background.weatherEffects.desktop'
G='.background.effects.glass.desktop'
E='.background.effects.desktop'
D='.background.depth.desktop.enable = true'

scene "clean" '.'

for fx in rain snow fog sun; do
    scene "weather: $fx" "$W.enable = true | $W.effect = \"$fx\""
done

for p in "lines lens" "lines prism" "rain contour" "chevron cascade" "bubble lens"; do
    set -- $p
    scene "fluted glass: $1 / $2" "$G.enable = true | $G.pattern = \"$1\" | $G.profile = \"$2\""
done

scene "blur: glass" "$E.blur.enable = true | $E.blur.style = \"glass\""
scene "blur: frosted" "$E.blur.enable = true | $E.blur.style = \"frosted\""
for f in grayscale sepia negative posterize pixelate chromatic radialBlur; do
    scene "filter: $f" "$E.filter = \"$f\""
done

scene "subject depth" "$D"

scene "combo: depth + rain" "$D | $W.enable = true | $W.effect = \"rain\""
scene "combo: fluted glass + snow" "$G.enable = true | $W.enable = true | $W.effect = \"snow\""
scene "combo: frosted + fog" "$E.blur.enable = true | $E.blur.style = \"frosted\" | $W.enable = true | $W.effect = \"fog\""
scene "combo: grayscale + vignette + grain + rain" "$E.filter = \"grayscale\" | $E.vignette = 40 | $E.grain = 30 | $W.enable = true | $W.effect = \"rain\""
scene "combo: depth + sun + saturation" "$D | $E.saturation = 140 | $W.enable = true | $W.effect = \"sun\""

lock_cycle "plain" '.'
lock_cycle "rain" "$W.enable = true | $W.effect = \"rain\""
lock_cycle "fluted glass" "$G.enable = true | $G.profile = \"prism\""
lock_cycle "frosted blur" "$E.blur.enable = true | $E.blur.style = \"frosted\""
lock_cycle "subject depth" "$D"
lock_cycle "depth + snow" "$D | $W.enable = true | $W.effect = \"snow\""

echo "done"
