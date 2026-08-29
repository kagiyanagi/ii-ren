#!/bin/bash
# Camera, screen sharing and location users, as one JSON line per state change.
# The microphone comes straight from Pipewire in QML, so it isn't polled here.

PARENT=$PPID
LAST=""

# A video consumer says nothing about what it is consuming, so follow its
# driver back to the source: a v4l2/Camera source is the webcam, anything else
# (the desktop portal) is a screen cast.
VIDEO_JQ='
  [.[] | select((.info.props."media.class" // "") == "Video/Source")] as $srcs
  | [.[] | select((.info.props."media.class" // "") == "Stream/Input/Video" and .info.state == "running")]
  | map(. as $c
      | (first($srcs[] | select(.id == ($c.info.props."node.driver-id" // $c.info.props."node.target")))) as $s
      | {name: ($c.info.props."node.name" // $c.info.props."application.name" // "?"),
         pid: ($c.info.props."application.process.id" // 0),
         kind: (if (($s.info.props."media.role" // "") == "Camera") or (($s.info.props."device.api" // "") == "v4l2")
                then "camera" else "screen" end)})'

while true; do
    # Quickshell doesn't reap us when it's killall'd; without this, every shell
    # restart leaks another copy of this poll loop.
    kill -0 "$PARENT" 2>/dev/null || exit 0

    video=$(pw-dump 2>/dev/null | jq -c "$VIDEO_JQ" 2>/dev/null) || video="[]"
    [ -n "$video" ] || video="[]"

    # Apps that open the device themselves never appear as a Pipewire stream.
    direct=""
    for pid in $(fuser /dev/video* 2>/dev/null); do
        comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
        # These hold the device on behalf of whoever asked through Pipewire,
        # and that app is already in the stream list above.
        case "$comm" in pipewire | wireplumber | pipewire-pulse) continue ;; esac
        direct+="$comm $pid"$'\n'
    done
    direct=$(printf '%s' "$direct" | sort -u -k2,2 |
        jq -Rc '{name: split(" ")[0], pid: (split(" ")[1] | tonumber), kind: "camera"}' | jq -sc .)

    cameras=$(jq -nc --argjson a "$video" --argjson b "$direct" \
        '[$a[], $b[]] | map(select(.kind == "camera")) | unique_by(.name) | map(del(.kind))')
    screens=$(jq -nc --argjson a "$video" '$a | map(select(.kind == "screen")) | map(del(.kind))')

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

    state="{\"camera\":$cameras,\"screen\":$screens,\"location\":$inuse,\"apps\":$apps}"
    if [ "$state" != "$LAST" ]; then
        echo "$state"
        LAST="$state"
    fi

    sleep 2
done
