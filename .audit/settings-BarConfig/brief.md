# settings-BarConfig — brief

**Purpose.** Lay out the bar and configure each of its widgets.

**Primary action.** Arrange the three layout lists.

**Hierarchy.** Unchanged section order: Bar layout, sizes, positioning & appearance, then
one section per widget (clock, active window, media, notifications, tray, indicators,
network speed, battery, resources, utility buttons, workspaces, tooltips).

**Reference.** Android 16 Settings → Display → Status bar: the arrangement first, each
element's options under its own heading.

**Interaction.**
- One level of subsection everywhere. Network speed's "Icon position" sat inside "Icon
  settings", and its closing braces did not match its indentation. Resources'
  "RAM & Swap measurement unit" and "Display value" were nested the same way, each one
  indent deeper than its neighbours.
- Disabled is 0.4, once. Four controls set `opacity: enabled ? 1.0 : 0.5` over widgets
  that already dim, which came out at 0.2.
- Moving the bar to a side no longer rewrites `networkSpeed.displayMode` to icon mode.
  `NetworkSpeed` already draws icon mode on a vertical bar, so the write only erased the
  user's horizontal choice. The mode selector now shows the mode actually drawn.

**Edge states.** Unchanged.

**Cost.** None.

**Delete.** The four extra dims, the displayMode write, and a `ConfigRow` around the lone
Tooltips switch. The battery preview's `colLayer1` card, invisible on a `colLayer1`
pane, is now `colSurfaceContainerHigh` at `rounding.large`, like the rows.

**Out of scope.** `ConfigListView` (the layout lists).
