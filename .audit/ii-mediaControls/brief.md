# ii-mediaControls — brief

Three files, two unrelated cards, one container. `MediaControls.qml` is the popup
`Super+M` opens; `PlayerControl.qml` is the card it stacks one of per player, and the
dock's media popup reuses it; `AndroidMediaPopup.qml` is a *different* card, reached
only from the sidebar's `androidStyle` 4x2 quick toggle. They are packed together
because they live in one directory, not because they share anything.

**Purpose.** Say what is playing and let the user drive it without finding the app.

**Primary action.** Play/pause the player under the cursor. Everything else — seek,
skip, choosing which player is "active" — is secondary and must look it.

**Hierarchy.** Album art, then the title, then the play/pause, then the seek, then
skip and the player picker. The art is the only thing on the card the eye can land on
from across the screen, so it keeps the full card height.

**Reference.** The Android 16 media notification. Art rail on the left, metadata
left-aligned against it, transport as one centred cluster. `AndroidMediaPopup` is
already that shape at a larger size; `PlayerControl` is the compact row and only
borrows the alignment, not the layout — a transport cluster plus a seek row does not
fit on one line in the 266px this card leaves beside the art.

**Interaction.**

- The popup has **no motion at all** today: `Loader.active` is bound straight to
  `GlobalStates.mediaControlsOpen`, so the surface is created and destroyed on the
  frame the flag flips. It gets `ArrowPopupMotion` — the shell's one assembly of
  `ArrowPopup.animateOpen()`/`animateClose()` — with the loader held alive through
  the close by an explicit `alive` flag, never by the request (the drop shelf's
  lesson: binding the surface to the request deletes the exit with no other symptom).
- **Transform origin is the bar edge the popup grew out of.** The popup is already
  placed against the bar from the same four booleans the margins read: top bar →
  `Item.Top`, bottom bar → `Item.Bottom`, vertical bar left → `Item.Left`, right →
  `Item.Right`.
- Card colour and symbol colour stay on `elementMoveFast`; nothing new overshoots.
- `AndroidMediaPopup`'s hand-written durations and easings become
  `Appearance.animation.*` / `Appearance.animationCurves.*` by name. The lyric swap
  is a leave-then-enter, so it keeps that shape: out on `elementMoveExit`, in on
  `elementMoveEnter`.
- Skip-previous / skip-next in `AndroidMediaPopup` dim their *symbol* to 0.4 while the
  button underneath still hovers, ripples and fires. Disabled is `enabled: false` plus
  `opacity: 0.4` on the control (3.1), not a dimmed glyph over a live button.
- The player picker (`keep`) is an 18px target under the 32px minimum (3.4), it is
  unlabelled, and it overlaps the title — which is why the info column carries a
  `Layout.rightMargin: 14` to get out of its way. It becomes a 32px target with a
  tooltip, shown only when there is more than one player to pick, and the margin
  follows its visibility instead of being permanent.

**Edge states.**

- *No player.* The placeholder becomes `PagePlaceholder` (9), which is what every
  other empty state in the shell uses, instead of a hand-rolled 20px-padded card.
- *One player.* The picker is not shown — there is nothing to pick. This is also the
  dock's case, which renders one `PlayerControl` and never wants the control.
- *No art.* Already handled: `music_note` on `colLayer1`, and the blurred underlay
  resolves to the flat card colour.
- *Not seekable.* Already handled: `StyledProgressBar` replaces the wavy slider.

**Cost.** Kept, because each is once per card and not inside a repeater:
the card's `OpacityMask`, the art's `OpacityMask`, the blurred-art `StyledBlurEffect`,
one `StyledRectangularShadow`, the `WaveVisualizer`. `AndroidMediaPopup` keeps its
`MultiEffect` vignette blur and its two masks.

Dropped: the `ColorQuantizer` and `AdaptedMaterialScheme` in `AndroidMediaPopup`.
They feed `useDynamicColors`, which reads `Config.options.media.dynamicAlbumColors` —
a key that does not exist on the `JsonObject`, so it has read `undefined` since the
file was written and every one of the twelve ternaries behind it has only ever taken
its else branch. That is a 1x1 rescale of the album art and a whole scheme object per
track change, for a branch nobody has seen run.

**Delete.**

- The dead dynamic-colour chain above, and the twelve ternaries it gated.
- `mask: Region { item: playerColumnLayout }` on the popup. The column is
  `anchors.fill: parent` inside a window sized to the column, so the mask is the whole
  window and does nothing — but it is the exact shape `check-mask-regions.py` exists
  for, and it would have frozen the input region at `arrowPopupScale` the moment the
  open animation landed.
- `PlayerControl`'s centred title and artist. Four centred rows beside a square of art
  give the eye nothing to follow; the metadata left-aligns against the art and the
  transport cluster stays centred, which is the one thing that earns it.
- The permanent `Layout.rightMargin: 14`, once the picker no longer sits in the title.

**Out of scope.**

- `modules/ii/background/widgets/media/AndroidMediaWidget.qml`, which is the vendored
  original this popup was copied from and carries the same missing config key. It is
  re-ported from ii-p3drovfx and a fix there is reverted by the next `port-widgets.sh`.
- Merging `PlayerControl` and `AndroidMediaPopup`. Different sizes, different jobs.
- `MprisController`'s duplicate-player filter and the cava process.
