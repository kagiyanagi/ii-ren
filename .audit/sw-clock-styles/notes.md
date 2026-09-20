# sw-clock-styles — notes

Lane 2, twelve near-clones of one page. Built directly on `sw-clock-configs`, which put the
page header on `ContentPage` and coined this family's vocabulary.

## What landed

**Header, all twelve.** `adopt_header.py` from lane 1's scratchpad, unmodified, on all
twelve in one go; every file's hand-rolled `RowLayout` + 40dp `RippleButton` + `arrow_back`
+ title `StyledText` + `signal goBack` collapsed to one `title:` on the root. No file's
shape defeated it. `DesktopNothingWheelClockConfig` declared `signal goBack()` *above*
`forceWidth`, so the script left `title:` above it too — normalised by hand to the family's
`forceWidth` / blank / `title:` order. Net −322 lines across the twelve.

**Placeholder wrapper.** `implicitHeight: 250` → `Appearance.sizes.pagePlaceholderHeight`
on eleven; `DesktopWordClockConfig` had **180**, which is why a token and not a
copy-pasted constant was the right call — that page's placeholder was 70px shorter than
every sibling and nobody noticed.

## The vocabulary the twelve now share

Verified mechanically, not by eye (see **The cohesion assertion** below):

| | |
|---|---|
| page title | `Translation.tr("<Name> Options")` |
| section | `Translation.tr("Clock Settings")` · icon `"schedule"` |
| placeholder | icon `"watch"` · `MaterialShape.Shape.Circle` · `"<Name> disabled"` · `"Enable the <Name> in Desktop Widgets settings to use this page."` |
| subsections | `Size` → `Display Elements` → `Style & Appearance`, in that order, none of them invented per page |
| last | `DesktopWidgetVisualOptions`, because it is global and not about this widget |

`<Name>` is **the registry's own `name`**, not the page's guess. That is the point a later
session will not see in the diff: the placeholder's whole job is to send someone to Desktop
Widgets and have them find the row it names, so the copy has to use the string that list
shows. Two pages were lying about it before this row:

- `DesktopNothingClockConfig` said *"Nothing Clock disabled"* while its own description said
  *"Enable the Nothing **Digital** Clock"* — the same page disagreeing with itself. Registry
  name is `Nothing Digital Clock`; both now say that.
- `DateDesktopWidgetConfig` called it *"Date widget"* / *"desktop date widget"*. The
  registry calls it **`Date Card`**. Renamed throughout, page title included. It keeps its
  date-flavoured icon (`calendar_today`, section and placeholder) and `Date Settings` as the
  section title, per the row brief; everything structural matches the other eleven.

Section titles before this row were `Nothing Digital Clock Settings`, `Word Clock Settings`,
`Flex Clock Settings`, `Hori Clock Settings`, `Nagasaki Clock Settings`,
`Nagasaki Text Clock Settings` and 5× `Clock Settings`. All eleven clocks are now
`Clock Settings`: the page title one line above already names the widget, so repeating it in
the section header is the widget's name twice in 40px.

## Design calls

- **`DesktopWordClockConfig` was the outlier on every axis** and is the one page worth
  reading the diff for. It had *no `Translation.tr` at all* — eleven bare user-facing
  strings, and no `import qs.services` to fix them with. Both added.
- It also hand-rolled a `ConfigSwitch` on `background.widgets.enableShadows` — the *global*
  key that `DesktopWidgetVisualOptions` already owns, 8 lines re-implementing a shared block
  that lives in the same directory. Replaced with the block, which also hands that page the
  `enableInnerShadow` toggle it was missing. No config key lost: checked key-by-key against
  `HEAD` for all twelve, and `enableShadows` is the only one that moved.
- **Subsection labels were eight different words for four ideas** — `Display Options`,
  `Size & Colors`, `Typography`, `Color`, `Widget Size` alongside the `Size` /
  `Display Elements` / `Style & Appearance` triple that four pages already used. Collapsed
  onto the triple. `Size & Colors` (Flex, Hori) split into the two groups it was actually
  two of, and `Nothing`'s single `Display Options` split so `useAccentColor` sits under
  style with every other colour switch in the family rather than among the visibility
  toggles.
- `DesktopNagasakiTextClockConfig` keeps `format_size` / `"Font Size"` on its slider under
  the `Size` label: the label is the family's, the row names the property honestly, and a
  font size in points is not the `aspect_ratio` / `"Widget Size"` percentage the other seven
  sliders are. Same reasoning kept Word Clock's 160–420 range while its icon and row label
  moved onto `aspect_ratio` / `"Widget Size"` — it *is* the widget's size.
- `DesktopNagasakiClockConfig` had `Item { Layout.preferredHeight: 8 }` as a manual spacer
  before the visual options. Deleted: the `ColumnLayout`'s `spacing: 4` and the block's own
  `ContentSubsectionLabel` do that, and no sibling page had one.
- `DesktopNothingWheelClockConfig` wrapped its single child in a second `ColumnLayout`
  identical to its parent. Flattened.
- The `// ── Size ──────────` comment banners (4 of 12 pages) are gone. The
  `ContentSubsectionLabel` on the next line says the same thing to the user, which the
  comment does not.
- Presence of `DesktopWidgetVisualOptions` was **left alone**. Seven pages have it, five do
  not, and the brief only fixes its *position* (last). It is a global toggle; adding it to
  five more pages would put the same two switches in twelve places instead of seven, which
  is the copy-paste this tranche exists to undo. Its position is now last on all seven.

## Cost

Unchanged at zero. No `layer.enabled`, no `MultiEffect`, no `OpacityMask`, no shadow, no
`Canvas`, no `Timer`, no new file, no new widget. Nothing was added to any of the twelve —
the only insertion in the whole row is `import qs.services` in one file.

## Motion

**None retimed.** These pages declare no `Behavior`, no animation and no duration, before or
after. The only motion they have is `ConfigSubPageHost`'s page slide and `PagePlaceholder`'s
own enter/exit, both of which are shared and audited elsewhere. One thing for the cohesion
pass: all twelve now toggle their placeholder via `PagePlaceholder`'s `visible`/`opacity`
path inside an `Item` whose `visible` flips at the same instant, so the fade is cut off by
the wrapper disappearing. That is the shape lane 1 shipped and every page in the directory
uses it — if it is worth fixing it is worth fixing once in `ContentSection`, not twelve
times here.

## The cohesion assertion

"If two pages disagree after this row, the row is not done" is not eyeballable across twelve
files, so it was asserted with a throwaway script rather than read: for each page, root
`title` matches `<Name> Options`; section title + icon match the family (or the date page's
own pair); the placeholder block matches the family template *with that page's own `<Name>`
substituted in*; the wrapper is on `pagePlaceholderHeight`; exactly one widget id gates both
blocks and the placeholder is gated on its negation; every `ContentSubsectionLabel` is one
of the three family words and they appear in family order; `DesktopWidgetVisualOptions` is
last; no `arrow_back` or `signal goBack` survives; no user-facing string is untranslated.
All twelve pass.

It is **not** a `tools/check-*.py`: this row's fence forbids adding files under `tools/`.
If the directory-wide version of this is wanted after the tranche, that assertion is the
shape to write, generalised over the family's placeholder template — it caught the two
self-contradicting widget names above, which reading the files did not.

## Outside the fence (findings, not diffs)

- `dots/.config/quickshell/ii/modules/settings/widgets/DesktopDialClockConfig.qml:27` —
  `"Enable the Dial Clock **widget** in Desktop Widgets settings…"`. The only page in either
  clock family with the extra word; the shared sentence has no "widget" in it.
- `DesktopClockWidgetConfig.qml:14` (`Cookie Clock Settings`) and
  `DesktopWearOSArcClockConfig.qml:14` (`Arc Clock Settings`) still repeat the widget name in
  the section header that the page title already carries, while the other four pages of
  their own family say `Clock Settings`. Both are `sw-clock-configs` files.

## Gates

`check-design.py --diff` 0 findings · `check-scaffold-containers.py` ok ·
`check-button-states.py` ok · qmllint clean on all twelve. qmllint's only remaining output is
`Member "widgets"/"pagePlaceholderHeight" not found on type "QObject"/"JsonObject"` — the
same `QtObject`-inside-a-singleton blind spot lane 1 recorded for `Appearance.colors.*`,
now also visible on `Appearance.sizes.*` and `Config.options.background.widgets.*`. Not a
finding. No runtime gate was run from this row by design; the parent runs
`probe-settings-pages.sh` once all eight lanes land.
