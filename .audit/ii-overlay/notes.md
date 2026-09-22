# ii-overlay — notes

Ran lane 1, not the lane 2 the queue said: the row turned out to be two lifecycle bugs in
the shared chrome rather than a layout, and neither had a symptom a brief could describe
to someone else.

## No screenshots

`shot-before.png` / `shot-after.png` are **missing**. The laptop panel was in DPMS off for
the whole session (`hyprctl monitors` → `dpmsStatus: 0`), and `grim` blocks forever on a
display that is producing no frames — `timeout 15 grim` returned 124 on six attempts,
including with nothing on screen at all. `.audit/ii-dropover/notes.md` records a one-off
grim hang that cleared on the next try; this is not that, it is the display being asleep,
and waking someone's laptop to take a picture of it is not a gate. Everything below was
measured instead, from `hyprctl layers` and from a `qs -p` probe. **The cohesion pass needs
both shots** — open with `qs -c ii ipc call overlay toggle`.

## What was actually wrong

Two of the four had no visible symptom in either direction.

**A pin could not survive a shell restart.** `Loader.active` was
`overlayOpen || OverlayContext.hasPinnedWidgets`, and `hasPinnedWidgets` came from a list
that live `StyledOverlayWidget`s pushed themselves onto — widgets that only exist *inside*
the window that list decides to open. So at startup nothing was alive to say it was
pinned, and the window never mapped. Measured: set `recorder.pinned = true` in
`~/.local/state/quickshell/states.json` with the shell already up and the overlay never
opened → `hyprctl layers` had no `quickshell:overlay`. Open the overlay once and it
appeared, and then survived the close — which is why this never looked broken in a session
where you had just pinned something by hand.

**And a closed pin was never released.** Same list, other direction. `close()` filters the
identifier out of `Persistent.states.overlay.open`, the `Repeater` destroys the delegate,
and nothing ran on the way out: `pinnedWidgetIdentifiers` kept the name for the rest of the
session, so a full-screen `WlrLayer.Overlay` surface stayed mapped over everything with
nothing in it, and `clickableWidgets` kept the destroyed `Item` that the mask's `regions`
still pointed at. Measured the same way: remove `recorder` from `open` while it is pinned →
the layer was still there. Both are 1 and 0 now.

**`property bool open: Persistent.states.overlay.open`** is what made the second one
unrecoverable rather than late. A `list<string>` assigned to a `bool`: QML coerces any
object to `true`, an **empty list included** — measured with a four-line `qs -p` probe
(`property bool fromEmpty: src.empty` → `true`), not assumed. So `actuallyPinned` and
`actuallyClickable` could never fall, and the guard that was written to mean "this widget
left the open list" said `true` from the first frame. The intent was `.includes(identifier)`;
it is gone instead, replaced by a derived list and a `Component.onDestruction`, because the
only thing it was guarding is now computed from the same place the truth lives.

**The surface had no exit.** The usual shape — `Loader.active` reading the open request.

## Retimings, for the cohesion pass

Measured with `hyprctl layers` polled in a loop, and with a `qs -p` probe that samples
`OverlayContext.shownProgress` / `openedProgress` on a 16ms `Timer`.

| | before | after |
|---|---|---|
| surface unmaps after the close request | ~30ms (the next frame) | ~148ms |
| `shownProgress` 0 → 1 (opacity, `elementMoveFast`) | n/a | 1.000 at 193ms, **never above 1** |
| `openedProgress` 0 → 1 (scale, `elementMoveEnter`) | 500ms, first open only | 1.000 at 210ms, overshoots to **1.014**, settled by 465ms |
| exit, both | none | 0 by ~118ms, latch cleared on the same frame |

The 1.014 is the expressive spatial overshoot landing on the scale where it belongs —
`scale = 1 + 0.08 * (1 - p)`, so the card settles a hair under 1 and comes back. The
opacity is on a separate value for exactly this reason (3): sharing one would have faded
past opaque and back.

Also **the enter used to run once per window lifetime**, not once per open. It was
`Component.onCompleted: scale = 1`, so with anything pinned — the case where the window
never dies — every open after the first had no zoom at all, while the scrim and the taskbar
still faded. Driven off `overlayOpenChanged` now.

## Found after the commit, from a screenshot the user took

**The assistant's input row took the whole card.** `ToolbarButton` declares
`Layout.fillHeight: true`, and a nested layout that holds a child which fills starts
filling itself -- which beats `Layout.preferredHeight`. So `AssistContent`'s 38px input
row was 389px tall: the transcript above it collapsed to 9px, putting its empty-state
line up against the title bar, and `IconToolbarButton`'s `implicitWidth: height` turned
the eye toggle into a 390px circle. `Layout.fillHeight: false` on the row, measured back
to 38 with the buttons at 35x38 and the field 370 wide.

Pre-existing, from `a5bb8d03e`, and not in the commit above -- but this row should have
caught it. Two reasons it did not, both worth naming: there were no screenshots (the
display was asleep), and `pack.py`'s reuse heuristic flagged the `ScrollView` in this
file, which I checked by asking whether `StyledScrollView` exists (it does not) rather
than by asking whether the row worked. A stale reuse hint is still a pointer at a line
worth reading.

**And the composer only ever showed one line.** Same row, second report. With
`wrapMode: Wrap` in a one-line viewport the draft scrolls out of sight as you type, so
the caret sits in what looks like an empty box -- the text is all still there and all
still sent on Enter, which is what made it read as a display bug rather than a loss.
Three traps had to be measured out of this one row, and the order matters because each
hides the next:

1. **The row's height hint is read once.** A `QQuickLayout` honours a *constant*
   `Layout.preferredHeight` on a nested layout and ignores every later change to it.
   Measured across four ways of feeding it the draft's height -- a binding on
   `field.implicitHeight`, one on `contentHeight`, one on `lineCount`, and an imperative
   assignment deferred with `Qt.callLater` -- the row stayed 35 while the value it was
   bound to read 168. So the composer cannot grow with the draft; three lines is a
   constant.
2. **A child that opts out of filling caps the row at its own height.** Giving the
   buttons `Layout.fillHeight: false` alone pinned the row to 35 no matter what it asked
   for. They need `Layout.alignment: Qt.AlignBottom` as well, which is also where a
   composer button belongs -- and is what keeps them square, since `IconToolbarButton` is
   `implicitWidth: height` and a filling one stretched to a 35x73 oval.
3. **`anchors.fill: parent` on a `TextArea` inside a `ScrollView`** sizes the field by
   the thing that is supposed to be measuring it. Measured at 20px wide when empty and
   **680px inside a 460px card** when full, so the wrap points were wrong as well as the
   height. `width: inputScroll.availableWidth` instead: 407 in a 460 card, 327 in a 380
   one, `lineCount` 1 -> 16 -> 20 as it should be.

The height is `oneLine.height * 3 + padding`, off a `TextMetrics` on the field's own
font: `StyledTextArea` sets `pixelSize.small` and deriving a line height from that token
lands a pixel off what it renders.

**The sidebar's Hermes composer has trap 3 too** -- `Hermes.qml:900`, a `StyledTextArea`
with `anchors.fill: parent` in a `ScrollView` whose `Layout.preferredHeight` reads that
same field's `height`. It is a wide panel so nobody has noticed, and it is a different
queue row (`ii-sidebarPolicies`); it goes there rather than here.

A scan of the whole shell for the same shape -- a nested layout with a fixed
`preferredHeight` holding a `ToolbarButton`/`IconToolbarButton`/`ToolbarTextField` --
returns exactly this one caller, so the shared widget is left alone and
`check-overlay.py` holds the single site.

## Things that were checked and left alone

- **The focus grab never arms on the first open.** `delayedGrabTimer` and the `Connections`
  that starts it live *inside* the `PanelWindow`, which is created **by** the signal they
  are listening for, so the first `overlayOpenChanged` is missed and `grab.active` stays
  false. Pre-existing, unchanged, and harmless: `WlrKeyboardFocus.Exclusive` covers the
  keyboard, `WidgetCanvas.onClicked` dismisses on a click anywhere, and Esc works. The
  latch makes it *more* likely to arm, not less, because the window now survives a close.
- **`regions:` leaks.** `OverlayContext.clickableWidgets.map(w => regionComponent.createObject(...))`
  builds a fresh `Region` per clickable widget every time the binding re-evaluates and
  never frees the previous set. A handful of QObjects per session; not worth the shape it
  would take to fix declaratively.
- **`iconSize:` literals.** 30 instances of `iconSize: 20` and 26 of `iconSize: 22` across
  `modules/`, and `check-design.py` does not flag them — literal icon sizes are the house
  norm, so changing this surface's would be churn against nothing.
- **`StyledScrollView`.** `pack.py`'s reuse heuristic suggests it for the two raw
  `ScrollView`s. It does not exist in this repo; the hint is stale.
- **`notes/NotesContent.qml`** (522 lines) and **`crosshair/CrosshairContent.qml`** (198).
  Out of scope in the brief — Notes has two callers in `modules/ii/background/widgets/`,
  which is the vendored tree, so touching it is a rule-9 change that wants its own row.

## Gates

`tools/check-overlay.py`. Every one of its eight rules was run against `HEAD` before the
fix and fires there: the latch, the list-to-bool, the shared card's effect, the unfiltered
`Repeater`, the missing tooltips.

`tools/check-mask-regions.py` **grew two holes shut** and needs a word, because it reported
`ok` on this surface the whole time it was wrong:

1. Its `item:` pattern was anchored on a bare identifier at end of line, and this window
   masks `GlobalStates.overlayOpen ? overlayContent : null`. A ternary matched nothing, so
   the surface was never scanned at all. It now takes every identifier in the expression
   that is also declared as an `id:` in the file.
2. The masked item is normally a *component instance*, and a resting scale on that
   component's own root lives in a different file — which the old scan never opened.
   `component_root_transforms()` follows the type name to `<Type>.qml` and reads the root's
   own properties.

Both were negative-tested: putting `scale: 1.08` back on `OverlayContent`'s root makes it
`FAIL modules/ii/overlay/Overlay.qml:44 masks 'overlayContent', which sets scale`. That is
the shape the overlay actually shipped in, and it is why the zoom now lives on a child
plane rather than on the item the window masks.

## Unmeasured

- **Input.** Nothing here drives a real click at the surface — the display was asleep, and
  `AUDIT.md`'s gate table says a row touching a `mask` has to. The mask's *item* is
  unchanged in shape (still `overlayContent`, still untransformed now rather than
  accidentally), and the `regions:` half is the same expression over a list that is now
  correctly emptied. The click grid still owes this surface a pass.
- **The extension widget path.** No extension in `user_widgets/` declares an
  `overlayWidgets` contribution point, so the `extensionWidgets`-derived half of
  `pinnedWidgetIdentifiers` is reasoned from `ExtensionManager.getContributionPoint`
  merging `saved?.pinned` into each entry (`ExtensionManager.qml:510`) and from
  `onExtensionOverlayConfigsChanged → refreshExtensions`, which is what makes it reactive.
  Never exercised.
- **The taskbar tooltips** and the two deleted dividers were not looked at.
