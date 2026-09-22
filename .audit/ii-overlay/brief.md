# ii-overlay — brief

**Purpose.** A summonable canvas of free-floating widgets over whatever is already on
screen — crosshair, recorder, resources, mixer, media, notes, assistant. You press a key,
the desktop dims, the widgets are there; you act on one and dismiss it. Widgets you pin
stay after the canvas goes.

**Primary action.** Reach one widget and act on it. Adding, removing, moving, resizing and
pinning are setup, done rarely; the taskbar that owns them is chrome, not the point.

**Hierarchy.** The widget cards first — they are the only thing the user came for, and
they sit where the user last dragged them. The taskbar second, one strip under the bar,
dim against the scrim until it is wanted. The scrim third: it exists to push everything
behind the overlay back, not to be looked at.

**Reference.** Android's **Game Dashboard**: a scrim, a toolbar of round widget toggles
hanging from the top edge, and draggable cards that survive dismissal when pinned. The
same shape and the same reason for it — reach a tool without leaving what is behind.

**Interaction.**

*The surface.* Two progress values on `OverlayContext`, because a scale and an opacity may
not share a spec (3):

| | enter | exit |
|---|---|---|
| `openedProgress` — scale, may overshoot | `elementMoveEnter` (500ms spatial) | `elementMoveExit` |
| `shownProgress` — opacity, must not | `elementMoveFast` (200ms effects) | `elementMoveExit` |

The canvas settles from 1.08 to 1 as everything on it fades up, and lifts back to 1.08 as
it fades out. Transform origin is the screen centre: a keybind has no origin on screen, so
the surface has nowhere to grow *out of* and settles onto it instead. **The zoom is
suppressed the moment anything is pinned** — a pinned crosshair may not drift a pixel when
the overlay is dismissed, and the pinned card lives inside the plane that scales.

*The window.* `Loader.active` reads a `rendered` latch, never `GlobalStates.overlayOpen`.
The two hang off one change signal in an undefined order; the binding wins and the exit
plays to a destroyed component (`ii-onScreenKeyboard`, `ii-mediaControls`, `ii-osd`,
`ii-cheatsheet` all shipped that way). Only the exit reaching 0 clears the latch.

*The cards.* One number, four states: a card is at `shownProgress` while it is transient,
and at its `restingOpacity` once pinned — full, or `overlay.clickthroughOpacity` when it is
also click-through. Its chrome — background, outline, title bar — is transparentized by
`1 - shownProgress`, so all of it leaves on one spec with no Behavior of its own.

*The taskbar.* Fades on `shownProgress` inside the canvas's zoom. No slide of its own:
motion inside a scaling parent is two specs on one gesture.

*States.* Title-bar buttons keep `RippleButton`'s four. The nine widget toggles are
icon-only and were unlabelled — each gets the `StyledToolTip` its title-bar siblings
already have, so an icon-only strip is readable.

**Edge states.**
- *Nothing open.* Empty scrim and the taskbar. Correct as-is — the taskbar is the way back.
- *Nothing pinned, overlay dismissed.* The window unmaps after the exit, not before it.
- *Something pinned, overlay dismissed.* The window stays; the scrim, the taskbar and every
  unpinned card fade out; the pinned cards do not move.
- *Pinned, then closed from its own X.* The window must unmap. It did not: see **Delete**.
- *Pinned, then the shell restarts.* The widget must come back. It did not: see **Delete**.
- *An identifier in `open` that no widget answers to* (every extension widget, and any id
  left by an older config) put `undefined` into the built-in `Repeater`'s model. Filtered,
  the way its sibling `Repeater` already does.

**Cost.** From the pack's effect budget: eight `layer.enabled`/`OpacityMask` pairs across
four files, every one of them inside a `Repeater` delegate two files away — which is why
`check-effect-budget.py` has never seen them. The shipped default opens five widgets, so
that is seven offscreen passes standing while the overlay is up.

The one in the shared base — `StyledOverlayWidget`'s card — pays for a single square
corner: the title bar is the only child that reaches the card's edge. Round its two top
corners and the pass goes, for every widget at once: **seven passes become three.** The
three that remain each clip an image, a circle of album art or a `Canvas`, which no radius
can do natively. Ceiling: **one effect per delegate file, none in the shared base.**

**Delete.**
- `StyledOverlayWidget.open`, a `list<string>` assigned to a `bool`. QML coerces any object
  to `true`, empty list included (measured), so `actuallyPinned` and `actuallyClickable`
  have never been able to go false and the guard has never fired. With it,
  `actuallyPinned`, `reportPinnedState`, and `OverlayContext.pin()`.
- `OverlayContext.pinnedWidgetIdentifiers` as *storage*. It was reported into by widgets
  that live inside the window it decides to open, which cannot work in either direction:
  a pin never survived a shell restart, and a pinned widget closed from its own X left a
  full-screen `WlrLayer.Overlay` surface mapped for the rest of the session with a
  destroyed `Item` still in its input mask. Derived from `Persistent` instead — one
  binding replaces a registration protocol that was wrong at both ends.
- Both `Separator`s in the taskbar (11), and the clock's and battery's literal font sizes.
- `OverlayContent.initScale` and the `scale !== initScale` test that stood in for a scrim
  that had no state of its own.
- The scrim's and the taskbar's private `Behavior on opacity`: one progress, one spec.

**Out of scope.**
- `notes/NotesContent.qml` (522 lines, a tab-managing text editor) — two of its three
  callers are background widgets outside this surface, so it is a rule-9 change that wants
  its own row.
- `crosshair/CrosshairContent.qml` — a 198-line renderer of a third-party crosshair code
  format, with no shell chrome in it.
- The `regions:` list in `Overlay.qml` allocates a fresh `Region` per clickable widget on
  every re-evaluation and never frees the last set. A handful of objects over a session;
  left alone.
- `AssistContent`'s raw `ScrollView` — the pack suggests `StyledScrollView`, which does not
  exist in this repo.
