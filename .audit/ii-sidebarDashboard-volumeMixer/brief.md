# ii-sidebarDashboard-volumeMixer — brief

**Purpose.** Choose where sound goes (or comes from), and set each app's level. The
quick panel's audio tiles open it on a long press, as "Audio output" and "Audio input".
The overlay's volume-mixer widget shows the same content, in two tabs.

**Primary action.** Pick a device. The dialog is named for it, and before this change it
was the least visible thing in it: a row of chips under a fixed 600px card that held one
app row and about 350px of nothing.

**Hierarchy.** Title. Then a devices card, with one row per device: an icon for its kind
(headphones for Bluetooth, a TV for HDMI, a speaker or a mic for everything else) and its
name. The device in use has its icon and name in primary. If there is more than one device,
the card ends with a "Play on several devices" switch row ("Record from several devices" for
input). Then an apps card, with one row per stream: a round mute button carrying the app's
icon, the app name (and media title), and the level slider. Details and Done sit in the
button row.

**Reference.** Android 16 SystemUI's Media Output dialog. It lists devices as rows, the one
in use is marked, and a tap on a row moves the sound there. The rows use the Bluetooth
dialog's styling (`DialogListItem`, primary colour for the device in use), and the switch
row is the one the Wi-Fi, hotspot and eye-protection dialogs use. The four sidebar dialogs
read as one family.

**Interaction.**
- A tap on a device row calls `Audio.pickDevice`. It switches the default device, or, with
  several devices on, adds or drops that device. The switch row's status line says so while
  it is on ("Tap a device to add or remove it"). The row in use is `active` only in
  single-device mode, because there a second tap on it would do nothing.
- The mute button is a `RippleButton`, so it gets all four states. Before, it was a bare
  `MouseArea` with none. Muted swaps the app icon for `volume_off` / `mic_off`, crossfading
  on `elementMoveFast` (effects).
- The switch never toggles itself. The row owns the state, as in the sibling dialogs.
- No new motion. `WindowDialog` owns the enter and exit and follows the content's height,
  so a stream arriving or leaving grows or shrinks the card on the dialog's own spec.

**Edge states.**
- *No apps*: one subtext line in the apps card, "No apps are playing sound" / "No apps
  are recording". That replaces the cookie placeholder in a 350px void.
- *One device*: no switch row, since there is nothing to combine. It stays visible while
  multi-device mode is still on, so the user can switch it off.
- *No devices* (Pipewire down): "No devices" in the devices card.
- *Many streams or a short sidebar*: the body scrolls under a fixed title and button row.
  At 1080p it fits.

**Cost.** Before: one `Desaturate`, an offscreen pass per app row, in a repeated delegate
(rule 8). `check-effect-budget.py` did not see it, because the delegate is its own file:
the dock's blind spot. After: that pass is gone, but the mute button is a `RippleButton`,
and every `RippleButton` keeps its corner `OpacityMask` layer on all the time. So an app
row still costs one pass, and now it buys four states. The old device chips were
`RippleButton`s too, so device rows cost the same as before. That always-on mask is
`cw-buttons`' to fix, not this row's. The one `ClippingRectangle` goes, because the device
rows round their own end corners, as the eye-protection rows do.

**Delete.** `backgroundHeight: 600`. The chip `Flow` and its `SelectionGroupButton`s.
`PagePlaceholder`. `Desaturate` and the `Qt5Compat.GraphicalEffects` import. The raw
`MouseArea`. `spacing: -4`. The `DialogSectionListView` component. Wire
`GlobalStates.requestVolumeDialog`: the media popup's audio-device pill sets it, but
nothing ever read it, so the pill opened the sidebar and stopped there.

**Out of scope.** Per-device volume in the rows, since the sidebar's quick sliders sit
right above the dialog. Moving the switch row into a shared widget: it is now the fourth
copy, and that belongs to `cw-dialogs`. The overlay widget's own tab bar and frame.
