# cw-battery — notes

## What actually needed fixing

The brief's four categories (literal durations, hex literals, off-grid margins,
hand-fitted easings) don't map 1:1 onto the file as it stood. `check-design.py -v`
scoped to this file found exactly 10 hits, all `literal-radius` (2) and
`off-grid-spacing` (8) — no bare `duration:` and no `"#hex"` string anywhere in the
file; both were already routed through `Appearance.animation.*`/`.animationCurves.*`
tokens. What the checker's regex can't see is where those tokens are used correctly
in *value* but not in *form*, and one place a token is used but not the *semantic*
one. That's the real work here:

1. **Two `Appearance.m3colors.m3error` → `Appearance.colors.colError`.**
   `highlightColor`/`contentColor` reached straight into the generated palette
   instead of the semantic layer (DESIGN.md 6.1: "`Appearance.m3colors.*` is the
   generated palette... `Appearance.colors.*` is the semantic layer. Use the
   semantic one."). `colError` is declared as `m3colors.m3error` verbatim
   (`Appearance.qml:196`), so this is a zero-value-change substitution — same
   pixel, right layer, and it's the correct semantic role besides ("`colError` for
   destructive and failure", DESIGN.md 6.1). This is the "hex literal" class finding
   the brief meant: not a `#rrggbb` string, but a raw-palette reference standing in
   for the semantic one, which the mechanical checker has no rule for.

2. **Four hand-assembled `Behavior on X { NumberAnimation/ColorAnimation {...} }`
   blocks → the ready-made `animation: Appearance.animation.<spec>.numberAnimation
   /colorAnimation.createObject(this)` form.** `animatedPercentage`'s Behavior spelled
   out `duration: Appearance.animation.elementMove.duration` +
   `easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial` by hand;
   the three `Behavior on color` blocks (dotted, big-dotted, landscape-signal dots)
   did the same against `elementMoveFast`/`expressiveEffects`. DESIGN.md 2.3 gives
   the shorthand explicitly and 28+ other widgets in this library already use it
   (`StyledComboBox`, `WindowDialog`, `ConfigListViewEntry`, `NoticeBox`, …). Verified
   the numbers match exactly before swapping: `elementMove.duration` (500) +
   `expressiveDefaultSpatial` is what `elementMove` *is* (`Appearance.qml:308-312`);
   same for `elementMoveFast` (200) + `expressiveEffects` (`Appearance.qml:330-334`).
   Net -16 lines, same render. This is the "4 hand-fitted easings" the brief meant —
   not wrong numbers, just not the canonical spelling.

## The hex/radius/spacing table — what got a real token vs. what got a citation

| Location | Was | Now | Why |
|---|---|---|---|
| `highlightColor`, `contentColor` (×2) | `Appearance.m3colors.m3error` | `Appearance.colors.colError` | Exact same value (`colError` *is* `m3colors.m3error`), right semantic layer. Real fix, not a citation. |
| `dotRadius: 7.5` (dotted, 12 dots) | bare literal | same value + `// design-ok: dot-placement radius matching circleComponent's arc, not a corner radius` | Checker's `literal-radius` rule pattern-matches any `\w*[Rr]adius:` — this one is a polar placement radius (distance from center to each dot), not a corner radius. It's deliberately equal to `circleComponent`'s `PathAngleArc` `radiusX`/`radiusY` (both 7.5, both centered at 10,10 on the same 20×20 canvas) so the "dotted" and "circle" styles trace the same ring. `Appearance.rounding.*` has no member near 7.5, and repurposing one would (a) be a false semantic match — a rounding token is a corner radius, this is a trig radius — and (b) break the dotted/circle alignment, which is a visible regression, not tokenisation. Same pattern already lives in this codebase: `CliphistImage.qml:99`/`FileSearchImage.qml:60` cite a Gaussian-blur radius the identical way. |
| `dotRadius: 9.5` (big-dotted, 16 dots) | bare literal | same value + citing comment | Same reasoning, matched against `bigCircleComponent`'s arc (9.5, centered 12,12, 24×24 canvas). |
| `spacing: 1` ×4 (portrait/landscape/landscape_left/landscape_ios nub gap) | bare literal | same value + `// design-ok: nub-to-body gap on the icon glyph, not layout spacing` | DESIGN.md 5.1's grid governs UI chrome (panel/card/row spacing); these are hand-drawn battery pictograms at 14–26px canvas size, the same category as glyph internal metrics. Rounding 1→2 to satisfy the grid is a redesign (it visibly widens the nub-to-body gap by 100% on a ~20px icon) for a brief that asks for tokenisation, not redesign. DESIGN.md 5.1 explicitly allows "a deliberate optical nudge with a comment saying why," and the checker's own docstring names `// design-ok:` as the suppression. |
| `anchors.margins: 1.5` ×4 (portrait/landscape/landscape_left/landscape_musku fill inset) | bare literal | same value + `// design-ok: fill inset on the icon glyph body, not layout spacing` | Same reasoning — this is the wall-thickness bezel between each style's body outline and its fill rect, consistently 1.5px across four styles. `landscape_ios` uses `2` here deliberately (it's a bordered variant, already on-grid, untouched). No `Appearance.*` token represents "icon bezel width"; inventing one for four call sites in one file would be the over-engineering direction, not the fix. |

No hex I couldn't honestly map — the only two real palette references were the
`m3error` pair above, and both had an exact semantic equivalent already declared.
**Nothing needed adding to `Appearance.qml`** — every citation above is a real
"no honest token exists" case, not a stand-in for one that should exist library-wide;
all ten are one-off icon-glyph metrics scoped to this single file.

## What I tried and rejected

- **Extracting the repeated `1`/`1.5` into a local `root.*` named property**
  (e.g. `root.iconGlyphGap`) instead of citing each literal. Rejected: it doesn't
  change the honesty problem (still not an `Appearance.*` token, still a
  self-invented name), it's an abstraction for four call sites in one file
  (ponytail: no unrequested abstraction), and it doesn't match this codebase's own
  precedent for this exact situation — `CliphistImage`/`FileSearchImage`
  (radius-that-isn't-a-corner-radius) and `LightDarkPreferenceButton` (literal with
  no honest token) both leave the literal in place and cite it inline.
- **Rounding `1`→`2` and `1.5`→`2`** to silence the grid check by brute force.
  Rejected per rule 2's spirit generalised beyond hex: an off-grid value with an
  honest reason gets a citation, not a nearby number chosen because the checker
  allows it.
- **Giving `isCritical` its own visual treatment** (see below) — no spec for it
  exists anywhere in DESIGN.md, so any specific choice (colour, pulse, icon) would
  be invented here, which is redesign, not tokenisation.

## Edge states

- **Charging** renders deliberately: a `MaterialSymbol` bolt overlay
  (`isCharging && showChargingIndicator`) plus a 100ms `Timer`-driven
  `chargingPulse` that sweeps a "filling" animation through the dotted/circle/
  big-dotted-circle/landscape-signal styles. Untouched, already correct.
- **Low battery** (`isLow && !isCharging`) swaps `highlightColor`/`contentColor` to
  the error token across every style. Now routed through `Appearance.colors.colError`
  instead of the raw palette (see table above) — same pixel, correct layer.
- **Critical battery does not render deliberately, and this is real, not
  theoretical.** `isCritical` is part of the public API (settable from outside,
  `readonly` nowhere) and `BarConfig.qml:732` — the live settings preview — wires
  it straight from `Battery.isCritical`, clearly expecting it to do something
  visible. Nothing inside this file ever reads `root.isCritical`: it renders
  byte-identical to merely-low. DESIGN.md has no critical-battery recipe anywhere,
  so there's no non-arbitrary answer for what it *should* look like (colour step,
  pulse, distinct icon), and inventing one is a design decision outside a
  lane-2 mechanical pass. Flagging it here rather than guessing.
- **Unknown percentage** fails toward "full and calm," not blank or broken:
  `property real percentage: Battery.percentage ?? 1.0` mirrors
  `services/Battery.qml`'s own `UPower.displayDevice?.percentage ?? 1` fallback
  (the widget's `?? 1.0` is technically redundant since `Battery.percentage` is
  already guaranteed non-null, but it's consistent with this file's existing
  belt-and-braces style for every other `Battery.*` read — `isCharging`,
  `isPluggedIn` — and touching it is out of scope for a token pass). A machine
  with no battery hardware shows this meter as a steady 100%, not a broken or
  empty state. `Battery.available` gating (if any) is the caller's job —
  `modules/ii/bar/BatteryIndicator.qml` doesn't gate on it either, which is
  outside this family.
- **No interaction states apply.** This widget is pure presentation — no
  `MouseArea`, no hover/focus/press anywhere in the file. Click/hover for the
  battery lives in the two `BatteryIndicator.qml` callers (`hoverTarget`,
  `BatteryPopup`), which own that surface, not this family.

## Verification

- `python3 tools/check-design.py --diff 2>&1 | grep CustomBatteryMeter` — empty
  (clean) both before and after the muskuFill fix; re-run a second time after
  every edit landed to be sure.
- `python3 tools/check-design.py -v 2>&1 | grep CustomBatteryMeter` — empty (all
  10 original hits resolved, no new ones).
- `python3 tools/check-m3-tokens.py` — passes (unchanged; no token *values*
  touched, only reference form).
- qmllint against an isolated `mkshadow.sh` tree: 0 errors, only pre-existing
  warning classes (`unqualified`, `missing-property` against `Appearance.colors`/
  `Appearance.animation`/`Config.options` — all generically-typed `QtObject`s, so
  *every* member access on them warns this way; verified `colError` produces the
  identical warning shape as the untouched `colOnSecondaryContainer` right next to
  it on the same line, and the two `Quick.layout-positioning` hits are in
  `landscapeLineComponent`, code this session never touched). No new warning
  class, no new count at any line this diff added — checked every changed line
  number against the qmllint output directly rather than eyeballing it.
- No `tools/check-*.py` added: every change here is a value-preserving token/
  form substitution or a citation comment. Nothing changed how a percentage maps
  to a rendered state, so there's no new behaviour for a check script to guard.

## Needs a change outside this family

Nothing requires editing `Appearance.qml` or any caller. The `isCritical`
dead-state above is a real gap, but it's a "what should this look like" design
question with no spec to point at, not a specific token or file change I can hand
over ready-to-apply — noting it in case a future session (or whoever specs a
critical-battery treatment) wants a starting point: `root.isCritical` exists,
is already wired end-to-end from `Battery.isCritical` through the settings
preview, and only needs a rendering branch.
