# ii-sidebarDashboard-calendar — brief

**Purpose.** See the month at a glance and what is on a given day.

**Primary action.** Point at a day with a dot and read its events. A tap opens that day in
Google Calendar. That tap is the owner's own feature (2cc76a2a1, the same commit as the
iCal feeds), so it stays as it is.

**Hierarchy.** The month title, then today (filled primary), then the dots that mark event
days, then the rest of the grid. The weekday initials are labels in `colOnSurfaceVariant`.
Before, they were disabled `RippleButton`s, so they were drawn at the disabled 0.4.

**Reference.** The M3 date picker grid: circular day cells, today filled, narrow locale
weekday initials. The event card is an M3 rich tooltip: a surface card with a subhead and
body. It is not a plain `colTooltip` tooltip, because it holds a list.

**Interaction.**
- *Day cell.* It gets hover and press through `colLayer1Hover`/`colLayer1Active`, or the
  primary pair on today. Colour changes on `elementMoveFast`. Tab reaches it, and focus
  shares the pressed layer (0.10). A focused event day shows its card, and Return or Space
  opens the day. It has no ripple and no layer (see Cost). The tap fires on
  `clicked`, so dragging off a cell cancels it. `RippleButton` fires on release wherever the
  press ends (FINDINGS, `RippleButton.qml:113`).
- *Event card.* There is one card per calendar, not one `LazyLoader` per cell. It opens on
  `ArrowPopupMotion`, which is spatial with an overshoot on the scale, and its exit is an
  asymmetric accelerate. It scales about the hovered day's top centre: the card hangs off a
  zero-size pivot at that point, so the origin is exact even when the card is clamped
  against the window edge. Before, the card scaled and faded on `elementMoveFast`, an
  effects spec, and grew from its own centre. Its `LazyLoader` only turned on past scale
  0.9, so the first third of the enter and the last part of the exit were never drawn.
- *Month header.* The title's width change runs on `elementMove`, not a velocity
  `SmoothedAnimation`.

**Edge states.**
- *No events anywhere* (no khal, no feeds): no dots and no card. The grid is the whole
  surface.
- *One event*: header plus one row.
- *More than six*: six rows and "+N more". Before, the rest were dropped silently.
- *All-day*: says "All day". Before, it showed "12:00 am - 11:59 pm", and ics all-day
  events showed midnight to midnight. khal events with no start time are now marked
  all-day in the service.
- *Days outside the month*: dimmed. They have no dot and no card, as before.

**Cost.** The grid used to hold 49 `RippleButton`s, and each one kept `layer.enabled` with
an `OpacityMask` for its ripple. That is 49 offscreen passes in a repeated delegate (rule
8). The cell is now a native-radius `Rectangle` with a `MouseArea`, which costs no layer.
The card keeps one `StyledRectangularShadow` (cached). That is one effect for the one
surface.

**Delete.** `CalendarPopup.qml`: its border, its literal 200 width and `normal + 4` radius,
its dead `Layout.margins` inside a non-layout parent, its flickable with no size, and its
1000px cap. The per-cell `LazyLoader` and the per-cell hover `MouseArea` laid over a
`RippleButton`. `CalendarDayButton`'s `bold` and `isToday`-as-int flags. The weekday row
as buttons, and the hard-coded English `Mo…Su`. Weekday names and the month title now come
from `Qt.locale(Config.options.calendar.locale)`, as waffle's calendar already does.

**Out of scope.** The "• " prefix on the title that signals a shifted month. The collapse
and expand buttons in `BottomWidgetGroup`, which share `CalendarHeaderButton`.
`RippleButton`'s own always-on layer, a `cw-buttons` revisit. Waffle's calendar, which is a
separate file. Arrow-key navigation of the grid. Tab walks all 42 days, as it did before.
