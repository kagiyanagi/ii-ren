#!/bin/bash
# GeoClue on/off. It is D-Bus activated, so stopping it is pointless: masking
# is the only thing that keeps it from coming straight back on the next
# request. GeoClue locates by WiFi/IP with no GPS chip at all, so the switch is
# offered wherever it is installed, not just on machines with a GNSS device.

case "$1" in
status)
    state=$(systemctl is-enabled geoclue.service 2> /dev/null)
    [ -n "$state" ] && present=true || present=false
    [ "$state" = "masked" ] && enabled=false || enabled=true
    echo "{\"present\":$present,\"enabled\":$enabled}"
    ;;
enable)
    systemctl unmask geoclue.service
    ;;
disable)
    systemctl mask --now geoclue.service
    ;;
esac
