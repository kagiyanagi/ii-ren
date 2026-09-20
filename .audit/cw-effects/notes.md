# cw-effects — notes

## The two shadow wrappers do not merge, and the brief's "check both first" is why

They are not two spellings of one thing. `RectangularShadow` is analytic: it
draws a blurred rounded rectangle from `radius`/`spread`/`offset` and never
samples its target, which is why it can be `cached: true` and why DESIGN.md 8
lists it as *cheap*. `DropShadow` blurs the target's own alpha with a live
gaussian, which is the only way to shadow an arc, a polygon, a glyph or a
`MaterialShape`. Of the 51 `StyledDropShadow` callers, the clock and cookie
widgets (`CookieClock` shadows a `SineCookie`/`MaterialShape` loader,
`WearOSArcClock`, `NothingWheelClockWidget`, `ConcentricClockWidget` …) are
exactly the case the rectangular one cannot express. So: **both stay**, and
DESIGN.md 6.2 already says so — "`StyledDropShadow` covers the non-rectangular
case". The file comments now say which to reach for.

A migration *is* available for the subset whose target is a plain
`Rectangle`/`Item` with a `radius` — `PhotoWidget`, `Photo1x1Widget`,
`OnScreenDisplay` and the pill widgets look like that from a read. Each would
drop a live gaussian for an analytic shadow. It belongs to those surfaces' own
rows: it is 20-odd caller edits, and this session may not touch callers.

## The actual defect in the family, and the number behind it

`samples: radius * 2 + 1`. Qt's own DropShadow docs: *"This property is not
intended to be animated. Changing this property will cause the underlying
OpenGL shaders to be recompiled."* `DockAppButton` animates `radius` 5 → 10 on
hover, so every dock hover recompiled the blur shader **every frame**, in the
one caller of the 51 that animates.

Measured with a throwaway `qml` harness (Intel Iris Xe, 1 and 8 shadows, 4s
frame counts, two repeats):

| | n=1 | n=8 | n=1 | n=8 |
|---|---:|---:|---:|---:|
| `samples: radius*2+1` (before) | 13 | 24 | 42 | 36 |
| `samples` fixed (after) | 18 | 31 | 53 | 61 |

4 of 4 paired runs favour the fix, +26% to +69% frames. The absolute numbers are
junk — eleven audit sessions were running on this machine — but the pairing is
not, and the mechanism is documented.

The derivation keeps the rendering **byte-identical** for the other 50 callers:
`elevationMargin * 0.8` is 8, `ceil(8) * 2 + 1` is 17, which is what the literals
said. That was deliberate: rule 9, 51 callers, no shell to check them in.

## What was measured and rejected

- **`blurMax: 100` → 64 in `StyledBlurEffect`.** DESIGN.md 8 names this value as
  the most expensive thing in the shell, so it was the obvious change. It is
  wrong. A structural probe (set `blurMax`, count the MultiEffect's internal
  blur items) gives **11 items for 8/16/32 and 13 for 64/100/128** — the extra
  blur level appears above 32, not above 64. Dropping 100 to 64 would cost blur
  radius and save no pass at all. The value that saves a level is 32, which
  `AndroidMediaWidgetToggle` already sets for its small tile; whether the two
  full-size media surfaces and the fullscreen immersive one can take 32 is an
  eyes-on-the-shell question, so it is recorded in the file and not done.
- **`cached: true` on `StyledDropShadow`.** Qt's docs recommend it for a static
  source and the rectangular twin already sets it, so it looked free. Measured:
  144 static shadowed 320x180 tiles hold 60fps with and without, as do 144
  *animating* ones. At desktop scale (5-15 widgets) it buys nothing and costs an
  FBO each, so it is not there.
- **`verticalOffset: 1` to match `StyledRectangularShadow`'s `offset (0, 1)`.**
  Tempting for coherence, but the two are different primitives with different
  units, it moves the shadow on 49 unverifiable surfaces, and rule 9 says no.
  `DockAppButton` is the only caller that offsets at all, and it already uses 1.
- **Deleting `Colorizer`** (zero callers, repo-wide). It is the documented
  modern replacement for Qt5Compat's `ColorOverlay`, which has 9+ live call
  sites, and deleting a public shared widget would break any installed
  extension using it. It got the one-line fix that makes it work instead.

## `Colorizer` never colorized anything

`colorization: 1` with no `colorizationColor`, and `MultiEffect`'s default for
that is **opaque red** (`m_colorizationColor = {255,0,0,255}` in
`qquickmultieffect_p_p.h`). `sourceColor` only ever fed `brightness`, and the
`Behavior on colorizationColor` animated a property nothing wrote. Any caller
would have got a red tint at the right lightness. That is presumably why it has
none. Now `colorizationColor: root.sourceColor`, and the Behavior does something.

## `StyledBlurEffect.source` was a dangling id

`source: wallpaper` — an id that does not exist in the widget's own scope,
inherited from wherever it was cut from. It only ever worked because all four
callers use it as a `layer.effect` and set `source` themselves. It was the one
real qmllint warning in the family (`[unqualified]`); the widget now carries no
default, which is the correct contract for a layer effect.

## The check this leaves behind

`tools/check-effect-budget.py` — DESIGN.md 8 / 10.11, the half a script can see:

- no expensive effect (`layer.enabled`, `OpacityMask`, a MultiEffect/Qt5Compat
  blur, a `ShaderEffect`) inside a repeated delegate. A `Repeater`'s whole body
  is delegate scope since it has no other children; a `ListView`/`GridView` is
  scanned only inside its `delegate:`, because `layer.enabled` on the *view* is
  the recommended fix, not the violation. The shell already had 21 such hits, so
  it is a **shrink-only** gate: `KNOWN` is the list as it stood, a new one fails,
  and a fixed one is printed so `KNOWN` can be trimmed.
- `StyledDropShadow.samples` does not mention `radius` — the regression above,
  which nothing about the expression makes look wrong.

Mutation-tested against all three assertions on a copied tree in scratch (a
delegate-nested effect, `samples: radius * 2 + 1`, and no `samples` at all).

## Harness know-how the next session will otherwise rediscover

- **`qml` prints nothing** — not `console.log`, not `QSG_RENDER_TIMING` — when
  stderr is not a tty, because Qt routes to journald. `QT_FORCE_STDERR_LOGGING=1`
  fixes it. This also applies to `tools/check-subject-depth-geometry.qml`, whose
  header comment does not mention it.
- **`qml file.qml -- a b c` does not put `a b c` in `Qt.application.arguments`.**
  A harness that reads its parameters that way silently measures an empty scene
  and reports a confident 60fps. Generate the harness with the values baked in.
- `Qt.exit(n)` is a fine way to get a number out of a harness when logging is
  fighting you: the frame count over a fixed window, as an exit code.
- **Do not trust an fps number measured while the other audit sessions are
  running.** The same config gave 7fps and 60fps ten minutes apart. Paired
  A/B runs interleaved in one batch survive it; single absolute numbers do not.
  A structural probe (count the effect's internal items) is load-independent and
  was the only measurement worth quoting here.

## Needs a change outside this family

1. **21 effects nested in repeated delegates**, listed in
   `tools/check-effect-budget.py`'s `KNOWN`. The worst is
   `BluetoothFillCardsWidget.qml`, which puts a whole `StyledDropShadow` — a
   live gaussian — inside a `Repeater` delegate alongside a
   `layer.enabled`/`OpacityMask` pair. `CalendarAgendaWidget.qml` instantiates a
   raw Qt5Compat `DropShadow` in a delegate instead of the shared widget.
   `Carousel.qml` is in `modules/common/widgets` and belongs to **cw-motion**.
2. **`ColorOverlay` → `Colorizer`**: 9+ call sites on the deprecated Qt5Compat
   effect (`CustomIcon`, `MediaWidget`, `BluetoothEarbudsStemWidget` ×4,
   `SysTrayItem`, `Workspaces`, `DockIcon`). The replacement works as of this
   commit. Per-surface call, not a bulk rename — `ColorOverlay` blends, and
   `Colorizer` flattens to one tone.
3. **DESIGN.md 8** says "`MultiEffect` blur (`blurMax: 100` most of all)". The
   measured boundary is 32, not 100: 64 and 100 build the same number of blur
   levels. Suggested replacement for that parenthesis, for whoever owns the
   file: "(`blurMax` above 32 most of all — 64 and 100 cost the same)".

## Still needs a running shell or a GPU

- That the 51 `StyledDropShadow` surfaces look unchanged. The maths says they
  are identical (radius 8, samples 17, as before); only `DockAppButton`'s hover
  differs, where the blur now holds 17 samples instead of ramping 11 → 21, so
  its shadow at full hover is marginally less smooth. Worth one look at the dock.
- Whether `StyledBlurEffect` at `blurMax: 32` is acceptable on
  `ImmersiveMediaContent` (fullscreen) and `PlayerControl`. That is the one
  remaining pass-saving change in the family and it is purely a look judgement.
- `Colorizer` has no caller to look at. Its fix is verified by reading Qt's
  default, not by eye.
