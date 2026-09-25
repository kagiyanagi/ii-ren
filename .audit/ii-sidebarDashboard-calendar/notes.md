# ii-sidebarDashboard-calendar — notes

**Opening it.** `qs -c ii ipc call sidebarRight open`, then the Calendar tab in the bottom
group. The group remembers its tab in `Persistent.states.sidebar.bottomGroup.tab`, so it
is usually already showing. Event dots need khal or `calendar.icsUrls`. A full shell reload
refetches the feeds, so the dots take a few seconds to appear after one. That is not a bug.

**The Google Calendar tap stays.** It looked like a hard-coded third-party link, and the
first draft of the brief deleted it. `git log -S calendar.google.com` shows the owner added
it on purpose, in the same commit as the iCal feeds (2cc76a2a1). Check the log before
deleting a behaviour that looks odd.

**How the card was looked at.** The user was using the sidebar during the session: the
audio dialog opened under the pointer. So the card was not driven with a real hover. It
was rendered in a throwaway `qs -p` probe on an overlay layer with `mask: Region {}` and
`keyboardFocus: None`, then saved with `grabToImage`. Two things about that probe are worth
keeping:
- A `WlrLayer.Background` probe never renders. It is occluded, so it gets no frame to grab.
- `grabToImage` on a `PanelWindow`'s `contentItem` fails with "item has no QML engine".
  Grab a QML `Rectangle` that fills the window instead, and reparent the card into it,
  since the card parents itself to `QsWindow.contentItem`.

`shot-after.png` shows the three placements from that probe: centred over the 4th, clamped
at the right edge (Sunday the 6th), and clamped at the left edge (5 October). The probe
runs its own palette, so the colours are not the live theme's. The live grid rendered as
expected, with no log lines from the touched files after the last reload.

**For the cohesion pass (motion).** The card now opens and closes on `ArrowPopupMotion`,
about the day's top centre. It used to be 0.85 to 1 on `elementMoveFast`, from the card's
centre, with the start and end clipped by the loader. Watch two things at 60fps:
- A sweep across adjacent event days. Each day restarts the open from
  `arrowPopupScale`, so the card pops again on every day.
- The collapsed/expanded month title's width change, which now runs on `elementMove`
  instead of a velocity `SmoothedAnimation`.

**The design-check review found two problems, both fixed before commit.** A
`hide()` on month change left the card shut while the pointer rested on a day that had
events in both months: the cell's `showsEvents` stayed true, so nothing reopened it. The
cell's own handler covers every month change, and the card's content is bound to the
cell, so the line was deleted. The days had also stopped being reachable by keyboard when
they stopped being `RippleButton`s. They take Tab again, and focus now shows the card too,
which it never did before. Keyboard focus was not driven in the probe, because a layer
with `keyboardFocus: None` never gets active focus. If the pointer rests on one event day
while another has keyboard focus, leaving the hovered day closes the card. That was left
as it is.

**`check-design.py`'s one warning is a false positive.** `colOutlineVariant` is the *text*
colour of spill-over days, not a fill. It was on HEAD before this row.

**Not done.**
- `tools/audit/smoke.sh`, because the user was on the desktop and it `pkill`s the shell.
- The agy/Gemini vision pass.
- A real hover and a real tap. The tap still opens `calendar.google.com/…/day/Y/M/D`. The
  URL is built from `cell` now instead of a `Date`, with the same fields.
