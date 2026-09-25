# ii-sidebarDashboard-bluetoothDevices — notes

**Opening it.** `qs -c ii ipc call sidebarRight openDialog Bluetooth`. That call is new in
this row, in `SidebarDashboard.qml`. It takes any dashboard dialog's name ("Wifi",
"Hotspot", "NightLight", "AudioOutput", "AudioInput"), and the queue rows for those have
been filled in with it. Opening this dialog turns the adapter on and starts discovery.
That was true before this row too.

**Pairing is unverified on hardware.** No device was in pairing mode during the session,
and pairing strangers' devices to test it was not an option. What is established:

- Quickshell's `device.cpp`, read from the installed package's source, holds `pairing` true
  for exactly the length of the `Pair()` D-Bus call. On a failed `connect()` it sets `state`
  back to `Disconnected`. Both failure paths in the row are built on those two facts.
- FastPair's commit fce2bf460 recorded that `Pair()` goes nowhere with no agent registered.
  No agent is running on this machine: no blueman, bluedevil or bluetoothctl process.
- The connect-failure path was seen once in the log (`br-connection-page-timeout` on
  Nirvana Ion, which was out of range). That is what now shows as "Couldn't connect".

**The first thing to test with real earbuds:** tap an unpaired device. Expect "Pairing…",
then "Connecting…", then "Connected". Discovery stops for the attempt and restarts
afterwards; the bar above the list goes away and comes back. If it fails, look at the log
for `quickshell.bluetooth.device` lines.

**FastPair keeps its own agent.** Its retry loop drives `Pair()` every 5s on
`agentReady`, and folding that into `BluetoothStatus.pair()` would change timing that
`check-fastpair.py` does not cover. If both run at once, each sends `default-agent` and
the last one wins. Both are NoInputNoOutput, so the result is the same either way. This is
marked with a `ponytail:` comment in the service.

**Waffle shares the row.** `modules/waffle/actionCenter/bluetooth/BluetoothControl.qml`
instantiates `BluetoothDeviceItem`, so waffle's list gets tap-to-connect too. That matches
Windows 11's quick settings.

**Not done.**
- `tools/audit/smoke.sh` was not run. The user was on the desktop, and it `pkill`s the
  running shell. The running shell hot-reloaded every changed file and rendered the dialog
  (`shot-after.png`), with no log lines from any touched file.
- The agy/Gemini vision pass was not run.
- The expanded state and the chevron's hover were not screenshotted. The user switched
  workspaces as the pointer was being driven, and driving it further would have clicked
  into their windows.

**For the cohesion pass (motion).** The chevron rotates on `elementMove`, the row's own
height spec. It first moved from `elementMoveFast` (an effects spec, on a transform) to
`elementMoveSmall`. The user found that version clunky: that curve's y1 is 1.67, and over
180 degrees the overshoot wobbles. It was also off-centre, because `RippleButton` sizes the
content box and the glyph was left-aligned in it. The rotation mirrored that offset, so the
arrow slid 3px sideways as it flipped. The glyph is centred now, measured to within 0.5px
in both states. `NotificationGroupExpandButton` still flips on `elementMoveSmall`; decide
that one in the cohesion pass. Watch this chevron at 60fps next to the Wi-Fi rows. Also: the busy row stays at full opacity, while Wi-Fi's busy row dims
to 0.4. The Wi-Fi row should come across to this one, not the other way round: 0.4 means
disabled.

**The design-check review found three warnings, all fixed before commit.** The Forget
button and the chevron hover on layer 4, because the row under them is already painting
layer 3's hover. Forget fades out on `elementMoveExit` before the row's height drops,
instead of vanishing on the first frame. The icon and status colours move on
`elementMoveFast`. A busy row does not ripple. For the cohesion pass, also watch the
Forget fade against `DialogListItem`'s height change: the two are sequenced but not tied
to each other.
