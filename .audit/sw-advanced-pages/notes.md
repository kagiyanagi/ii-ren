# sw-advanced-pages — notes

Lane 2. Two files: `CustomCursorConfig.qml`, `ThemedIconsConfig.qml`. Both reached from
Advanced. Both are pickers; neither had a preview before this row, and both opened with a
40-line prose card where the preview should be.

## The header, adopted by hand

These are two of the three `Item`-rooted pages, so `sw-clock-configs`' transform was not
run on them. Done by hand, exactly as that row's notes prescribe:

- `showBackButton` / `signal goBack()` stay on the **`Item` root** — that is the object the
  `Loader` produces and the object `ConfigSubPageHost.onLoaded` writes to.
- The nested `ContentPage` now carries `title:`, `showBackButton: subPageRoot.showBackButton`
  and `onGoBack: subPageRoot.goBack()`, and the hand-rolled `RowLayout` + 40dp
  `RippleButton` + `arrow_back` + title `StyledText` is gone (~30 lines each).
- Titles kept verbatim (`"Cursor Configuration"`, `"Icon Packs (Apps & Folders)"`) so no
  `Translation.tr()` string churns.

Neither file had an `implicitHeight: 250`; the placeholders this row *adds* use
`Appearance.sizes.pagePlaceholderHeight` from the start.

## The restructuring

**The preview is the first row under the section header, and it is a `ContentGroup` card,
not a hand-rolled `Rectangle`.** Both files opened with two stacked `Rectangle`s at
`Appearance.rounding.small` — an "info" card on `colLayer2` and a "status" card on
`colLayer1`, i.e. a child card on a *deeper* layer than the card below it, both at a
card radius the rest of the directory does not use. Both are deleted:

- The info card's prose became the `ContentSection`'s `tooltip`. Every word is kept; it is
  a scope note for the section and `ContentSection` already renders one as an info icon
  beside the title. This is what stops the explanation out-ranking the preview.
- The status card became the preview: a bare `Item` with `readonly property bool wantsCard: true`,
  so `ContentGroup` paints the card — correct `colSurfaceContainerHigh`, correct
  `rounding.large` run ends, correct 8px bleed, correct in sharp mode, zero hand-rolled
  geometry. Text inside uses `colOnSurface` / `colOnSurfaceVariant`, the roles for that card.

**Cursor preview** — the pointer glyph at `iconSize: CursorTheme.configuredSize`, 1:1 with
what the compositor will draw, inside a fixed 96-wide cell (`maxCursorSize`, the spin box's
own bound, named once on the root and used by both) so the lines beside it do not reflow as
it grows. Second line is the *live* system theme + size + the sizes the theme actually
ships.

**Icons preview** — a `folder` glyph in `colPrimary` when the effective pack is dynamic and
`colOnSurfaceVariant` when it is not, plus a `Pill` reading Dynamic/Static. That is the ✦
in the chip labels, shown instead of spelled. The second line names *which mode* is being
previewed (`Appearance.m3colors.darkmode`), which is how the page admits that the other
mode's picker is a change for later rather than a control that did nothing.

## Design calls a later session should not re-litigate

- **The apply button is not the primary action, so it no longer looks like one.** On the
  cursor page `CursorTheme.setCursor()` already runs the apply script, so every chip, the
  spin box and the text field apply on change; the button only re-runs it. It was a
  full-width 48-tall `colPrimaryContainer` button — the one thing on the page styled bigger
  than everything else, which the shared brief bans outright. It is now a settings row:
  `wantsCard: true`, `implicitHeight: contentItem.implicitHeight + 12 * 2`,
  `buttonRadius: rounding.verysmall`, transparent `colBackground` (the `ConfigSwitch` /
  `AdvancedConfig` entry idiom), so `ContentGroup` hands it the card's corners and bleed and
  hover fills edge to edge.
- **The `appliedRecently` property + 2000ms `Timer` + icon/label swap are deleted from both
  files.** A two-second "Applied!" label is a toast bolted to a button, and it lied about
  the one thing that matters: whether the *system* took it. The preview's live line reports
  that continuously instead (both services re-query 400–500ms after applying). Nothing
  outside these files read `appliedRecently` — the pack lists it only because it scans
  property declarations.
- **Icon picking now applies immediately**, guarded to the mode you are actually in
  (`if (!subPageRoot.darkMode) IconThemes.applyCurrent()` and the mirror). The cursor page
  already worked this way; the icons page wrote config and waited for Apply, which is the
  shared brief's Purpose line failing. The guard matters: without it, picking the light pack
  in dark mode execDetaches the apply script over an unchanged pack.
- **Cursor size is one option, so it is one card run.** The size chips, the custom-px
  `ConfigSpinBox` and the below-`min_size` `NoticeBox` were three loose blocks in two
  different groups; they are now the three rows of the "Cursor Size" `ContentSubsection`.
  A hugging chip row seamed to a full-width row inside one subsection is existing house
  vocabulary — `BarConfig`, `HyprlandConfig`, `InterfaceConfig` and `ServicesConfig` all do
  it — not something invented here.
- **`MaterialTextField` is kept over `ConfigTextField`, deliberately.** `ConfigTextField`
  publishes `inputText` on every keystroke and exposes no commit signal; binding
  `CursorTheme.setCursor` to it would `execDetached` the apply script once per character.
  `MaterialTextField` is the same shared input with an `editingFinished` to hang it on. See
  the finding below.
- **The cursor size chips stay enabled even when the theme ships no bitmap at that size.**
  XCursor substitutes the nearest available size, so those values do apply, just not
  crisply — "does not apply right now" would be a lie and the existing `NoticeBox` already
  says the true thing. Left as-is on purpose.

## Edge states, named

| page | state | treatment |
|---|---|---|
| cursor | no packs installed | `PagePlaceholder` in the preview's slot, `mouse` / Circle, naming the three search dirs **and** pointing at the Custom Cursor Theme Name field, which stays visible so the state has an exit. The Installed Cursor Packs subsection hides (an empty chip card is the "empty card" the brief forbids). |
| icons | management off | `PagePlaceholder`, `palette` / Circle, "Turn on icon theme management to choose packs for light and dark mode." |
| icons | no packs installed | `PagePlaceholder`, `folder_off` / Circle, naming the three search dirs. |
| both | one item | nothing. A one-option `ConfigSelectionArray` renders as a one-chip row; not special-cased, as the brief asks. |

**Departure from the shared brief, deliberate:** the brief says the widget-off placeholder
is "the only thing in the section". On `ThemedIconsConfig` the switch that turns management
back on is *on this page*, not on a widget list elsewhere, so making the placeholder
exclusive would strand the user. The placeholder takes the preview's slot; the enable
`ConfigSwitch` stays; the auto-switch row is `enabled: false` (→ `RippleButton`'s
`opacity: 0.4`) rather than hidden, per the brief's single-control rule; the two picker
subsections are `visible: false`, per the brief's whole-group rule.

## Motion, for the cohesion pass

Nothing was retimed. Two `Behavior on color` added on the icons preview (the folder glyph
and the Dynamic/Static pill), both `Appearance.animation.elementMoveFast.colorAnimation` —
default effects, no overshoot, the correct pair for a two-state tint.

**The cursor preview's pointer deliberately snaps to its new size rather than tweening.**
`MaterialSymbol.iconSize` also feeds the symbol's `opsz` variable-font axis, so animating it
remaps the font every frame; at 350ms/60fps that is ~21 font remaps per size change, in the
one directory whose brief says the effect cost is "zero, and it stays zero". If a later
session wants that motion, measure it at 60fps first (DESIGN.md rule 4) — this row could
not, because audit rows may not start a shell.

The preview ↔ placeholder swap is a plain `visible` toggle on both wrappers, matching the
house pattern (`DesktopCalendarMinimalWidgetConfig` and the rest of the directory).
`PagePlaceholder.shown` is therefore not driven, so its own fade does not play. Consistent
with every sibling page; change it for the family, not for these two.

## Found outside the fence (not touched)

- `modules/common/widgets/ConfigTextField.qml:97` — `onTextChanged` republishes `inputText`
  on every keystroke and the widget exposes no `accepted` / `editingFinished` signal. Any
  page whose text field triggers something expensive (a process, a file write) cannot use
  it, which is why eight settings pages reach past it to raw `MaterialTextField`. An
  `editingFinished` passthrough would let this page drop the exception above. → FINDINGS.md.
- `modules/settings/AdvancedConfig.qml:66-193` — the two entry rows that open these pages
  are hand-rolled `RippleButton`s with an inline `contentItem` (icon + two-line label +
  `chevron_right`), duplicated once per entry. That is a nav-row widget waiting to be
  extracted, and `modules/settings/*.qml` is its own queue row.
- `dots/.config/quickshell/ii/services/CursorTheme.qml` and `services/IconThemes.qml` both
  declare `refreshThemes()` and only call it from `Component.onCompleted`. Install a theme
  while the shell is running and neither list updates until restart — which is exactly the
  exit path the new "no packs found" placeholders point at. A refresh on sub-page open (or
  a `FileSystemWatcher` on the icon dirs) is the fix; it belongs to the services row.

## Gates

`check-design.py --diff` → 0 findings, 0 errors (whole-tranche run; nothing in this fence).
`qmllint` on both files → clean, including the two unused imports (`QtQuick.Controls`,
`Quickshell`) this row removed; they were dead before the edit too.
No runtime gate run — this row starts no process, per the parallel-rows rule.
