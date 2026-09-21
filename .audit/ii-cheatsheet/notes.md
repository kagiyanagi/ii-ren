# ii-cheatsheet — notes

Ran **lane 1**, not the lane 2 the queue row said, for the same reason `ii-altTab` and
`ii-background-root` did: the surface turned out to be hiding content rather than merely
looking dated, and deciding what to do about that is not a mechanical follow-through.

## Read this before driving the shell from a session

**`ydotool mousemove -a` is 2× off on this machine.** Asking for `-x 855 -y 145` puts the
pointer at `1711, 291`; asking for anything past half the screen clamps it to the edge.
Halve every coordinate, and **check with `hyprctl cursorpos` before trusting a click test**.

This cost the better part of an hour and produced a confident, completely wrong finding —
"a click anywhere inside the card dismisses the cheatsheet, and the tab bar cannot be
clicked at all" — which was reproduced on `HEAD` as well, and written up as pre-existing,
before the coordinates were checked. With the pointer actually where it was asked to be:
clicking a tab switches tabs, clicking the content does nothing, and only a click outside
the card dismisses. All correct, in both branches. Nothing was wrong except the tool.

`wtype -k Escape` needs no such correction and is the reliable way to test dismissal.

## What was measured, not assumed

- **The 2000ms keyboard-focus timer was pure cost.** The comment beside it said setting
  `WlrLayershell.keyboardFocus` declaratively "makes it take its sweet time to open".
  Measured: declared on the `PanelWindow`, the sheet is fully drawn and the persisted tab
  restored **within 350ms** of the IPC call, and `wtype -k Escape` at **400ms** closes it.
  The timer bought nothing and cost Escape, Ctrl+Tab and Ctrl+PageUp/Down for two seconds
  every time the sheet opened.
- **The keybinds tab was hiding two whole columns, not a few characters.** The "Foc…"
  clipped at the right edge looked like one truncated label. Dragging the fixed view
  sideways shows an entire app-launch column (`File manager`, `Browser`, `Code editor`,
  `Office software`, `Text editor`, `Volume mixer`, `Settings app`, `Task manager`), the
  `Focus 2…10` set, `Session`, and an `Uncategorized` category nobody could have known
  existed. Vertically, `Send to workspace left/right` and `Send to scratchpad` were below
  the cut. Verified by drag on the real shell, both axes, after the fix.
- **`StyledScrollBar` had no horizontal path.** `contentItem` hard-coded
  `implicitWidth: 4; implicitHeight: visualSize`, and `active` only watched
  `movingVertically`, so a bar attached with `ScrollBar.horizontal:` would have drawn as a
  4px stub. Made orientation-aware; the vertical path is byte-identical and all four
  existing callers use `ScrollBar.vertical:`. **`horizontal` is a FINAL property on QQC2's
  `ScrollBar`** — naming the new one that stops the shell booting with `Cannot override
  FINAL property`, which is how this was found. It is `isHorizontal`.

## Retimed after the first pass, on the user's call

The row landed with the dialog recipe transcribed literally — `elementMoveFast` (200ms)
and `closedScale` 0.92, what `WindowDialog` and `AltTab` use — and the user did not like
it. They were right, and the design-check had already said so as a NOTE without following
it through: 0.92 of a 1400×860 card is **112px of travel per axis**, and 200ms is the
ladder's *widget* rung (2.4). A fraction that suits AltTab's 400px card is a lurch on the
largest surface in the shell.

Now `closedScale` 0.96 on `elementMove` — the default **spatial** duration, 500ms in,
250ms out. It does not feel slower, because `emphasizedDecel` is at 0.7 of the distance by
5% of the elapsed time; it stops lunging. Options put to the user and declined: fade with
no transform at all, and 0.98 at the original timing.

The **page** slide was retimed rather than replaced. DESIGN §9's tab recipe says content
should crossfade, and the user chose to keep the slide — so what changed is only its
duration, which QQC2 hard-codes as `highlightMoveDuration: 250` inside
`QtQuick/Controls/Basic/SwipeView.qml`'s `contentItem`. A `Binding` onto that property is
five lines; overriding `contentItem` to get the easing too would copy fifteen lines of
Qt's own ListView configuration into this repo, where it would drift. `ListView` does not
expose the easing of a highlight move at all, so the duration is the whole of what a token
can buy here.

## What the cohesion pass has to watch at 60fps

- **The sheet's own enter and exit.** `elementMove` decelerating in, half of it
  accelerating out, scale from `closedScale` 0.96 with `transformOrigin: Item.Center`.
  A `grim` at 85ms after the IPC call catches nothing — the window is not mapped yet — so
  no still frame in this directory proves any of it.
- **The page slide at 500ms.** It is the one place in the shell running Qt's own
  highlight-move easing rather than an AOSP curve, so if any transition looks foreign in
  the contact sheet, it is this one.
- **The current-time line's `Behavior on y`** (`elementMove`). It only moves once a minute,
  and only while the sheet happens to be open, so it is unlikely to be seen by accident.

## The column packing

The first pass made the overflow *reachable* — both scrollbars, content bounds off
`childrenRect`. The user asked for the stronger thing: no column should run past the
bottom at all, so the sheet only ever scrolls sideways.

A `Flow` cannot do that on its own. `flow: TopToBottom` wraps *between* children, so a
child taller than the wrap height simply overflows it; the Window category is 28 binds,
about 1100px, against a 732px viewport, and it will not fit atomically at any window size
this screen can produce. Three shapes were considered:

- **One Flow child per bind row.** Flow then guarantees no overflow, and it is a ten-line
  change — but a category is cut wherever the packing happens to land and the continuation
  has no heading, so a column can begin with a bare `Send to workspace 5…10`. Rejected.
- **Glue each heading to its first row** to stop orphan headings. Fixes the smaller half of
  the same problem and not the one that matters.
- **Pack explicitly**, which is what shipped: the parent cuts each category into blocks of
  `rowsPerColumn`, every block carries the heading, and the second and later ones say
  `(cont.)`.

`rowsPerColumn` needs a row pitch before anything is laid out, which is circular if it is
read off the blocks themselves. It is measured off three hidden probes instead — a
`KeyboardKey` at the configured keycap size, a `StyledText` at the comment size, a
`StyledText` at title size. Not computed from font metrics: `KeyboardKey` carries its own
border, `extraBottomBorderWidth` and padding, and a recomputation here would drift the
first time that widget changes. No feedback loop, because a row's height does not depend
on how many rows are in a column.

`maxBindWidth` moved up to the parent in the same change. Per-category it would have let
two halves of one category, sitting in adjacent columns, disagree about where their
comment text starts. The cost is that a narrow category now pads its key column out to the
widest bind on the sheet (`⌘ Shift Alt`), roughly 60px of extra whitespace in the Shell
column — which reads as a table rather than as a ragged edge, so it was kept.

## The Elements tab, rebuilt as a study tool

Asked for after the audit row landed, by the person who uses it: a class-12 chemistry
student who pointed out that a periodic table which shows four facts is worse than the
poster on their wall. The tab is now a reference tool rather than decoration, and it is
the one part of this surface that is a feature rather than a repair.

**Nothing in it was typed by hand.** `tools/gen-periodic-table.py` builds
`periodic_table.js` from three public sources and cross-checks the fields that overlap:
Bowserinator/Periodic-Table-JSON (Wikipedia, CC-BY-SA 3.0) for configurations, shell
occupancies, the ionisation series, phase, mp/bp, density and the summaries;
andrejewski/periodic-table (PubChem-derived) for ionic radius, oxidation states, bonding
and year; and Wikipedia's atomic-radii data page for the radii, because the PubChem
column is blank for Ce–Yb and every actinide — exactly the stretch someone revising the
lanthanide contraction is looking at. The generator prints the 72 values the first two
sources disagree on so they can be eyeballed rather than silently resolved.

**Two unit traps the cross-check caught**, both of which would have shipped as confident
wrong numbers:
- Wikipedia quotes a gas density in **g/L** and PubChem in **g/cm³**, so the two look like
  they disagree by a factor of 1000 on every gas. Taken at face value the tab would have
  printed oxygen at 1.429 g/cm³ — denser than aluminium. The unit now travels with the
  value and `check-periodic-table.py` fails if a gas is quoted in g/cm³.
- Lanthanum ships upstream as `[Xe] 5d16s2`, one space short, which reads as a single
  term. Normalised in the generator and asserted in the check.

**Families are re-derived, not taken from either source.** Bowserinator files every
halogen under "diatomic nonmetal"; a table that does not colour group 17 as its own
family is not much use to someone learning group trends.

**Colour.** See `DECISIONS.md` 28. Ten fixed family hues, four block hues and a 7-step
sequential ramp, each produced by search and run through the data-viz validator rather
than picked by eye, each mode stepped for its own surface. Ten hues cannot pass the
all-pairs gate — no ten can — so the **Block** mode is the 4-colour view that does, every
tile is directly labelled, and a legend is always on screen.

**What it does now:** family / block / five trend heat maps (atomic radius,
electronegativity, ionisation enthalpy, electron gain, melting point, density — density on
a log scale, because linear puts everything but the heavy metals on one step), group and
period rulers, search by symbol/name/number, and a detail card per element with the shell
diagram, both configuration forms, all five radii, the successive ionisation enthalpies as
bars (the jump after a noble-gas core is the point of that chart), oxidation states,
physical constants in °C and K, discovery and a summary.

**Not verified interactively.** The table, the modes, the legend and the rulers were
checked on the running shell. The click-to-open detail card, the shell diagram and the
ionisation chart have only been checked by the gates and by reading — the desktop was in
use and driving it further was not reasonable. If the detail card misbehaves, that is
where to look first.

## Left alone, deliberately

- **Colouring the element tiles by series.** The `type` field is in `periodic_table.js`
  (`metal`, `nonmetal`, `noblegas`, `lanthanum`, `actinium`, `empty`) and unused, and a
  coloured periodic table is the obvious win. The four container roles this theme resolves
  to are `#2d2a2f`, `#4d4b4d`, `#31292b`, `#2b2a2a` — four near-identical greys. A series
  map built from them is invisible here and arbitrary under the next wallpaper. It needs
  palette roles that do not exist, which is the same gap `ii-bar-popups` hit asking for
  `colPositive`/`colOnPositive`. See `DECISIONS.md` 27.
- **The `0.7`-of-screen tab sizing and the timetable's `maxContentWidth: 1350`.** Invented
  numbers, but layout constants rather than tokens, and once both axes scroll a window
  smaller than its content is a choice instead of a defect.
- **The element names still elide** (`Rutherfordi…`, `Praseodymi…`). Eight names do not fit
  72px at the smallest size, and a tile wide enough for the longest would put the table at
  ~1580px, past a 1366 laptop. The symbol and atomic number identify the element; the name
  is the third datum on the tile. A tooltip would fix it and would also put an interaction
  back on a surface this row just finished taking one off.
- **`Synchronizer on currentIndex`** between `ToolbarTabBar` and the `SwipeView` is
  untouched and works. What changed is that the persisted tab is now assigned **once**, at
  the end of the `Component.onCompleted` that creates the extension tabs, instead of being
  a `currentIndex:` binding the first tab change destroyed — and it is clamped to
  `count - 1`, so a persisted index pointing at an extension that has since been removed no
  longer lands on nothing.

## Gate notes

`tools/check-cheatsheet.py` is new: it evaluates the keybinds content-bounds expressions
against category shapes that do not fit the window, walks `dayColumnWidth` from 0 to 7 days
for the `n/0` the empty week used to hit, and asserts the window's two-flag open/close
structure — `Loader.active` destroys the surface, so merging `open` and `rendered` back
into one boolean silently deletes the exit animation. Verified to fail by reintroducing
three of the defects in a copy of the tree.

`check-config-paths.py`, `check-singletons.py` and `check-unknown-types.py` fail on `HEAD`
too; every finding is in `modules/ii/background/widgets`, which is out of scope
(`DECISIONS.md` 3).
