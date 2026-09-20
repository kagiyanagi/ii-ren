# sw-clock-configs — notes

Lane 1. Owns the shared change the other eight `sw-*` rows are built on.

## What landed on `ContentPage`

`title`, `showBackButton` and `goBack()`, plus the header itself as the first child of
`contentColumn` — a `RippleButton` with `arrow_back` and a title `StyledText`. Additive:
no existing property changed meaning.

The header is `visible: root.title !== ""`. That is not cosmetic. `ContentPage` reports
`contentColumn.implicitWidth`, and a `ColumnLayout` excludes an invisible child from its
implicit size but not a transparent one — so a header that merely faded out would widen all
14 callers that never had one. Decision 21 is what that costs when nobody notices.

Two tokens, because the brief's **Delete** list named both literals:
`Appearance.sizes.pageHeaderButtonSize` (40, written four ways across the copies, once as
`elevationMargin * 4`) and `Appearance.sizes.pagePlaceholderHeight` (250, on every
placeholder wrapper in the directory).

## The shadowing question, answered before anything was deleted

All 61 sub-pages declared `signal goBack` of their own, and four also declared `title` or
`showBackButton`. Whether redeclaring a base type's signal or property is an error, a
silent shadow, or a runtime break is not something to reason about — so it was measured:
`tools/audit/probe-settings-pages.sh` instantiated all 61 against the new base **before**
any page was touched, and the log was clean.

That is what makes the remaining eight rows safe to run in parallel: a row that has not
adopted the header yet is not broken by one that has, so the eight orderings are all
equivalent.

## The new gate, and why the old one was not enough

`tools/audit/smoke-settings.sh` proves the settings app opens. It proves nothing about the
70 sub-pages, because every one of them loads on demand — the documented alternative was
"click the five entry points by hand", which is not a gate and does not survive eight
sessions running at once.

`tools/audit/probe-settings-pages.sh` writes a throwaway `qs -p` config into the shell dir
(the `qs.` imports resolve nowhere else), puts every sub-page in one `Repeater`, and greps
the log. It kills only the pid it started and names its probe file after that pid, so
several can run at once.

Its selector is a **union** — root type `ContentPage`, *or* declares `signal goBack`. The
first version matched the signal alone and silently dropped from 61 pages to 55 the moment
this row's six stopped declaring it. A gate that shrinks as the work lands is worse than no
gate.

## The header transform

`/tmp/…/adopt_header.py` in this session's scratchpad: finds the `RowLayout` containing
`arrow_back`, lifts the title `StyledText`'s `text:` expression, deletes the block and
replaces the `signal goBack` line with `title:`. 32 lines out, 1 in, per page. The three
`Item`-rooted pages (`FingerprintConfig`, `ThemedIconsConfig`, `CustomCursorConfig`) are
**not** candidates: their header sits inside a nested `ContentPage` while `goBack` and
`showBackButton` stay on the `Item` root that `ConfigSubPageHost` binds to. Their own rows
handle them by hand.

## Design, this family's six

- `DesktopClockWidgetConfig` (cookie clock) had **no widget-off edge state at all** — every
  block was gated on `Config.isWidgetActive("clock_cookie")`, so switching the widget off
  left an empty card, not a placeholder. It now carries the family's placeholder.
- `DesktopDialClockConfig`'s placeholder was the odd one out twice: `alarm_off` where the
  other five use `watch`, and "Clock widget disabled" where the others name the widget.
- Section order was already geometry → colour → visual options; `DesktopWidgetVisualOptions`
  is only in the cookie clock page and is already last, which is where the brief wants it.

## Gates

`check-design.py --diff` 0 · `check-scaffold-containers.py` (new section 6, negative-tested
by breaking the `visible:` guard) · `check-button-states.py` · `probe-settings-pages.sh` 61
pages clean · `smoke-settings.sh` clean.

qmllint reports `Member "colSecondaryContainer" not found on type "QObject"` for every
`Appearance.colors.*` read. That is its standing blind spot on a singleton's `QtObject`
sub-objects, not a finding — the whole shell reads colours that way.

## Motion, for the cohesion pass

The header now enters as part of the page `ConfigSubPageHost` slides in, rather than as its
own element. Watch that it does not animate separately from the page carrying it.
