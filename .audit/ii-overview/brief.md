# ii-overview — brief

Seven files, two surfaces in one window. `SearchWidget` / `SearchBar` / `SearchItem` are
the launcher — the pill `Super` and `ipc call search` open, which expands into a results
card. `OverviewWidget` (classic grid) / `ScrollingOverviewWidget` (hyprscrolling) /
`OverviewWindow` are the workspace canvas, shown only while the search box is empty.
`Overview.qml` is the window that holds both, dims the desktop behind them and owns the
zoom that the desktop plane answers.

They are one surface because typing replaces the canvas with results. That is the right
shape and it stays.

**Purpose.** One place to reach anything: type to find it, or look at where the windows
are and go there.

**Primary action.** Type. The caret is in the field the moment the surface opens, and
Enter runs the first result. The canvas is what is on screen while nothing has been typed.

**Hierarchy.** The search pill, then the occupied workspace tiles and their thumbnails,
then the active-workspace outline, then the empty slots and their numbers. The first
result carries `colPrimaryContainer` and its verb ("Open", "Run") — it is already the
loudest thing in the results card, and Enter fires exactly it.

**Reference.** Android 16's Desktop Windowing overview: rounded window cards on a dimmed
backdrop, the focused one outlined, quiet numbering. The launcher half is the M3E search
bar that grows into a results sheet — one container, no rule between the field and the
list.

**Interaction.**

- **The open/close zoom is spatial and asymmetric.** `scaleAnimated` runs on
  `elementMoveFast` today — 200ms on the *effects* curve — while the desktop plane behind
  it zooms on `elementMoveEnter`, 500ms default spatial. Opening the overview moves two
  halves of one gesture over durations that differ by 2.5×, and by 2.1 the overview's is
  the wrong one: a scale is spatial. Enter goes to `elementMoveEnter`, exit to
  `elementMoveExit`. This is the finding `ii-background-root` left here, and it is the
  motion the user feels on every `Super`.
- **`visible` stays derived from the animated scale**, never from `GlobalStates.overviewOpen`.
  The window has to stay mapped through the close or the exit plays to nobody — five other
  rows in this audit found the same defect in `Loader.active` form, and it has no symptom
  beyond a surface that vanishes.
- Transform origin is the screen centre, which is what the surface grows out of: it is
  full-screen and the desktop behind it zooms about the same point.
- The dim stays an effects animation (`elementMoveFast.colorAnimation`) in both directions.
  Colour leads, geometry follows — measured at 0.5 alpha and working.
- **Workspace tiles get their four states (6).** A tile is clickable through a bare
  `MouseArea` with no hover, no pressed, no focus; `hoveredWhileDragging` is the only state
  it has and that is the drag one. `StateOverlay` on the tile, with the drag state moved
  onto it, so all four come from one place and the 0.08 / 0.10 / 0.16 tokens are not
  hand-mixed.
- The launcher's card keeps `elementMove` on its height — a size, so spatial — and the
  search field keeps its width expansion, moved off a hand-rolled `duration: 300` onto
  `Appearance.animation.elementMove.numberAnimation`.

**Edge states.**

- *Nothing typed.* The canvas. This is the ordinary case.
- *No results.* Unreachable in the shipped config — `showDefaultActionsWithoutPrefix`
  synthesises Command / Math result / Web search for any string — but a prefix search
  (`>zzqq`) empties the list and leaves a card with a field and a void under it. It gets
  `PagePlaceholder`, which is what every other empty state in the shell uses.
- *One result.* Already right: it is selected, carries its verb, and Enter runs it.
- *No windows on any workspace.* Ten empty slots with their numbers. Already the quietest
  thing on the surface and it stays that way.

**Cost.**

Kept. `OverviewWindow`'s `layer.enabled` + `OpacityMask` is one offscreen pass per open
window and it sits inside a `Repeater`, which 8 forbids — but the rounding is the
thumbnail's whole silhouette, the four radii are computed per window from its distance to
each tile edge, and `ClippingRectangle` is the same two framebuffers rather than fewer
(its own documentation says it costs more than a `Rectangle`). What changes is that the
ceiling is *stated*: `check-effect-budget.py` reads a `Repeater`/`delegate:` block inside
one file and every overview window is its own file, so it has never seen this — the dock's
blind spot, same shape, same answer. `tools/check-overview.py` pins one effect per delegate
file. Also kept: one `StyledRectangularShadow` per card, neither repeated.

Dropped. `SearchWidget`'s `layer.enabled` + `OpacityMask`. Its mask is `width × width` —
square, stretched over a card that is always taller than it is wide, so the curvature it
draws is not the curvature it is masking to. And it is masking nothing: every `SearchItem`
is inset `horizontalMargin` from the card edge and the list sits on 4dp-grid margins top
and bottom, so no delegate pixel ever reaches the card's corner radius. Two framebuffers
for a correction that is both wrong and unnecessary. The parent's `clip` and the list's own
`clip` do the rest.

**Delete.**

- The 1px `colOutlineVariant` separator between the field and the results (11). Whitespace
  on the 4dp grid instead.
- `SearchItem`'s `Layout.bottomMargin: -root.buttonVerticalPadding`, whose comment reads
  "Why is this necessary? Good question." Negative margins are out under 11.
- `workspaceNumberMargin` — declared, read by nothing.
- `focusedWorkspaceIndicator`'s four `Behavior on *Radius` — the radius is
  `Appearance.rounding.normal`, a constant, so they animate a value that never changes.
- `searchWidgetWrapper`'s `Keys.onPressed` — a bare `Item` that never takes focus, under a
  window that already has the identical Escape handler.
- The commented-out `console.log` block and the two commented properties in
  `OverviewWindow`.

**Out of scope.** The grid geometry and every `Config.options.overview.*` knob that feeds
it (rows, columns, scale, ordering, workspace map) — those are the user's, not the brief's.
Drag-and-drop between workspaces and windows, which is behaviour rather than design and has
no gate. `LauncherSearch` and what it returns. The `ScrollingOverviewWidget` layout itself,
which the shipped Hyprland layout never reaches; it takes the shared token and colour fixes
and nothing else.
