# cw-primitives — notes

## The elide default, and why MaterialSymbol had to opt out

`StyledText` now defaults to `elide: Text.ElideRight`. That is DESIGN.md 10.17 for
471 callers at once, and the reason it is safe is measured, not argued — a throwaway
`FloatingWindow` harness, before any of it was written:

| case | before | with ElideRight |
|---|---|---|
| `width: 40`, long text | `truncated=false`, `contentWidth` 160.8 spilling past 40 | `truncated=true`, cw 38.3 |
| `wrapMode: Wrap`, width set, no height | cw 47.3 | unchanged, `truncated=false` |
| no width constraint | cw == w | unchanged |
| `MaterialSymbol` squeezed to 11px in a `RowLayout` | cw 28, glyph drawn | **cw 0 — the glyph vanishes** |

So the default only ever reaches the callers that were already overflowing. Wrapped
text is untouched until its height is capped, which is exactly when eliding is what
you want.

The last row is the one that mattered. A Material Symbol is a single codepoint; elided
it measures **zero** wide and renders *nothing* — not even an ellipsis. `Layout.fillWidth`
on a symbol does get squeezed below its implicit width (measured: 11 of 28), so
inheriting the default would silently drop icons out of tight rows. `MaterialSymbol`
therefore sets `elide: Text.ElideNone` explicitly, and
`SqueezedAnnotationStyledText` does too — it fits text by binary-searching the font
size, and eliding would let it declare a fit it does not have.

**Note for `ii-onScreenDisplay`:** nine `StyledToolTip`s there read
`extraVisibleCondition: !xBtnText.visible || xBtnText.truncated`. With elide off,
`truncated` was permanently false and those tooltips could never appear. They work now.
That surface was already written expecting this default.

**Not done:** `Layout.minimumWidth: 0`, the other half of 5.7. Defaulting it on 471
callers changes layout everywhere — a row that currently pushes its siblings would
start collapsing instead. It belongs per-caller, in each surface's own row.

## The text swap

`duration: 300 / 2` plus six hand-fitted sine curves became two inline components on
named specs: exit on `elementMoveExit` (130ms), enter on `elementMoveFast` (200ms).
Measured live: `opacity=[0.000, 1.000]` — no overshoot — and the offset returns to
exactly 0.

Both halves ride *effects* specs on purpose. The travel is 6px; it garnishes a
crossfade rather than moving the label, and this is AOSP's `AnimatedContent` shape.
The spatial alternative is worse in both directions: `elementMoveEnter` is 500ms
default spatial, so a clock tick would still be animating at the next tick, and its
curve overshoots past 1, which on opacity clips (10.6). 130 → 200 keeps the exit
faster than the enter (2.5) and both inside 2.4's ≤200ms widget budget.

The old code also hand-fitted `Easing.InSine`/`OutSine` at every use site, which
*overrode* the `elementMoveFast.bezierCurve` set on the shared `Anim` component — so
that binding had been dead for as long as it existed.

### The travel moved to a Translate

Found while measuring, not in the brief. The swap animated `root.x`/`root.y` back to
values captured in `Component.onCompleted`. Two bugs in one:

- 2.9 — assigning x/y to an item its parent positions is overridden every layout
  pass. In the harness `restY` came back as the *anchored* position, so for every
  anchored or Layout-placed caller the advertised slide had been doing nothing; they
  only ever saw the fade. `PlayerControls`, `PlayerControl` and `PlayerControlsLyrics`
  all pass `animationDistanceX: 6` into a `RowLayout` and got no travel from it.
- The captured originals go stale the moment the parent moves the label, at which
  point a text change would snap it to its construction-time position.

It now animates a `transform: Translate`, which composes with anchors and Layouts
instead of fighting them, and the `Component.onCompleted` plus both `original*`
properties are gone. Measured after: `yTravel=12.0` on an **anchored** label — exactly
`animationDistanceY * 2` — resting at 0.

The visible consequence is that ~20 `animateChange` callers gain the ±6px travel the
property always promised. `AlarmsCard`'s alarm icon sets its own `transform: Rotation`
and would clobber the Translate, but it does not use `animateChange`, so nothing there
changes.

## The third instance, so it became a rule

cw-buttons' notes said *"`check-design.py` has no rule for a spatial spec on an
opacity/colour property... Worth adding if a third instance turns up."*
`StyledImage`'s `Behavior on opacity` was running on `elementMoveEnter` — default
spatial, whose curve peaks at 1.21 and clips. That is the third.

`check-design.py` gained **`spatial-on-effects`** (error level): a `Behavior` on
`opacity`/`col*`/`*Color` whose block names a spatial spec or an `expressive*Spatial`
curve. Mutation-tested ten ways, including that a spec named in a *comment* does not
count and that a sibling `Behavior on x` below does not bleed in.

It found **eight more**, all pre-existing, none broken by this family — left for the
rows that own them:

| file | spec | row |
|---|---|---|
| `ConfigListViewEntry.qml:95` | `elementResize` | `cw-config-rows` |
| `PagePlaceholder.qml:38` | `elementMoveEnter` | `cw-scaffolding` |
| `StyledComboBox.qml:28` | `elementResize` | `cw-inputs` |
| `background/widgets/media/MediaWidget.qml:174` | `elementResize` | `ii-background-widgets` |
| `bar/Workspaces.qml:278,588` | `elementMove` | `ii-bar-root` |
| `dock/widgets/DockContextMenuBase.qml:121` | `elementResize` | `ii-dock` |
| `screenTranslator/ScreenTextOverlay.qml:86` | `elementMoveSmall` | `ii-screenTranslator` |

DESIGN.md's "not checkable here" list lost *spatial-vs-effects* accordingly.

## Also fixed here, found while reading

- **`OptionalMaterialSymbol` read a property that does not exist.** Its symbol colour
  was `root.toggled ? colOnPrimary : colOnSecondaryContainer`, and `root` is a
  `Loader` — there is no `toggled`. It read `undefined` with no warning, so the
  ternary was a constant. Neither of its two callers sets `toggled`; the branch is
  gone. It also wrapped the symbol in a bare `Item` that declared no
  `implicitHeight`, so the `Loader` reported height 0 and a row sized itself as if
  the icon were not there — while the icon is *larger* than the label beside it. The
  symbol is now the loaded item directly.
- **`RoundCorner` defaulted to solid black** (`"#000000"`, the family's one hex hit)
  and `implicitSize: 25`, off the grid. Every caller but one sets both. The default
  is now `"transparent"` — a corner nobody coloured should paint nothing — plus
  `Appearance.rounding.screenRounding` for the size, and `ScreenCorners`, the one
  caller that *wanted* black, now says `Appearance.m3colors.m3scrim` itself. That is
  M3's token for the void outside a rounded screen, and it puts the intent in the one
  place it applies instead of in a widget default six other callers override.
- **`Pill`** was `Config.options.appearance.sharpMode ? 0 : Math.min(width, height) / 2`
  — a second copy of the branch that already lives in `Appearance.rounding.scale`.
  `Appearance.rounding.full` is 9999, which `Rectangle` clamps to half the shorter
  side, and 0 in sharp mode. Same render, one token, no `Config` dependency.
- **`MaterialSymbol`'s `Behavior on fill`** spelled out duration + type + curve with
  `Appearance?.` guards and an inline `[0.34, 0.80, ...]` fallback — a hand-copy of
  `expressiveEffects`. Now `elementMoveFast.numberAnimation.createObject(this)`, the
  same idiom as the rest of the library. Its parent already dereferences `Appearance`
  unguarded, so the optional chaining was buying nothing.

## What was deliberately not done

- **`MaterialShapeWrappedMaterialSymbol`'s `Behavior on rotation` stays on
  `elementMoveFast`.** Rotation is a transform, so 2.1 says spatial — but
  `OsdMaterialValueIndicator` binds `rotation: root.value * 360`, i.e. the volume or
  brightness *value* drives it continuously. `elementMoveSmall`'s curve peaks at 1.67,
  so a slider drag would make the shape wobble past and settle, repeatedly. A
  continuously-driven readout wants the monotone effects curve. Rule 9.
- **The `GaussianBlur radius: 35`** in `CliphistImage`/`FileSearchImage` is
  `design-ok`, not retokenised: it is a blur radius in px, not a corner radius, and
  `rule_literal_radius` already tries to skip those by name — it just cannot see that
  a bare `radius:` inside a `GaussianBlur` block is one. `MultiEffect` would drop the
  literal and cost less (one pass against 71 taps), but its default `blurMax: 32` is a
  weaker blur than radius 35, and this is the *privacy* blur over a hidden clipboard
  image. Weakening it to satisfy a regex is the wrong trade. **`cw-effects` owns
  blur** — decide it there, with `StyledBlurEffect` in hand.
- **`ClippingRectangle` instead of the `layer.enabled` + `OpacityMask` crop** in those
  two files. 8 says prefer a native radius over a mask, and this looked like the
  native answer — but reading
  `/usr/lib/qt6/qml/Quickshell/Widgets/ClippingRectangle.qml` it is a
  `ShaderEffectSource` plus a `ShaderEffect` over a hidden layered `Rectangle`. Two
  framebuffers where the mask uses one. Its own doc comment says it "costs more than
  Rectangle". Worse, not better; left alone.
- **`Circle` and `Pill` did not die.** The brief allows it if they are `StyledRectangle`
  with a radius; they are not — `StyledRectangle` picks a layer colour and sets no
  radius at all. Inlining them would mean editing eight caller files to save 17 lines.
  `Circle` also stays deliberately sharp-mode-blind: a dot indicator, a slider thumb
  and an avatar are circles on purpose, and squaring them is a visible change across
  five callers that nothing asked for.
- **`StyledRectangle`'s `ContentLayer` enum** is five values for one caller
  (`bar/Workspaces.qml`) with a comment hoping someone gets to the other styles. It is
  the shape the brief calls "a widget with no caller", but it has one, and deleting it
  means editing that caller. Left for `ii-bar-root` to decide when it reads it.
- **`animationDistanceX` defaults to 0**, so for most callers two of the six swap
  animators animate to the value they already hold. Deleting the axis would be a public
  property removed from a 471-caller widget to save six lines, and four callers do use
  it horizontally. Left.
- **`CustomIcon`'s `width`/`height: 30`** is off the 4dp grid and off 5.4's icon ladder
  (20/24/40–48), but nine of its eleven callers set both, so the default is nearly dead
  code and changing it would shrink icons in the two that do not. Left; no design-check
  hit.

## Driving this family, for the next session

- The two harnesses were `check-elide.qml` and `check-swap.qml`, dropped in
  `dots/.config/quickshell/ii/` as lowercase filenames (ignored by `mkshadow.sh`, not
  QML types) and deleted before committing — the same trick cw-buttons documented, and
  still the cheapest way to get a number out of a shared widget.
- `Text.ElideNone` is **3** and `Text.ElideRight` is **1**. QML's `Text.elide` maps to
  `Qt::TextElideMode`, not to the order the docs list. A harness that prints `elide=3`
  is printing the *default*, which is what made the "it is already set" reading wrong
  for about a minute.
- `magick montage -geometry x560` and `-label ''` both die here with `unable to read
  font (null)`. Use `magick a b +append` / `-append` and resize each tile first.
- `tools/audit/smoke.sh` logs `ExpressiveMediaWidget` warnings about
  `font.weight`/`colBackgroundHover` whenever a player is running. Pre-existing, in a
  vendored widget, nothing to do with this family.
