#!/usr/bin/env bash
# Start the settings app and fail unless its window appears and its log is clean.
#
# smoke.sh covers `qs -c ii` -- the shell. The settings app is a SECOND quickshell
# process (`qs -p .../settings.qml`, its own QApplication), so nothing smoke.sh does
# touches it: a settings page that fails to load leaves the shell perfectly healthy.
# Every modules/settings row needs this gate as well as that one.
#
#   tools/audit/smoke-settings.sh [timeout-seconds]      default 25
#
# It never pkills anything -- `pkill -x qs` would take the running shell down with it.
# Only the process this script started is killed, by pid.
set -uo pipefail

TIMEOUT="${1:-25}"
SETTINGS="${SETTINGS_QML:-$HOME/.config/quickshell/ii/settings.qml}"
LOG="$(mktemp /tmp/ii-smoke-settings-XXXXXX.log)"

[ -f "$SETTINGS" ] || { echo "FAIL: no settings.qml at $SETTINGS"; exit 1; }

nohup qs -p "$SETTINGS" --no-color >"$LOG" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null' EXIT

titles() { hyprctl clients -j 2>/dev/null | grep -o '"title": "[^"]*"'; }

for _ in $(seq "$TIMEOUT"); do
    sleep 1
    kill -0 "$PID" 2>/dev/null || { echo "FAIL: settings process exited"; tail -30 "$LOG"; exit 1; }
    titles | grep -qi 'settings' || continue
    # The window is up. QML errors here are non-fatal to the process but fatal to the
    # page: a sub-page that fails to load leaves an empty pane and says so only in the log.
    errs="$(grep -Ei 'ReferenceError|TypeError|is not a type|Unable to assign|non-existent property|Syntax error|No such file' "$LOG" | grep -v user_widgets || true)"
    if [ -n "$errs" ]; then
        echo "FAIL: settings window up, but its log is not clean [$LOG]"
        printf '%s\n' "$errs" | head -20
        exit 1
    fi
    echo "ok: settings window up, log clean"
    exit 0
done

echo "FAIL: no settings window within ${TIMEOUT}s"
tail -30 "$LOG"
exit 1
