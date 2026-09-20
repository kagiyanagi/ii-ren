# cw-buttons — notes

## What the two library-wide findings cost, and why one of them was not done the obvious way

**Finding 1 (no focus state) was free.** `Button.visualFocus` is the keyboard-only
half of `activeFocus`, and both roots already inherit it. `focusPolicy` on
`RippleButton` measures as `11` (`Qt.StrongFocus`) and `forceActiveFocus(Qt.TabFocusReason)`
makes `visualFocus` true, so the film is reachable, not inert — verified with a
throwaway `FloatingWindow` harness before writing any of it. A focused button
measures +4.6/+5.2 on G/B against an unfocused one on this palette.

**Finding 2 (pressed == hover) is where the session actually went.** The obvious
fix — default `colBackgroundActive` to `colLayer1Active`, the way `GroupButton`
already does — is a regression in **261 files**. They set `colBackgroundHover` to
their own layer's Hover sibling and inherit the pressed colour from it; hand them
a hard-coded layer-1 tone and a press on a layer-3 dialog button flashes the wrong
grey. Today's bug is invisible (no press feedback); that one would be visible.
Rule 9, exactly.

Extrapolating the 0.10 film out of the caller's own 0.08 hover colour
(`mix(hover, base, 1.25)` recovers it algebraically) also fails, because the
default `colBackground` is `transparentize(colLayer1Hover, 1)` — the hover colour
at alpha 0, not a real base. The arithmetic then returns the hover colour again.

So the press is resolved per caller instead:

```qml
readonly property bool ownPressColor: root.toggled ?
    !Qt.colorEqual(colBackgroundToggledActive, colBackgroundToggledHover) :
    !Qt.colorEqual(colBackgroundActive, colBackgroundHover)
```

A caller that gave a pressed colour keeps it and gets no film. A caller that left
the default gets the base plus a real 0.10 `StateOverlay` film, which composites to
the M3 token over whatever layer it painted — without this file having to know
which layer that is. Measured: `default=false explicit=true toggledDefault=false
toggledExplicit=true`. `Qt.colorEqual` is what makes that comparison safe; `===`
on two `color` properties is not.

The two mechanisms are mutually exclusive on purpose — applying both would give
~0.18, which is the drag token, not the pressed one.

## The film and the ripple do not fight

`buttonBackground` has `layer.enabled` + `OpacityMask`, so the `StateOverlay` inside
it is clipped to the button's corners for free and does not repeat the radii.
`GroupButton` has no mask, so its overlay does take all four radii explicitly.
`StateOverlay` is declared before `ripple` so the ripple still draws on top.

On a pointer a press is always preceded by a hover, so the visible press transition
is hover-colour → base+film. Both halves run on effects specs of the same duration
and the composite is monotone 0.08 → 0.10; there is no dip to see.

## Also fixed here, found while reading

- `GroupButton` greyed only its *background* when disabled, leaving the label at
  full strength. Now `opacity: 0.4` on the control (DESIGN.md 3.1).
- Both roots animated that opacity on `elementResize` — `expressiveFastSpatial`,
  whose curve overshoots past 1 and clips. Moved to `elementMoveFast`. **`check-design.py`
  has no rule for a spatial spec on an opacity/colour property**; it only catches a
  `ColorAnimation` on a real. Worth adding if a third instance turns up.
- `GroupButton.onDownChanged` dereferenced `root.parent` unguarded — it is null
  while the button is still being constructed and `down` is already bound.
- `GroupButton`'s keyboard focus was a 2px `colSecondary` border (`tabbedTo`), which
  is neither a token nor a state layer. Deleted; nothing else referenced it.
- `RippleButtonWithShape` put `anchors.verticalCenter` on two children of a
  `RowLayout` — undefined behaviour per qmllint. Now `Layout.alignment`.
- `RippleButton.buttonColor` was wrapped in
  `ColorUtils.transparentize(…, root.enabled ? 0 : 0)` — both branches are 0, so the
  whole call was a no-op. Gone.

## What was deliberately *not* done

- **`colBackgroundHover`/`colBackgroundActive` do not die.** The brief allows it, but
  36 files set the pressed colour explicitly and whole alternate palettes
  (`modules/waffle/looks/*` on `Looks.colors.bg2Active`) depend on it. A film cannot
  express those. The properties stay; the *default* is what changed behaviour.
- **§5.6 on the button groups.** `ButtonGroup`/`VerticalButtonGroup` already derive
  their own radius as `child.radius + padding`, so the card is correctly larger than
  its children and the nesting rule holds. They are transparent layouts, not cards,
  so there is no edge-to-edge hover fill to get wrong. Nothing to do.
- **`GroupButton.clickedWidth: baseWidth + (isAtSide ? 10 : 20)`** is off the 4dp grid
  and drives the quick toggles' click bounce. Changing it is a visible motion change
  across 47 quick-toggle files with no token to justify a specific new value. Left.
- **`LightDarkPreferenceButton`'s three hex literals** are `design-ok`. They are the
  neutral surfaces of the mode you are *not* in; `Appearance` only ever expresses the
  current mode, so the preview cannot come from it — only its hue can.

## The check this left behind

`tools/check-button-states.py` asserts that every QQC2-`Button`-rooted widget in
`modules/common/widgets` renders all four states: binds `visualFocus`, disables via
`opacity: 0.4`, and never defaults pressed to hover without a `down`-driven press
layer. It also fails if a *third* shared button root appears, because that root would
be the next thing to silently ship three states. Mutation-tested against all three
assertions.

`tools/check-m3-tokens.py` gained `StateLayer.qml`'s own opacity switch — the same
AOSP `StateTokens` table the `Appearance` colours are checked against, now checked in
both places it is written down.

## Driving this family, for the next session

- **`qs -c ii settings.qml` is wrong** (AGENTS.md says it; the binary rejects it).
  It is `qs -p ~/.config/quickshell/ii/settings.qml`. The window comes up as
  `org.quickshell` / `illogical-impulse Settings`, and Hyprland *tiles* it, so its
  size is not the implicit size — always read the geometry back from `hyprctl clients`.
- **`pkill -f check-focus.qml` kills the shell script that launched it**, because the
  script's own command line contains the filename. Kill by PID.
- A harness dropped in `dots/.config/quickshell/ii/` as a **lowercase** filename is
  ignored by `mkshadow.sh` and is not a QML type, so it costs nothing while it exists —
  but delete it before committing.
- `hyprctl dispatch focuswindow …` does not work here (Lua config). The pilot's notes
  cover the ydotool closed-loop warp; for this family the harness was cheaper than
  driving the real app.
