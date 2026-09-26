# ii-sidebarPolicies-continuity — notes

**Opening it.** `qs -c ii ipc call sidebarLeft open`, then the Continuity tab (`devices` icon,
about `350,82` on this 1920x1080 screen with Anime closeted). The panel pins Hermes on open. A
first click after a cursor warp sometimes lands with the sidebar already dismissed. Check
`hyprctl layers -j` for `quickshell:sidebarLeft` before clicking, or the click goes to the
window behind.

**The host line this row changed.** `Continuity.qml`'s peer `ScriptModel` is keyed on `id`
now. `Tailscale.qml` rebuilds `peers` from new objects every 8s while the page is watched.
Unkeyed, every row was destroyed and rebuilt each poll, so an expanded peer folded shut 8s
later at most. Verified live: a peer stays open across a poll. It is one line in the root
row's file because this row's primary action did not work without it.

**Verified live.** The out-of-reach phone card in the neutral tone with a live pill. The
battery on `StyledProgressBar`. Peers expand, with hover film and chevron. A press on Copy
IP runs the action and leaves the card open. The peer pills have a layer-3 container at rest
now; before, they matched the card and showed only while the card was hovered.

**Careful driving this surface.** Copy IP overwrites the clipboard, and `wl-paste -n` fails
when the top type is `text/html`, so a backup taken that way is empty. Restore from
`cliphist` instead (`cliphist list | grep ^<id> | cliphist decode | wl-copy`), then delete
the IP entry. SSH opens a terminal and Send opens a file picker, so neither is safe to
click unattended.

**Not done.** The agy/Gemini vision pass. KDE Connect had no reachable device and nothing was
charging, so these were not seen live: the accent card, the notifications swap and the
charging colour. The accent card's colours are unchanged from before apart from being keyed
on `accent`.

**Filling the page (second commit, asked for by the user).** The page used to end in a
void with one placeholder line. Two sections of real content went in rather than
decoration; a device-orbit hero was offered and declined.
- *Saved devices*: `BluetoothStatus.pairedButNotConnectedDevices`, one `SavedDeviceItem` each.
  The card is a layout and its Connect pill is the only target. Connected devices are left
  out on purpose: a tap there would be a disconnect, and the keyboard being typed on is a
  bluetooth device. With the adapter off, the section says so and offers Turn on.
- *This device*: a plain `DeviceCard` with Tailscale's name for this machine
  (`/etc/hostname` otherwise), its tailnet IP, the exit node it routes through, and the
  laptop battery. Copy IP is a `CardAction`.
- The placeholder no longer reserves 120px. It shows only when the leftover height fits it,
  so a full page does not scroll to show "nothing more".
- `CardAction.qml` is the layer-3 pill that both the peer and the saved row use.
- Only one device is paired here and it is connected, so the saved row was seen in a
  throwaway `qs -p` probe window, not on the page. Its Connect was never pressed.

**For the root row.** Grouping the peers into one connected run (DESIGN.md 5.6: run ends
`rounding.large`, seams `rounding.verysmall`) needs the host's spacing and each row's position
in the run. `ActionPill` scales on hover. DESIGN.md 3.3 prefers the state layer for a filled
button.

**For the cohesion pass (motion).**
- A saved device that connects leaves its section with no exit, and its Audio card
  appears with no enter. Every section on this page pops the same way. A `ColumnLayout`
  has no add/remove transitions, and changing that is the root row's call.
- The peer's actions fade in on `elementMoveFast` and out on `elementMoveExit` before the
  height drops. They used to pop in on `visible` and paint over the next peer while the card
  grew.
- Both chevrons flip on `elementMove`. They were on `elementMoveFast`, an effects curve.
- The battery value runs on `StyledProgressBar`'s spec, which does not overshoot. It used to
  run on `elementMove`, which does.
- The phone card going out of reach is a colour change on the effects spec, no longer an
  opacity fade.
