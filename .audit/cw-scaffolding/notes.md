# cw-scaffolding — notes

## The overscroll stretch, which the brief said to verify rather than assume

It works, and nobody has ever seen it.

Measured in a throwaway `FloatingWindow` harness against a live `StyledListView`,
by driving `WheelScrollHandler.overscroll` and reading the `Scale` back off
`contentItem` a frame later — the first read was wrong because `overscroll` has
its own 500ms `Behavior`, so an immediate read always says 1.0000:

| state | yScale | origin.y | expected |
|---|---|---|---|
| rest | 1.0000 | 0 | no transform cost |
| pushed past the **bottom** (+30, view 964) | 1.0313 | 0 (top) | `1 + 30/964`, far edge pinned |
| pushed past the **top** (−30) | 1.0314 | 964 (bottom) | far edge pinned |
| released | 1.0001 | 0 | springs back |

Magnitude and both origins are right — 2.6's "far edge, pinned so the content the
finger is on stays put".

**But `WheelScrollHandler` is `visible: Config.options.interactions.scrolling.fasterTouchpadScroll`,
which defaults to `false`.** An invisible `MouseArea` receives no wheel events, so
on a default config the handler never runs, `overscroll` never leaves 0, and the
stretch is dead on every list and flickable in the shell. The config key reads as
a scroll-*speed* preference; it is also the on switch for an M3 behaviour the
design law asks for unconditionally. That is a config-defaults decision, not a
widget fix, so it is in `FINDINGS.md` rather than in this diff.

Second-order, same cause: with the handler off, `boundsBehavior: DragOverBounds`
means a *drag* past the end **translates** the content, which 3.6 says explicitly
not to do — "Do not translate the content; stretch it." Feeding the drag overhang
into `overscroll` is not a small change (it needs `StopAtBounds` plus the shell's
own drag tracking), so it is also a finding, not a line here.

## Two Qt-level bugs that had nothing to do with design

Both found by putting one `ContentSection` in a harness and reading the log.

**`anchors` on an item a layout manages — 11 warnings per settings session.**
Both section widgets parented a `MouseArea` into their header `RowLayout` and
filled it with anchors. Qt prints *"Detected anchors on an item that is managed by
a layout. This is undefined behavior"* and carries on; **qmllint says nothing at
all** about it, so the boot gate never saw it. `cw-buttons` hit the same shape in
`RippleButtonWithShape` and fixed it with `Layout.alignment`; that does not work
here, because the area genuinely has to cover the row. The header is now its own
`Item` — the layout child — with the row, the interaction and the state film
anchored *inside* it. Settings log: 11 → 0.

**`ReferenceError: page is not defined`.** `ContentSection.Component.onCompleted`
read a bare `page`, the enclosing `ContentPage`'s id, resolved out of the caller's
file scope. **146 of the 177 caller files never had one** — ids do not cross a file
boundary, so every `modules/settings/widgets/*Config.qml` throws instead of
skipping registration. `page?.register` does not help: the *identifier* is
undefined, not its value. Now `typeof page !== 'undefined'`, which returns early
exactly where it used to throw, so no section's registration changes.

## The collapsible header, and why it was worth the restructure for two callers

`collapsible: true` has exactly two callers in the shell, both in
`WidgetsConfig.qml`. That is not enough to justify rebuilding the header as a
`RippleButton`, and it *is* enough that the family's one interactive widget
should not ship with zero of DESIGN.md 3.1's four states — which is what it did:
a bare `MouseArea` with a cursor and nothing else.

It now carries a `StateOverlay` (3.1's second-ranked mechanism) driven by
`containsMouse` / `activeFocus` / `pressed`, is in the tab chain, and toggles on
Space/Enter. Measured by grabbing the header to a PNG:

| | alpha at (400, 20) |
|---|---|
| at rest | 0 — nothing painted |
| focused via `forceActiveFocus(Qt.TabFocusReason)` | **0.098**, colour `colOnLayer0` |

0.098 is 25/255; the M3 focus token is 0.10. That is 8-bit quantisation, not a
wrong token.

The `MouseArea` is declared **before** the row, not after, so the info icon's own
area still wins the pointer — nothing in the row accepts a press, so one falls
through to the header. It is also `visible: root.collapsible`, which is what stops
the other 175 sections advertising a pointing hand over a title that does not
click. `visible` and not `enabled`: an invisible item registers no cursor, and
whether a *disabled* `MouseArea` still claims its `cursorShape` is not something
the Qt docs commit to.

The subsection header additionally takes 3.4's 32px minimum, but only when
`collapsible` — its label row is ~22px and raising it unconditionally would push
the content of all 63 subsections down.

## Motion, measured

`FrameAnimation` sampling every frame, min/max/rest over the whole animation:

| what | min | max | rest | length |
|---|---|---|---|---|
| chevron 0 → −90 (`elementMoveSmall`) | **−98.27** | 0 | −90 | 350ms |
| chevron −90 → 0 | −90 | **+8.28** | 0 | 350ms |
| `Revealer` height in (`elementMove`) | 0 | **81.11** | 80 | 500ms |
| `Revealer` height out (`elementMoveExit`) | **0.00** | 80 | 0 | **133ms** |
| `PagePlaceholder` opacity in (`elementMoveFast`) | 0.00 | **1.00** | 1.00 | 200ms |
| `PagePlaceholder` opacity out (`elementMoveExit`) | 0.00 | 1.00 | 0.00 | **133ms** |
| `PagePlaceholder` rotation in (`elementMoveEnter`) | −70 | **+0.97** | 0 | 500ms |
| `PagePlaceholder` rotation out (`elementMoveExit`) | −70 | 0 | −70 | **133ms** |

The chevron overshoots 9.2% and settles — which is the curve, not a guess:
`expressiveFastSpatial` is `[0.42, 1.67, 0.21, 0.90]` and **1.67 is a control
point, not the peak**. The actual maximum of that bezier is 1.092, at t ≈ 0.39 of
the duration. Worth writing down, because `cw-primitives`' notes describe the same
curve as "peaks at 1.67", and on a 90° rotation that reading would have ruled out
the correct spec for a 150° swing that never happens.

Both spatial rows overshoot and settle; neither effects row leaves [0, 1] or dips
past its target. The placeholder's opacity was on `elementMoveEnter`, a spatial
spec — the `spatial-on-effects` hit `cw-primitives` left for this row.

## A Behavior cannot read its own direction, and that cost most of the session

The obvious way to give one property an enter spec and an exit spec is to let the
animation ask:

```qml
Behavior on opacity {
    NumberAnimation { duration: root.shown ? enter.duration : exit.duration }   // wrong
}
```

**It silently runs the exit on the enter's spec.** A Behavior bakes duration and
curve at the instant the binding that *writes* its property runs, and the other
bindings on `shown` have not necessarily been re-evaluated by then. Traced with
`console.log` in the change handler, the animation and the spec property:

```
SHOWN -> true
ANIM start  shown=true  spec=130  anim=130     <- the exit spec, on the way in
SPEC -> 200                                    <- the enter spec, one step late
```

Three things that look like fixes and are not:

- **Declaration order.** Moving the spec property above the animated one fixes it
  in `Revealer` and does nothing in `PagePlaceholder` — `opacity`'s binding beat a
  spec declared at the very top of the object. An isolated harness with the
  trigger on a *parent* object orders correctly every time, which is why this
  reads as reliable until it is not. Anything that depends on which binding the
  notifier reaches first is luck.
- **A `ScriptAction` first in a `SequentialAnimation`.** The job is built from the
  declarative object before the script runs, so the values land **one trigger
  late**: measured, the first reveal ran `NumberAnimation`'s default 250ms and the
  collapse got the spec the script had set during the reveal.
- **`pragma ComponentBehavior: Bound`.** Tried on the hypothesis that an inline
  `component` was failing to capture an outer id. No change.

What works, by construction: assign the spec **inside the binding that drives the
animation**, which necessarily runs before the write that starts it.

```qml
property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
opacity: {
    root.fadeSpec = root.shown ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit
    return root.shown ? 1 : 0
}
```

Writing a property from inside another property's binding is not a shape to reach
for casually, and it is the only one measured correct in both widgets, in both
directions, across repeated toggles. It is now DESIGN.md 2.9, because every later
row that implements 2.5 on a `Behavior` will walk into this, and
`check-scaffold-containers.py` fails on the ternary-in-its-own-binding form.

## Also fixed here, found while reading

- **`StyledListView`'s `add` animated `opacity` and `scale` on one spatial spec.**
  The scale is meant to overshoot; the fade is not, so it reached 1 at ~60% of the
  500ms and then sat there. Split: opacity on `elementMoveFast`, scale on
  `elementMove`, and only when `popin` — the old `properties: popin ?
  "opacity,scale" : "opacity"` string is gone. `check-design.py`'s
  `spatial-on-effects` rule cannot see this: it only reads `Behavior` blocks, not
  `Transition` animators.
- **`remove` was the enter spec too.** A row leaving now rides `elementMoveExit`
  both legs (2.5's exit spec, monotone), so the fade cannot dip past 0 and blank
  the row before the slide lands. The `*Displaced` transitions keep `elementMove`
  — their `opacity,scale → 1` legs are snap-backs for an item interrupted
  mid-`add`, not motion anyone watches, and splitting five of them is thirty lines
  for nothing.
- **`StyledScrollBar` faded on `duration: 350` with the effects curve** — the fast
  *spatial* duration wearing an effects curve, i.e. neither spec. Now the
  `elementMoveFast` one-liner. Its `radius: width / 2` became
  `Appearance.rounding.full`, which clamps to the same 2px and squares off in
  sharp mode, where `width / 2` never did.
- **`PagePlaceholder`'s title could not elide.** The description had a
  `Layout.maximumWidth`; the title had none, so in a narrow panel it set the
  column's width and ran past it. Measured in a 260px panel: title
  `truncated=true` at 228, description wraps to 3 lines. (5.7, 10.17.)
- **`m3colors.m3outline` → `colors.colSubtext`** in `PagePlaceholder`. 6.1 says use
  the semantic layer; `colSubtext` *is* `m3outline`, so the render is identical.
- **`rotation: -70 * (1 - shown ? 1 : 0)`** is now `shown ? 0 : -70`. Not a bug —
  the precedence works out to the same two values — but it reads like one, and the
  next person to "fix" it would break it.
- `ContentSection` dropped an unused `import QtQuick.Controls`.
- Grid: `ContentPage` 30 → 32, `ContentGroup` 3 → 4, `StyledListView` 5 → 4,
  `PagePlaceholder` 5 → 4 and ±30 → ±32, `ContentSection`'s icon tile 38 → 40
  (5.4's 40–48 tile ladder). Before/after screenshots of the settings page are
  identical apart from those 2px.

**No separators anywhere in the family** — `ContentGroup` already does 5.5
properly, with `colSurfaceContainerHigh` cards, `rounding.large` on run ends and
`verysmall` on the seams. Nothing to delete.

## What was deliberately not done

- **The expand/collapse does not animate.** The chevron rotates and the content
  still snaps. The fix wants a `clip` on the section's content `Item`, and
  `ContentGroup`'s cards deliberately bleed 8px *past* that Item on both sides
  (5.6) — clipping cuts the bleed off, so the cards would lose their overhang for
  the length of the animation and pop back at the end. Doing it properly means
  moving where the bleed lives, in the widget both section types are built on, for two callers that
  load their content through an async `Loader` and so have nothing on screen to
  animate for the first frames anyway. Wrong trade; recorded rather than bodged.
- **`FadeLoader` stays symmetric at 200/200.** It is the obvious next place for
  2.5's enter/exit split, and it is the one place not to do it: `StateOverlay`
  builds all four state layers out of `FadeLoader`, so a 130ms exit would shorten
  the release half of every button press in the shell. `cw-buttons` measured that
  composite one session ago and found it monotone because both halves share a
  duration. Trading that for 70ms on a fade-out is rule 9 in miniature.
- **`StyledScrollBar.active: hovered || pressed`** overrides what QQC2 binds
  (`movingVertically || hovered || pressed`), so the bar does not appear while the
  content scrolls — only when the pointer is on it. Probably wrong, but it is a
  visibility decision for every scrollable surface in the shell and the row that
  should make it is whichever one first misses the feedback. Left; flagged here.
- **`ScrollEdgeFade`'s `color` default is `colLayer1Base`,** the pre-transparency
  colour, so with transparency on the fade paints an opaque band over a
  translucent panel. Three of its seven callers already pass their own colour,
  which is the honest answer — the widget cannot know what is behind it. A better
  default needs the transparency pass (`colLayer1`) checked on a real panel, which
  belongs with the surfaces, not here.
- **`ContentPage` gained no `ScrollEdgeFade`.** The brief lists one "where content
  runs under a header", and the settings page does run under its toolbar — but the
  page container does not know whether there is a header or what colour it is, and
  a fade at the *bottom* of a settings page is wrong. It belongs to
  `settings-widgets`, one level up.
- **`FocusedScrollMouseArea` is untouched.** The pack flags it under "raw
  primitives → consider RippleButton / StateLayer". It is not a button: it is a
  scroll-intent tracker for the bar's scroll-to-change-volume, and it has no
  pressed or hover state to render.
- **`ContentPage`'s `spacing` went 30 → 32, not → 16.** 5.3's "sections in a panel,
  12–16" is written for a sidebar panel; these are full-page sections with a 40px
  icon tile and a 22px title, and 175 pages would visibly reflow. On the grid,
  same look.

## The check this left behind

`tools/check-scaffold-containers.py`, three concerns under one banner:

1. Both section widgets render hover, focus and pressed on the collapsible header
   through a `StateOverlay`, take tab focus, act on a key, and gate all of it on
   `collapsible`. `check-button-states.py` cannot cover this — the header is a
   `MouseArea`, not a QQC2 `Button`.
2. **No direct child of a layout anchors itself**, across all 14 family files. This
   is the one worth having: Qt reports it only at runtime, only for surfaces that
   actually load, and qmllint is silent. The rule walks brace depth and flags
   `anchors` written in a block whose *parent* block is a positioner.
3. `Revealer` and `PagePlaceholder` each name an enter spec and an exit spec, and
   neither resolves the direction in a binding of its own — the shape above, which
   fails silently and in a way no screenshot shows.

Mutation-tested eleven ways, all caught, and the committed baseline fails all
three concerns at the right line numbers.

**Generalising rule 2 to the whole repo is a real follow-up** and deliberately not
done here — it is a Qt-correctness rule rather than a design one, it would want a
home in `check-design.py`, and on a first pass it will light up surfaces nobody has
audited yet. Scoped to this family it is a regression guard; unscoped it is a
backlog.

## Driving this family, for the next session

- **`pkill -f settings.qml` kills the script that launched it.** `cw-buttons`
  wrote this down for `check-focus.qml` and it cost time again anyway, twice,
  once *with a `git stash` outstanding* — the tree was left at HEAD with the work
  in `stash@{0}`. Kill by PID, or
  `for p in $(pgrep -x qs); do grep -qa settings /proc/$p/cmdline && kill $p; done`,
  which matches the process's *name* so the shell running it cannot match.
- A before/after pair for the settings app is worth the two minutes on a
  240-caller change: `git stash push` → launch → `grim -g` → kill by PID →
  `git stash pop`, all inside one `bash script.sh` so a failed step cannot leave
  the stash applied. The settings window is floating at `410,154 1100x750` here —
  read it back from `hyprctl clients -j`, never assume the implicit size.
- The harness idiom for motion: a `FrameAnimation` pushing a probe closure into an
  array, a `Timer` stepping between animations, min/max/rest printed at the end.
  It is about fifteen lines and it is the difference between "measured at 60fps"
  and "looked fine".
- `grabToImage(r => r.saveToFile(path))` plus
  `magick f.png -crop 1x1+x+y -format "%[fx:a]" info:` is how to get a state
  layer's opacity out. The grab has no window behind it, so the alpha *is* the
  film.
- A `default property alias` does **not** capture the defining file's own body
  children — only the caller's. Verified: `ContentSection`'s own children are
  `[SearchHandler, header, content]` while a caller's child lands in
  `ContentGroup`'s column. Worth knowing before moving anything in these files.
