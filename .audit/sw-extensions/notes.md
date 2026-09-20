# sw-extensions — notes

Lane 2. Three files, all in `modules/settings/widgets/`. No header work: these are
`ColumnLayout`/`Item`-rooted tab contents loaded by `WidgetsConfig.qml`, not
`ConfigSubPageHost` sub-pages, so the `ContentPage` header extraction does not apply.

`WidgetExtensionsContent.qml` 486 → 398 · `WidgetCommunityContent.qml` 227 → 271 ·
`ExtensionWidgetSettingsRenderer.qml` 153 → 140.

---

## The renderer was dead code, and lint says why

`ExtensionWidgetSettingsRenderer` set **`isFirst` / `isLast` on `ConfigSwitch`,
`ConfigSlider` and `ConfigTextField`, and `textField.onEditingFinished` on
`ConfigTextField`**. None of those four exist on those widgets any more — `cw-config-rows`
moved run-end radii onto `ContentGroup`, and `textField` was always a private id. A
missing property is fatal at component load, so **the extension settings overlay rendered
nothing at all**; qmllint prints all six as `[missing-property]` / `unknown grouped
property scope`. That is the first thing to know if a later session wonders why this page
was "changed so much for a reuse pass".

What it is now: root is **`ContentGroup`** — the same widget `ContentSection` puts its own
rows in — and the delegate emits one bare `Config*` row. The group draws the card run,
picks run-end vs seam radii, and hands the row the corners and the per-side bleed the card
actually has. The rows carry no radii, no first/last plumbing and no background, which is
what "look exactly like a first-party page" means mechanically.

Type → control, now matching what `.github/EXTENSIONS.md` documents:

| schema `type` | control | note |
|---|---|---|
| `bool` | `ConfigSwitch` | |
| `int` | `ConfigSpinBox` | was a slider; the doc has said SpinBox all along |
| `slider`, `float` | `ConfigSlider` | `onMoved`, not `onValueChanged` — see below |
| `enum` | `ContentSubsection` + `ConfigSelectionArray` | was a hand-drawn `Rectangle` + `StyledText` + four spelled-out radii |
| `string` | `ConfigTextField` | writes on `inputText`, the only write-back it exposes |

The enum row is the one delegate with `wantsCard: false`: a labelled chip group brings its
own card (the subsection's inner `ContentGroup`), the other four take the outer one's.
Label-above-chips is the shape `QuickConfig` and `ServicesConfig` give every first-party
selection, so an extension's enum now reads identically to a shell one.

`onValueChanged: save(value)` on the slider was a write-back loop waiting to happen — the
signal fires for the `value:` binding too, so every config write re-entered the save. The
house idiom (`BackgroundConfig`) is `onMoved: v => …`, the drag only.

**`float` still renders a slider, not the "SpinBox (decimal)" the doc promises**, because
`StyledSpinBox` wraps Controls' integer `SpinBox` and would truncate. Doc row vs code — the
doc is outside this fence; see Findings.

## The four network states, and how to drive each one

Both browse-and-install lists now have loading / empty / offline / install-in-progress, and
**none of them is a spinner over a greyed page** — the list keeps its shape and the rows
fill in.

### `WidgetExtensionsContent` (installed list)

| state | condition | what renders | how to reach it |
|---|---|---|---|
| loading | `!WidgetExtensionManager.ready` | one `PendingCard` — same colour, radius, margins and width as a real card, with `StyledIndeterminateProgressBar` | `rm ~/.config/illogical-impulse/widget_extensions.json` (`Directories.widgetExtensionsPath`) and reopen Widgets: the manager retries for a 2000ms grace period before writing the file, so `ready` is false for up to ~2s |
| empty | `ready && installedIds.length === 0 && !loading` | `PagePlaceholder` `extension_off`, at `Appearance.sizes.pagePlaceholderHeight` | the same, once the retry lands |
| offline / failed | `lastError !== ""` | `NoticeBox { materialIcon: "error" }` — the shell's failure surface, self-hiding while the text is empty | install `https://github.com/nope/nope` with the network down: `widget_extensions.py` returns `git clone failed: …` |
| install in flight | `loading && pendingInstall !== ""` | a second `PendingCard` at the end of the list, named after the target, with the progress bar | paste any GitHub URL and press Install (or Enter — the field now accepts) |

`pendingInstall` is set at the click and never cleared: it is only read while `loading`, so
clearing it would be work for nothing. `loading` is also true during `updateWidget`, which
is why the pending card needs `pendingInstall !== ""` — an update must not conjure an
"Installing…" row. **An update in flight has no per-card progress**, because the manager's
`loading` is global with no id attached; that needs a service change and is out of fence.

### `WidgetCommunityContent` (GitHub browse)

| state | condition | what renders | how to reach it |
|---|---|---|---|
| loading | `discoverLoading` | `StyledIndeterminateProgressBar` under the header + **three `PendingCard`s**, each a 240-wide card of blank bars at the sizes the real rows are | expand "Browse Community Widgets" (the kickoff Timer fires), or press Refresh |
| empty | `!discoverLoading && !offline && length === 0` | `PagePlaceholder` `travel_explore` | GitHub answers with `items: []` |
| offline | `discoverError !== ""` | `PagePlaceholder` `cloud_off`, "Can't reach GitHub", description = the error + "press Refresh" | drop the network and press Refresh: `discover` returns `Network error: <reason>`, `GitHub API error: 403 …` on a rate limit, or "Discover process exited unexpectedly" if it dies silently |
| install in flight | `loading && installingId === extId` | that card's button says "Installing…"; every card's button disables | press Install on any card |

`installingId` exists because `WidgetExtensionManager.loading` is global — before this,
**every card in the grid said "Installing…" at once**.

The error string moved out of the header and into the offline placeholder. The header line
is now only the count or "Fetching…", so the surface says one thing at a time.

Every `discoverError` is treated as offline, deliberately: HTTP error, URL error, JSON
parse failure and a dead process are all "could not look", and none of them is worth
sniffing the string for. If a later row wants rate-limiting to read differently from no
network, `widget_extensions.py:41` already distinguishes them.

## Reuse, which is most of the diff

- **Six hand-rolled `Rectangle` + `MouseArea` buttons are gone.** Each had hover and
  nothing else — no focus, no pressed, no ripple, 28px against 3.4's 32 minimum. Add to
  Desktop / Remove, Install and Refresh are `RippleButtonWithIcon`; settings, reload,
  update and uninstall are an in-file `CardIconButton` on `RippleButton`, 32×32,
  `rounding.full`, with `StyledToolTip` reading the button's own `hovered` (500ms delay,
  where the old tooltips fired instantly off `containsMouse`).
- **The lock-behaviour chip row is a `ConfigSelectionArray`.** It was a `Repeater` of four
  `Rectangle`s with their own `MouseArea`, their own toggled colours and a literal `150ms`.
  Three of its four tooltips were never wrapped in `Translation.tr()` and the fourth
  double-translated (`Translation.tr(modelData.tooltip)` over an already-translated
  string). Now four chips with icon and label, and the group carries every state.
- `RippleButton` already does `opacity: enabled ? 1 : 0.4`, so the card's hand-written
  `opacity: isEnabled ? 1.0 : 0.4` went with it (3.1).
- `topLeftRadius`…`bottomRightRadius` spelled out four times per button collapsed to
  `buttonRadius`, which is what they derive from.
- The bare red `StyledText` error line is `NoticeBox`, which `WidgetsConfig.qml:223`
  already uses two sections up.
- Both empty states are `PagePlaceholder` in an `Appearance.sizes.pagePlaceholderHeight`
  wrapper — the exact shape `sw-clock-configs` left behind, `visible` on the wrapper rather
  than `shown` on the placeholder, because a 250px wrapper that is always visible would
  push every page down.

## Motion, for the cohesion pass

**Nothing was retimed. Seven timings were deleted, and the widgets under them now own the
motion.** There is no `Behavior`, no `NumberAnimation` and no `Timer` left in any of the
three files. What to watch at 60fps, and what drives it:

| where | was | now |
|---|---|---|
| Add to Desktop / Remove pill, background | `ColorAnimation { duration: 100 }` | `RippleButton`'s own background behaviour + ripple |
| settings button, background | `duration: 100` | same |
| reload button, background | `duration: 100` | same |
| update button, background | `duration: 100` | same |
| uninstall button, background | `duration: 100` | same |
| lock-behaviour chips, background | `duration: 150` | `SelectionGroupButton` — colour *and* the leftRadius/rightRadius morph on selection |
| community card, `Behavior on color` | `duration: 150` | dropped; the colour is static except on a theme change, and the card is no longer the thing that reacts — its button is |

New motion introduced, all of it from audited widgets: `StyledIndeterminateProgressBar`
(AOSP's two-segment sweep, one instance per page, `running: root.visible` so it stops when
its card is hidden), `PagePlaceholder`'s own enter/exit fade and icon rotation, `NoticeBox`'s
radius behaviours, and `StyledToolTip`'s 500ms delay. Nothing scales, so no transform
origin is in play anywhere in this row.

The state transitions themselves (`PendingCard` ↔ real cards, placeholder ↔ grid) are plain
`visible` toggles with no animation, matching the 61 other pages in this directory. If the
cohesion pass wants them faded, that is a change to the family pattern, not to this row.

## Cost

Still zero. No `layer.enabled`, no `MultiEffect`, no `OpacityMask`, no shadow, no `Canvas`,
no new `Timer`. The one pre-existing `Timer` (`interval: 0`, one-shot, the community
kickoff) was left alone. The skeleton cards deliberately do **not** shimmer: a pulse would
be motion inside a repeated delegate, and the indeterminate bar above already says the
fetch is running.

## Gates

- `check-design.py --diff` → 0 findings, 0 errors (whole tranche, all eight rows).
- `check-design.py -v` → **zero hits in all three files**; the seven literal `100ms` /
  `150ms` durations named in the brief are gone and nothing replaced them.
- qmllint (shadow tree) → clean on all three. The only line left is
  `Member "activeWidgets" not found on type "qs::io::JsonObject"` in
  `WidgetExtensionsContent.qml:176`, which predates this row: it is the standing blind spot
  on `JsonAdapter` sub-objects, and `Config.qml:1105` declares the property.
- Not run, by instruction: anything that starts a process. **The renderer has never been
  instantiated successfully** (see the top of this file), so the parent's runtime gate is
  the first time this page will have rendered at all — watch the extension settings overlay
  specifically, and with an extension whose `configSchema` has one key of each type.

## Findings outside the fence

1. `.github/EXTENSIONS.md:606-612` — the type table promises `float` → "SpinBox (decimal)".
   `StyledSpinBox` wraps Controls' integer `SpinBox`; a decimal one does not exist, so
   `float` renders a slider. Either the doc row or a decimal spin box has to give.
2. `.github/EXTENSIONS.md:610` — the table says `enum` → "Dropdown". The shell has no
   dropdown and M3's answer here is a chip group; the renderer emits
   `ConfigSelectionArray`. Doc row is wrong, not the code.
3. `services/WidgetExtensionManager.qml:27-29` — `loading` is one global flag for install
   *and* update, with no id attached. Both pages have to guess which card it belongs to
   (`pendingInstall`, `installingId`). A `busyId: ""` alongside it would let the card that
   is actually updating show its own progress.
4. `services/WidgetExtensionManager.qml:29` — `lastError` is only cleared by the next
   `installWidget()`. A user who gives up after a failure keeps the NoticeBox forever. A
   dismiss would have to write the service property from a view, so it was left out; the
   clean fix is a `clearError()` on the manager.
5. Not a finding, checked because the empty state had to say something true:
   `scripts/widget_extensions.py:26` searches three topics
   (`ii-vynx-extension`, `ii-ren-extension`, `quickshell-widget`) and `EXTENSIONS.md:621`
   documents the first. The placeholder says "the widget topic" rather than naming one,
   so it stays correct if that list changes.

## For a later session

- No translation keys were harmed: `translations/*.json` has no entry for any string in
  these three files, so the reworded placeholders and labels cost nothing. New wording is
  free here.
- `WidgetExtensionsContent` keeps `...` and `WidgetCommunityContent` keeps `…` in their
  ellipses, each matching the strings already in that file. Normalising is a one-line
  sweep whenever someone does the tranche-wide copy pass.
- `pragma ComponentBehavior: Bound` was added to both content files (the renderer already
  had it). Every delegate now qualifies `modelData` through its own id, which is what let
  the pragma go in; a later edit that writes a bare `modelData.foo` inside a delegate will
  fail to resolve rather than silently working.
- The community card is still a literal `width: 240`. It is the one shared dimension in
  this row that belongs in `Appearance.sizes` and could not go there from inside this fence.
