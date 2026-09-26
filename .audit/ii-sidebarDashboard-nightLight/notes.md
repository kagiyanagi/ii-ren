# ii-sidebarDashboard-nightLight — notes

**Opening it.** `qs -c ii ipc call sidebarRight openDialog NightLight`, or long-press any
of the Night Light, Comfort View, Reading Mode or Anti-flashbang tiles.

**Driven live with real clicks** (ydotool, half coordinates):
- The Night Light switch went on and off: `hyprctl hyprsunset temperature` read 4011, then
  6000.
- Automatic went on at 21:23. Night Light came on by itself, and the status line read "On
  until 06:30". The switch followed without the dialog calling the service, which is the
  regression the old rows had.
- Comfort View on, then a drag of 24→71 across its slider: `configreloaded` on socket2 fired
  **2** times. The old code applied on every integer, and again on its own config write.
- All of it was put back afterwards: Night Light off, automatic off, Comfort View off at
  intensity 24, `screen_shader` empty. The service rewrote the tracked
  `services/hyprlandComfortViewShader/comfort-view.glsl`, which was restored with
  `git checkout`.

**Found and left alone (service, out of scope):**
- Comfort View, Reading Mode and Anti-flashbang all write `decoration:screen_shader`, and
  the last writer wins. Turn on Anti-flashbang while Comfort View is on, and Comfort View's
  switch goes on saying "On" with its shader gone. `HyprlandComfortView.active` (the
  config value compared with its path) exists and is unused. Fixing it means one owner for
  the screen shader.
- `enable()` writes `comfortView.enable`, whose `onEnableChanged` runs `applyShader()`
  again, so each toggle is two `hyprctl reload`s. It is the same shape as the intensity
  echo, and it was not debounced, because a toggle is one event and not a drag.
- Turning Night Light's automatic off leaves the temperature wherever the schedule had put
  it. Android does the same.

**Height (2026-09-26, owner's call).** The first pass sized the card to its content, about
870px at 1080p. The owner wanted the same height as the Wi-Fi, audio and Bluetooth dialogs,
so it is `Math.round(root.height * 0.6)` now, with the flickable filling the space. The
body scrolls, and Night Light stays at the top. `check-night-light-dialog.py` pins the
expression to the Wi-Fi dialog's.

**Brightness and gamma were removed** on the grounds that the sidebar's default quick
slider (`sidebar.quickSliders.showGamma`, on by default) covers both. If
`showGamma` is switched off, this dialog no longer offers a fallback. Restore the section
only if someone asks for it.

**Not done.**
- `tools/audit/smoke.sh` was not run, because it `pkill`s the shell and the user was on the
  desktop. The running shell hot-reloaded all four files, and nothing it logged came from
  them after the `icon` → `symbol` rename (`icon` is FINAL on AbstractButton, and
  overriding it made the whole type unavailable — qmllint names it as `property-override`).
- The agy/Gemini vision pass was not run.

**For the cohesion pass (motion).** Nothing is retimed and nothing new animates. The
200ms service debounce is not motion.
