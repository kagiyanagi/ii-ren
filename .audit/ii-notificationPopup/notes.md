# ii-notificationPopup — notes

## What this surface actually is

76 lines of placement and lifetime. Every control on a notification belongs to the card
kit (`cw-notifications`, done) and nothing was changed there. The whole row is: where
the stack sits, how long the layer surface stays mapped, and what it publishes to the
three surfaces that share this corner.

## The headline: the exit was deleted, for every notification

`visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked` unmaps
the layer surface in the same frame the model empties. `NotificationListView`'s `remove`
transition — a slide out to `width + removeOvershoot` plus a fade, on `elementMoveExit`
— then plays to a surface nobody can see. The card disappears, which is exactly what it
is supposed to do, so there is no symptom and no still frame that shows it.

It was not an edge case. One notification at a time is the ordinary case, so **the last
card of every burst, which is usually the only card, vanished with a hard cut.**

The window now outlives the list by a grace timer set to `elementMoveExit.duration`.

**The grace is a latch, not `hasPopups || exitGrace.running`.** That binding reads like
the same thing and is not: it and the handler that starts the timer are two connections
to one change signal, and nothing fixes which runs first (2.9), so the surface can unmap
for a frame before the grace begins. `mapped` is written only by the handler and by the
timer, and `visible` reads nothing else. `check-notification-popup.py` asserts both the
latch and that the grace is `>=` the remove transition's duration, with both numbers
read out of `Appearance.qml` and `StyledListView.qml` rather than transcribed — so
retiming the shared list's `remove` fails here instead of silently outrunning the grace.

## The published height had to learn to say zero

`GlobalStates.notificationPopupHeight` is read by `ClipboardToast`, `FastPairPopup` and
`ScreenshotPreviewPopup`, all of which treat `<= 0` as "nothing in the corner". The
value was `listview.y + min(contentHeight, height)`, which is the top margin on its own
when the stack is empty — harmless while the window unmapped instantly, and a permanent
gutter-sized inset on all three the moment the exit grace kept it mapped. Gated on
`contentHeight > 0`. The check script sweeps empty / one card / taller than the screen,
and asserts all three readers still gate on `<= 0`, so the zero keeps meaning something.

## Smaller things

- **The dodge ran on the enter spec.** `Behavior on x` was `elementMoveEnter`, which has
  `alwaysRunToEnd: true`; it is driven by a sidebar toggle and must reverse mid-flight
  (2.7). Now `elementMove`, which is the call `ii-clipboardToast` documented for the
  identical slide.
- **Two literal `4`s**, where every other surface in this corner uses
  `Appearance.sizes.hyprlandGapsOut` (5). A 1px move; a still shows nothing, which is
  why there is no `shot-before.png`.
- **`implicitWidth` is derived now** — `list + gutter + elevationMargin + sidebarWidth`,
  the split the toasts and the sidebars use — instead of `notificationPopupWidth +
  sidebarWidth` happening to come out one pixel wider than the parts.
- **The `screen` ternary** was 180 columns and read its config twice. It is a block with
  an early return, and a pinned monitor that is not connected now falls back to the
  focused one instead of `null`, which hands the choice to the compositor.
- **`WlrKeyboardFocus.None` is stated**, not defaulted. A notification never takes the
  keyboard off what the user is doing.
- `popupBounds` and the mask got the comment they never had: a `Region` over `listview`
  would swallow every click down the right edge of the screen, because the list is
  anchored top to bottom. Asserted, since it is a tempting simplification.

## Measured on a live shell

- Two cards, correct gutter, newest on top, shadows intact — `shot-after.png`. agy vision
  on `gemini-3.1-pro-high` (`--mode plan`) against the brief: "no departures".
- **The mask, both sides**, because no gate in this process tests input. Middle-click at
  (1721, 91), on the card: notification dismissed, layer gone. Middle-click at (1721,
  400), below the stack: notification still up, click reached the window behind.
  `ydotool mousemove -a` is **2× off here** — ask for half the coordinate.
- **The latch does not stick.** `notify-send`, wait out the 7s timeout, and
  `quickshell:notificationPopup` is gone from `hyprctl layers`. A stuck `mapped` has no
  visible symptom but would hold all three neighbours down permanently.

## Not measured, and why

**The sidebar dodge, at 60fps.** Under the shipped config it is unreachable:
`sidebar.position` is `"default"`, so `effectiveRightOpen` is `dashboardPanelOpen`
alone, and `GlobalStates.onDashboardPanelOpenChanged` calls `Notifications.timeoutAll()`
— opening the sidebar clears the stack before it can dodge. The dodge is only reachable
with `sidebar.position` at `"inverted"` or `"right"`, where `policiesPanelOpen` counts
and nothing times the popups out, or during the new 130ms exit grace, where the stack
now slides out of the sidebar's way as it leaves.

**For the cohesion pass:** the dodge on `elementMove` with the sidebar at `"inverted"`,
opened and closed again before the slide lands — that reversal is the whole reason for
the spec swap, and it is the one thing here a still frame cannot settle.

## Rejected

- **A window-level enter/exit.** The cards already carry `add`/`remove`. A fade on the
  surface as well would double-animate every notification.
- **A `PagePlaceholder`.** The window hiding itself *is* the empty state —
  `cw-notifications` settled this, and one added inside the view is a second ghost.
- **Touching the grouping.** Two `notify-send`s with the same app name collapse into one
  card. That is `NotificationGroup`'s business and it is already audited.
- **`waffle-notificationPopup`.** Its own queue row, and it shares nothing but a
  layershell namespace.
