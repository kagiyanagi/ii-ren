# ii-bar-widgets — brief

Read `.audit/ii-bar/brief.md` first. One fifth of the old `ii-bar-root` row.

**Your files** (16, and nothing else):

```
Workspaces.qml  ActiveWindow.qml  ClockWidget.qml  Media.qml
NetworkSpeed.qml  Resources.qml  Resource.qml  TimerWidget.qml
UtilButtons.qml  CircleUtilButton.qml  DashboardPanelButton.qml
PoliciesPanelButton.qml  NotificationUnreadCount.qml
HyprlandXkbIndicator.qml  Visualizer.qml  BatteryIndicator.qml
```

all under `dots/.config/quickshell/ii/modules/ii/bar/`.

**Purpose.** The readouts in the strip — the things the bar exists to show.

**Primary action.** Per widget, one: `Workspaces` is switched with, everything
else is read and opens a popup on hover.

**Hierarchy.** `Workspaces` is first-rank and the only widget allowed an accent
fill — its active indicator is the single loudest thing in the bar, and
correctly so. `ClockWidget` is second: read constantly, so it must be quiet and
perfectly legible. `ActiveWindow` is third-rank text and must not compete with
the workspaces beside it (it currently prints a two-line class+title block —
check that it still reads as subordinate). `Resources`, `NetworkSpeed`,
`BatteryIndicator`, the util buttons and the indicators are fourth: noticed only
when a number is bad.

**Interaction.**

- **The workspace indicator is the cluster's most-watched motion.** It slides
  and stretches between workspaces (`indicatorPosition`, `indicatorLength`,
  `stretchAmount`). That is position and size: `elementMove`, one spec for both,
  never two different timings — `ii-background-root` shipped exactly that bug
  (two planes on different timings) and its `notes.md` says why it reads wrong.
- Workspace icons scale on hover: §3.3's composition (`hoverScale *
  pressScale`), as `DockButton` does it, not a hand-written number.
- Every widget is a hover target that opens something: four states off
  `colLayer0Hover` / `colLayer0Active` (§3.1), ≥32px hit area (§3.4),
  `Qt.PointingHandCursor`. Several are bare `MouseArea`s with hover only.
- `Resource` warning thresholds: the bad state is a colour change on
  `elementMoveFast`, using `colError`/`colErrorContainer` (`cw-battery` settled
  this: the *container* token for a track, not `m3error`). No pulse (law 8).
- `UtilButtons` / `CircleUtilButton` / `DashboardPanelButton` /
  `PoliciesPanelButton` are buttons: `RippleButton` conventions (§9), which
  three of them already are. Check the fourth.

**Edge states.** No windows in a workspace; more windows than `maxWindowCount`;
`dynamicWorkspaces` on and off; no media playing (`Media` with a null
`activePlayer`); no battery (`BatteryIndicator` on a desktop); a title so long
it must elide; the vertical bar.

**Cost.**

- `Workspaces.qml:534` — `ColorOverlay` **per workspace icon**, inside a
  repeated delegate. Law 8. Use a tinted `MaterialSymbol`/`CustomIcon` or
  `IconImage`'s own colouring instead.
- `Workspaces.qml:357` `layer.enabled` and `:433` `MultiEffect` — one effect per
  widget. Keep whichever actually draws the active indicator's shape; drop the
  other or explain in your report why both are load-bearing.
- `Media.qml:94` `layer.enabled` + `OpacityMask` is the lyrics gradient mask —
  one effect, one widget, gated by `useGradientMask`. It stays.

**Delete.** Dead properties (`pack.md` lists the full declared API;
`Workspaces.qml` alone declares ~60 and several are unread). Every literal
duration and curve.

**Out of scope.** `BarComponent.qml` instantiates all of these — it belongs to
`ii-bar-chrome`, so freeze the type names and the properties it passes.
`modules/ii/verticalBar/**` reads `Media`, `Resources`, `ClockWidget` and
`BatteryIndicator` by name too. `ResourcesPopup`, `NetworkSpeedPopup`,
`MediaPopup`, `ClockWidgetPopup` and `BatteryPopup` belong to other rows.
