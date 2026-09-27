# settings-HyprlandConfig — brief

**Purpose.** Change what Hyprland is actually running: displays, layout, window
decoration and input. Each control reads `hyprctl getoption`.

**Primary action.** Per display: resolution and scale.

**Hierarchy.**
1. **Displays** — the monitor canvas, then one subsection named after the selected display
   holding Enabled (only when there is more than one display), the mode combo and Scale.
   Orientation follows as its own subsection. It used to be a subsection holding two
   more subsections, and each nesting indented its rows by another 8. Enabled showed
   greyed out on every single-display machine.
2. **Layout** — Dwindle / Master / Scrolling.
3. **Appearance** — rounding, border, gaps, then blur with its size and passes, then the
   battery notice (shown only while blur is on, under the controls it is about), the
   opacities, and **Window animations**. That switch was a whole section of its own.
4. **Input** — keyboard, cursor, focus follows mouse, touchpad (unchanged).

**Reference.** Android 16 Settings → Display: size and resolution first.

**Interaction.** Widget defaults. Writes still go through `put()`, behind the 800ms settle
window.

**Edge states.** No monitors reported: Displays is hidden (unchanged). Blur off: size and
passes disabled, notice hidden.

**Cost.** None.

**Delete.** The Animations section (its switch moved into Appearance), the nested
subsections, and the disabled-but-shown Enabled switch.

**Out of scope.** `MonitorCanvas`, `HyprlandConfigOption`, and the cursor combo, which
duplicates Advanced → Cursor. It is noted, not removed.
