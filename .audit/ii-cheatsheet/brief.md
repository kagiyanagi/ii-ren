# ii-cheatsheet — brief

**Purpose.** Answer "what was that shortcut" without leaving the keyboard, and — because
the same window grew two more tabs — "what is on this week" and "what is element 47".
It is a reference sheet: it is read, not operated.

**Primary action.** Read a line and close. Every tab's job is to *show all of its content*;
the window's job is to get out of the way fast. There is no action on this surface beyond
picking a tab and dismissing.

That single sentence is what the surface fails at today. On a 1920×1080 screen with the
shipped config, **the keybinds tab clips its content on both axes** — the Workspace column
reads `Foc…`, the Window column is cut off below "Send to workspace 10" — and neither axis
has a scrollbar, a fade, or any other sign that more exists. A cheatsheet that hides
bindings is not a cheatsheet. Everything else in this brief is secondary to that.

**Hierarchy.**
1. The content of the selected tab. It fills the window; nothing else may compete.
2. The tab bar, centred at the top — three peers, no primary.
3. The close button, top right, `colOnLayer0` on no fill. Escape is the real dismiss.

**Reference.** Android 16's full-screen dialog (`M3 Expressive` full-screen dialog, and
`WindowDialog` in this repo, which already transcribes it): a centred, elevated,
`verylarge`-radius card over a dimmed desktop, dismissed by Escape or by the X in its
corner. Not a sheet — it is not anchored to an edge and it did not grow out of anything
on screen. The tabs are `ToolbarTabBar`, already the shell's tab recipe (9).

**Interaction.**
- **Enter and exit, which the surface has none of today.** The window pops into existence
  and vanishes; `Loader.active` is flipped and that is the whole animation. It gets the
  driver `AltTab` and `WindowDialog` share: one `reveal` property drives `scale`
  (`closedScale` → 1) and `opacity` together, assigned from inside the binding that writes
  it (2.9's `Behavior` trap). Enter on `emphasizedDecel`, exit at half the duration on
  `emphasizedAccel` (2.5).
  **On the *default spatial* duration, not the effects one, and `closedScale` 0.96.**
  `WindowDialog`'s 200ms/0.92 suits a dialog; this card is 1400×860, the largest surface
  in the shell, and the same fraction is 112px of travel per axis at the fastest rung of
  2.4's ladder — which reads as a lurch rather than a grow. 2.4 puts something
  screen-sized at 500ms, and `emphasizedDecel` is at 0.7 of the distance by 5% of the
  time, so the longer spec still feels immediate. Opacity rides the same curve safely:
  `emphasizedDecel` has no control point above 1, so it cannot overshoot (2.1).
- `transformOrigin: Item.Center`, stated. The cheatsheet is screen-centred and is opened
  from a keybind, so there is nothing on screen for it to grow out of (2.6).
- **The loader must outlive the exit.** `active: false` destroys the window, so an exit
  animation written against today's structure would never render once — the same defect
  `AltTab` had with `visible: root.open`. Intent (`open`) and mapping (`rendered`) split;
  `rendered` clears when the exit animation lands on 0.
- **Escape must work the moment the window is on screen.** It does not: the layer shell
  takes keyboard focus on a **2000ms** timer, so for two seconds after opening, Escape,
  Ctrl+Tab and Ctrl+PageUp/Down all do nothing. The comment next to it says the
  declarative form "makes it take its sweet time to open". Measure it; take the smallest
  delay that keeps the open fast, and if none is needed, take zero. Two seconds is an
  invented number standing between the user and the only dismiss they will reach for.
- Tabs: `ToolbarTabBar`'s own indicator motion (9), unchanged. The **page** slide is
  QQC2's — `highlightMoveDuration: 250`, a literal inside
  `QtQuick/Controls/Basic/SwipeView.qml`'s `contentItem`. It keeps sliding, retimed onto
  `elementMove`; the easing of a `ListView` highlight move is not exposed, so the duration
  is all there is to take from the token. Bound rather than restated, because overriding
  `contentItem` would copy fifteen lines of Qt's own configuration that then drift.
- Four states belong to the things that are actually pressable — the tab buttons and the
  close button, both already `RippleButton` descendants. **The 162 element tiles are
  `RippleButton`s with no `onClicked`**: they ripple and take a hover film for an action
  that does not exist, on a table that is pure reference. They become plain surfaces.
- `Qt.PointingHandCursor` stays where it already is, on the real buttons.

**Edge states.**
- *Keybinds, a category taller than the window*: today it is cut off mid-row. **It is cut
  into as many blocks as it needs instead, each sized to fit a column, each carrying the
  heading again** — so a column never runs past the bottom of the sheet and the reading
  direction stays left-to-right. The parent owns that packing, because only it knows how
  tall the viewport is; the category renders the slice it is handed. Row pitch and heading
  height are measured off hidden `KeyboardKey`/`StyledText` probes rather than recomputed
  from font metrics, since both follow live config.
  One key-column width for the whole sheet, not one per category: two halves of the same
  category sitting in adjacent columns would otherwise disagree about where their comments
  start.
- *Keybinds, content wider than the window*: today it is cut off mid-word. A horizontal
  `StyledScrollBar`, which `StyledFlickable` already gives vertically.
- *Keybinds, no binds at all*: one "Uncategorized" heading over nothing. Acceptable — an
  empty Hyprland keybind list means the shell is not running its own config.
- *Timetable, a week with no events*: `days` is empty, `dayColumnWidth` divides by zero,
  and the surface renders as a 108px-wide sliver with a lone clock in it. `PagePlaceholder`
  (9's named empty state), and the divide guarded.
- *Timetable, an all-day event*: **nothing renders.** The chips are transparent rectangles
  containing only a tooltip, in a `Column` anchored horizontally but not vertically, so
  they overflow the 40px day pill; and every chip's tooltip is bound to the *pill's* hover
  handler, so hovering one day pops all of that day's tooltips at once. The day pill
  already recolours to `colPrimaryContainer` when the day has all-day events — that is the
  indicator. One tooltip on the pill lists them.
- *Timetable, an event with no colour*: the card falls back to `colTertiaryContainer`, but
  the label's contrast is computed from the **undefined** original, so
  `getContrastingTextColor` reads a NaN luminance, fails its `< 0.5` test and returns black
  on a dark card. The contrast must be computed from the colour actually painted.
- *Timetable, a long event title or a narrow day*: elides. Already correct.
- *Elements, a long name*: `Rutherfordium`, `Praseodymium`, `Protactinium` and five others
  paint straight through the sides of their 70px tiles and over their neighbours. The label
  gets the tile's width, so `StyledText` can do what `cw-primitives` made it do.
- *Elements, a table wider than the window*: no scroll at all today — the block is centred
  in an `Item` and whatever falls outside is simply gone. At 1362px it fits on this
  machine and does not on a 1366 laptop. Both bars, as the keybinds tab gets.

**Cost.** From the pack's effect budget, three entries, and one of them is free to lose:
- `StyledRectangularShadow` on the card — **kept**. Elevation 5, one shadow, the only
  effect the surface needs (6.2).
- `layer.enabled` + `OpacityMask` on the `SwipeView` — **dropped**. It is a full-window
  framebuffer that rounds the view's corners to `rounding.small`, under content that is
  either a `rounding.large` card of its own (timetable) or fully transparent (the other
  two). It rounds nothing that is visible, and `clip: true` on the same item already does
  the clipping. Law 8's clearest case in the surface.
- Nothing new. The tiles lose their ripple rather than gaining an effect, and the two
  transparent chip rectangles behind each element's number and weight — `transparentize`
  of the colour they sit on, so invisible — go with it.

**Delete.**
- The `OpacityMask` pair, above.
- `ElementTile`'s `RippleButton` root, its two invisible chip rectangles, and
  `opacity: element.type != "empty" ? 1 : 0` — 44 of the 162 tiles are fully transparent
  buttons that still hit-test, hover and ripple.
- The timetable's separator bar under the header (`colOutlineVariant` as a fill: law 11,
  and `check-design.py` already fails on it), with 4dp-grid whitespace in its place.
- `allDayChipHeight`, `allDayChipSpacing`, `maxAllDayEventCount`, `hasAllDayEvents` and the
  transparent chip `Column` they feed. `hasAllDayEvents` has no reader at all.
- `backgroundColor` on the timetable and `padding` on the keybinds tab — declared, never
  read.
- `slotDuration`, as a name. It is 60 **minutes**, and `check-design.py` reads it as a
  literal animation duration; `slotMinutes` is both what it means and clean.
- The raw `Text` in the current-time chip, for `StyledText` (the pack's one reuse miss).
- The hand-written `20`/`10`/`5`/`7`/`6`/`4` paddings and spacings that are off the 4dp
  grid (5.1).

**Out of scope.**
- **Colouring the element tiles by series.** It is the one thing that would make the
  periodic table readable, the `type` field is already in the data, and it is still not
  done here: the five container roles this theme resolves to (`#2d2a2f`, `#4d4b4d`,
  `#31292b`, `#2b2a2a`) are four near-identical greys, so a series map would be invisible
  on this wallpaper and arbitrary on the next one. It needs colour roles the palette does
  not have — the same gap `ii-bar-popups` hit with `colPositive`. Noted, not invented.
- The `0.7`-of-the-screen sizing of the keybinds tab and the timetable's `1350` content
  cap. They are layout constants, not tokens, and once both axes scroll, a window that is
  smaller than its content is a choice rather than a bug.
- `HyprlandKeybinds` itself — how binds are parsed and categorised is a service, not this
  surface.
- Extension cheatsheet tabs. They are third-party QML loaded by URL; this row owns the
  frame they load into, not their contents.
