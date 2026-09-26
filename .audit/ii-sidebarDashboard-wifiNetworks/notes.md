# ii-sidebarDashboard-wifiNetworks — notes

**Opening it.** `qs -c ii ipc call sidebarRight openDialog Wifi`. Opening it turns the radio
on and starts a rescan, which it did before this row too.

**No connection was ever attempted live.** The machine's only adapter carries the
session's uplink (`Excitel_ansh_5g`), and every `nmcli dev wifi connect` takes it off
that network first. So "Connecting…", "Wrong password", "Couldn't connect" and a
successful join were not seen. `check-wifi-dialog.py` evaluates the tap decision, the exit
handler and the status line under node. What was driven with real clicks: a tap on an
unsaved secured network (`www.excitel.com`) opens the field, focused, **with the machine
still on its network** (checked with `nmcli` after each tap). Connect stays disabled below
8 characters. The reveal button works. Cancel fades the field out and then collapses the
row.

**The nmcli facts this rests on**, read from `src/nmcli/devices.c` on NM main (1.58 is
installed):
- `dev wifi connect SSID password P` finds an available profile that matches the AP. If it
  finds one, it writes the psk into that profile (`nm_remote_connection_update2`) and
  activates it. If not, it creates one. So a wrong saved password and a first join are the
  same command.
- nmcli never deletes a profile whose activation failed. That is why the old
  "connect → Secrets were required → modify → retry" dance could have worked. But the
  retry ran `connectProc` again after `wifiConnectTarget` had been nulled, so both
  handlers threw on `null.askingPassword`.
- A wrong psk comes back as "Secrets were required, but not provided", because NM asks for
  the secret again and no agent answers. That is what "Wrong password" keys on.

**Saved profiles** are read as `nmcli -g UUID,TYPE connection show | … | xargs nmcli -g
802-11-wireless.ssid connection show`: one process pair, on each rescan and after each
attempt. Nothing re-reads them when a profile is deleted elsewhere while the dialog is
open. The next open catches it. The password sits in nmcli's argv while it runs, which the
old `connection modify` also did. nmcli has no stdin form for `dev wifi connect`, and
this is marked `ponytail:` in the service.

**`RippleButton` changed (shared, rule 9).** A press started a ripple while the row was
tappable. The click then made the row untappable, and the release skipped the fade
because `rippleEnabled` was false by then, so the ripple stayed at full opacity. The
Bluetooth row's pair tap hits the same thing. The fade now runs on every release and
cancel. With no ripple running it animates an opacity that is already 0, so no caller that
never ripples can change.

**Rows are keyed on SSID.** `getNetworks` already dedupes by SSID. The old key (SSID +
BSSID + band) destroyed the row whenever a scan picked a different access point, and scans
here drop networks in and out constantly: `Excitel_ansh_2.4` and `www.excitel.com`
each vanished from one scan to the next during the session. That took the password
field away mid-typing (seen live, before the fix). A network that is asking for a password,
or connecting, now outlives a scan that missed it.

**Waffle.** `WWifiNetworkItem` calls the same `connectToWifiNetwork`. Tapping Connect on an
unsaved secured network there now does nothing visible, because it sets `askingPassword`
and waffle has no field. Before, it also dropped the uplink first. Giving waffle a password
field is its own row.

**Height: fixed while open, scaled with the screen — the owner's call.** The first
version fitted the card to its rows. That re-centred the card on every scan and whenever
the password field opened or closed, and moved the rows under the pointer (about 57px at
1080p). The owner asked for a Bluetooth-style static height that follows the screen size.
It is `root.height * 0.6`, about 600 at 1080p, and the list scrolls inside it (driven
live: opening the field left the card where it was). The Bluetooth dialog is still a
literal 600. Bring it across in the cohesion pass if the two should match on other
screens.

**Live-reload trap, again.** The Write tool replaces a file's inode, and Quickshell's
watcher then stops seeing that file. An in-place rewrite with *identical* content does not
reload either. Twice this row, "live" results were old code. Check for `Reloading` in the
smoke log, and restart with `tools/audit/smoke.sh`. Its `pkill -x qs` misses a shell
that crash-restarted itself (that one runs as `/usr/bin/quickshell`), so kill that pid first.

**Not done.** The agy/Gemini vision pass was not run.

**For the cohesion pass (motion).** Nothing retimed. New: the password field fades in on
`elementMoveFast` and out on `elementMoveExit` before the row's `elementMove` height
change, which is the Bluetooth Forget sequencing. Watch the two side by side. The connected
icon's colour moves on `elementMoveFast`. A busy row no longer dims to 0.4, as the
Bluetooth notes asked.
