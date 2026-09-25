#!/usr/bin/env bash
# Wi-Fi power saving, behind the switch in the Wi-Fi dialog.
#
#   wifi-powersave.sh get        on/off for the first managed interface, no root
#   wifi-powersave.sh install    as root: copies this file to $BIN and lets the
#                                active session run that copy without a password
#   ii-wifi-powersave on|off     as root, through pkexec
#
# The choice is kept where NetworkManager reads it, not where the shell does:
# NM applies wifi.powersave on every activation, so it outlives shell restarts,
# reboots and reconnects. NM cannot re-apply it to a live connection -- the iwd
# backend refuses a reapply of any 802-11-wireless key -- so `iw` sets it now.
set -u

BIN=/usr/local/bin/ii-wifi-powersave
POLICY=/usr/share/polkit-1/actions/org.iiren.wifi-powersave.policy
CONF=/etc/NetworkManager/conf.d/ii-wifi-powersave.conf

# P2P and AP interfaces have no station power save to set.
managed() { iw dev | awk '$1 == "Interface" { i = $2 } $1 == "type" && $2 == "managed" { print i }'; }

case "${1-}" in
get)
    # Prints nothing, which greys the switch out, wherever `on`/`off` could
    # not take: nothing to escalate with, no station, or NM not running or not
    # managing it (its config is where the choice is kept). A driver without
    # power save fails `iw` here too.
    command -v pkexec >/dev/null || exit 1
    i=$(managed | head -n1)
    [ -n "$i" ] || exit 1
    state=$(nmcli -g GENERAL.STATE dev show "$i" 2>/dev/null) || exit 1
    case $state in *unmanaged*) exit 1 ;; esac
    iw dev "$i" get power_save | awk '{ print $3 }'
    ;;
on | off)
    # 3 enables, 2 disables (nm-settings(5), 802-11-wireless.powersave).
    mkdir -p "${CONF%/*}"
    printf '[connection]\nwifi.powersave = %s\n' "$([ "$1" = on ] && echo 3 || echo 2)" >"$CONF"
    # TLP sets power save itself on every charger plug and unplug, defaults
    # included; 99 is read last, so its own config cannot win it back.
    [ -d /etc/tlp.d ] && printf 'WIFI_PWR_ON_AC=%s\nWIFI_PWR_ON_BAT=%s\n' "$1" "$1" >/etc/tlp.d/99-ii-wifi-powersave.conf
    nmcli general reload conf
    for i in $(managed); do iw dev "$i" set power_save "$1"; done
    ;;
install)
    install -Dm755 "$0" "$BIN"
    cat >"$POLICY" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <action id="org.iiren.wifi-powersave">
    <description>Switch Wi-Fi power saving</description>
    <message>Authentication is required to switch Wi-Fi power saving</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>yes</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">$BIN</annotate>
  </action>
</policyconfig>
EOF
    ;;
*)
    echo "usage: $0 get | on | off | install" >&2
    exit 2
    ;;
esac
