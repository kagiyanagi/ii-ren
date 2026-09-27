#!/usr/bin/env bash
# Put the lock surface on screen without locking the screen.
#
# The only other way to look at this surface is to lock, and then the only way
# back is the user's password -- which also means no screenshot tool can reach
# it while it is up. This writes a throwaway `qs -p` config inside the shell dir
# (the `qs.` imports only resolve from there), puts LockSurface in a normal
# window over a dark backdrop, and grabs it.
#
#   tools/preview-lock.sh <out.png> [timeout-seconds] [setup-js]
#
# `setup-js` runs against `previewContext` once the surface is up, which is how
# the states that need PAM to answer get looked at without PAM:
#
#   preview-lock.sh busy.png 20 'previewContext.unlockInProgress = true'
#   preview-lock.sh armed.png 20 'previewContext.targetAction = 1'
#
# Never pkills: only the pid it started is killed, and the probe file it wrote
# is removed on exit. The probe filename carries the pid, so several can run.
set -uo pipefail

OUT="${1:?usage: preview-lock.sh <out.png> [timeout]}"
TIMEOUT="${2:-20}"
SETUP="${3:-}"
SHELL_DIR="${SHELL_DIR:-$HOME/.config/quickshell/ii}"
PROBE="$SHELL_DIR/.probe-lockpreview-$$.qml"
LOG="$(mktemp /tmp/ii-preview-lock-XXXXXX.log)"
TITLE="ii-lock-preview"

cat > "$PROBE" <<EOF
//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.panels.lock
import qs.modules.ii.lock

ApplicationWindow {
    visible: true
    width: 1280
    height: 720
    title: "$TITLE"
    color: "#101014"

    LockContext { id: previewContext }

    LockSurface {
        anchors.fill: parent
        context: previewContext
    }

    Component.onCompleted: { $SETUP }
}
EOF

trap 'rm -f "$PROBE"; kill "$PID" 2>/dev/null' EXIT

nohup qs -p "$PROBE" --no-color >"$LOG" 2>&1 &
PID=$!

for _ in $(seq "$TIMEOUT"); do
    sleep 1
    kill -0 "$PID" 2>/dev/null || { echo "FAIL: preview process exited"; tail -30 "$LOG"; exit 1; }
    geom=$(hyprctl clients -j 2>/dev/null | TITLE="$TITLE" python3 -c '
import json, os, sys
c = next((c for c in json.load(sys.stdin) if c["title"] == os.environ["TITLE"]), None)
if c:
    print("%d,%d %dx%d" % (c["at"][0], c["at"][1], c["size"][0], c["size"][1]))
')
    [ -n "$geom" ] || continue
    sleep 2   # let the entry animation settle
    grim -g "$geom" "$OUT" || { echo "FAIL: grim"; exit 1; }
    echo "ok: $OUT"
    grep -Ei 'ReferenceError|TypeError|is not a type|Unable to assign|non-existent property|Cannot assign' "$LOG" | grep -v user_widgets | sort -u | head -20
    exit 0
done

echo "FAIL: preview window never appeared in ${TIMEOUT}s [$LOG]"
tail -30 "$LOG"
exit 1
