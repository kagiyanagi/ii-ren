# ii-sidebarPolicies-hermes-composer — notes

Split 2/3 of `ii-sidebarPolicies-hermes`. Ran alone rather than dispatched, so this
session ran the shell and took the shots itself.

## What landed

- **`HermesPopover.qml`** (new, the one file the brief allowed). ArrowPopupMotion on a
  zero-size pivot at the opener's top or bottom centre, and a `m3surfaceContainerHigh`
  card at full alpha, `rounding.verylarge`, with one `StyledRectangularShadow`. The card
  is centred on the opener, then clamped. It is reparented to the window's content item
  from `open()`, never from a binding. Dismissal is an outside press (consumed), a wheel
  (dismisses and still scrolls), Escape, or the sidebar closing. The approval-mode menu
  (downward, under the status pill) and the context breakdown (upward, out of the
  composer) are both this now. The QQC2 `Popup`, the context meter's
  `createObject`/`popoverItem` lifecycle and both hand-assembled animations are gone.
- **Clamped to the panel, not the window.** The sidebar `PanelWindow` is
  `sidebarWidthExtended` wide and masks input to `sidebarLeftBackground`. `open()` walks
  from the opener up to the host's direct child (the panel, in both docked and detached
  modes) and clamps inside that.
- **Selection toolbar.** It has its own pivot at the selection's top centre, or its
  bottom centre when flipped under, and it is a `rounding.full` pill. It opens and
  closes on `ArrowPopupMotion`, and `visible: shown` is gone. The rect is latched while
  shown, because otherwise the exit dragged the pivot to (0,0). It hides while the
  selection is scrolled out of the transcript.
- **Approval card.** Full-width 40px pills stacked in the gateway's order. "Allow once" is
  filled primary, the rest are `colLayer3` tonal, Deny included. The command is a read-only
  `StyledTextArea`, so it can be selected.
- **Clarify card.** Full-width `colLayer3` rows (`rounding.small`, wrapping). A
  multi-select row carries a `check_box` glyph and takes `colSecondaryContainer` when
  picked. `questionIndex` resets on a new request. A question with no choices focuses
  the typed field, through `onCurrentChanged`/`onVisibleChanged`, because focus cannot
  land before the card has started to open.
- **Console.** The inert `transformOrigin` is gone, and the scroll bar is `StyledScrollBar`.
- **Pills.** Both tooltips hide while their own card is open. The mode chevron flips on
  `elementMove`. The yolo `StyledSwitch` is `checkable: false`, so a refused change
  cannot leave it looking applied.
- **Model picker.** Untouched, as briefed.

## Runtime findings

1. **Escape closed the sidebar instead of the menu.** `open()` focuses the card, but the
   pivot is at opacity 0 on that frame, and `visible: opacity > 0` made the card
   unfocusable. The root's `visible` now reads `shown || pivot.opacity > 0`.
   `anime/BooruResponse.qml` has the same shape (`card.forceActiveFocus()` before
   `motion.open()`, with `visible: shown || pivot.visible`, so its card's own item is
   invisible). See *Found outside the fence*.
2. **One shell crash** after a live reload, when the sidebar was then opened:
   SIGSEGV in `QQmlConnections::connectSignalsToMethods` under incubation
   (`~/.cache/quickshell/crashes/txa62njpylt`). This is the signature the thread row
   recorded for `InlineCode`. The only new `Connections` in this change was
   HermesPopover's → `GlobalStates`, built twice as the page incubates. It is now a
   property-change handler (`panelOpen`). Three more reload-while-closed → open cycles
   after that did not crash. The crash is not proven to be this change's, but this row
   no longer adds a `Connections`.
3. The Hermes session was left in **Manual** approval mode after testing (it was Smart).
   Put it back from the pill.

## How it was seen

- Live: the console (`!` command, stdin prompt answered, exit 0), the mode menu open,
  a hover film on a row, a mode change, outside-press dismissal, and Escape (after the fix).
- Probe (`qs -p` throwaway file, since removed): an approval card with four choices and
  one with a lone `deny`, clarify single-choice, a multi-select batch at 2 of 2, typed-only,
  and the context breakdown opened upward from its pill in the loading state. HermesService's
  gateway is lazy (`ensureStarted`), so building the cards starts nothing.
  The probe window sat 40px lower than its margin because of the bar's exclusive zone.
  That looked like a clamp bug until the numbers were printed.
- Not seen: the selection toolbar live (it needs a real selection in a reply), and
  motion at 60fps. For the cohesion pass: all three popovers now share ArrowPopup's
  numbers, so watch that the mode menu, the context card and the selection pill each
  grow out of their opener.

## Design-check (0 error, 1 warn, 3 note)

- WARN: ModeRow's hover film is `transparentize(colOnSurface, 0.92)`, because no token is
  solved for the opaque popover card. The proper fix is shared: a `hover:` binding on
  RippleButton's own `StateOverlay`, or a film token in `Appearance`.
- NOTE: `ArrowPopupMotion.open()` runs `from:` rest values, so a reopen mid-close snaps.
  This affects every caller, and the selection toolbar most.
- NOTE: after a popover closes, keyboard focus stays on the hidden card until a click.
  The fix is to keep the opener and give it focus back in `close()`.
- NOTE: each choice is a RippleButton (one `OpacityMask`) in a Repeater, the same count as
  the old FlowButtonGroup.

## Check

`tools/check-hermes-composer.py`. Mutation-tested against a temp copy of `hermes/` (the
live shell stays untouched): removing the clarify reset, un-centring the clamp, dropping
`shown` from the popover's `visible`, dropping the panel walk, removing the in-view guard,
un-latching the rect, a red Deny, `colLayer2Hover` on a row, a raw `ScrollBar`, and
`opensUp` on the meter. All ten fail.

## Found outside the fence

- `HermesHistoryPanel.qml:132` logs a binding loop on `implicitHeight` (`-panels` row).
- `anime/BooruResponse.qml` focuses its menu card while the card is invisible (see
  finding 1), so Escape there reaches whatever holds focus rather than the menu.
