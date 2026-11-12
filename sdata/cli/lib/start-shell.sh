#!/usr/bin/env bash
# A daemon/nohup still belongs to its caller's systemd cgroup. An agent or
# terminal being stopped would kill the desktop too. Let the user manager own it.
set -euo pipefail

options=(--user --collect --quiet --service-type=exec)
for key in PATH WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS; do
    if [[ -v "$key" ]]; then
        options+=("--setenv=$key=${!key}")
    fi
done

if [[ -n "${1:-}" ]]; then
    options+=("--property=StandardOutput=append:$1" --property=StandardError=inherit)
fi

exec systemd-run "${options[@]}" env -u ELECTRON_RUN_AS_NODE qs -n -c ii --no-color
