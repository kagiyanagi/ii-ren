# cw-notifications — notes

## The decision the brief asked for: the group root stays a MouseArea

`NotificationGroup` is rooted in a bare `MouseArea`, which the pack flags as a
rebuilt `RippleButton`. It is not one, and it should not become one:

- The card has **no left-click action**. Right-click expands it, middle-click and
  a swipe dismiss it. There is nothing for `RippleButton.releaseAction` to carry.
- §3.2 forbids a ripple on "a whole row that is really a layout", and forbids a
  second ripple inside a rippled parent. The expander in the header *is* a
  `RippleButton`, so a rippled group would break the second rule outright.
- `SwipeDismissible` is a `DragManager`, which is itself a `MouseArea` filling
  the root. `RippleButton` installs its own `MouseArea` over the background, and
  the two would fight for the press — §10.12.

So the group takes §3.1's **second-ranked** mechanism instead: a `StateOverlay`
inside the card, bound to hover / focus / pressed / dragged. That is the whole of
finding 1 for this family — before this the card answered a pointer and a swipe
and rendered nothing at all.

Two details that are easy to get wrong and are load-bearing here:

- **The three pointer states exclude each other.** `hover: containsMouse &&
  !pressed`, `press: pressed && !dragging`, `drag: dragging`. `StateOverlay`
  composites its layers independently, so hover + pressed stacked is 0.18, which
  is the *drag* token, not the pressed one. `SecondaryTabButton` and
  `ConfigListViewEntry` already write it this way; that is the convention.
- **The corners are set explicitly.** `background` has `clip: true`, and Qt's
  `clip` is a bounding-box scissor — it does not follow `radius`. Without all
  four `*Radius` on the overlay the film squares off the card's rounded corners.
  `GroupButton` does the same thing for the same reason.

`focused: root.activeFocus` renders but is currently unreachable: a `MouseArea`
takes no focus on its own, and the popup's layer surface has no keyboard focus at
all. **Deliberately not given `activeFocusOnTab`** — that would insert every
notification card into the sidebar dashboard's tab order, which is a caller-side
behaviour change this family is not allowed to make and cannot verify. The layer
is wired so that whoever does give the card focus gets the state for free.

## Expansion: the headline bug, and why the fix is shaped like this

`toggleExpanded()` used to read:

```qml
if (expanded) implicitHeightAnim.enabled = true;
else implicitHeightAnim.enabled = false;
```

so **collapsing animated and expanding snapped**, and both the height and the row
spacing ran on `elementMoveFast`, which is the *default effects* spec on a size
(§2.1). Three faults, none of them visible to `check-design.py`: a disabled
Behavior is an absence, and the checker's `spatial-on-effects` rule only catches
the opposite mistake.

Now one `property AnimSpec expandSpec` drives both the card height and the inner
list's spacing, and `toggleExpanded()` writes it: `elementMove` (default spatial,
500ms, §9's "group expansion on default spatial") to expand, `elementMoveExit`
(fast effects, 130ms) to collapse, per §2.5.

It is set **inside the function**, not from a binding on `expanded`. §2.9's trap
is that a Behavior bakes its duration when the binding that *writes* the property
runs, and a sibling binding on the same driver is not necessarily current by
then. A function that assigns the spec before flipping `expanded` sidesteps the
ordering question entirely — same outcome as `PagePlaceholder`'s in-binding
assignment, with less to get wrong.

`tools/check-notification-expansion.py` is what keeps it: it asserts the spec
property exists, that the toggle assigns two *different* specs to it, that at
least one is spatial, that the toggle does not disable a Behavior again, and that
no `Behavior on implicitHeight/spacing/rotation/anchors.leftMargin` anywhere in
the family is back on `elementMoveFast`. Mutation-tested against all six.

## What was checked and deliberately left

- **`ClippingRectangle` is not the §8 fix it looks like.** Both remaining
  `layer.enabled` + `OpacityMask` pairs (the round avatar in
  `NotificationAppIcon`, the round clip on the actions row in `NotificationItem`)
  are effects inside a repeated delegate, which §8/§10.11 want gone, and §8 says
  to prefer a native radius. Quickshell's `ClippingRectangle` is the obvious swap
  and is **strictly worse**: read its source — it is an internal `Rectangle` with
  `layer.enabled`, plus a `ShaderEffectSource`, plus a `ShaderEffect`. Two FBOs
  and a shader where the mask is one FBO. Its own doc says "It costs more than
  Rectangle". Both masks stay, with a `design-ok` comment saying so, and both are
  gated: the avatar's only exists when the notification carries an image, the
  actions row's only when the row is expanded (`visible: opacity > 0`).
  `StyledFlickable` does **not** clip, so the actions mask is also the only thing
  keeping a pill inside the card — it is not decoration.
- **No `PagePlaceholder` in `NotificationListView`.** The sidebar caller
  (`modules/ii/sidebarDashboard/notifications/NotificationList.qml`) already has
  one as a sibling of the list, and the popup window sets `visible:
  popupList.length > 0`. One added inside the view would be a second ghost
  drawn behind the first.
- **The expander stays visible for a one-item group.** Expanding a lone
  notification is what reveals its actions, so it is not a dead control; only the
  count label hides at `count <= 1`. That is the one-item edge state.
- **The `•` between app name and time is not a §5.5 divider.** It is Android's
  own header separator glyph, inline in a text run, not a bar between sections.
- **`contentColumn`/`header` keep `spacing: 6`.** §5.1 allows 6 and 10 "where a
  sibling in the same surface already does", and both do.
- **`copyIconTimer.interval: 1500` is a dwell, not an animation.** No token
  covers how long a "copied" tick stays up. Commented rather than tokenised.

## Smaller things fixed while reading

- `NotificationAppIcon.shape` called `Math.random()` **inside a binding**, so the
  urgent shape re-rolled on every re-evaluation and `ShapeCanvas` morphed the
  icon between VerySunny and SoftBurst each time. Rolled once into
  `urgentShapeIndex` now.
- `implicitSize: 38 * scale` multiplied by `Item.scale`. `MaterialShape` has no
  `scale` of its own, every caller overrides `implicitSize`, and animating the
  icon's scale would have resized it. Now just `38`.
- Both swipe snap-backs specified `elementMove`'s *duration* with
  `expressiveFastSpatial`'s *curve* — a spec that exists in neither table. Now
  `elementMove.numberAnimation`, which is also what `SwipeDismissible`'s own
  destroy animation uses.
- `NotificationActionButton` painted its label with `Appearance.m3colors.*`
  rather than the semantic layer (§6.1), and on the critical variant it used
  `m3onSurfaceVariant` **over a `colSecondaryContainer` fill** — the wrong pair.
  Now `colOnSecondaryContainer` / `colOnLayer4`, through one `colContent`
  property that also feeds `colStateLayer`, so the inherited focus and pressed
  films are films of this button's content colour and not layer 1's.
- `NotificationGroupExpandButton.colBackground` was
  `ColorUtils.mix(colLayer2, colLayer2Hover, 0.5)` — a hand-mixed tint, which
  §3.1 forbids outright, and a resting colour half-way to its own hover, so there
  was nearly nothing between rest and hover. It is a control on a layer-2 card,
  so it is layer 3 now.
- `NotificationActionButton` redeclared `buttonText`, shadowing `RippleButton`'s.
- The expander's `contentItem` had `anchors.centerIn: parent` **and** was being
  sized by `Control::resizeContent()` — §10.14. The anchor moved to the row
  inside it, and the wrapper gained the `implicitHeight` it never had.
- `urgency` is a **string** everywhere: `Notif.urgency` is
  `notification?.urgency.toString()`, i.e. the enum's decimal. `NotificationGroup`
  compensated with `=== NotificationUrgency.Critical.toString()` (works, and
  qmllint flags `toString` as not an enum entry) while `NotificationAppIcon` used
  a bare `===` against the enum (silently false for any caller handing it the
  service's value). All three now go through `Number(urgency) === …`, which reads
  the string form, the live enum, and the JSON-restored form.
- `itemIndex` is passed down from each list's delegate instead of
  `root.index ?? root.parent.children.indexOf(root)`. `index` is not a member of
  either widget — it only existed because the delegate declared it — so qmllint
  flagged both, and the `children.indexOf` fallback was dead.
- The inner delegate anchored itself to its `ListView`'s contentItem. A delegate
  that anchors inside its view is undefined behaviour; it takes
  `width: ListView.view.width` now, like the outer one already did.
- `ScrollEdgeFade` ramps from an **opaque** copy of `color` (default
  `colLayer1Base`) to transparent, and the notification card is layer 2 or the
  popup surface container — so the action row's edge fade was painting a band of
  the wrong layer. `NotificationItem.surfaceColor` carries the card's real colour
  down from `NotificationGroup`.
- `pragma ComponentBehavior: Bound` on the three files that lacked it, plus the
  ~40 unqualified accesses that came with it. qmllint on this family went from 43
  warnings to 1 (`ScriptModel.values` wants a `QVariantList` and gets a
  `QList<QString>`; `.slice()` does not silence it and costs a copy per model
  update, so it is left).
- Dead: `multipleNotifications` (zero readers anywhere), an unused
  `Quickshell.Hyprland` import, an unused `qs.services` import, an unused
  `appIconImage` id, two missing trailing newlines.

## Needs a change outside this family

Nothing. `SwipeDismissible` needed no change: both surfaces here already have a
real `ListView` owner — the outer `NotificationListView`, and the inner
`StyledListView` inside `NotificationGroup` — so `owner.parent.parent` resolves
and the 0.3 / 0.1 neighbour nudge works as §3.6 specifies. This is the opposite
of `ii-clipboardToast`, which had a lone card and no view.

**That inner `StyledListView` is load-bearing and must not be "simplified" to a
`Column` or a `Repeater`.** It carries `interactive: false` and
`implicitHeight: contentHeight`, so it looks exactly like a column — but it is
the only thing giving each row's `SwipeDismissible` its
`dragIndex`/`dragDistance`/`resetDrag`. A note to that effect is now in the
file's doc comment.

For `cw-gestures`, one observation rather than a request: `SwipeDismissible`
calls `root.qmlParent.resetDrag()` and writes `qmlParent.dragIndex` with no null
guard. With a `ListView` owner that is fine and always has been; if that family
loosens the coupling for non-list owners, these two call sites are where a lone
owner would throw.

## Rejected

- **Making the group a `RippleButton`.** Reasoned out at the top.
- **`ClippingRectangle` for the two masks.** Reasoned out above — it is two FBOs
  and a shader against the mask's one. This is the single most likely thing for a
  later session to "fix" backwards.
- **Giving the card `activeFocusOnTab`.** Renders the focus layer, but changes
  the sidebar's tab order, which is a caller's business and unverifiable from
  here.
- **Eliding `NotificationActionButton`'s label.** The action row lives in a
  `StyledFlickable` whose `contentWidth` is the row's implicit width, so the row
  is always as wide as its buttons need and scrolls instead of squeezing. An
  elide would also make the button report its *elided* width as
  `implicitWidth` — the trap `NotificationGroup`'s `TextMetrics` exists to dodge.
- **Dropping the `•` separator in the header** as a §5.5 divider. It is a glyph
  in a text run, not a bar.
- **A second check script** for the four state layers. One concern per script is
  the house shape, and the expansion is the half that is invisible when broken —
  a missing state layer at least shows up as a card that does not react.

## Still needs a running shell

Nothing here was verified against a live shell; the parallel rules forbid it and
the orchestrator runs smoke at the end. Four things are worth a real look:

1. **The expansion, at 60fps, on a group with 3+ notifications.** The Behavior
   was disabled on expand by someone, and the most likely reason is that the
   inner `ListView` lands its `contentHeight` in steps as it creates delegates,
   so a 500ms Behavior chases a moving target. `elementMove` has
   `alwaysRunToEnd: false`, so each step should retarget smoothly rather than
   restart — but that is an argument, not a measurement. If it does read as
   laggy, the fix is `elementMoveSmall` (fast spatial, 350ms) for the enter, not
   switching the animation off again.
2. **`implicitHeight: 40` on the action buttons** (was 34). It grows an expanded
   notification by 6px. Check it against a notification with three or more
   actions in the popup, which is the narrowest place it appears.
3. **The state film over a popup card**, which is translucent. That is the case
   `StateOverlay` exists for, but it has never been rendered on this surface.
4. **`colLayer3` on the expander** against a popup card, whose background is
   `colBackgroundSurfaceContainer` rather than `colLayer2`. `colLayer3` is solved
   as an overlay on layer 2's base, so it should sit a step above either — worth
   a glance in both the popup and the sidebar.
