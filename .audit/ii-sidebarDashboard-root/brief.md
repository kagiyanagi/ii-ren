# ii-sidebarDashboard-root — brief

**Purpose.** The frame of the right sidebar: the header row, the quick panel, the
notification card and the bottom card (calendar, to-do and timer), in a floating sheet
that slides in from its screen edge.

**Primary action.** None of its own. The frame shows its children; the quick panel is
what the user came for. So this is a repair rather than a redesign. The layout already
reads as Android 16's shade (header, tiles, notifications, then a card that can collapse),
and every child row was redesigned inside it.

**Hierarchy.** Unchanged: the header (uptime pill, then the edit, reload, settings,
update and power buttons), the quick panel, the notification card taking the spare
height, the bottom card.

**Reference.** Android 16 SystemUI's notification shade: QS header, tiles, notification
stack, one expandable card.

**Interaction.**
- *The sheet* slides from its edge on Hyprland's `layersIn`/`layersOut` springs (the
  `quickshell:sidebarRight`/`Left` layer rules). The QML side keeps no motion of its own.
- *Bottom card collapse* is a fade-through. The leaving row fades on `elementMoveExit`,
  and the arriving row waits out that fade and then comes in on `elementMoveFast`. The
  height moves on `elementMove`, as before. Before this row the rows' opacity was set
  from JS, which broke both bindings. So the first collapse and the first expand after
  each open cross-faded at the same time, with the two rows' text overlapping, and every
  later one faded through. It is declarative now and does the same thing every time.
- *Tab switch* slides 10px and fades. The exit is on `elementMoveExit`. The enter slides
  on `elementMoveEnter` and fades on `elementMoveFast`. Before, the enter's opacity ran on
  the spatial overshoot curve (rule 3), and both halves ran on `elementMoveFast`, so the
  exit was not the faster half (rule 4). The slide direction came from `previousIndex`,
  which started at -1, so the first switch after each open always slid the same way.
- *Tab selection* has one source, `Persistent.states.sidebar.bottomGroup.tab`. The rail
  and Ctrl+PgUp/PgDn both write it. Before, both assigned `selectedTab`, which broke its
  binding, and Ctrl+PgUp/PgDn never saved the tab.

**Edge states.**
- *A stored tab that no longer exists* (an extension tab whose extension was removed):
  the index is clamped to the last tab. Before, `tabs[i].widget` threw and the card came
  up blank.
- *Quick sliders with only gamma enabled*: the classic panel now shows the gamma
  slider. The loader's guard listed mic, volume and brightness but not gamma, so it
  hid the row.
- *Dialogs*: `WindowDialog` accepts Escape itself, so Escape closes the dialog first and
  the sidebar only on a second press. Checked, no change.

**Cost.** Keep the sheet's `StyledRectangularShadow` and the avatar's one `OpacityMask`
(not repeated, and `NotificationAppIcon` records why `ClippingRectangle` would cost more).
Nothing added.

**Delete.** `previousIndex`, `collapseCleanFadeTimer`'s imperative opacity writes, and
`setCollapsed`'s bookkeeping. It becomes one Persistent write.

**Out of scope.** The off-grid paddings (`sidebarPadding` 10, the header's 5): every
child's width comes from them, and the quick-toggle grid was just re-centred against them.
The sheet's concentric radius (`screenRounding - gapsOut + 1`), which DESIGN.md's
`verylarge` would replace. That radius is shared with `WindowDialog`, so it is the
owner's call. The bottom card's 350 height, which is what the calendar's six rows need.
The header buttons' set: update and reload belong to this fork.
