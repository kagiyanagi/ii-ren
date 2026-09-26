# ii-sidebarDashboard-wifiNetworks — brief

**Purpose.** Get this machine onto a Wi-Fi network: see what is in range, join one, and
type its password when it has one.

**Primary action.** Tap a row. A saved or open network connects. A secured network with
no saved profile opens its password field *first*, as in Android 16's Internet dialog.
Before, every tap ran `nmcli dev wifi connect` straight away. On an unknown secured
network that took the adapter off the current network, failed on "Secrets were
required", and only then asked for the password, so the machine was offline while you
typed it. Tapping the connected row ran the connect again and bounced the link.

**Hierarchy.** Title, then the scan bar, then the list card: the connected network, then
the rest by signal, in the order `Network` already sorts them. The connected network's
icon is in primary colour. Under each name is one status line saying what the network is
doing now: "Connected", "Connecting…", "Saved", or how the last attempt failed. The
Bluetooth dialog's row, so the two sidebar radio dialogs read as one. The power-saving
card, then Details and Done, as before.

**Reference.** Android 16 SystemUI `InternetDialog`: the row is the action, the active
network is marked in primary, and a new secured network asks for its password before
anything disconnects. The sibling is `bluetoothDevices`, which set the status line and
the busy-row rule.

**Interaction.** The row is `DialogListItem` and keeps its four states and its
`elementMove` height change, which is what opens the password field. A row that a tap
cannot act on (connected, connecting, or another connect already running) does not
ripple and has no pointing hand. A busy row stays at full opacity: 0.4 means disabled
(rule 6), and this row is working. The Bluetooth notes asked for exactly this. The icon
and status colours move on `elementMoveFast`. The password field gets focus when it
opens. It has the hotspot dialog's trailing reveal button, and Connect is disabled until
the password is long enough for the network's security (8 for WPA). `StyledListView`
replaces the bare `ListView`, so a re-sort slides rows rather than cutting them.

**Edge states.**
- *Connecting*: said in the status line; taps are ignored until the attempt ends.
- *Wrong password*: the field reopens, and the status line says "Wrong password" in
  error colour. That is also what a saved network whose password changed shows.
- *Other failure* (out of range, DHCP, timeout): "Couldn't connect" in error colour. It
  no longer opens a password field on an open network.
- *Empty*: "Searching for networks" while the scan runs, "No networks found" after it,
  "Wi-Fi is off" when the radio is off. Before, the card was blank.
- *One network*: the card fits its rows. It was a fixed 600px dialog, and with four
  networks in range, a third of the card was empty.

**Cost.** None. No effects. The `ClippingRectangle` stays the one clip.

**Delete.** The fixed `backgroundHeight: 600`. The trailing "check" and
"settings_ethernet" glyphs, which the status line replaces. `Network.changePassword()` and
its process: it modified a profile named after the SSID, which misses any profile NM had
named "SSID 1", and then re-ran the connect with its target already nulled, so the retry
threw in both handlers and never said whether the password worked. One
`nmcli dev wifi connect SSID password …` does both: nmcli updates a matching profile's
secret, or creates one.

**Out of scope.** Forget and Disconnect, which Details opens the network manager for.
WPA-Enterprise, which nmcli cannot create. The "Open network portal" button. Waffle's
`WWifiNetworkItem`, which gets the service fixes (no dropped link on an unknown secured
network) but still has no password field of its own.
