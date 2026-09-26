# ii-sidebarDashboard-volumeMixer — notes

**Opening it.** `qs -c ii ipc call sidebarRight openDialog AudioOutput` (or `AudioInput`),
or long-press the quick panel's audio tiles. The overlay's Volume Mixer widget
(`qs -c ii ipc call overlay toggle`) instantiates the same `VolumeDialogContent`.

**Driven live** (ydotool, half coordinates):
- The mute button muted and unmuted the Zen stream: `wpctl get-volume 80` read `1.00
  [MUTED]`, then `1.00`. The glyph swap, the hover fill and the "Unmute" tooltip all showed.
- The input dialog with nothing recording shows "No apps are recording", level with the
  device row's icon.
- The overlay widget renders the new content, top-aligned, in both tabs.

**Not driven live.**
- The "several devices" switch row. This machine has one sink and one source, so the row
  is hidden, which is the one-device edge state. The corner arithmetic for the other
  layouts is evaluated in `check-volume-dialog.py`, but the switch was never clicked.
  `Audio.setMultiDeviceEnabled` / `pickDevice` are unchanged.
- The media popup's audio pill → `requestVolumeDialog`. The pill lives in the popup of
  the sidebar's Android media *tile*, which is not placed on this panel. The reader is a
  `Connections` handler on `GlobalStates`, next to the existing close handler, and the
  check asserts that it consumes the flag and opens the output dialog. The three writers,
  two of them in the vendored background widgets, set it after `openRightSidebar()` and a
  `callLater`, and by then the sidebar's `Loader` has already created the content.

**Live reload died mid-session.** A `sed -i` on `VolumeDialog.qml` replaced the file's
inode, and after that no edit reached the running shell, in that file or any other. It
looked like a missing-import bug that would not go away. `tools/audit/smoke.sh` restarted
the shell, came up clean and fixed it. Edit shell files in place (the Edit tool, or python
`open(p, 'w')`), never with `sed -i`.

**Cost.** `RippleButton` keeps its corner `OpacityMask` on permanently, so the mute
button's layer replaces the `Desaturate` one for one. It is not zero. Making that mask
conditional is `cw-buttons`' job, and it would lift every dialog row in the shell.

**For the cohesion pass (motion).** Nothing is retimed. The one new animation is the
icon ↔ mute-glyph crossfade on `elementMoveFast`, in both directions, as the old
`Desaturate` opacity was.

**Not done.** The agy/Gemini vision pass was not run.

## Follow-up: per-device balance (asked for on 2026-09-26)

With devices combined (two or more members), each member row has a slider and a percent
readout for that device's own volume, which is its balance against the others. The combined
device is the master, and the sidebar's volume slider drives it. With multiple on, every row
ends in a check or an empty circle, so it is clear what a tap will add or drop.

- **Levelling.** Before, every member was set back to unity on each module reload, and the
  module reloads whenever a member joins or leaves. Adding a third speaker flattened the
  first two. `Audio.setCombinedNames` now queues only the members that are *joining*
  (everyone when going from one member to combined), and `levelTimer` levels that queue
  once. The balance also survives a shell restart now, because nothing levels on startup,
  and WirePlumber restores each device's own volume.
- **Latency.** `combine.latency-compensate = true` for playback. PipeWire 1.6.9 has it, and
  the loaded module was confirmed with it in `pgrep -a pw-cli`. The sync itself was **not
  heard**, because the test members were null sinks.

**Driven live** with two null sinks (`pactl load-module module-null-sink
sink_name=ii_test_kitchen …`) plus the Nirvana Ion earbuds:
- Kitchen dragged to 0.72; the earbuds stayed at 1.00; the master (`ii_combine_sink`) stayed
  at 0.12.
- Bedroom set to 0.5 by hand and then added. The module reloaded (node 87 → 127). Kitchen
  **stayed at 0.72**, Bedroom went to 1.00, and the master stayed at 0.12.
- Multi off: the earbuds became the default at 0.12, and `pw-cli` exited. Two- and
  three-member runs both shut down cleanly.
- Everything was put back afterwards: sinks unloaded, `combinedSinks` `[]`, the laptop
  speakers at 0.42.

**Found, not fixed (quickshell).** Once, after a three-member run, switching off left
`pw-cli` running, because `sync()` was holding on "the default is still the combined node".
Instrumented reruns did not reproduce it. The log shows the default flapping during every
reload (combined → none → combined → member → combined), and the hold rode that out each
time. Killing that `pw-cli` by hand then segfaulted the shell on its next reload, in
`Pipewire.defaultAudioSink` → `PwNodeIface::instance` on a freed node. That is quickshell
0.2.1's stale default tracker, the same bug `setCombinedNames`' ponytail comment works
around. So the stuck state was quickshell's default pointing at a destroyed node, and it is
not safe to force the stop from QML. If it recurs: restart the shell, and don't kill the
`pw-cli`.

**Device order is not stable** across a shell reload (the ALC row moved from last to
first). One test click therefore landed on the laptop speakers. Drive this dialog from a
fresh screenshot every time.

## Owner decision: a fixed height, scaled to the screen (2026-09-26)

The brief made the dialog fit its content. The owner wants it fixed, like its siblings. It
takes the Wi-Fi dialog's `Math.round(root.height * 0.6)` (about 600 at 1080p, the
Bluetooth dialog's number, but scaled to the screen). The apps card stretches into what the
devices card leaves, the way Wi-Fi's list card does, and "No apps…" centres in it. The body
scrolls past that height. A fixed card also stops re-centring under the pointer when a
stream arrives or a device joins, which is the reason the Wi-Fi dialog gave for the same
choice. `check-volume-dialog.py` pins the expression to Wi-Fi's, so the two cannot drift.
Do not return this dialog to content height.
