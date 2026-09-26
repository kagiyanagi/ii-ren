# ii-sidebarDashboard-root — notes

**Opening it.** `qs -c ii ipc call sidebarRight open`. The bottom card's collapsed state and
tab live in `~/.local/state/quickshell/states.json` (`sidebar.bottomGroup`). Writing that file
drives both live, since `Persistent`'s `FileView` reloads it. That is how collapse and tab
switching were driven here without a pointer.

**Measured.** Collapse and expand were recorded at 60fps with `wf-recorder` and checked frame
by frame. Each direction fades the leaving row out, shows an empty card for about 8 frames,
then fades the arriving row in, with no frame where both rows' text shows. The clamp was driven
by writing `tab: 9`: the card lands on Timer, on the live change and on a fresh open.

**Retimed, for the cohesion pass to watch at 60fps.**
- The bottom card's tab switch. The exit went from `elementMoveFast` (200ms) to
  `elementMoveExit` (130ms). The enter's slide went from 200ms to `elementMoveEnter`'s 500ms on
  the spatial curve, and its fade went from the spatial curve to `elementMoveFast`. The slide is
  10px, so the overshoot is small. Judge whether the 500ms tail reads as slow on a rail the user
  flicks through.
- Collapse and expand: now always a fade-through, where the first toggle after each open used
  to cross-fade.

**Not run.** `tools/audit/smoke.sh` does `pkill -x qs`, which would also have killed the
owner's open settings window. The running shell hot-reloaded both files and logged no error
from them. The gamma-only quick slider is a one-clause guard and was not driven, because it
needs the classic quick-toggle style, and this desktop runs android.

**Seen, not this row's.** `SysTray.qml:34` throws `closeOverflowMenu is not a function` on
reload. The avatar's fallback chain logs `Cannot open …/AccountsService/icons/user` on every
open. That is the chain doing its job, but it is noisy.
