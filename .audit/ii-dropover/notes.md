# ii-dropover — notes

Ran lane 1, not 2. 339 lines across three files; dispatching a brief this small
costs more than building it.

## What the diff will not show
**Shipped broken, and every gate passed.** The first version masked the card:
`mask: Region { item: shelfCard }`, unchanged from before the row. But the card now
rests at `arrowPopupScale` (0.5), and a `Region` computes the input region from the
masked item's rect *with its transform applied*, refreshing it when that item's
**geometry** changes and never when its `scale` does. So the region was baked at 0.5
at startup and stayed there: a half-size rectangle in the middle of the shelf, with
the close, both actions and the whole drop target outside it, clicking through to the
window behind. Restarting the shell was the only way to get rid of it.

Measured, not reasoned: a 3x3 grid of synthetic clicks over the card landed 1/9, and
the one that landed was dead centre. The pre-change file under the same grid landed
9/9. After the fix, 9/9.

The fix is structural and is now a gate — `tools/check-mask-regions.py`. Mask a plain
`Item` that owns the geometry (`shelfFrame`) and put the `scale`/`opacity`/
`transformOrigin` on a `Rectangle` filling it. The input region is then the card's
full box for the whole animation, which is 400ms of accepting clicks a few pixels
outside the drawn edge, and that is the right trade.

**The lesson for the process, not just this row.** `check-design.py`, qmllint,
`smoke.sh`, `check-dropshelf.py`, the design-check pass and a screenshot all went green
on a surface that could not be clicked at all. **Nothing in the audit tests input.** A
still frame proves a surface renders; it says nothing about whether the compositor is
sending it pointer events. Any row that touches a `mask`, a layer surface's geometry or
a transform on something masked has to drive a click at it — `ydotool` with the 2x
correction, and a **held** press (`click 0x40`, sleep, `click 0x80`): an instant
press-and-release in one batch is dropped by a `RippleButton` about a third of the time
and reads exactly like a dead button.


**The panel is deliberately not behind a `Loader`.** `DesktopMenu` holds its
`PanelWindow` in one and gates `active` on a `closing` flag so the exit can
finish, and that is the shape this surface started toward. It was rejected for
two reasons, both written into `check-dropshelf.py`:

- `DragProxy` lives on the panel and owns the mime data of an in-flight drag.
  Destroying the window mid-drag frees it while the compositor is still reading,
  which is a segfault, not a glitch — the same hazard the delegate comment has
  always named. A window that is never destroyed cannot hit it.
- `DesktopMenu`'s `dismiss()` exists because `closing = true` has to be set
  *before* `desktopMenuOpen = false`, or the `active` binding destroys the item
  before the handler that would have started the close ever runs. Every caller
  therefore has to route through one function. The shelf closes from
  `DropShelf.hide()`, which `removeItem()` and `clear()` call from a singleton
  that knows nothing about the panel, so there is no single door to route
  through.

`visible: dropShelfOpen || shelfCard.opacity > 0` has neither problem: the flag
is the request, the card's own alpha is what says the surface is still needed,
and the two are read in one binding rather than raced across two.

**Measurement trap, if the card looks wrong in a screenshot.** A scan for "not
the wallpaper" around the card reads the shadow's alpha ramp as card, and a shot
taken within ~400ms of the open catches the scale mid-flight. One such reading
came out 308×216 against a 360×216 card and cost half an hour. The card's real
geometry is worth logging rather than measuring: a throwaway `Component.onCompleted`
that stores a closure over `width`/`height`/`scale`/`opacity` on the `Scope`, plus
a temporary `dbg()` on the existing `IpcHandler`, prints it to `qs -c ii log` and
comes back out in one `sed`.

**There is no `shot-before.png`.** The first capture of the session came back a blank
white frame and the retry hung (below); by the time capture worked the surface was
already rebuilt. The before state is described in the brief instead — a centred
"4 items" label under the strip, three equal-width buttons, and no motion at all.

**`grim` hung once**, for over two minutes, with no output and no error, on the
first capture of the session; a `timeout 15 grim` on the next try succeeded
immediately and every time after. Wrap it — an unwrapped `grim` is what a stuck
capture looks like from here.

## For the cohesion pass

- **The open and close**, which did not exist at all before. `ArrowPopupMotion`
  out of the corner nearest the drop point — the fourth caller of the composite
  and the first that was not a transcription being collapsed. Worth watching
  against `DockContextMenuBase`, since both now grow out of a point rather than
  a widget.
- **The card's resize**, `elementMoveFast` → `elementResize`, which fires every
  time an item lands on an open shelf.
- **Tile add and remove**, new: `elementMove` scale in, `elementMoveExit` out,
  `displaced` on `x`. A horizontal list is the only one in the shell, so nothing
  else sets the expectation.
- **The tile's remove chip**, `elementMoveFast` with `alwaysRunToEnd` overridden to
  `false` at the `createObject` call — the only place in the repo that does that, and
  the alternative was a third hover-shaped `AnimSpec` beside `iconHover` for one chip.
  `AnimSpec` defaults `alwaysRunToEnd` to **true**, so every hover fade built from a
  spec that does not opt out runs to end; the dock hit this and answered it with a new
  token. Worth deciding which of the two is the pattern.
- **Radius.** The card is `rounding.large`, matching `DesktopMenu`, where
  DESIGN.md 9 says a popup is `verylarge`. `DesktopMenu` is the recipe's own
  worked example and disagrees with it, so this followed the sibling rather than
  splitting the difference. Both or neither.

## Rejected

- **`StyledListView` for the tile strip**, which the pack flags as a reuse miss.
  It is vertical by construction — `ScrollBar.vertical`, a `Behavior on contentY`,
  `add`/`displaced` transitions that move `y`, and a `remove` that slides a leaving
  row out by `root.width`. Turned sideways it animates the wrong axis on every
  transition. The parts that do apply — the specs, `DragOverBounds`,
  `StyledScrollBar` — are on the raw `ListView` instead, on the right axis.
- **A scrim and outside-click dismiss**, which DESIGN.md 9 asks of a popup. The
  whole surface is click-through on purpose: the window you are dragging into is
  behind it. Recorded in the brief as a deliberate departure.
- **`WlrKeyboardFocus.Exclusive`**, which `DesktopMenu` needed because nothing
  ever handed it focus. Here it would take the keyboard away from the application
  being dragged into, which is the one thing this surface must not do. `OnDemand`
  means Escape works once the card has been clicked.

## Left for another row

- **Dragging the whole pile out in one gesture.** The service already models it
  (`copyAll()` emits a uri-list) and `DragProxy` would take a list where it takes
  a path. It is the feature the name "dropover" implies and the shelf does not
  have; it is a feature, not a defect, so it did not ride in on an audit row.
- **`maxItems: 30`** silently drops the 31st file with no feedback.
- **`ClipboardToast`'s masked card**, which is the same shape at `scale: 0.8` and is
  in `check-mask-regions.py`'s `KNOWN`. It could not be triggered from `wl-copy` in
  this session, so whether its geometry settles late enough to re-bake the region at 1
  is **unmeasured**. `Cheatsheet`'s was measured and is clean — its content loads
  lazily, so the sheet resizes after the reveal and the region re-bakes at full size,
  which is luck rather than design and is why it is still listed.
- **`DesktopMenu`'s hand-assembled `ArrowPopup` motion.** Its row landed four
  commits before `ii-dock` extracted `ArrowPopupMotion`, so decision 14's count
  is now two of four collapsed with `DesktopMenu` still transcribing it. This
  surface is a new caller of the composite, not one of the four.
