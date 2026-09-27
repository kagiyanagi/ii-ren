#!/usr/bin/env bash
# Start the shell and fail unless its surfaces actually appear on screen.
#
# ~/.config/quickshell/ii is a symlink into this repo, so whatever is committed IS
# the running desktop. A commit that does not boot is an outage, not a stopping
# point -- this is the gate that proves a change boots.
#
#   tools/smoke.sh [timeout-seconds]      default 30
#
# On failure: `git checkout .` restores the last good shell, then re-run.
#
# Why layers and not the log: a QML type error that blanks the entire panel family
# prints NOTHING to stdout and nothing to `qs log` -- verified by deliberately
# breaking IllogicalImpulseFamily.qml. The only reliable signal that the shell came
# up is that its layer surfaces exist. Layers take ~8s to appear here, so this polls.
set -uo pipefail

TIMEOUT="${1:-30}"
WANT="${SMOKE_WANT:-quickshell:bar}"
LOG="$(mktemp /tmp/ii-smoke-XXXXXX.log)"

layers() { hyprctl layers 2>/dev/null | sed -n 's/.*namespace: \([^,]*\).*/\1/p' | sort -u; }

pkill -x qs 2>/dev/null
sleep 0.5
nohup qs -c ii --no-color >"$LOG" 2>&1 &

for _ in $(seq "$TIMEOUT"); do
    sleep 1
    pgrep -x qs >/dev/null || { echo "FAIL: shell process exited"; tail -30 "$LOG"; exit 1; }
    if layers | grep -qx "$WANT"; then
        echo "ok: shell up, surfaces present [$(layers | tr '\n' ' ')]"
        errs="$(grep -Ei 'ReferenceError|TypeError|is not a type|Unable to assign|non-existent property|Syntax error' "$LOG" | grep -v user_widgets || true)"
        [ -n "$errs" ] && { echo "note: non-fatal errors in log [$LOG]"; printf '%s\n' "$errs" | head -10; }
        exit 0
    fi
done

echo "FAIL: '$WANT' never appeared within ${TIMEOUT}s -- the shell is up but not rendering"
echo "      present: [$(layers | tr '\n' ' ')]"
tail -30 "$LOG"
exit 1
