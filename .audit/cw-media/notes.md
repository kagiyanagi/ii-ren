# cw-media — notes

## `Lyrics.qml` was not styling real data — it was reading properties that do not exist

`LyricsService.status`, `LyricsService.slots`, `LyricsService.before` and
`LyricsService.restartLyrics()` are referenced by `Lyrics.qml` (and
`lyricsComp.restartLyrics()` by `PlayerControlsLyrics.qml`) but none of them are
declared anywhere — not on the `LyricsService` singleton, not on its `lrclib`
child (`modules/common/utils/LrclibLyrics.qml`). Verified by reading both files
in full; the real API is `hasSyncedLines`, `currentIndex`, `syncedLines`,
`statusText`.

Effect before this session: `LyricsService.status !== "ok"` is
`undefined !== "ok"`, always `true`, so the "ok" (lyrics) branch was dead and
the loading branch showed forever. Its `Repeater` read
`LyricsService.slots[index]`, i.e. `undefined[index]` — a TypeError on every
one of its 7 delegates, caught and logged by QML as a runtime warning rather
than crashing, but real spam had this branch ever rendered. Its retry
`MouseArea` called `LyricsService.restartLyrics()` (not a function -> another
TypeError on click). `PlayerControlsLyrics.qml`'s seek handler called
`lyricsComp.restartLyrics()` for the same reason and would have thrown on every
scrub of the slider.

Fixed entirely inside `Lyrics.qml` (no service file touched, both ends of every
call are in this family): rewired the two branches onto `hasSyncedLines` /
`currentIndex` / `syncedLines` / `statusText`, using the exact same
windowed-index pattern `LyricScroller.qml` already uses correctly. Added
`function restartLyrics() {}` on `root` with a comment explaining why it is
empty — every value in the file is a plain binding on
`LyricsService.currentIndex`/`statusText`, so a position jump already redraws
itself; there is nothing to redrive by hand. The MouseArea's target changed
from the nonexistent service call to `root.restartLyrics()`.

This also closes the "no lyrics" edge state the brief calls out for this
family: the fallback branch now shows `LyricsService.statusText` (which is
already a real fetching/error/instrumental/`♪` message) as one line, instead of
a spinner that could never turn off.

## The retry tap became a `RippleButton`

The pack flags `Lyrics.qml`'s bare `MouseArea` as "a possible rebuild of a
shared widget". Replaced the `Item` + `MouseArea` wrapper around
`MaterialLoadingIndicator` with a `RippleButton` (`padding: 0`,
`buttonRadius: Appearance.rounding.full`, `downAction` in place of
`onClicked`), keeping the indicator as `contentItem`. It inherits finding 1
(focus ring via `Button.visualFocus`) and finding 2 (press separate from
hover) for free, plus keyboard reachability, with zero new code for either —
matches the house-style note that anything rooted in `RippleButton` already
has both post cw-buttons.

## `LyricScroller`'s `visible: hasSyncedLines>0` is a contract, not a bug — checked, not changed

Before touching it I grepped all 3 callers:

- `modules/ii/bar/Media.qml` shows a plain title/artist line
  (`visible: !LyricsService.hasSyncedLines || !lyricsEnabled`) in the same slot
  when there are no synced lines.
- `modules/ii/immersiveMedia/ImmersiveLyricsPane.qml` already does the
  textbook thing: `LyricScroller { visible: root.hasSynced }` next to a plain-
  lyrics fallback and a `PagePlaceholder` for the true-empty case.
- `modules/ii/overlay/media/MediaContent.qml` has no fallback at all — see
  "Needs a change outside this family" below.

Two of three callers *depend on* `LyricScroller` collapsing to invisible so
their own fallback shows in its place. Making `LyricScroller` always render a
placeholder internally (my first instinct, before checking) would have
regressed both of them — exactly rule 9's warning. Left the `visible` binding
alone. `Lyrics.qml` was the one file in the family with no caller-side safety
net, which is why the real fix landed there instead.

## `LyricScroller`'s tokenized animation: a nuance for whoever reads the diff

`scrollAnimation` (line ~52) drove a bare `duration: 400` / `Easing.OutQuart`
`NumberAnimation` on `scrollOffset`. Retokenized to
`Appearance.animation.elementMoveSmall.duration` +
`Appearance.animationCurves.expressiveFastSpatial` (fast spatial: small
element, short distance).

Caveat worth flagging for design-check: every line's `opacity`/`scale` in this
file is *linearly derived* from `scrollOffset` via `animProgress`, not driven
by its own `Behavior`. `expressiveFastSpatial` overshoots (by design, ζ 0.6);
`OutQuart` did not. In principle that couples a spatial overshoot into an
effects property (opacity), which 2.1/10.6 want kept apart. In practice
`animProgress = Math.abs(scrollOffset) / rowHeight` cannot go negative, so the
overshoot shows up as a small wobble back toward the settled value near the
tail of the animation, not a value exceeding `[0,1]` — it does not clip or
flash. Not restructured: splitting position and opacity onto independent
specs is a real architecture change to a file whose whole point is one driving
property, and that is redesign, not this lane's job. Flagged here so a future
pass does not have to re-derive this from scratch.

## `MaterialMusicControls` — the "no player" edge state is one line

`MediaContent.qml` binds `player: root.currentPlayer` with no null guard
around it, and the three `GroupButton`s only optional-chain the *actions*
(`root.player?.previous()`), so a null player left them visually normal but
inert. Added `enabled: !!root.player` on the outer `ButtonGroup`. This is
deliberately *only* an `enabled` binding, not an added `opacity` binding:
`GroupButton.qml:51` already has `opacity: root.enabled ? 1 : 0.4` with its own
tokenized `Behavior`, and Qt Quick's `enabled` cascades its *effective* value to
children (confirmed by reading `GroupButton.qml`, not assumed) — so each
button dims itself. Adding a second `opacity: 0.4` at the container level would
have compounded to `0.16`, past the token.

Otherwise reviewed and left alone: this file is the "M3 Expressive reference"
the brief calls it — 0 mechanical hits, the play/pause button already gives
its own distinct `colBackgroundActive` (a real 0.10-equivalent press colour,
not the film), and the previous/next buttons inherit cw-buttons' fixed
defaults with no overrides to re-check.

## `Player.qml` has zero callers anywhere in the live shell

Exhaustively grepped (`Player {`, `Player.qml`, every import path) across
`modules/ii` and `modules/waffle` — nothing instantiates it. `PlayerControls`
and `PlayerControlsLyrics` are therefore also only reachable through it today,
i.e. also dead in the running shell. This does not change how I treated them
(mechanical hits and the 32px hit-area gap are real regardless of who calls
the file), but it does mean:

- I did not add any defensive "no player" UI to `Player.qml` /
  `PlayerControls*` beyond what already exists (`required property MprisPlayer
  player` plus the optional-chaining already in place) — inventing behaviour
  for an edge case with zero live callers is exactly the speculative work
  AUDIT.md's contract says not to do. If this file gets wired up, whoever does
  it should re-check the null-player path then, with a real caller in hand.
- Gave `property real radius` a real default (`Appearance.rounding.verylarge`)
  since it had none (silently rendered square corners at 0). Zero risk (no
  caller to break), closes a "wrong by default" gap DESIGN.md's contract
  ranks above per-widget polish.

## TrackChangeButton's shape: considered, left alone

`PlayerControls.qml` and `PlayerControlsLyrics.qml` each define a local
`TrackChangeButton: RippleButton { ... }` with no `buttonRadius` set, so it
inherits `RippleButton`'s own default (`Appearance.rounding.small`, a rounded
square) rather than `rounding.full` (a circle), which is what DESIGN.md 9's
"Icon button" recipe names. That default is still a real token (not a
literal), and "small" is also a legitimate reading of 4.2's table ("List row,
tile, chip"). Reshaping it to a circle is a visible shape change on a
duplicated component across two files — a style decision, not a violation —
so it stayed as inherited. Flagging it here rather than silently picking one.

## Hit areas: `TrackChangeButton` was 24×24, under the 32px minimum (3.4)

Bumped to 32×32 in both `PlayerControls.qml` and `PlayerControlsLyrics.qml`.
The icon (`iconSize: Appearance.font.pixelSize.huge`, 22) is unchanged; the
button is fully transparent at rest (`colBackground` is
`transparentize(colSecondaryContainer, 1)`), so this only grows the
(currently invisible) tap target, per 3.4's "expand the MouseArea, do not
inflate the paint." `playPauseButton` (44×44) was already well over the
minimum.

## `LyricsStatic.qml` — not deleted, per the explicit instruction

Grepped its callers first: exactly one,
`modules/ii/bar/Media.qml` (`Loader { active: lyricsStyle == "static";
sourceComponent: LyricsStatic { ... } }`, config-gated by
`Config.options...lyricsStyle`). Left the file untouched.

Neither `Lyrics.qml` nor `LyricScroller.qml` is a drop-in replacement as they
stand: `Lyrics.qml` is a 7-line stack sized for the ~250px background widget
it lives in (`MediaWidget.qml`), not the bar's single text-row slot;
`LyricScroller` needs a `rowHeight` and animates a scroll transition
`LyricsStatic` never had. The brief's "`Lyrics` with scrolling disabled" does
not map cleanly onto either file under its current name — flagging the
mismatch rather than guessing. See "Needs a change outside this family" for
the concrete migration if this is still wanted.

## Needs a change outside this family

**`modules/ii/bar/Media.qml`** (not in cw-media's file list) — if
`LyricsStatic.qml` is still meant to die, `LyricLine.qml` (already in this
family, already used solo-per-line by `LyricScroller`) is the closer building
block, not `Lyrics.qml`. Concrete edit, around the existing `Loader { active:
lyricsStyle == "static"; ... }` block:

```qml
sourceComponent: LyricLine {
    anchors.fill: parent
    rowHeight: parent.height
    highlight: true
    textHorizontalAlignment: Text.AlignHCenter
    text: LyricsService.hasSyncedLines
        ? (LyricsService.syncedLines[LyricsService.currentIndex]?.text ?? "")
        : (LyricsService.statusText || "")
    Component.onCompleted: LyricsService.initiliazeLyrics()
}
```

`LyricLine` does not call `initiliazeLyrics()` itself (unlike `LyricsStatic`),
so the caller has to, or the service never starts fetching. Not applied here:
it is a `bar/Media.qml` edit, outside the writable file list for this family.

**`modules/ii/overlay/media/MediaContent.qml`** (also outside the file list) —
its `LyricScroller` (inside `Item { id: lyricsItem; Layout.preferredHeight:
... } `) has no fallback for `!LyricsService.hasSyncedLines`, unlike the other
two callers. Not cw-media's to fix (a pre-existing caller-side gap, not
something my edits broke — the contract explicitly leaves caller redesign to
each caller's own audit row), but worth flagging since it is the exact "no
lyrics" edge state the brief names, and this caller is the one place it is
still unhandled. `ImmersiveLyricsPane.qml`'s `PagePlaceholder` pattern is the
worked example to copy.

**Optional, not blocking** — `LyricsService` does not expose `lrclib`'s
`loading`/`error`/`instrumental` split, only the combined `hasSyncedLines` and
the human-readable `statusText`. `Lyrics.qml`'s fixed retry indicator therefore
just spins (`loading: true`) whenever there are no synced lines, rather than
distinguishing "still fetching" from "gave up" — `statusText` underneath
already says which. If a future session wants the indicator itself to stop
spinning on a permanent failure, that needs a new alias on `LyricsService`
(e.g. `readonly property bool lyricsLoading: alias lrclib.loading`), which is
a services file, outside this family.

## Orchestrator message about `SwipeDismissible` / owner-coupling

Received mid-session, addressed to "your owner-coupling decision" re:
`SwipeDismissible`'s `owner.parent.parent` coupling. None of cw-media's eight
files use `SwipeDismissible`, drag, or dismiss gestures — that is cw-gestures'
row (`.audit/ii-clipboardToast/notes.md`, brief section 13). No owner-coupling
decision exists here; the message looks misdirected. Taken no action on it.

## Rejected

- **Restructuring `LyricScroller` to split position (spatial) from opacity
  (effects) onto independent animations.** Would fix the overshoot-coupling
  nuance above cleanly, but rewrites the file's core animation model for a
  wobble that does not currently clip or flash. Lane 2 is faithful
  implementation, not redesign; flagged in notes instead.
- **Adding a placeholder inside `LyricScroller` for `!hasSyncedLines`.**
  Would break `bar/Media.qml` and `ImmersiveLyricsPane.qml`, both of which
  rely on it going invisible so their own fallback shows. Checked before
  writing any code, not after.
- **Reshaping `TrackChangeButton` to `rounding.full`.** Legitimate per the §9
  icon-button recipe, but a visible shape change on a duplicated component
  with no mechanical violation backing it — a style call outside this lane's
  mandate. Recorded above instead of acted on.
- **Deleting `LyricsStatic.qml`.** Explicitly told not to, given a caller
  exists; migration documented above instead.

## Gates run

- `python3 tools/check-design.py --diff`, filtered to this family's 8 files:
  clean.
- `python3 tools/check-mpris-hover-preview.py`: `ok: 5 previews filtered, 7
  real players kept`.
- `python3 tools/check-button-states.py`: `ok: 2 shared button roots render
  hover, focus, pressed and disabled` (still exactly two roots — this session
  reused `RippleButton`, did not add a third).
- `python3 tools/check-text-primitives.py`: `ok: text primitives, 0
  failure(s)`.
- `qmllint` (own shadow tree) on all 8 files: zero hard errors; every
  `Warning`/`Info` present is one of four pre-existing, codebase-wide classes
  (`Appearance.*` singleton member resolution, delegate-scope unqualified
  access, unused top-of-file imports, one pre-existing `QList<double>` /
  `QProcess::ExitStatus` note in untouched `Player.qml` code) — verified none
  of them sit on a line this session touched.

## Still needs a running shell or a playing player to verify

- The retry `RippleButton` in `Lyrics.qml` and the dimmed transport in
  `MaterialMusicControls.qml` were checked by reading, not by watching them
  render — this session could not run `qs -c ii` (parallel rule 4) or a media
  player.
- `MediaWidget.qml`'s two `Lyrics { ... }` instances (desktop background
  widget) are the only place the rewritten "ok" branch (real synced-lyrics
  stack) and the "no lyrics" branch will be seen together in the live shell;
  worth a visual pass with and without an active player once the shell is
  free.
- The `LyricScroller` retokenized animation (350ms fast-spatial vs the old
  400ms OutQuart) should get a 60fps-recorded check per DESIGN.md 2.4's rule,
  not eyeballed — not done here since it needs the running shell.
