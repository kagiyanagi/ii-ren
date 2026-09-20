# common-widgets — notes

## This row is a split, not an implementation

`common-widgets` produced `brief.md`, `families.md`, fifteen family packs and fifteen queue
rows. No QML changed. The one code change was `--only` on `tools/audit/pack.py`.

## Why `--only` exists

`pack.py` takes a directory, and the tranche's own pack is 953 lines — bigger than most
surfaces' entire QML. Fifteen sessions each reading it would pay 953 lines fifteen times,
which is precisely the cost AUDIT.md's burn control exists to avoid. `--only <regex>`
filters the file list against the path relative to the surface dir, so each family gets a
41–145 line pack instead. The regexes are in `families.md` and each is regenerable with one
command; nothing needs maintaining.

The whole-tranche `pack.md` stays, because the **Used by** section is the only place the
cross-family caller picture exists.

## How the split was drawn

By what a widget *is*, not where it sits. The directory is flat — 169 files in one folder
plus `transitions/`, `animations/` and `widgetCanvas/` — so there is no structure to
inherit, and the design law is written per component kind (§9 is a list of recipes), so
family-by-kind is the cut that makes a brief per family possible.

Fifteen families, 446–1,648 lines each, all under the 2,500-line rule. Verified complete:
every `.qml` under `modules/common/widgets` outside the exclusions belongs to exactly one
family, and every name in the split resolves to a file that exists.

**Excluded**, and why:

- `shapes/**` — git submodule (rounded-polygon-qmljs). AUDIT.md scope says out. ~3,220
  lines, mostly `.js`. `MaterialShape` depends on it and is audited; the submodule is not.
- `shaders/check.qml`, `check-weather.qml`, `check-matte.qml` — 502 lines of root `Window`
  dev harnesses for the shader widgets, not shipped surfaces.

That is why the queue row said 175 files / 14,956 lines and this says 169 / 14,176: the
queue counted the harnesses and some submodule `.qml`.

## Order, and the one dependency that forces it

`cw-buttons` runs first because fourteen library widgets are rooted in `RippleButton`, four
of them owned by other families (`ConfigSwitch` → config-rows, `ToolbarButton` →
navigation, `NavigationRailExpandButton` → navigation, `NotificationActionButton` →
notifications). Fix the root first and those four inherit it; fix them first and the work
is done twice, then contradicted.

Nothing else in the library has a cross-family root-type dependency. The rest of the order
is by caller count, which is what decides how much a fix is worth:

| widget | callers | family |
|---|---:|---|
| `StyledText` | 471 | primitives |
| `MaterialSymbol` | 398 | primitives |
| `RippleButton` | 295 | buttons |
| `ContentSection` | 177 | scaffolding |
| `ContentPage` | 175 | scaffolding |
| `StyledToolTip` | 139 | dialogs |
| `ConfigSwitch` | 129 | config-rows |
| `StyledRectangularShadow` | 71 | effects |
| `PagePlaceholder` | 71 | scaffolding |
| `ConfigSelectionArray` | 70 | config-rows |

Counted with `grep -rlE '\b<Name>\s*\{'` over the shell tree excluding `user_widgets/` and
the widget's own file. Regenerate before changing any shared default — rule 9 is the rule
this tranche is most exposed to.

## The mechanical baseline, so a family can tell its work from the tranche's

`python3 tools/check-design.py -v` finds **94 hits** across the library. By rule:

| rule | hits |
|---|---:|
| literal `duration:` | 22 |
| off-grid `spacing:` | 19 |
| hex literal | 8 |
| literal `pixelSize:` | 7 |
| off-grid `margins:` | 7 |
| literal `radius:` (incl. `maskRadius`, `dotRadius`, `borderRadius`) | 11 |
| off-grid other margins | 8 |
| bare `Text` | 3 |
| off-grid `padding:` | 2 |
| inline bezier | 2 |
| `Connections` under async incubation | 1 |

Worst files: `CustomBatteryMeter` 10, `PlayerControlsLyrics` 7, `LightDarkPreferenceButton`
7, `ErrorShakeAnimation` 5, `PlayerControls` 4.

94 hits in 14k lines is a library that is mechanically nearly clean — which is the point of
finding 1 in the brief. **What is wrong here is what a script cannot see**: a missing focus
state, a pressed colour equal to hover, a knob that exports a violation. Do not read a
clean `check-design.py --diff` as a finished family.

## Checker blind spots found while writing this

Both are real and both let a violation through today:

- **Arithmetic literals.** `StyledText.qml:26` is `duration: 300 / 2`. The `duration:`
  rule matches a bare number, so this does not register.
- **Exported knobs.** `CircularProgress` declares `property int animationDuration` and
  `property int easingType`; the literal then lives at each call site, in a different file,
  under a property name the rule does not know.

Neither is worth a checker change on its own. If a third shape turns up, tighten the
`duration:` regex to `[\d\s+\-*/().]+` and add a rule for a `property` whose name ends in
`Duration` or `Curve` inside `modules/common/widgets`.

## Rejected

- **A pack per family generated by a committed shell script.** The `--only` regex in
  `families.md` plus one documented command does the same job with no file to rot. The
  packs are committed anyway, so the common case reads a file and runs nothing.
- **Folding `cw-battery` into `cw-progress`.** 1,040 + 1,060 is under the 2,500 rule, so it
  would be legal. It is still one file with one job and the worst hit count in the library;
  keeping it alone makes it the cheapest possible lane 2 row.
- **`cw-misc` split into per-widget rows.** Four leaves, 463 lines, few callers, identical
  work (tokenisation). Four sessions to save one page of reading is the wrong trade.
- **Deleting `WindowDialogSeparator` here.** Zero callers, §5.5 forbids it, and it is a
  three-line diff — but it lands in `cw-dialogs` with the rest of the dialog family so the
  §5.5 replacement (whitespace + layer card) arrives in the same commit rather than leaving
  dialogs with a gap and no spacing decision.
