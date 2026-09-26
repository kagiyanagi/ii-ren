# ii-sidebarPolicies-hermes-composer — brief

Split 2/3 of `ii-sidebarPolicies-hermes`. Read `.audit/ii-sidebarPolicies-hermes/brief.md`
first: this row inherits its contracts 2 and 4 and the fences.

**Files (yours).** `hermes/HermesApprovalCard.qml`, `HermesClarifyCard.qml`,
`HermesConsole.qml`, `HermesSelectionActions.qml`, `HermesApprovalModeMenu.qml`,
`HermesContextMeter.qml`, `HermesModelPicker.qml`. In `Hermes.qml`, only the lines that
instantiate these (the `HermesSelectionActions`, `HermesApprovalCard`, `HermesClarifyCard`,
`HermesConsole`, `HermesContextMeter` and `HermesApprovalModeMenu` blocks) and only if the
brief below needs a property changed there. You may add one file, `hermes/HermesPopover.qml`,
if contract 2 is cleaner as a shared piece than as three inline copies.

**Purpose.** Everything that sits on or around the composer: what the agent is blocked on,
what a `!` command is doing, and the three small popovers (approval mode, context, text
selection).

**Primary action.** When the agent is blocked, answering it. That is the only loud thing on
the page, and nothing else here may compete with it.

**Hierarchy.** Approval or clarify card, if present. Then the console, if a `!` command ran.
Then the composer (root's). The popovers are transient and rank nowhere.

**Reference.** The approval card is the Android 16 runtime-permission dialog: an icon, a
title that names the actor, the thing being asked for, then the choices **stacked
full-width**, the grant first. The clarify card is an M3 single- or multi-choice dialog,
laid inline. The popovers are Launcher3's `ArrowPopup` (DESIGN.md §9).

**Interaction.**
- *Approval card.* Choices become a vertical column of full-width 40px buttons, in the
  order the gateway sends them. "Allow once" is filled primary. The rest are tonal
  (`colLayer3` / hover / active). **Deny is not red**: it is the safe answer, and the error
  container on it today says the opposite. Danger belongs to the request, which is the
  `gpp_maybe` icon, the title and the verbatim command. The command box stays `colLayer3`,
  monospace, and can be selected (it is a `StyledText` today). Height and opacity enter and
  exit as they do now, which is already right.
- *Clarify card.* Choices become full-width list rows in a column. Single-choice rows answer
  on press. Multi-select rows carry a check glyph and toggle, and Send confirms. The typed
  answer field and Send stay under them. **`questionIndex` resets to 0 when a new request
  arrives.** Today it only resets after the last answer, so a replaced batch opens partway
  through. In a batch, the "(2 of 3)" moves into the title, as now.
- *Console.* Keep its structure. Its `transformOrigin: Item.Bottom` does nothing (nothing
  scales) and goes. The raw `ScrollBar` becomes `StyledScrollBar`.
- *Selection toolbar.* This is contract 2. The pivot is at the selection's top centre when
  the toolbar sits above it, and at its bottom centre when it flips below. It opens on
  `ArrowPopupMotion.open()` and closes on `.close()`, latched: the root's `visible` follows
  the motion, not `shown`. A `rounding.full` pill. The three buttons keep `focusPolicy:
  Qt.NoFocus`, which is what keeps the selection alive.
- *Approval-mode menu.* This is contract 2, with the pivot at the status pill's bottom
  centre, so it opens downward. The card is centred under the pill and then clamped, and the
  QQC2 `Popup` goes. The mode rows take films over the opaque card. The Yolo block stays an
  `colErrorContainer` card inside the menu: that one really is dangerous.
- *Context meter.* This is contract 2, with the pivot at the pill's top centre, so it opens
  upward. It keeps what it does (the breakdown, the loaded files, the focus field, "Fold
  conversation"). The pill's tooltip `extraVisibleCondition: true` goes.
- *Model picker.* It already reads right. Leave it unless contract 4 says otherwise.

**Edge states.**
- *Approval with one choice* (a Smart-DENY override can leave only `deny`). One full-width
  button, and the card still says what it wanted to run.
- *Clarify with no choices.* The typed field alone, focused.
- *Clarify batch, last question.* Answering it lets the card leave. The latched content
  stays on screen through the exit, as now.
- *Console, still running.* The stdin field is focused, and the password echo guard stays.
- *Context breakdown loading.* The loading row, as now.
- *Selection that scrolls out of view.* The toolbar follows `repositionTrigger`, as now, and
  must not stay drawn over the composer. Hide it while the rect is outside the transcript.

**Cost.** One `StyledRectangularShadow` per popover, only while it is shown. No new layers.

**Delete.** The hand-assembled ArrowPopup animations in `HermesApprovalModeMenu` and
`HermesContextMeter`. The QQC2 `Popup`. The `FlowButtonGroup`s in both cards. Deny's error
container. The console's inert `transformOrigin`. The context pill's always-true tooltip
condition. `HermesSelectionActions`' `visible: root.shown`.

**Out of scope.** The composer itself, the status pill it sits in, `StatusItem`,
`ApiInputBoxIndicator` and the suggestion strip (all root's). `HermesService`.
