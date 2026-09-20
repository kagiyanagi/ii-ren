# ii-bar — notes

Written mid-flight, because the session that dispatched the cluster expected to
be cut off by a quota limit before the rows landed. Everything a later session
needs is here; nothing is in that conversation.

## Where the cluster was left

| row | state |
|---|---|
| `ii-bar-chrome` | **committed** (`refactor(ii-bar-chrome)`) |
| `ii-bar-cards` | dispatched, unreported |
| `ii-bar-weather` | dispatched, unreported |
| `ii-bar-widgets` | dispatched, unreported |
| `ii-bar-tray` | dispatched, unreported |
| `ii-bar-popups` | dispatched, unreported — **owns `StyledPopup`** |
| `ii-bar-resources` | dispatched, unreported |

Packs, briefs and the stagger token are committed (`docs(ii-bar)`), so every
unreported row can be re-run cold from two files with nothing reconstructed.

## Resuming: first sort the working tree into three piles

A row cut off mid-write leaves a broken file; a row that finished but never
reported leaves a *complete* diff that was simply never gated. Those look
identical in `git status` and are not the same thing. Sort them mechanically,
per row's file set (the lists are in each row's `brief.md`):

```sh
bash tools/p3-widget-port/mkshadow.sh \
     dots/.config/quickshell/ii /tmp/shadow-resume
/usr/lib/qt6/bin/qmllint -I /tmp/shadow-resume <that row's files>
python3 tools/check-design.py --diff 2>&1 | grep -E '<that row's files>'
```

- **qmllint Error-level output** (above all *assigning a property a type does
  not have*) → cut off mid-write. `git checkout -- <that row's files>` and
  re-run the row from its brief. Cheap: one row, not the cluster.
- **clean qmllint + empty design-check** → finished, ungated, unreported. Read
  the diff against the row's `brief.md` and commit it. Do not throw it away.
- Use `/usr/lib/qt6/bin/qmllint`. `/usr/bin/qmllint` is a Qt5 stub that prints
  nothing and exits 255, which looks exactly like a clean run.

Nuclear option, if the desktop is unusable and the diff is not worth triaging:
`git checkout -- dots/` restores the last committed shell and costs only the
uncommitted rows.

## The gate that was deliberately deferred

`tools/audit/smoke.sh` has **not** been run for this cluster. It does
`pkill -x qs`, so it cannot run while sibling rows are mid-edit — it would kill
the user's desktop and gate six half-finished rows at once. Run it once, after
the last row is committed, and `smoke-settings.sh` is not needed here (no
`modules/settings` file is touched).

## Fences, if the remaining rows are re-dispatched in parallel

The four from `.audit/common-widgets/notes.md`, plus two this cluster needs:

1. Disjoint file lists, enumerated per row in its `brief.md`. The coupling is
   real: `cards/` is composed by eight files across four rows, and
   `StyledPopup` is the root type of ten popups.
2. Frozen APIs — nothing another file reads gets renamed or removed, additive
   only. This is what lets parallel diffs land without a merge.
3. No git and no shell from a row session; the dispatcher owns both.
4. Path-filtered `check-design.py --diff` — unfiltered, it reports every
   concurrent session's added lines at once.
5. **The popup shell and the card kit are frozen-API for every row that does
   not own them.** `ii-bar-popups` owns `StyledPopup.qml`; `ii-bar-cards` owns
   `cards/*.qml`.
6. **Private qmllint shadow dir per row.** `mkshadow.sh` `rm -rf`s its output.

## Cross-row findings, reported but not fixed

From `ii-bar-chrome`, which was fenced out of all three:

- `modules/ii/bar/NetworkSpeed.qml:44` — assigns `rootItem.visible` directly
  instead of calling `toggleVisible()`, so that one widget still pops instead of
  collapsing. Not a regression; it broke the old binding too. (`ii-bar-widgets`)
- `modules/ii/bar/PrivacyIndicator.qml:74` — reads `rootItem.visible` as the
  state flag, which is now true for the 130ms of the collapse. Harmless,
  `toggleVisible`'s guard absorbs it, but `rootItem.shown` is the accurate read.
  (`ii-bar-tray` owns the file, `ii-bar-widgets` owns the pattern)
- `modules/ii/verticalBar/VerticalBarContent.qml:19` — `HorizontalBarSeparator`
  is a separator bar (law 11) *and* dead: declared, never instantiated. Outside
  this cluster entirely; for whoever takes `verticalBar`.

## Open ruling, raised rather than decided

`ii-bar-chrome` left the two `FocusedScrollMouseArea` halves of the bar without
a state layer. Contract 3 asks for four states on a bar item, but these are
half-screen-wide targets that toggle the sidebars, and a hover film over half
the strip would outrank every widget in it. `ScrollHint` revealing on hover is
the affordance today. Decide it in the cohesion pass, not in a row.

## For the 60fps cohesion pass

Still frames prove nothing about any of this. From `ii-bar-chrome`:

1. The auto-hide reveal at both edges, with `autoHide.pushWindows` on and off —
   the `exclusiveZone` flip is Hyprland's own animation running alongside. Check
   the 500ms enter does not feel sticky against the 130ms exit, and that a
   reversal mid-slide cuts in rather than finishing.
2. The Super-press reveal (`showWhenPressingSuper`) — same motion, different
   trigger, after the configured delay.
3. A widget collapsing out of the row (start a recording or a timer, or empty
   the tray): the 4px `RowLayout` spacing dropping at the end of the collapse
   must not read as a hitch, and the neighbours' corner morph should land with
   it rather than after it.
4. `padding: 5 → 4` makes every bar item 2px narrower. One look at the strip as
   a whole, especially the centre run.
5. The vertical bar — the `root.vertical` → `rootItem.vertical` fix changes
   which anchor the group takes there, and the collapse runs on height.

Later rows append here; `.audit/DECISIONS.md` holds the standing list.

## Re-port hazard

`cards/*.qml` and the five popups are vendored from ii-p3drovfx by
`tools/p3-bar-popups/port-popups.sh`. Unlike the background widget tree it
`cp`s named files rather than rsyncing with `--delete`, and it only runs when
someone deliberately points `P3=` at a fresh clone — so this redesign stands.
But a future re-port overwrites these files outright and must be reviewed file
by file, not run blind. None of `ii-bar-chrome`'s six files is touched by it.

## Screenshots

`shot-before.png` is the bar on a bare workspace
(`hyprctl dispatch 'hl.dsp.focus({ workspace = 9 })'` — this machine's Hyprland
takes Lua, not the hyprlang dispatch form). No popup shots: they need hover
driving that a session cannot do unattended, and the Gemini vision tier was not
available. The vision step of the protocol did not run for this cluster.
