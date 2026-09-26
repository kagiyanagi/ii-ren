# ii-sidebarPolicies-root — notes

**Opening it.** `qs -c ii ipc call sidebarLeft open`. Hermes is pinned first and every open
lands on it. The stored tab is `sidebar.policies.tab` in `~/.local/state/quickshell/states.json`,
and writing it switches the tab live. The Anime tab needs `policies.weeb` 1 (tab) or 2 (closet).
It was driven here by editing `~/.config/illogical-impulse/config.json` and then restoring the
saved copy byte for byte (`cmp` identical).

**Seen live.**
- Closet (`weeb: 2`) with tab 2 opens Continuity. Before this row it opened the anime grid.
- The Anime page with `weeb: 1`: the `•` is gone and the NSFW row sits in line. Two ydotool
  clicks on the row flipped `booru.allowNsfw` false, then true, and the switch followed both.
  A broken binding would have stopped following after the first. Clicks go at half
  coordinates (ydotool absolute is 2x, see memory).
- Hermes, empty: the description is centred and three lines long. The status pill has no
  dots.
- The zerochan disable was not driven. It is one binding (`nsfwRow.enabled`), and the check
  pins the switch to it.

**Retimed, for the cohesion pass to watch at 60fps.**
- *Scroll to bottom*: the scale was `elementResize` in both directions. It now enters on
  `elementMoveSmall` (fast spatial, the chip is small) and leaves on `elementMoveExit`. The
  opacity leaves on `elementMoveExit` instead of `elementMoveFast`. It grows from its bottom
  edge. It was centre-origin.
- *Pin*: the sheet's radius now springs on `elementResize` with the height and y it changes
  beside. It used to snap on frame 1. A spatial overshoot takes the radius below 0 for a few
  frames, and Qt clamps that to square. Check that the unpin, 0 → concentric, does not look
  late.

**Not run.** `tools/audit/smoke.sh` (it runs `pkill -x qs`, as `ii-sidebarDashboard-root`
noted). The running shell hot-reloaded every edit and logged nothing from these files. The agy
vision pass was not run either: the shots are `shot-after.png` (Hermes) and
`shot-after-anime.png`.

**Left for others.**
- `InputIconButton` → `hermes/HermesIconButton.qml` (hermes brief, contract 5). The panels row
  creates that file. Whoever lands second points `InputIconButton` at it.
- `HermesHistoryPanel.qml:132` binding loop, still logging (the panels row's file).
- `ApiInputBoxIndicator` as a button is about 24px tall, under the 32px target. It sits in the
  composer's 32px control row, so raising it means raising that row.
- The sidebar's width rule (`weeb == 1 && wallpapers && translator`) is a stale proxy for
  "four tabs". It does no harm (see the brief).
- Two strings changed, so their translations fall back to English: the Hermes placeholder
  lost its Enter line, and the tab host's empty placeholder is now a title.
