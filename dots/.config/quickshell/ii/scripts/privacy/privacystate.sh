#!/bin/bash
# Who is using location, as one JSON line per state change. The microphone
# comes straight from Pipewire in QML, so there is nothing to poll for it here.

PARENT=$PPID
LAST=""

while true; do
    # Quickshell doesn't reap us when it's killall'd; without this, every shell
    # restart leaks another copy of this poll loop.
    kill -0 "$PARENT" 2>/dev/null || exit 0

    # Asking GeoClue for a property would D-Bus-activate it, so only ask when
    # it is already up.
    inuse=false
    apps="[]"
    if busctl --system call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus NameHasOwner s org.freedesktop.GeoClue2 2>/dev/null | grep -q "b true" &&
        busctl --system get-property org.freedesktop.GeoClue2 /org/freedesktop/GeoClue2/Manager \
            org.freedesktop.GeoClue2.Manager InUse 2>/dev/null | grep -q "b true"; then

        # GeoClue only lets a client read its own DesktopId, so name the
        # clients by who has a geoclue library mapped instead. Apps that talk
        # to GeoClue over raw D-Bus stay anonymous.
        inuse=true
        found=""
        for maps in $(grep -l geoclue /proc/[0-9]*/maps 2>/dev/null); do
            pid=${maps#/proc/}
            pid=${pid%/maps}
            # The agent is GeoClue's own permission prompt, not a consumer.
            case "$(readlink "/proc/$pid/exe" 2>/dev/null)" in *geoclue*) continue ;; esac
            comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
            found+="$comm $pid"$'\n'
        done
        apps=$(printf '%s' "$found" | jq -Rc '{name: split(" ")[0], pid: (split(" ")[1] | tonumber)}' | jq -sc .)
    fi

    state="{\"location\":$inuse,\"apps\":$apps}"
    if [ "$state" != "$LAST" ]; then
        echo "$state"
        LAST="$state"
    fi

    sleep 2
done
