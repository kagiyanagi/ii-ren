# ii-immersiveMedia — notes

## For the cohesion pass: motion to watch at 60fps

The exit was retimed. It used to be `Math.round(elementMoveEnter.duration / 2)` = 250ms on
`emphasizedAccel`; it is now `elementMoveExit` = **130ms** on `expressiveEffects`.

That is the token the design law names for an exit ("fast effects", 2.5) and what
`StyledText`, `PagePlaceholder` and `DropShelfPanel` already use — but 130ms is 26% of the
enter, not the "roughly half" the same paragraph also offers, and this is a **screen-sized**
surface, which is the one case where the skill's own checklist says a fast spec is suspect.
Both readings are inside the law. Watch a dismiss and, if 130ms reads as a blink rather
than a leave, `elementMoveFast` (200ms, same curve family, still a token) is the fallback —
not a hand-computed number, which is what was there.

Nothing else was retimed. The enter's scale still runs 500ms on `elementMoveEnter`; only
the opacity moved off it, onto `elementMoveFast`.

## Why the card's width is a binding and not a number

`ImmersiveNowPlayingPane.chromeHeight` is measured from its own `ColumnLayout`, and
`ImmersiveMediaContent` sizes the card as `mediaRow.height - chromeHeight + 32`. It looks
like a loop and is not: the pane's height comes from `Layout.fillHeight`, and every label in
the card elides rather than wraps, so no child's height knows how wide the card turned out.
Verified in the running shell — no `Binding loop detected` for this surface. The moment
something in that card wraps, it becomes a real loop; `check-immersive-media.py` asserts
`wrapMode` never appears in the pane for exactly that reason.

The `Layout.minimumHeight: 160` that used to sit on the art box had to go — a minimum is
folded into the layout's `implicitHeight` and therefore into `chromeHeight`, which would
make the card narrower than the art can be tall and bring the void straight back. That is
the single most likely way to silently undo this row. It is the first thing the check tests.

## Tried and rejected

- **Letting the surplus height fall into a gap** between art and title, with the controls
  anchored at the bottom of the card (the Android full-screen player shape). It moves the
  void rather than removing it, and in single-pane mode — where the current centring already
  looks right — it makes things worse.
- **A constant for the pane's chrome** instead of measuring it. Shorter, and wrong the first
  time a row lands in that layout, with no symptom: the card just goes back to being a
  guess.
- **A pure width rule** (`min(680, width * 0.42)`). Fixes 1920×1080 and nothing else — the
  chrome is a fixed 330-odd px while the screen height is not, so the void returns on a
  1366×768 panel.

## Left alone, deliberately

- **The art-download `Process`** in `ImmersiveMediaContent`. The same eight lines appear in
  thirteen files across the shell (`grep -rn 'Directories.coverArt'`). It wants one shared
  helper, not a fourteenth copy, and six of the thirteen are in the vendored
  `modules/ii/background/widgets/` tree that `port-widgets.sh` rsyncs with `--delete`. Its
  own row, not this one.
- **`LyricLine`'s per-line `OpacityMask`** — `layer.enabled` inside `LyricScroller`'s
  `Repeater`, so 6 offscreen passes per scroller, ×3 callers. Under rule 8's ~20 ceiling, so
  not a violation, and `check-effect-budget.py` cannot see it because the `Repeater` and the
  delegate are in different files — the same blind spot `ii-dock` hit. Belongs to `cw-media`,
  which is closed; recorded here rather than reopened.
- **The empty lyrics card** when a track has no lyrics: with `showLyrics` on, 60% of the
  screen is a `PagePlaceholder`. Collapsing the pane would make the layout jump on every
  track change, which is worse, and the toggle is one keypress (L). Left as is.
- **`LyricsService`'s lookup** does not strip a YouTube title suffix, so
  `Love Me Like You Do (From "Fifty Shades Of Grey") - YouTube` finds nothing while
  `Lana Del Rey - Diet Mountain Dew (Lyrics)` resolves. `StringUtils.cleanMusicTitle` is
  applied to the *display* title only. Observed here, belongs to `services/LyricsService.qml`.

## Gotcha for the next session

`qmlformat` is not on `PATH`; it is `/usr/lib/qt6/bin/qmlformat`, and it reads
`.qmlformat.ini` from the **working directory only**. That file lives in
`dots/.config/quickshell/ii/`, so running the formatter from a module directory reflows the
whole file at the default 80 columns instead of the repo's 110. Run it from the shell dir or
not at all.
