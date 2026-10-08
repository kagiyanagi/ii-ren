#!/usr/bin/env bash
# Instantiate every settings sub-page at once and fail if any of them complains.
#
# smoke-settings.sh proves the settings app opens. It proves nothing about the 70
# sub-pages, because every one of them is loaded on demand -- a page that throws
# leaves an empty pane and says so only in a log nobody reads. The documented
# alternative was "click the five entry points by hand", which is not a gate.
#
# This builds a throwaway quickshell config inside the shell dir (the `qs.` imports
# only resolve from there), puts every ContentPage-rooted file under
# modules/settings/widgets into one Repeater, and greps the log.
#
#   tools/probe-settings-pages.sh [timeout-seconds]      default 25
#
# Like smoke-settings.sh it never pkills: only the pid it started is killed, and
# the probe file it wrote is removed on exit. Safe to run several at once -- the
# probe filename carries the pid.
set -uo pipefail

TIMEOUT="${1:-25}"
SHELL_DIR="${SHELL_DIR:-$HOME/.config/quickshell/ii}"
PAGES_DIR="$SHELL_DIR/modules/settings/widgets"
PROBE="$SHELL_DIR/.probe-settings-$$.qml"
LOG="$(mktemp /tmp/ii-probe-pages-XXXXXX.log)"

[ -d "$PAGES_DIR" ] || { echo "FAIL: no $PAGES_DIR"; exit 1; }

# A sub-page is a ContentPage-rooted file, or any file declaring `signal goBack`
# -- the contract ConfigSubPageHost loads against, which catches the Item-rooted
# pages a root-type match misses. The union matters: a page that adopts
# ContentPage's own header stops declaring the signal, and a signal-only selector
# would quietly drop it from the gate. The other live files in this directory are
# blocks and overlays that only make sense with properties set by a parent.
# Plus the live pages that are neither: the Widgets tab contents, which
# WidgetsConfig.qml loads by type. sw-extensions found that
# ExtensionWidgetSettingsRenderer had been assigning three properties
# cw-config-rows removed, so the extension settings overlay rendered nothing --
# and no gate in this repo would have said so, because nothing instantiates
# these three.
EXTRA=(WidgetExtensionsContent.qml ExtensionWidgetSettingsRenderer.qml)

mapfile -t PAGES < <({ grep -lE '^ContentPage \{' "$PAGES_DIR"/*.qml
                       grep -lE '^\s*signal goBack\b' "$PAGES_DIR"/*.qml
                       for e in "${EXTRA[@]}"; do [ -f "$PAGES_DIR/$e" ] && echo "$PAGES_DIR/$e"; done; } |
                     xargs -n1 basename | sort -u)
[ "${#PAGES[@]}" -gt 0 ] || { echo "FAIL: no sub-pages found"; exit 1; }

list=$(printf '"%s",' "${PAGES[@]}")
# settings.qml's own qs. imports, so a page sees exactly the types it would there:
# Quickshell registers a directory's types only once something imports it as a
# module, and the widget config pages lean on that for their siblings.
imports=$(grep -E '^import qs\.' "$SHELL_DIR/settings.qml")

cat > "$PROBE" <<EOF
//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
$imports

ApplicationWindow {
    id: probeRoot
    visible: true
    width: 800
    height: 600
    title: "ii-probe-pages"

    readonly property var pages: [${list%,}]

    Column {
        Repeater {
            model: probeRoot.pages
            Loader {
                width: 700
                height: 400
                source: Qt.resolvedUrl("modules/settings/widgets/" + modelData)
                onStatusChanged: {
                    if (status === Loader.Error)
                        console.error("PROBE_LOAD_ERROR: " + modelData);
                }
            }
        }
    }
}
EOF

trap 'rm -f "$PROBE"; kill "$PID" 2>/dev/null' EXIT

nohup qs -p "$PROBE" --no-color >"$LOG" 2>&1 &
PID=$!

titles() { hyprctl clients -j 2>/dev/null | grep -o '"title": "[^"]*"'; }

for _ in $(seq "$TIMEOUT"); do
    sleep 1
    kill -0 "$PID" 2>/dev/null || { echo "FAIL: probe process exited"; tail -30 "$LOG"; exit 1; }
    titles | grep -q 'ii-probe-pages' || continue
    sleep 2   # the Repeater creates every page after the window is up
    errs="$(grep -Ei 'PROBE_LOAD_ERROR|ReferenceError|TypeError|is not a type|Unable to assign|non-existent property|Syntax error|No such file|Duplicate|Cannot assign' "$LOG" | grep -v user_widgets || true)"
    if [ -n "$errs" ]; then
        echo "FAIL: ${#PAGES[@]} pages instantiated, log is not clean [$LOG]"
        printf '%s\n' "$errs" | sort -u | head -30
        exit 1
    fi
    echo "ok: ${#PAGES[@]} settings sub-pages instantiated, log clean"
    exit 0
done

echo "FAIL: probe window never appeared in ${TIMEOUT}s [$LOG]"
tail -30 "$LOG"
exit 1
