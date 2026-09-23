# ii-sessionScreen — notes

Ran lane 1, not 2. The layout was a real redesign, but the row turned out to be three
behaviour bugs, none with a symptom in a still frame, and each needed the shell driven to
prove it.

## How to drive it without firing anything

**Enter and a left click are live.** Every tile runs a real action: Lock needs the
password to get back, Sleep suspends the machine, and the bottom row closes every
window first. So:

- Open and close with `qs -c ii ipc call session open|close`. The layer is
  `quickshell:session` in `hyprctl layers -j`, and it is mapped exactly while the menu is
  on screen.
- Arrow keys and a single Esc through `wtype` are safe, but only while the layer is
  confirmed mapped. A key sent after it closes goes to the focused window, and here that
  was the Claude Code terminal, where Up recalls history and Esc interrupts.
- Only **Task Manager** is safe to fire. It runs `plasma-systemmonitor --page-name
  Processes`, and `pkill -x plasma-systemmo` closes it again (`comm` truncates the name).
  Check `pgrep` first, so you never kill a copy the user opened.
- Which tile is lit: sample a 4px square 34px left of each tile centre,
  `(780 + 120·col, 447 | 592)` on this 1920×1080 panel. Primary reads ~175, the tonal
  fill ~63, hovered ~79, and disabled ~43.
- `ydotool mousemove -a` takes **half** coordinates here (`-x 570` lands on 1140) and
  jumps through (0,0) on the way. Relative moves are accelerated over long distances.
  One overshot to (1,1), which is outside the top-left hot corner only because
  y=0/1 is not in its zone.
- The warning states without touching the user's files: copy `/usr/bin/sleep` to the
  scratch dir as `paru` and `aria2c` and run them. `pidof` matches on the process name.
- **The shell stopped hot-reloading again** after a Python in-place write. There was no
  `Reloading` line in `/run/user/1000/quickshell/by-id/<id>/log.log`. `tools/audit/smoke.sh`
  restarts the shell and is what loaded each change. That is the same trap
  `ii-screenCorners` hit.

## What was wrong, and what was measured

1. **No enter or exit.** `Loader.active` read `GlobalStates.sessionOpen`, and
   `rules.lua` gives the layer `no_anim`, so it mapped and unmapped on the frame the flag
   changed. It is latched now (`rendered`) and released by `WindowDialog` hiding itself
   once its card has collapsed. Measured over 12 runs: unmapped 102–127ms after the IPC
   close or the Esc key returned, where before it was the same frame. One outlier, 194ms,
   came right after a shell restart, while the IPC call itself was taking twice as long.
   Closing and reopening at once never unmapped the window (0 gaps in 0.8s of polling),
   and it reopened with Lock lit.
2. **Two selected tiles.** Hover painted the same `colPrimary` as focus. In the
   before-shot, the pointer resting over the firmware tile at open lit it next to the
   focused Lock, with "Reboot to firmware settings" in the tooltip and "Lock" in the
   subtitle. Focus is the selection now (`toggled: tile.activeFocus`), hover is a tint
   (63 → 79, measured with a real pointer move), and focus stays put under hover.
3. **Hibernate did nothing.** logind answers `CanHibernate` = `na` here, since
   `/sys/power/disk` is `[disabled]` even with a 32G swapfile. The tile closed the menu
   and both `systemctl hibernate` and `loginctl hibernate` failed silently. Tiles now read
   `Can*` from logind on every open, and `na`/`no` disables them. `challenge` stays live,
   because polkit will ask.

Also measured: the arrow keys over nine steps (row-bounded, Hibernate skipped, Up into
it holds), a click in the card's padding (stays open) and on the scrim (closes), Esc
(closes, with the exit), and Enter on Task Manager (it launched, and the menu left in
124ms). The scrim is `colScrim`: a static corner read 23.7 closed and 11.3 open, and
settled by 150ms. Blur is off in this Hyprland config (`decoration:blur:enabled`
false), so the `blur` layer rule does nothing here.

`tools/check-session-screen.py` holds all of it. Against the pre-row code it fails 18
asserts, and it catches each of eleven targeted mutations of the new code: the latch, the
row bound, hover focus, the second-Enter guard, `challenge`, the unguarded release, a
bound `show`, an unasked hibernate, a mistyped logind method, a swallowed Esc, and hover
painting primary.

## Decided while building

- **No pressed shape.** M3E gives round icon buttons `CornerLarge` when pressed, but a
  press here focuses the tile first, so the pressed tile always rests round. DESIGN.md 4.3
  does not square a circle on press. The design-check caught this; the brief records it.
- **The warnings are `NoticeBox`es** (design-check reuse note) in its error tone, in
  their own column at `ContentGroup`'s 4px row gap. At `WindowDialog`'s 16, `NoticeBox`'s
  run grouping still joined them, and the result read as two cards with squared-off
  inner corners.
- **Hover does not move focus,** as in a menu. Opening under a resting pointer would
  retarget Enter to whatever it happened to be over, which on this menu can be Shutdown.

## For the cohesion pass (60fps)

- **The whole surface now moves**, on `WindowDialog`'s recipe: the scrim fades in on
  `elementMoveFast`, the card slides 60px down on 200ms `emphasizedDecel`, and it collapses
  in 100ms on `emphasizedAccel`. The card is fully opaque from the first frame and only
  its contents fade, so on this card-sized surface the first frame is an empty card. That
  belongs to `WindowDialog` and every caller of it, not this row.
- **The focus morph:** a tile goes square → round on `elementMoveSmall` (fast spatial,
  overshoots) and tonal → primary on `elementMoveFast`, each time an arrow key moves.
- **A press lights the pressed tile**, so the chosen tile is the one that is round and
  primary while the menu leaves.

## Vision step

agy on `gemini-3.1-pro-high`, `--mode plan`, `--add-dir` on this directory, with
**absolute paths**. Its workspace defaults to its own scratch dir, so relative paths
fail, and it then tried a `find` that headless mode denied. It reported two departures,
and both were misreads, checked against full-resolution pixels. It said the focused Lock
is a rounded square: (742,409) sits inside a 23px corner and outside a 48px circle, and
reads card-coloured. It said the download warning is cut off: the sentence wraps to a
second line, "Downloads folder.".

## Left alone on purpose

- **Drag-off does not cancel a tile. Measured:** a press on Task Manager, dragged onto the
  scrim and released there, launched it anyway. `RippleButton`'s `MouseArea` calls
  `root.click()` in `onReleased` without asking whether the release was inside. That is
  every button in the shell, so it is in `FINDINGS.md` for a `cw-buttons` revisit, and it
  matters most here.
- **Nothing asks before Logout/Shutdown/Reboot.** `Session.qml`'s `closeAllWindows()`
  SIGTERMs every window first, which is what the package-manager warning is about: the
  terminal running pacman is one of those windows. Android's power menu does not confirm
  either, but its apps are built to be killed. A confirm step or an inhibitor check is a
  product call for whoever owns `Session.qml`, which `waffle` shares.
- **The Hibernate icon is `downloading`.** It is upstream's metaphor (saving to disk),
  and now it sits above a "download in progress" warning. The label disambiguates it. An
  icon pass can decide.
- **Multi-monitor is unmeasured.** The window has no `screen` and anchors all four edges,
  so it fills whichever output Hyprland maps it on (the focused one). A headless second
  output (`hyprctl output create headless X`) is how `ii-screenCorners` measured the same
  class of bug.
- **`SessionWarnings.downloadRunning` flags any running `curl`/`wget`.** That includes
  background fetches, so it can false-positive. The wording already says "might".
- **Space and Tab** go through `Button` and were not driven. Tab follows creation order,
  which is row order.
