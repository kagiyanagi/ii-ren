#!/usr/bin/env bash
# Starts the shell, and starts it again if it dies while the screen is locked.
#
# A session lock outlives its client: when qs dies under the lock, Hyprland keeps
# the session locked behind its own "lockscreen died" screen, and only a new lock
# client ends that -- LockScreen.qml takes the session back on start. Quickshell
# relaunches itself after a crash, but not after one within 10s of its own launch
# (a crash loop, it assumes), and then nothing starts that client and no keybind
# gets through. Only a TTY.
#
# Only while locked: unlocked, a crash loop is Quickshell's call and the user can
# restart it. Never after 0 (-n found an instance already running) or SIGTERM
# (pkill, `iiren run`, Super+Ctrl+R): whoever killed it starts the next one.
state="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/states.json"

# Electron-based terminals/agents can export this for their own helpers. If qs
# inherits it, every Electron app opened from the launcher runs as Node and exits.
while env -u ELECTRON_RUN_AS_NODE qs -n -c "${qsConfig:-ii}"; s=$?
    ((s != 0 && s != 143)) && grep -q '"locked": true' "$state"; do
    sleep 1
done
