# ii-onScreenDisplay — notes

## The row covered the whole directory, not half of it

3,451 lines is past AUDIT.md's ~2,500 split threshold, and the two styles really are
two surfaces. It was still done in one session because the line count is misleading:
~900 of those lines were nine copy-pasted toggle bodies and three widgets that no
reachable code path rendered. What actually needed designing was one card and one pill.
The directory came out at 2,340 lines.

## What the shipped config runs

`osd.style` is **"material"** in `~/.config/illogical-impulse/config.json`, so
`MinimalistOsd` is the surface the user sees and `OnScreenDisplay` — the 1,644-line
one — is not loaded at all. Both were done. To look at the default OSD you have to
flip `osd.style` to `"default"` and flip it back; the live config was restored
byte-for-byte afterwards (only the shell's own `bluetooth.fastPair.mutedUntil` write
survives, which is the shell's state, not this session's).

## Things that cost time, so the next session does not re-spend it

- **`ipc call osdVolume expand` was a no-op from a closed OSD** and this is the
  documented way to open the surface. `expand()` set `osdLoader.item.isExpanded` and
  *then* called `triggerOsd()` — but the Loader has no item while the OSD is closed,
  and `triggerOsd` zeroes the expansion on the way in, so both orderings of the old
  code lost. It calls `triggerOsd()` first now. If a future session finds `expand`
  doing nothing, check that order before anything else.
- **Screenshotting the display indicators.** `brightnessctl` will not trigger the
  brightness OSD on this machine (the panel reads 0 and `set 1%-` at 0 changes
  nothing, so `Brightness.onBrightnessChanged` never fires). What worked: temporarily
  edit `property string currentIndicator: "volume"` to `"gamma"`, screenshot, revert.
  The shell live-reloads, so it costs about ten seconds.
- **The OSD times out in 1000ms.** `trigger` then `expand` then `grim` inside ~0.7s,
  or the shot comes back empty. `expand` restarts the timer, so it is the last call
  before the screenshot.

## Rejected

- **Replacing `OsdMorphToggle` with the shared `GroupButton`.** It is the same idea —
  the comment in the old code even said "matching GroupButton" — but `GroupButton` is
  a `Button` with `clickIndex`-based neighbour tracking and a left/right radius pair,
  while the OSD's run needs radii that read each neighbour's *toggled* state and a
  base of `RippleButton`. Porting the toggled-neighbour rule into `GroupButton` would
  have touched a widget with a large caller list for one caller's benefit, which is
  DESIGN.md rule 9. `OsdMorphToggle` stayed, but it is now ~70 lines that nine
  instantiations share rather than nine 60-line copies.
- **Keeping the labels and widening the card.** AOSP's volume dialog has no labels in
  it; the labels were the thing that did not fit, and every one of them already had a
  `StyledToolTip` carrying the same string.
- **Rescuing the stereo/mono toggle.** `Config.options.sounds.monoAudio` and
  `MonoAudioService` both do not exist. Adding the config key is easy and useless
  without the PipeWire side; that is a feature row, not this one.

## For the motion pass (AUDIT.md's cohesion session)

Two things were retimed and a still frame proves neither:

1. **`MinimalistOsd` gained an enter and an exit it never had.** It slides out of the
   bar edge on `elementMoveEnter` and retracts on `elementMoveExit`, with the loader
   held alive by an `isClosing` latch. Watch that it does not pop, and that the
   overshoot at the end of the enter reads as a settle rather than a bounce — the
   card is small and `expressiveDefaultSpatial` is tuned for larger travel.
2. **Both value indicators' shape rotation moved from `350ms Easing.OutBack,
   overshoot 1.5` to `elementMoveSmall`.** Same duration, different overshoot
   (the bezier fit's, not 1.5). Only visible with
   `osd.material.rotateShape` on, or on the "minimalist" style where the rotation is
   unconditional.

## Deliberately left

- The card's content sits ~2px from its right edge rather than the 6 `osdMargin`
  implies. Measured identical before and after (`x=1911` either way), so it is the
  pre-existing `extrasExpandedWidth` arithmetic, not this change. Re-deriving that
  chain is its own piece of work.
- `OsdMaterialValueIndicator` is four layouts in one file behind
  `material.minimal` / `shapedValues` / `circledShapes` / `rotateShape`. Only its
  motion, its error colour roles and the percentage cell that could not hold `100`
  were touched. Splitting it is a queue row of its own.
- `MinimalistOsd` dismisses on hover, so the slider inside the material card can
  never actually be dragged. That is pre-existing and deliberate-looking (the OSD is
  an acknowledgement), but if the material style is meant to be interactive, the
  hover dismissal is the thing to remove.
- `reachable.py` says `modules/ii/topLayer/OsdDrop.qml` (333 lines) is dead. It
  belongs to whichever row covers `topLayer`; `OsdProgramSlider` from that directory
  is live and imported by `OsdSlidersRow`.

## Gate

`python3 tools/check-osd.py` is new. It sweeps the card-versus-row width arithmetic
across playback-stream counts and keyboard-backlight availability (the old geometry
overflowed at 0 and 1 streams — the two most common states), evaluates the connected
group's radii at both `osd.position` values, and holds the minimalist pill's exit
structurally.
