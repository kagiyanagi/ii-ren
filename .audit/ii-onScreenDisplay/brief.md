# ii-onScreenDisplay — brief

One directory, **two** surfaces that share only a trigger. `OnScreenDisplay.qml` is the
edge dialog that `osd.style` "default" loads; `minimalist/MinimalistOsd.qml` is the
top-centre pill that "minimalist" and "material" load, and it is what the shipped config
actually runs. Both are briefed here because they answer the same keypress and must not
disagree about what a volume change looks like.

**Purpose.** Show the value a hardware key just changed, and get out of the way.

**Primary action.** None. This surface is an *acknowledgement*, not a control panel — the
user already pressed the key. Everything it offers beyond "here is the new value" is
secondary and must look it. The one exception is the slider itself, which is the thing
the key is a coarse version of.

**Hierarchy.** The value, then the icon that says which value, then the extra sliders,
then the toggles. Nothing in the dialog may outrank the slider the user came for.

**Reference.** The Android 16 volume dialog (`SystemUI` `volume_dialog.xml`): a 60dp
vertical pill on the screen edge, one 40dp track, a mute icon above it and a settings
icon below. Expanding it reveals **more sliders beside it**, never a stack of labelled
rows. The dimens already transcribed at the top of `OnScreenDisplay.qml` are that
dialog's; the layout underneath them is not.

## The defect this brief exists to fix

The expanded dialog computes its own width twice and the two answers disagree. The card
is `osdContractedWidth + extrasExpandedWidth` — 192px for volume with no app streams —
while each toggle row asks for `200 + 4 + osdButtonHeight` = 252px of extras. So every
labelled button is laid out into a cell it does not fit, and the labels the expansion
exists to reveal elide to `D…` and `Mut…` (see `shot-before.png`). Widening the card is
the wrong repair: AOSP's dialog has no labels in it at all.

**So the labels go.** Every toggle becomes an icon-only 48px button in a connected group,
with its text in the tooltip that is already written for it. That is both the AOSP shape
and the shape these buttons already collapse to when the layout squeezes them — the
difference is that it will now be deliberate, sized, and legible.

## Hierarchy, restated as layout

Collapsed (60px wide, the AOSP number): mute button · slider · settings button. Nothing
else.

Expanded: the card grows **leftwards by exactly `extrasExpandedWidth`**, the extra
sliders fill that growth, and the top and bottom button rows are given the *same*
`osdExtrasMaxWidth` the slider row gets. Three 48px buttons plus their 4px gaps fit the
narrowest expanded card (192px) with room to spare; the display indicator's card is
wider still. The primary button (mute for volume, dark mode for display) stays pinned at
the screen edge where it was when collapsed, and the extras pack against it.

## Interaction

- **Connected button group.** `OsdMorphToggle` keeps the part of itself that is right:
  full radius on the ends and on any button that is on, `rounding.small` on the seams,
  each morph on `elementMoveSmall`, width bouncing on `clickBounce` when pressed and
  yielding when a neighbour is pressed. That is M3E's button group and it is the reason
  to keep the component. Neighbours are derived from the parent's child list, not
  assigned by hand in nine `Component.onCompleted` blocks.
- **Selection reads on the icon.** `MaterialSymbol.fill` 0 → 1 with the toggle, plus the
  `colPrimary` fill — DESIGN §7. No label to change.
- **The card's open/close is already correct** and is not touched: enter on
  `elementMoveSmall`'s fast-spatial curve, exit on `emphasizedAccel` at
  `elementMoveFast`'s duration, and the radius interpolates off the same
  `expandedProgress` that drives the width so the pill→card morph cannot lag it.
- **Transform origin** is the screen edge the dialog is anchored to; it grows out of that
  edge by animating the anchor margin, never `x`.
- **The minimalist/material pill has no motion at all today** — `Loader.active` is bound
  straight to `GlobalStates.osdVolumeOpen`, so the surface is built and destroyed on the
  frame the flag flips. It gets the same `openedProgress`/`isClosing` latch its sibling
  already uses: enter translating out of the bar edge on `elementMoveEnter`, exit on
  `elementMoveExit`, with the loader held alive by the latch and never by the request.
- **Rotation and colour inside both value indicators** come off `Appearance` rather than
  the hand-written `350ms OutBack` and `150ms ColorAnimation` they use now. The rotation
  is spatial and may overshoot; `elementMoveSmall` is 350ms of fast spatial, so this is a
  swap, not a retiming. The colour is effects and must not.

## Edge states

- **Empty** — no app is playing: the volume card's extras are system-sounds and mic only,
  and `extrasExpandedWidth` already drops the app group's spacing. Unchanged.
- **One item** — one app stream: one extra slider. Unchanged.
- **No keyboard backlight**: the display card loses the kbd slider and the kbd toggle.
  Both already test `KeyboardBacklight.available`.
- **Error** — the sink-protection message. It keeps its `m3error` card beside the dialog,
  gains the fade in/out it never had, and sits a symmetric 10px from the dialog on both
  sides instead of +12 on one and −12 on the other.
- **Value over `maxLimit`** — the protection ceiling. Stays `colError`-tinted, but on the
  *content* roles (`colOnErrorContainer`), not `colErrorContainerActive`, which is a
  container state colour being used as a text colour in both indicators.

## Cost

From the pack's effect budget, the dialog keeps **one** shadow and drops everything else:

- `StyledDropShadow` on `osdContainer` → `StyledRectangularShadow`. The container is a
  plain rounded rectangle, which is exactly the case §6.2 assigns to the rectangular one;
  the drop shadow was re-rendering a 418px offscreen pass every frame with hand-picked
  `radius: 24, samples: 49`.
- `OsdSlidersRow`'s `layer.enabled` + `OpacityMask` + `Canvas` gradient **die**. The
  layer is gated on `currentIndicator` being neither volume nor a display indicator —
  and for exactly those indicators `extrasExpandedWidth` returns 0. The mask has never
  had a non-zero-width item to fade in the whole time it has existed.
- The `stateResetTimer` polling every 150ms for the lifetime of the shell dies with them;
  the three real reset paths (`triggerOsd`, `onOsdVolumeOpenChanged`, `onVisibleChanged`)
  already cover what it was watching for.

## Delete

- **`components/OsdToggleRow.qml`** (164 lines). Its only instantiation carries
  `visible: A !== "volume" && A !== "brightness" && (A === "volume" || A === "brightness")`
  — a contradiction, false for every value of `A`. It has never rendered.
- **`components/OsdSectionLabel.qml`** (19 lines) and its four instantiations, every one
  of them `visible: false`.
- **`components/OsdDeviceOutputButton.qml`** (84 lines) and its one instantiation,
  `visible: false`. The output-device popup it wrapped is reached from the headphones
  button in the top row and stays.
- **The stereo/mono toggle.** `Config.options.sounds.monoAudio` is not a member of
  `Config.qml`'s `sounds` object, so it reads `undefined` and the button is permanently
  "Stereo"; `MonoAudioService` is not a file in this repo, so clicking it throws a
  `ReferenceError` and does nothing. Neither half of it has ever worked. Mono audio is a
  PipeWire feature request, not a rescue for this button (anti-pattern 16).
- **`root.indicators`** in `OnScreenDisplay.qml` — a five-entry url table nothing in that
  file loads. `MinimalistOsd` has its own copy, which is the live one.
- **`osdSliderFillHeight`**, computed from five other tokens and passed to nobody, and
  `OsdSlidersRow.sliderFillHeight`, which receives it.
- **The music button's brightness/gamma branch.** `musicCircle` is visible for volume and
  gamma, its content branches on brightness and gamma, and in gamma it draws a second
  nightlight toggle directly under the nightlight toggle in the top row. It becomes the
  music-recognition button it is named after, volume only.
- **`OsdTopButton`'s brightness/gamma branches**, unreachable behind its own
  `visible: currentIndicator !== "volume" && !isDisplayIndicator`.
- ~700 lines of copy-pasted toggle body: nine near-identical
  `RowLayout { Item; MaterialSymbol; StyledText; Item } + StyledToolTip` blocks.

## Out of scope

- `Config.options.sounds.monoAudio` is not added and `MonoAudioService` is not written.
  Deleting a control that has never worked is this row; shipping a mono-audio feature is
  a different one.
- `osd.height`, `osd.position`, `osd.timeout`, `osd.style` and the `osd.material.*` flags
  keep their meanings and their settings rows. The `material.minimal` / `shapedValues` /
  `circledShapes` / `rotateShape` matrix inside `OsdMaterialValueIndicator` is four
  layouts in one file and deserves its own row; this one only tokenises its motion and
  fixes the value cell that cannot hold three digits.
- `modules/waffle/onScreenDisplay` is its own queue row.
- `modules/ii/topLayer/` — `OsdProgramSlider` is imported from there and left alone.
  `reachable.py` says `topLayer/OsdDrop.qml` (333 lines) is dead; that belongs to
  whichever row covers `topLayer`, not this one.
