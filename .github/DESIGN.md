# DESIGN.md — Android 16 / Material 3 Expressive design law for ii-ren

The shell imitates Android 16's system UI. This file is the spec: what a new
widget should look like, how it should move, how it should answer a pointer, how
far apart things sit. It applies to **every** change that draws, moves, or
responds to input — not only when someone asks for "Android animations".

Read this before writing QML. Cited numbers are transcribed from AOSP; the
"Sources" section says how to re-fetch each one.

---

## 0. The four rules that outrank everything else

1. **Reuse before you build.** `modules/common/widgets/` has ~140 widgets. A new
   button is `RippleButton`, a new panel is `PanelLoader` + an existing content
   component. Building a fresh one is the last resort, not the first move.
2. **Never invent a number.** Durations, curves, radii, opacities and state
   colours all exist as tokens in `Appearance`. If a number is not in
   `Appearance` and not in this file, fetch it from AOSP and cite the file in a
   comment. A hand-picked `duration: 180` is a bug even if it looks fine.
3. **Spatial overshoots, effects never do.** Anything that moves, resizes or
   reshapes may overshoot. Anything that fades or tints must not — opacity and
   colour clip at their bounds, so an overshoot is a visible flash.
4. **Measure motion, don't eyeball it.** Record at 60fps and count frames. A
   change that "feels snappier" and a change that is snappier are different
   things.

---

## 1. Sources of truth

Every number below comes from one of these. Re-fetch with:

```sh
curl -s "<url>?format=TEXT" | base64 -d
```

| What | Path |
|---|---|
| Spring scheme (ζ, stiffness) | `frameworks/support` → `compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/ExpressiveMotionTokens.kt` |
| Non-expressive scheme | same dir → `StandardMotionTokens.kt` |
| Duration + easing ladder | same dir → `MotionTokens.kt` |
| State layer opacities | same dir → `StateTokens.kt` |
| Corner radii | same dir → `ShapeTokens.kt` |
| Elevation levels | same dir → `ElevationTokens.kt` |
| Button metrics | same dir → `ButtonSmallTokens.kt`, `ButtonMediumTokens.kt`, … |
| Long-press popup motion | `packages/apps/Launcher3` → `src/com/android/launcher3/popup/ArrowPopup.java` |
| Icon hover/press scale | `packages/apps/Launcher3` → `src/com/android/launcher3/icons/FastBitmapDrawable.java` |

Host is `https://android.googlesource.com/platform/<repo>/+/refs/heads/main/<file>`
(`androidx-main` instead of `main` for `frameworks/support`).

### Checking a change against this file

**`/design-check`** is the entry point. It runs the script below for the
mechanical rules, then reads the diff for the ones no regex can see — transform
origin, spatial-vs-effects, enter/exit pairing, layer nesting, effects inside
repeated delegates, a widget that should have been reused. Pass it a git ref or a
path; bare, it reviews uncommitted changes.

Underneath:

- `tools/check-design.py` — literals where a token exists, animation types that
  do not match their property, the crash and shadowing patterns. `--diff` scopes
  it to added lines and exits non-zero on an error; a bare run audits everything
  and counts legacy debt too. `--rule <id>` expands one rule.
- `tools/check-m3-tokens.py` — asserts the Hyprland spring curves and the state
  layer mix factors still match AOSP. Run after touching either.

---

## 2. Motion

### 2.1 Spatial vs effects — pick this first

| | What it animates | Damping | Feel |
|---|---|---|---|
| **Spatial** | position, size, shape, scale, rotation | ζ 0.6–0.8, underdamped | settles with a small overshoot |
| **Effects** | opacity, colour, blur, elevation | ζ 1.0, critically damped | no overshoot, ever |

Then pick a speed by **travel distance and element size**, not by taste:

- **fast** — small element, short distance, or direct response to a click.
- **default** — the normal case. A panel sliding, a list reflowing.
- **slow** — large surface crossing a lot of screen.

### 2.2 The token table

Source values are `ExpressiveMotionTokens.kt`. Qt has no usable spring
(see 2.9), so the repo ships bezier fits at fixed durations.

| Scheme token | ζ | stiffness | Qt curve (`Appearance.animationCurves`) | duration | Hyprland curve |
|---|---|---|---|---|---|
| Fast spatial | 0.6 | 800 | `expressiveFastSpatial` | 350 | `m3FastSpatial` |
| Default spatial | 0.8 | 380 | `expressiveDefaultSpatial` | 500 | `m3DefaultSpatial` |
| Slow spatial | 0.8 | 200 | `expressiveSlowSpatial` | 650 | `m3SlowSpatial` |
| Fast effects | 1.0 | 3800 | `expressiveEffects` | 130 | `m3FastEffects` |
| Default effects | 1.0 | 1600 | `expressiveEffects` | 200 | `m3DefaultEffects` |
| Slow effects | 1.0 | 800 | `expressiveEffects` | 280 | `m3SlowEffects` |

The three effects rows share one curve and differ only in duration — that is
correct, a critically damped spring's shape barely changes with stiffness.

Hyprland wants a damping *coefficient*, AOSP publishes a *ratio*:
`dampening = 2·ζ·√(stiffness·mass)`. That derivation is what
`tools/check-m3-tokens.py` guards.

The non-expressive ("standard") scheme is ζ 0.9 at stiffness 1400/700/300
spatial. It is not used here — the shell is deliberately expressive — but reach
for it if something reads as too playful for its job (a destructive
confirmation, a system error).

### 2.3 Ready-made specs — use these, not raw numbers

`Appearance.animation.*` are `AnimSpec` objects carrying duration + curve plus
prebuilt `Component`s:

```qml
Behavior on x     { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
```

| Spec | Scheme | Use for |
|---|---|---|
| `elementMove` | default spatial | the default for position and size |
| `elementMoveSmall` | fast spatial | small widgets, radius morphs, chips |
| `elementMoveEnter` | default spatial | something appearing |
| `elementMoveExit` | fast effects | something leaving |
| `elementMoveFast` | default effects | colour, opacity, tint |
| `elementResize` | fast spatial | implicit size changes |
| `clickBounce` | fast spatial | press feedback springing back |
| `scroll` | `standardDecel` @200 | programmatic scrolling |

When a `Behavior` will not do, spell out the three properties — never a bare
number:

```qml
NumberAnimation {
    duration: Appearance.animation.elementMoveSmall.duration
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
}
```

`modules/ii` currently holds 188 hand-written durations against 27 tokenised
ones. That is legacy debt, not a precedent. Do not add to it; convert the ones
you touch.

### 2.4 Curve-based motion, and when it is right

Springs belong to *components reacting to input*. Whole surfaces moving on a
fixed trip — a window opening, a workspace sliding, a page transition — are
curve-based in AOSP too. For those use the emphasized/standard curves with an
official duration:

| Curve | Points | Use |
|---|---|---|
| `emphasized` | AOSP `fast_out_extra_slow_in` | a surface entering and leaving in one move |
| `emphasizedDecel` | 0.05, 0.7, 0.1, 1 | entering, appearing, expanding |
| `emphasizedAccel` | 0.3, 0, 0.8, 0.15 | leaving, dismissing, collapsing |
| `standard` | 0.2, 0, 0, 1 | small utilitarian moves |
| `standardDecel` / `standardAccel` | | in / out of the utilitarian kind |

Duration ladder from `MotionTokens.kt` — snap to these, do not interpolate:

```
Short   50  100  150  200
Medium 250  300  350  400
Long   450  500  550  600
XLong  700  800  900 1000
```

Rule of thumb: ≤200ms for a widget, 300–500ms for a panel, 500ms+ only for
something screen-sized.

### 2.5 Enter and exit are not symmetric

Entering is slower and decelerating — the user is waiting to see the thing.
Leaving is faster and accelerating — the user has already decided. In practice:
enter on default spatial or `emphasizedDecel`, exit on fast effects or
`emphasizedAccel`, at roughly half the enter duration. Every new appearing
surface must specify **both**; a component that fades in over 500ms and
disappears instantly is the most common motion bug here.

### 2.6 Transform origin

A scale animation without a deliberate origin looks wrong even with perfect
timing. Growth starts where the thing came from:

- Popup or menu → the corner or edge nearest the thing that opened it.
  `ArrowPopup.setPivotForOpenCloseAnimation()` puts it on the corner nearest the
  touch point, so the card grows out of the finger.
- Panel anchored to a screen edge → that edge (`Item.Bottom` for a bottom dock,
  `Item.Left` for a left sidebar).
- Press feedback → `Item.Center`.
- Overscroll stretch → the far edge, pinned so the content the finger is on
  stays put.

### 2.7 Interruption

Motion here is interruptible. `alwaysRunToEnd` defaults to `true` in `AnimSpec`,
and `elementMove`/`elementMoveSmall`/`elementMoveEnter` deliberately set it
`false` so a reversal cuts in immediately. Anything driven by hover or a toggle
must be reversible mid-flight; only a one-shot acknowledgement (a bounce, a
ripple) may run to completion.

Reset on hide. A surface that keeps its final scale/opacity while invisible will
animate from stale values next time it opens.

### 2.8 Stagger

When several siblings enter together, offset each by ~25–50ms, capped at about
6 items — past that the tail feels broken rather than choreographed. Do not
stagger inside a scrolling delegate; the offsets fire on recycle.

### 2.9 Traps that have actually bitten

- **`SpringAnimation` is not a Compose spring.** Qt integrates with dt left out
  of the velocity update, so the effective stiffness is roughly `k/62.5`, it
  caps at 62fps, and it goes unstable at effects-level stiffness. That is why
  this repo uses bezier fits. Do not "improve" it back to `SpringAnimation`.
- **Match the animation type to the property type.** `colorAnimation` on a real
  property, or `numberAnimation` on a colour, silently snaps instead of
  animating.
- **`Behavior on <bound property>` breaks the binding.** Animating `scale`
  directly kills a `scale:` expression. Animate a helper property and compose:
  `scale: hoverScale * pressScale` (see `DockButton`).
- **`animationMultiplier`** exists (`Appearance.animMultiplier`,
  `Config.options.appearance.animationMultiplier`) but `AnimSpec` does not apply
  it. When a component's motion is long enough to be worth disabling, follow the
  androidStyle toggles: treat `<= 0.25` as "animations off".
- **Async `Loader` + `Connections`** whose target is not a live QObject
  segfaults in `QQmlConnections::connectSignalsToMethods()`. Guard with
  `target: foo ?? null`, or keep the loader synchronous.
- **Do not animate `x`/`y` of an anchored item.** Animate the anchor margin, or
  drop the anchor.

### 2.10 Hyprland side

`dots/.config/hypr/hyprland/general.lua` is the source of truth; the six
`m3*` curves are declared there and every animation leaf references one.
Notes that cost time to rediscover:

- Springs are Lua-only: `hl.curve(name, {type="spring", mass=, stiffness=, dampening=})`,
  then `spring="name"` in `hl.animation`. `speed` is ignored for springs, and
  mass/stiffness/dampening must each be ≥ 0.5.
- `hyprctl keyword` is rejected under the Lua parser. The runtime path is
  `hyprctl eval '<lua>'`.
- `layer_rule` can override an animation *style* but never its speed. There is
  no per-layer animation speed.
- `shellOverrides/repo-defaults.lua` and `sdata/cli/lib/hyprset.lua` also write
  animation leaves. Change a leaf in `general.lua` and check both, or they clobber it.

---

## 3. Interaction

### 3.1 State layers

A translucent film of the content colour over the container, from
`StateTokens.kt`:

| State | Opacity |
|---|---|
| Hover | 0.08 |
| Focus | 0.10 |
| Pressed | 0.10 |
| Dragged | 0.16 |

Three ways to apply it, in order of preference:

1. `Appearance.colors.colLayerNHover` / `colLayerNActive` — already the right
   mix for that layer, transparency-aware. Use these on a solid background.
2. `StateOverlay` — composites each state independently, so hover → press →
   release stays continuous, and it reads correctly over a photo or video.
3. `StateLayer` — one layer, if you are driving states yourself.

Never mix your own tint. `ColorUtils.mix(base, on, 0.92)` is hover and `0.90` is
pressed (mix keeps `p` of the base), and that arithmetic already lives in
`Appearance`.

Every interactive element needs **hover, focus, pressed and disabled** covered.
Disabled is `opacity: 0.4` on the whole control (what `RippleButton` does), not
a greyed-out colour.

### 3.2 Ripple

Compose `RippleAnimation`, as implemented in `RippleButton`:

- Fade in over **75ms linear**.
- Radius from **60% to 100%** of the distance to the furthest corner, over
  **225ms** on `standardDecel`.
- Fade out over **150ms linear**, starting on release.
- Origin is the actual press point, not the centre.
- Clipped to the container's shape (`OpacityMask` against the same radii).

Ripple is for a container that accepts a click. Do not put one on a whole row
that is really a layout, and do not add a second ripple inside a rippled parent.
Where the press already reads through a scale (dock icons), set
`rippleEnabled: false`.

### 3.3 Press and hover scale

Launcher3 `FastBitmapDrawable`: `HOVERED_SCALE` 1.1 over 300ms on
`PathInterpolator(0.05, 0.7, 0.1, 1.0)` — which is `emphasizedDecel` —
and `PRESSED_SCALE` 1.1 over 200ms.

Both being 1.1 means that on a pointer, which is always hovering before it
clicks, the press would be invisible. `DockButton` solves it by keeping the
hover growth and multiplying a press *squish* on top:

```qml
scale: root.hoverScale * root.pressScale   // 1.1 on hover, 0.88 on press
```

Copy that composition for anything icon-sized. For a filled button, prefer the
state layer plus the shape morph over a scale — a growing rectangle reads as a
layout glitch.

### 3.4 Hit targets

AOSP's minimum touch target is 48dp. This is a pointer-driven desktop shell, so:
**32px minimum** hit area, 40px where a mis-click is costly. The visual can be
smaller than the hit area — expand the `MouseArea`, do not inflate the paint.

Cursor: `Qt.PointingHandCursor` on anything clickable (`RippleButton` does this
via `pointingHandCursor`; `PointingHandInteraction` is the drop-in for
everything else). Text gets an I-beam. A non-interactive surface gets nothing.

### 3.5 Button conventions in this shell

| Input | Meaning |
|---|---|
| Left click | primary action, fires on **release** |
| Right click | contextual menu, or the inverse action (remove, unpin) |
| Middle click | close / dismiss |
| Long press | drag start, or the launcher-style popup |
| Scroll | value adjustment on a slider-like widget |

`RippleButton` exposes `downAction`, `releaseAction`, `altAction` (right) and
`middleClickAction`. Use them rather than adding another `MouseArea`, which
would fight the ripple's.

### 3.6 Drag, dismiss, overscroll

- Swipe-to-dismiss: `SwipeDismissible` — 70px confirm threshold, neighbours
  follow at 0.3 and 0.1 of the drag.
- Scroll overscroll: `WheelScrollHandler` accumulates past the end
  (`overscrollMax` 0.12 of viewport, diminishing, 60ms release) and
  `StyledListView`/`StyledFlickable` turn it into an Android-style stretch — a
  `Scale` on `contentItem` with the origin pinned at the edge being pushed. Do
  not translate the content; stretch it.
- Drag state gets the 0.16 layer, and the dragged item should lift (elevation),
  not fade.

### 3.7 Keyboard

Everything reachable by mouse should be reachable by keyboard. Escape closes any
popup, dialog or menu. `Enter` accepts a text field. A focused control shows the
0.10 focus layer — visibly, not just as an `activeFocus` boolean nothing renders.

Popups that need typing (search, rename) require
`WlrKeyboardFocus.OnDemand` on their own `PanelWindow`; an xdg popup on a layer
surface cannot take focus. `DockFolderPopup` is the worked example.

### 3.8 Haptics

Android pairs press feedback with a haptic tick. There is no equivalent here.
Do not compensate by exaggerating the motion — the visual spec stands as-is.

---

## 4. Shape

### 4.1 The scale

`ShapeTokens.kt` ↔ `Appearance.rounding`:

| AOSP | dp | Repo token | px |
|---|---|---|---|
| CornerExtraSmall | 4 | `unsharpenmore` (6) | 6 |
| CornerSmall | 8 | `verysmall` | 8 |
| CornerMedium | 12 | `small` | 12 |
| CornerLarge | 16 | `normal` | 17 |
| CornerLargeIncreased | 20 | — | |
| CornerExtraLarge | 28 | `large` | 23 |
| CornerExtraLargeIncreased | 32 | `verylarge` | 30 |
| CornerExtraExtraLarge | 48 | — | |
| CornerFull | pill | `full` | 9999 |

Plus `windowRounding` 18 (matches the Hyprland decoration radius) and
`screenRounding`.

Always go through `Appearance.rounding.*`. It carries a `scale` factor that
`Config.options.appearance.sharpMode` zeroes — a literal radius ignores sharp
mode and looks broken there.

### 4.2 Which radius

| Surface | Radius |
|---|---|
| Screen-level panel, sheet, sidebar | `verylarge` |
| Card, popup, dialog, menu | `large` or `verylarge` |
| Content block inside a card | `normal` |
| List row, tile, chip | `small` or `normal` |
| Small badge, inline indicator | `verysmall` |
| Button, pill, toggle, FAB | `full` |
| Progress track, tiny divider | `unsharpen` |

The nesting rule: a child's radius is smaller than its parent's, by roughly the
padding between them. Equal radii on nested surfaces reads as a rendering error.

A surface flush against a screen edge or another panel rounds only its free
corners — use `topLeftRadius`/`topRightRadius`/`bottomLeftRadius`/`bottomRightRadius`
rather than a uniform `radius` plus a clip.

### 4.3 Shape morph on press — opt in, never globally

AOSP does morph a pressed button toward a smaller radius, but the target scales
with the button: `ButtonSmallTokens.PressedContainerShape` is `CornerSmall` (8),
`ButtonMediumTokens` is `CornerMedium` (12). There is no single universal value.

`RippleButton.buttonRadiusPressed` defaults to `buttonRadius` — no morph —
because 58 buttons in this repo rest at `rounding.full` or `height/2`, and
squaring a pill or a circle reads as a glitch, not feedback. Opt in per widget,
on rectangular buttons only, and pick the value from the button's size.

Selection is the other legitimate morph: a selected/toggled control may change
shape (`SelectedContainerShape`), animated on `elementMoveSmall`. That is the
M3 Expressive signature and it is worth using on toggles and tabs.

### 4.4 Beyond rounded rectangles

`MaterialShape`, `MaterialShapeWrappedMaterialSymbol` and the `shapes`
submodule (rounded-polygon-qmljs) cover cookie/clover/pill shapes, and
`MaterialCookie`/`SineCookie` are the ready-made ones. Use them for decorative
containers — loading indicators, avatar frames, expressive badges — not for
anything the user has to read text out of.

---

## 5. Spacing and layout

### 5.1 The grid

Multiples of **4**. The de-facto ladder in this repo, by frequency, is
4 / 8 / 12 / 16, with 6 and 10 also common. Use 6 or 10 only where a sibling in
the same surface already does. Never 3, 5, 7, 9, 11 — except a deliberate
optical nudge with a comment saying why.

### 5.2 Padding by container

| Container | Padding |
|---|---|
| Screen-level panel | 16–20 |
| Card, popup, dialog | 12–16 |
| List row | 8–12 horizontal, 4–8 vertical |
| Compact chip, badge | 4–6 |
| Icon-only button | 0 (size the button, not the padding) |

Text buttons keep AOSP's asymmetry: 16 leading / 16 trailing on a small button,
24 / 24 on a medium one, and **8** between an icon and its label.

### 5.3 Gaps

| Between | Gap |
|---|---|
| Sections in a panel | 12–16 |
| Rows in a list | 4–8 |
| Items in a toolbar or chip row | 4–6 |
| Grid tiles | 2–4 |
| A popup and the thing it anchors to | 10 |
| Any floating surface and the screen edge | 8 minimum |

### 5.4 Sizing

- Prefer `implicitWidth`/`implicitHeight` so parents can lay out; use
  `Layout.preferredWidth`/`fillWidth` inside a `Layout`. Hard `width`/`height`
  only when the number is genuinely fixed.
- Reserve room for shadows: `Appearance.sizes.elevationMargin` (10). A surface
  with a shadow and no margin gets its shadow clipped.
- Shared dimensions belong in `Appearance.sizes`, not scattered as literals.
  That is where `sidebarWidth`, `dockButtonSize`, `notificationPopupWidth` and
  friends live.
- Icons: 20 inline/compact, 24 standard, 40–48 for an app icon or tile.
- Text: never a hard height. Set `elide` or use `MarqueeText`; long strings are
  the norm here (app names, notification bodies, MPRIS titles).

### 5.5 No decorative dividers or separator lines

Material 3 Expressive surfaces rely on **whitespace on the 4dp grid** (12–16dp
gaps between sections) and **tonal layer nesting** (`colLayer1`, `colLayer2`) to
establish visual hierarchy and separation.

Do not insert hairline divider lines, separator bars, or
`WindowDialogSeparator` between section headers and controls or around content
groups. Separator lines clutter dialog surfaces, fight with container rounding,
and frequently lead to brittle negative-margin hacks (e.g. `topMargin: -22`) to
close the gap. Let whitespace and background layer cards do the work.

---

## 6. Colour, layers, elevation

### 6.1 The layer system

`Appearance.colors.colLayer0` … `colLayer4`, background to foreground, each with
`colOnLayerN`, `colLayerNHover` and `colLayerNActive`. Nest by depth: a panel on
layer 0 puts its cards on layer 1 and their inner blocks on layer 2. Skipping a
level, or reusing the parent's layer for a child, flattens the hierarchy.

Take the `Hover`/`Active` sibling of whatever layer you painted with. They are
computed through `solveOverlayColor` so they stay correct when transparency is
on — a hand-mixed tint will not.

Never write a hex literal. `Appearance.m3colors.*` is the generated palette
(it is rewritten by the wallpaper theming pipeline); `Appearance.colors.*` is
the semantic layer. Use the semantic one.

Roles: `colPrimary` for the single most important action per surface,
`colSecondary`/`colTertiary` for accents, `colError` for destructive and
failure, `colSurfaceContainer*` for neutral surfaces, `colOutlineVariant` for
dividers, `colOnSurfaceVariant` for secondary text.

### 6.2 Elevation

`ElevationTokens.kt`: 0, 1, 3, 6, 8, 12 dp.

| Level | dp | What |
|---|---|---|
| 0 | 0 | flush content |
| 1 | 1 | a card at rest |
| 2 | 3 | a raised chip, a search bar |
| 3 | 6 | a menu, a popup |
| 4 | 8 | a navigation drawer |
| 5 | 12 | a dialog, a dragged item |

`StyledRectangularShadow` renders it (`blur: 0.9 * elevationMargin`, offset
(0, 1), `cached: true`) and `StyledDropShadow` covers the non-rectangular case.
Elevation *changes* — hover lifting a card, a drag picking an item up — animate
on an effects spec, never a spatial one.

A modal surface dims what is behind it with `colScrim`, faded on
`elementMoveFast`.

---

## 7. Typography

`Appearance.font.pixelSize.*` only — never a literal. Role mapping:

| M3 role | Repo token | Notes |
|---|---|---|
| Display / Headline | `huge` 22, `hugeass` 23 | with `font.family.title`, wght 550 |
| Title | `large` 17, `normal` 16 | DemiBold |
| Body | `normal` 16, `small` 15 | wght 450 |
| Label | `smallie` 13, `smaller` 12 | buttons, chips, captions |
| Micro | `smallest` 10 | badges only |

Families: `main` for UI, `title` for headings, `numbers` for anything tabular or
counting, `monospace` for code and paths, `reading` for long text, `expressive`
for the deliberately decorative, `iconMaterial` for symbols.

Weight goes through `font.variableAxes` (`wght`), not `font.bold`. Use
`StyledText` — it wires up the family, rendering and hinting; a bare `Text` will
not match.

Icons are `MaterialSymbol`, sized by `iconSize` (which also feeds the `opsz`
axis). Its `fill` axis animates 0 → 1, and that is the idiomatic way to show
selection on an icon-only control — animate `fill`, not colour alone.

---

## 8. Effects and shaders

This shell targets integrated graphics. Effects are a budget, not a garnish.

**Cheap** — opacity, `scale`/`rotation`/`Translate`/`Scale` transforms, colour
animation, gradients, `RectangularShadow` with `cached: true`.

**Expensive** — `layer.enabled` (an extra framebuffer per item),
`OpacityMask`, `MultiEffect` blur (`blurMax: 100` most of all), anything
recomputed in JS per frame.

Rules:

- At most one layer/effect per interactive widget.
- Never an effect inside a delegate that can appear more than ~20 times. Cache
  it at the container, or drop it.
- Prefer native per-corner radii over an `OpacityMask` clip.
- Blur: `StyledBlurEffect` is the wallpaper-backed one. Blur the *source*, once,
  and sample it — do not stack blurs per panel.
- `FlutedGlass` and `WallpaperFilter` are the shipped shaders. Adding a shader
  needs a real reason: write the `.frag`, compile with
  `modules/common/widgets/shaders/build.sh`, commit the `.qsb`, and verify with
  `check.qml`/`check.sh`. Do not write a shader for something a `MultiEffect` or
  a `Gradient` already does.
- A transition between images is `widgets/transitions/` (Crossfade, Radial,
  Wave, Wipe, …) via `TransitionImage`. Do not hand-roll another.

---

## 9. Component recipes

The short answer to "how should this look". Reuse the named widget.

**Button** — `RippleButton` (`RippleButtonWithIcon`, `RippleButtonWithShape`).
Height 30 compact / 40 standard. `full` radius for pills, `small` for
rectangular. State layer + ripple; no scale. Icon 20, gap 8, side padding 16.

**Icon button** — `RippleButton` sized square, `rounding.full`, `padding: 0`,
hit area ≥ 32. `IconToolbarButton` and `ToolbarButton` for toolbar rows.

**Toggle / quick-settings tile** — `full` radius, `colPrimary` fill when on,
`colSurfaceContainer` when off, colour on `elementMoveFast`, shape morph on
`elementMoveSmall` if it changes shape when selected. The `androidStyle` quick
toggles are the reference.

**Popup / context menu** — `ArrowPopup` motion, transcribed:
open scale 0.5 → 1.02 over 200ms `emphasizedDecel`, then 1.02 → 1 over 200ms on
`[0.3, 0, 0.33, 1]`; alpha 0 → 1 linear 83ms. Close scale 1 → 0.5 over 233ms
`emphasizedAccel`; alpha 1 → 0 over 83ms after a 150ms delay. Origin at the
corner nearest the click. Radius `verylarge`, elevation 3, gap 10 from the
anchor, 8 from the screen edge. Dismiss on any outside click and on Escape.
`DockFolderPopup` and `DesktopMenu` are the worked examples.

**Dialog** — `WindowDialog` and its `WindowDialogTitle`/`Paragraph`/
`ButtonRow`/`Separator` parts. Scrim behind, elevation 5, radius `verylarge`,
enter on `emphasizedDecel`, exit `emphasizedAccel` at ~half the duration.
Confirming action on the right, destructive in `colError`.

**Sheet / sidebar** — slides from its edge on default spatial, `verylarge`
radius on the free corners only, scrim if modal.

**List** — `StyledListView` (overscroll stretch and `WheelScrollHandler` come
with it). Rows 40–56 tall, 4–8 apart, radius `small`/`normal`, whole row
hoverable. `StyledScrollBar` for the bar, `ScrollEdgeFade` where content runs
under a header. Empty state is `PagePlaceholder`, not blank space.

**Tabs** — `SecondaryTabBar`/`ToolbarTabBar`. Indicator moves on
`elementMoveSmall`; the label crossfades on `elementMoveFast`.

**Switch / slider** — `StyledSwitch`, `StyledSlider`, `ConfigSlider`. Thumb on
fast spatial, track colour on default effects. M3 Expressive sliders squeeze the
thumb on press; keep the value text tabular (`font.family.numbers`).

**FAB** — `FloatingActionButton`. `full` radius, `fabShadowRadius` 5 at rest and
`fabHoveredShadowRadius` 7 on hover, animated on an effects spec.

**Tooltip** — `StyledToolTip`/`PopupToolTip`. `colTooltip` background, ~500ms
delay in, fade only, no scale.

**Notification** — `NotificationItem`/`NotificationGroup`/`NotificationListView`.
Swipe to dismiss via `SwipeDismissible`, group expansion on default spatial,
`NotificationActionButton` for actions.

**Progress** — `StyledProgressBar`, `ClippedProgressBar`,
`CircularProgress`, `MaterialLoadingIndicator` (the morphing-shape M3
Expressive one) and `StyledIndeterminateProgressBar`. Indeterminate only when
the duration is genuinely unknown.

**Dock / taskbar item** — `DockButton`. Hover 1.1 over 300ms `emphasizedDecel`,
press squish 0.88 multiplied in, ripple off, radius `normal`.

---

## 10. Anti-patterns

Each of these has actually shipped and had to be reverted.

1. Applying a spec globally to a shared base widget. AOSP's pressed shape is
   per-size; forcing one value on `RippleButton` squared 58 pills and circles
   into rectangles.
2. Replacing a bezier fit with `SpringAnimation` (see 2.9).
3. `colorAnimation` on a real property, or the reverse — it snaps silently.
4. `Behavior on scale` on top of a `scale:` binding — the binding dies.
5. Async `Loader` plus a `Connections` whose target is not a live QObject —
   segfault.
6. Overshooting opacity or colour — clips, flashes.
7. Hex literals, literal durations, literal radii.
8. Animating `x`/`y` of an anchored item.
9. Shadowing `state` or `focus` with a custom property — breaks the QML state
   machine and keyboard focus respectively. `StateLayer` uses `layerState` and
   `StateOverlay` uses `focused` for exactly this reason.
10. An enter animation with no exit animation.
11. An effect inside a repeated delegate.
12. Adding a second `MouseArea` over a `RippleButton` instead of using its
    action properties.

---

## 11. Before calling a UI change done

- [ ] Reused an existing widget where one fit.
- [ ] Every duration and curve comes from `Appearance`.
- [ ] Spatial vs effects chosen correctly; nothing that fades overshoots.
- [ ] Enter **and** exit both specified, exit faster.
- [ ] Transform origin set on anything that scales.
- [ ] Hover, focus, pressed and disabled all render.
- [ ] Hit area ≥ 32px; pointing-hand cursor on clickables.
- [ ] Radii from `Appearance.rounding`, nested smaller than the parent, sharp
      mode still correct.
- [ ] Spacing on the 4dp ladder.
- [ ] Colours from `Appearance.colors`, on the right layer, transparency on and
      off both checked.
- [ ] Keyboard reachable; Escape closes.
- [ ] No new effect inside a repeated delegate.
- [ ] `qs -c ii` starts with no new warnings.
- [ ] Motion changes measured at 60fps, not eyeballed.
- [ ] `/design-check` clean.
- [ ] `tools/check-m3-tokens.py` passes if tokens were touched.
