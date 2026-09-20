# cw-config-rows — notes

## The one mechanism worth understanding before touching these files again

`ContentGroup` (cw-scaffolding's) draws the card behind every row that sets
`wantsCard`. It hands the card's four corner radii and its per-side 8px bleed *only*
to a row that exposes `buttonRadius`:

```qml
readonly property var tiles: (row?.buttonRadius !== undefined) ? [row] : (row?.visibleChildren ?? [])
readonly property bool paints: card.carded && tile?.buttonRadius !== undefined && tile?.wantsCard === true
```

`ConfigSwitch` is rooted in `RippleButton`, so it had `buttonRadius` and got them for
free. **Nothing else in the family did.** `ConfigSpinBox` and `ConfigTextField` now
declare `buttonRadius` + the four `*Radius` + `backgroundBleedLeft/Right` purely so
that handshake fires; ContentGroup overwrites them with the card's real values via
`Binding`, and the widget's own film reads them back.

Two consequences that are not obvious from the diff:

- Declaring `buttonRadius` flips `ContentGroup.tiles` for that row from
  `visibleChildren` to `[row]`. For a bare row that is what you want. Inside a
  `ConfigRow` the row is the container and *its* children are the tiles, so a spin box
  or text field in a `ConfigRow` now gets only the edges it actually touches — which
  is §5.6's "only the outermost tile of a row touches an edge", finally reaching
  through a container.
- The films this fixes sit at `opacity: 0` except during the three blinks of a search
  hit, so **a regression here is invisible**. That is why
  `tools/check-config-row-cards.py` exists: it asserts both halves of the handshake
  (ContentGroup still keys off `buttonRadius`, the rows still size from the bleed and
  take all four corners) and it is mutation-tested against four ways of breaking it.

## `StateOverlay` forwards per-corner radii only — a bare `radius` gives you a square film

`StateOverlay` passes `topLeftRadius`…`bottomRightRadius` down to its `StateLayer`
children and nothing else. `StateLayer` is a plain `Rectangle` with no `radius`
default, so an unset corner arrives as `-1`, falls back to `0`, and the film paints a
square inside your rounded surface. Cost me one round trip on `MonitorRect`. Set all
four, always — even when the surface has a single uniform `radius`.

## What each file owed and what it got

| file | what was wrong | what it is now |
|---|---|---|
| `ConfigSwitch` (129 callers) | label never elided; icon+label each re-applied `opacity: 0.4` on top of `RippleButton`'s, so a disabled row's text sat at **0.16** while its switch sat at 0.4; search flash at one `buttonEffectiveRadius`, no bleed | elides; one disabled opacity; flash matches the card |
| `ConfigSpinBox` (56) | flash anchored with `-2/-2/-4/-4` margins — 4px short of the card horizontally, 2px **past** it vertically (§10.13 verbatim) | card geometry via the handshake |
| `ConfigTextField` (22) | painted its own `rounding.verysmall` rectangle (harmless only because the colour was `transparentize(…, 1)`, alpha 0); **no focus state at all**; label could not elide | rectangle gone, `opacity` on the root, 0.10 focus film on `textField.activeFocus`, label elides |
| `ConfigSlider` (47 files / 124 sites) | no `Layout.fillWidth`; 35 sites set it themselves, 89 sized to the label row inside a full-width card | default fixed; §5.7's label-above-track was already correct |
| `ConfigSelectionArray` (70) | delegate overrode `GroupButton`'s disabled `opacity: 0.4` with `0.5` | line deleted; the token wins |
| `ConfigListViewEntry` | dragged row **faded** to 0.8 (§3.6 says lift, not fade) on `elementResize`, a spatial spec, which overshoots past 1 — the family's only `check-design.py` hit; `colHover` declared and never used, so no hover state; title could not elide; `colTitle` was `colOnLayer0` on a layer-2/3 surface; cursor read the list's `dragging`, so every row showed a closed hand while any one moved | 0.16 drag film + hover + press via `StateOverlay`, `colOnBackground` for both film and title, title elides, per-row cursor |
| `ConfigListView` | transparent `Rectangle` root carrying a `rounding.large` of its own that painted nothing and could only disagree with the card | `Item` |
| `ConfigSubPageHost` | enter and exit were the same 500ms spatial spec (§2.5); the overshoot could push `x` past `width`, and `overlayActive` releases at `x >= width - 1` | enter `elementMove`, exit `elementMoveExit`, spec assigned from inside the `x` binding per §2.9 (`Revealer`/`PagePlaceholder` shape), `alwaysRunToEnd: false` |
| `MonitorRect` | drag = `Qt.alpha(colPrimaryContainer, 0.7)`, a fade; hover only, no press, no focus, no keyboard; two literal `font.pixelSize` clamps; overlap fill was a half-alpha `m3colors.m3error` | four states via `StateOverlay`, `scale: 1.03` lift, `activeFocusOnTab` + Enter/Space, tokenised sizes, `colErrorContainer`/`colError` |
| `ConfigRow`, `MonitorCanvas`, `MonitorPicker` | nothing | unchanged |

**No row-level dividers or separator bars exist anywhere in this family** — §5.5 had
nothing to kill here. `MonitorCanvas`/`MonitorRect` borders are container outlines, not
separators, and `check-design.py`'s `no-separator-bars` rule agrees.

## Edge states

`ConfigListView` is the only widget here that can be empty, and it already degrades to
a collapsed card whose entire content is the "Add component" row — the fix for the
empty state is the one control still on screen. A `PagePlaceholder` above it would make
the card taller to say what the button already says, so it was left out deliberately
rather than missed. `MonitorCanvas` cannot be empty (there is always at least one
screen). The rest are single controls with no empty/loading/error state.

## Rejected

- **Rebuilding `ConfigTextField` on `MaterialTextField`.** The pack suggests
  `StyledTextField`; no such type exists. `MaterialTextField` does, but it is the M3
  *filled* field with its own container and label, so adopting it redesigns 22 callers'
  rows, and it belongs to `cw-inputs`. The raw `TextField` here is already fully styled
  inline; what it lacked was the focus state, which is what it got.
- **A shadow for the two drag lifts.** §3.6 asks for elevation. `ConfigListViewEntry`
  is a repeated delegate and §8/§10.11 forbid an effect there outright. `MonitorRect`
  could afford one (1–3 instances) but `StyledRectangularShadow` has to be a *sibling*
  of its target — as a child it draws over the parent's own fill — which would mean
  restructuring `MonitorCanvas`'s `Repeater`. Both use a scale lift instead, which is
  what `DockButton` and the rest of the shell already read as "picked up".
- **Escape closing `ConfigSubPageHost`** (§3.7). A `Shortcut` is the only way in — the
  host is an `Item` with no focus — but `Qt.WindowShortcut` is processed ahead of the
  focused item's key handling, so it would very likely steal Escape from any
  `StyledComboBox` popup or `WindowDialog` open inside a sub-page. The host already
  supports nesting, so two enabled Escape shortcuts would also collide (guardable with
  `navigationPath.length === 1`, but that is guessing). Mouse-back already works via
  `win.navigateBack`. **Needs a running shell to settle** — snippet below.
- **Changing `ConfigSlider`'s search highlight.** Its `HighlightOverlay` is
  `visible: false` and exists only to drive `opacity: 1 - highlightOverlay.opacity` on
  the label and icon, so a slider row "flashes" by dimming itself three times while
  every other row flashes a `colSecondaryContainer` film. Making it match needs the
  overlay to escape the `ColumnLayout` (a visible child takes a cell; anchoring a
  layout child to its own layout is the undefined behaviour
  `check-scaffold-containers.py` exists for), which means changing the root type on a
  widget with 124 instantiations. Left as is and exempted by name in
  `check-config-row-cards.py`.
- **Deleting `ConfigSpinBox.hovered`/its `HoverHandler`.** No caller reads it in this
  tree, but it is public API on 56 callers and the row is not clickable, so there is no
  state to render either way. Not worth the risk for four lines.

## Needs a change outside this family

Nothing my work depends on. Two pre-existing defects found while reading, both for the
`modules/settings/widgets/` tranche, neither touched:

1. **`BarLayoutConfig.qml` and `LauncherResultsConfig.qml` set properties
   `ConfigListView` does not have.** `availableComponents` (both),
   `addButtonText`, `infoProvider`, `normalizeEntry` (`LauncherResultsConfig`). None are
   declared in `ConfigListView.qml` — never were, per `git log`. Assigning a
   non-existent property is a load error, so those two sub-pages should be failing to
   load today (`ConfigSubPageHost` would log `LOADER_ERROR`). Either the properties get
   added to `ConfigListView` or the callers get cut back; deciding that is a redesign of
   `ConfigListView`'s API, not an audit fix, so it is recorded rather than guessed at.
2. **`ExtensionConfigPanel.qml:78`** sets `anchors.left: parent.left` on a
   `ConfigSwitch` that is a `ContentGroup`/`ColumnLayout` child, with the comment "i
   have no fricking idea why configswitch applies parent margins twice". That is
   anchoring an item a layout manages — Qt calls it undefined behaviour. The doubled
   margin it works around is almost certainly the anchor fighting the layout.

## Still needs a running shell

- The 0.10 focus film on `ConfigTextField` — Tab into a settings text field and check
  the film renders over the card and clips to its corners.
- `MonitorRect`'s `activeFocusOnTab`: whether Tab actually reaches the tiles from the
  Hyprland settings page's focus chain, and whether Enter/Space select without the page
  eating the key first.
- `ConfigSubPageHost`'s exit: the close should now take ~130ms against a ~500ms open.
  Measure at 60fps, do not eyeball (§0.4).
- The search flash (`ContentSection` search → a `ConfigSpinBox`/`ConfigSwitch`/
  `ConfigTextField` row) filling its card edge to edge — checked on a lone row, on the
  first and last of a run, and inside a `ConfigRow`.
- Whether Escape currently closes a `StyledComboBox` popup inside a sub-page. If it
  does not (i.e. nothing else claims Escape there), this is the snippet:

  ```qml
  // in ConfigSubPageHost's root Item
  Shortcut {
      sequences: [StandardKey.Cancel]
      enabled: host.isOpen && host.navigationPath.length === 1
      onActivated: host.requestBack()
  }
  ```

  The `navigationPath.length === 1` guard is what keeps a nested host from making the
  shortcut ambiguous with its parent's.
