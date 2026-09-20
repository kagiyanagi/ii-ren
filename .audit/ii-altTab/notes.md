# ii-altTab — notes

## How to drive it

`qs -c ii ipc call altTab next` / `prev` / `confirm` / `cancel`. `cancel` is new and is
what a probe wants — `confirm` changes focus, which reorders `focusHistoryID` and makes
the next run's shot different.

Two things will otherwise read as the surface being broken:

- **Nothing appears for ~150ms.** That is `popupDelay`, and it is the point of the row.
  `next` immediately followed by `cancel` maps no layer at all; sleep 0.6 before `grim`.
- **`currentWorkspaceOnly` is `true` in the live config here**, against the shipped
  `false`. This machine had four mapped windows across three workspaces and the switcher
  showed exactly one tile. Flip the key in `~/.config/illogical-impulse/config.json` to
  see the real thing — `FileView` picks it up without a restart — and put it back
  byte-exact afterwards, because `iiren save` pulls that file into the repo.

## The Hyprland half is not live until `iiren update`

`~/.config/quickshell/ii` is a symlink into the repo, so the QML is live the moment it is
saved. `~/.config/hypr` is **not** — it is a copy. The `ALT + Escape` bind added to
`keybinds.lua` therefore does nothing on this machine until `iiren update` runs. The
`altTabCancel` shortcut itself is registered by the shell either way, so the IPC call
works now and the keybind works after an update.

## What the cohesion pass has to watch at 60fps

Everything on this surface was retimed, so all of it:

- **Enter**, after the 150ms hold: scale 0.92 → 1 with opacity, 200ms `emphasizedDecel`.
- **Exit**: the same, 100ms `emphasizedAccel`. Measured at ~145ms of the layer staying
  mapped past a `cancel` (100ms animation, the rest IPC and a frame), against `visible:
  root.open` before, which dropped the window in the same event loop turn as the state
  change and so never drew a frame of it.
- **The highlight** on `elementMoveSmall` (fast spatial, 350ms). This is the one worth a
  second opinion: a fast Tab repeat is ~150ms, so the highlight trails the selection by
  about a tile. That is what a switcher highlight does elsewhere and 2.1 puts a chip-sized
  hop on fast spatial, but it is a judgement call that a still frame cannot settle.
- **Re-opening.** Select the last window, confirm, Alt+Tab again: the highlight must be
  *already* on the new selection as the card fades in, not sliding to it.

## Rejected

- **Keeping a short hand-picked duration instead of the delay.** The comment on the old
  `110 * animMultiplier` was right about the problem — a tap-and-release is over before a
  spatial curve finishes — and wrong about the fix. Every token in `Appearance` is too
  slow for a surface that must appear and leave inside 100ms, so the surface has to stop
  trying: nothing is drawn until Alt has been held past GNOME's `POPUP_DELAY_TIMEOUT`.
  The delay is what makes the real tokens affordable, and it is the only new number.
- **`StateLayer` per tile, driven by hand.** `StateOverlay` is the drop-in (DESIGN.md 3.1,
  preference 2) and it composites, so it survives the tile sitting on the highlight or on
  the bare card. Its four `FadeLoader`s are per tile, which looks like rule 8 until you
  read it: a `Loader` is not an effect and nothing loads until a state is actually on.
- **A press film on the shared highlight instead.** Tempting — one film, no per-delegate
  anything — and wrong, because `onPositionChanged` deliberately does not fire for a
  pointer that has not moved. It also hid a real bug: pressing a tile the pointer was
  already resting on confirmed whatever the *keyboard* had selected. `onPressed` now sets
  the selection, which is both the fix and what makes the film land on the right tile.
- **A `Flickable` that scrolls the tile row to keep the selection visible.** More state
  and more code than a `Grid` that wraps, and it hides windows that a switcher exists to
  show. The grid balances its rows (`ceil(n / rows)`), so 21 windows on a 1080p screen is
  11 + 10, not 20 + 1.
- **Verifying the wrap by staging twenty windows.** Not something a session can set up,
  and the arithmetic is the part that breaks. `tools/check-alttab-grid.py` lifts the four
  expressions straight out of the QML and evaluates them over 320–5120px screens and
  1–200 windows, so it cannot drift from what it is asserting about. It was confirmed to
  fail on both the old single-row shape and on an unbalanced grid before being kept.
- **Window thumbnails instead of icons.** Wants screencopy and is a different surface.

## Left alone, deliberately

- `restoreWarpsTimer`'s `interval: 600`. It is the length of a Hyprland workspace
  animation, not a motion token, and it has the comment that says so.
- `Appearance.animMultiplier`. `AnimSpec` applies it nowhere in the shell (2.9) and 200ms
  is not long enough to be worth a disable path, so the old `110 * animMultiplier` lost
  its multiplier along with its literal.
- **One window.** Alt+Tab with a single mapped window still shows a one-tile card naming
  the window you are already in. It is honest about the state and the title cell floors at
  three tiles so it does not collapse to chrome, but it is arguably a card that should not
  open. Left as it was; changing it is a behaviour call, not a design-law one.
