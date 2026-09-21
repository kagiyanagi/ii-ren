# ii-mediaControls — notes

## The IPC does not open this surface under the shipped config

`qs -c ii ipc call mediaControls open` sets `GlobalStates.mediaControlsOpen`, and two
surfaces watch that flag:

- `MediaControls`' own popup, whose loader is `wantOpen && (!dockMediaPresent || barMediaPresent)`
- `DockMediaWidget`, whose `shouldOpenFromShortcut` is `!barMediaPresent && mediaControlsOpen`

They are deliberately exclusive, and with the shipped config — dock media widget on, no
bar media widget — the IPC opens **the dock's** popup, which renders exactly one
`PlayerControl`. Half an hour of this session went into screenshotting that and believing
it was the stack.

To reach the real surface: set `dock.enableMediaWidget` false in
`~/.config/illogical-impulse/config.json`, restart, then call the IPC. Put it back
afterwards — that file is the live config, not a repo default, and `iiren save` would
otherwise commit the change.

## Verification that is not in the diff

- **Input with the scale on it.** The column now rests at `arrowPopupScale` and the mask
  is gone; a held press (`ydotool click 0x40` / `0x80`, 250ms apart) on the first card's
  play button toggled the player, and on the third card's picker set the active player
  and showed its tooltip. Both points are outside the half-size rectangle a baked region
  would have left, which is what `ii-dropover` shipped.
- **Enter and exit both animate.** A burst of `grim` captures over the card region, mean
  luminance per frame: exit `0.177 → 0.174 → 0.157 → 0.087 → 0.083` settled; enter
  `0.083 → 0.082 → 0.110 → 0.248 → 0.169 → 0.177` settled. The enter's overshoot past the
  settled value is `arrowPopupOvershoot` doing its job. Neither is a step function, which
  is the only thing that distinguishes a real transition from a deleted one here.
- **`ydotool mousemove --absolute` is half-scale on this machine.** Ask for `x/2, y/2` to
  land on `x, y`. `hyprctl dispatch 'movecursor X Y'` does **not** work — this config is
  Lua and a bare dispatcher string is a syntax error, which `check-hermes-desktop.py`
  already exists to stop people rediscovering. It got rediscovered anyway.

## `tools/audit/mock-mpris.py`

Added, because none of this surface's states are reachable without music and the
more-than-one-player layout is not reachable with one player. It advertises a seekable,
playing track with local cover art; `MOCK_NAME` / `MOCK_TITLE` / `MOCK_ARTIST` /
`MOCK_POSITION` / `MOCK_LENGTH` let a second instance stand alongside the first.
`canSeek` is what picks the wavy slider over the flat progress bar, so it is set.

## Rejected

- **Merging `PlayerControl` into `AndroidMediaPopup`'s layout.** The popup is the Android
  16 media notification at 380×220 with a lyrics pane; the card is 440×160 with a
  full-height art rail, leaving 266px beside it. A transport cluster and a seek row do not
  share a line in 266px, so the card keeps its vertical stack and borrows only the
  alignment. If that changes, the thing to move first is `Appearance.sizes.mediaControlsWidth`.
- **Adding `Config.options.media.dynamicAlbumColors` instead of deleting the branch it
  gated.** The key never existed, so the album-tinted variant of `AndroidMediaPopup` has
  never been on screen; shipping a settings row for an appearance nobody has seen is a
  feature request, not this row's job. The deletion is asserted by
  `check-media-controls.py` so it cannot come back by accident. `PlayerControl`'s own
  `AdaptedMaterialScheme` is untouched and still tints each card by its art — that one
  reads a live quantiser.

## Motion for the cohesion pass to watch

One retiming, at 60fps:

- The lyric line swap in `AndroidMediaPopup` (sidebar `androidStyle` 4×2 toggle) was one
  hand-written 120/180/180 sequence; it is now `elementMoveExit` out, then the slide and
  fade **together** on `elementMoveEnter`. They used to be sequential, which meant the new
  line finished travelling before it started fading in and arrived already in place.
  Needs a track with synced lyrics from `LyricsService`.

## Left alone

- `MprisController.filterDuplicatePlayers`'s *title-prefix* half still merges on
  `includes()` in either direction, so a player whose title is a substring of another's
  is swallowed regardless of position. That is the heuristic as designed; only the
  unsigned position test was a defect. `check-media-controls.py` pins the tolerance.
- The vendored `modules/ii/background/widgets/media/AndroidMediaWidget.qml` is the
  original this popup was copied from and carries the same dead config key. Out of scope
  — `port-widgets.sh` rsyncs that tree with `--delete`.
