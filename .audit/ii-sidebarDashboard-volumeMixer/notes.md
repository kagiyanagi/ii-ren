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
