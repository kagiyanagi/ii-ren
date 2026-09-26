# ii-sidebarPolicies-hermes-thread — brief

Split 1/3 of `ii-sidebarPolicies-hermes`. Read `.audit/ii-sidebarPolicies-hermes/brief.md`
first: this row inherits its contracts 1, 4 and the fences.

**Files (yours).** `hermes/HermesMessage.qml`, `hermes/ToolActivityRow.qml`,
`hermes/HermesToolSummary.qml`, and all five of `aiChat/`: `MessageTextBlock`,
`MessageCodeBlock`, `MessageThinkBlock`, `SpeechHighlight`, `AiMessageControlButton`. The
packs are `pack.md` (hermes files) and `pack-aichat.md`. No `Hermes.qml` edits.
`HermesMessage` has a second caller, `modules/ii/overlay/assist/AssistContent.qml:75`, which
sets `width` and `messageData`. It must keep working unchanged.

**Purpose.** Read one turn: what was asked, what came back, and what the agent did in
between.

**Primary action.** Reading the reply text. The turn chrome (header, buttons, run time) and
the tool one-liners are quiet by construction.

**Hierarchy.**
1. The reply's prose and code.
2. Tool activity, as one-line rows between paragraphs, where they happened. This stays as
   it is.
3. The turn header: the model name and the per-turn buttons.
4. The run time.

**Your turns are a bubble.** Every turn is currently the same full-width `colLayer2` card,
and your own is told apart only by a `person` icon, your username and a mirrored header.
That is the one thing a chat has to make obvious at a glance, and here you have to read it.
Your turns become a card that hugs its text: right-aligned, at most ~85% of the transcript
width, and the same `colLayer2`. It keeps the layer chain exact for anything pasted into it,
so no second text colour needs to be plumbed through the blocks. It sits under a
right-aligned control row that holds the time and the Copy / Edit / Markdown-source
buttons, drawn outside the bubble so a two-word prompt is not wider than its buttons. The
`person` icon and the username go. Agent and interface turns keep the full-width card and
their header exactly as they are. `TextEdit`'s `implicitWidth` is the unwrapped width, so
the bubble's width is `min(max, content implicitWidth + padding)`. Measure it on a
one-word prompt, a long one and one containing a code fence.

**Interaction.**
- *Tool row* (`ToolActivityRow`). The header is the `RippleButton` it already is, and the
  details move into a `Revealer` (contract 1). Delete the root's own `Behavior on
  implicitHeight`: with the Revealer that would be two motions for one press. The chevron
  goes to `elementMove`.
- *Tool group* (`HermesToolSummary`). Built lazily and kept (contract 1), and the chevron
  goes to `elementMove`.
- *Think block*. Its header becomes one `RippleButton`, or carries a `StateOverlay`, over
  its whole width. Its body is a `Revealer`. The 22px expand button inside the header goes,
  since the whole header is the button. The "Thinking" label drops `".".repeat(Math.random()
  * 4)`, which is evaluated once and so prints a random number of dots that never move. A
  `MaterialLoadingIndicator` at the inline size (20, as `Hermes.qml`'s activity line) sits
  in front of the label while it is not `completed`.
- *Code block*. It is one `colLayer3` card: header row, line numbers and code inside it,
  on whitespace. The 2px seams between three separately-rounded rectangles show the
  `colLayer2` card through, and act as divider lines (law 11). The header's
  `colSurfaceContainerHighest` is on the wrong base (contract 4). Line numbers become **one**
  `StyledText` holding the joined numbers, not a `Repeater` of bare `Text` per line: a
  1,600-line block laid out 1,600 items. Paddings go onto the 4dp grid.
- *Entrance*. Tool rows keep fading in once per `toolId`, on the effects spec, as today.

**Edge states.**
- *Streaming, nothing yet.* The page's activity line covers it, and the in-turn loading
  indicator only shows when that line is off, as now.
- *Error.* The `m3errorContainer` strip stays.
- *A one-word prompt.* The bubble hugs it and the control row stands beside it, not over it.
- *A turn that is all tools.* A group of nine reads as one line ("Explored 9 files, ran 2
  commands") until it is opened.
- *Search hit in a folded tool.* It opens itself, as now. Opening now goes through the
  Revealer.

**Cost.** No layers. The 60ms `resplitThrottle` runs only while a reply streams and stays.
A 1,600-line code block drops from ~1,600 `Text` items to one.

**Delete.** The user header's `person` icon and username. The think header's raw
`MouseArea` and its expand `RippleButton`. `thinkBlockHeaderPaddingVertical: 3`, the
`topMargin: 7` / `leftMargin: 3` literals, and the code block's 5/7 paddings. The line-number
`Repeater`. The 2px component spacings that draw seams. `ToolActivityRow`'s root height
`Behavior`. `HermesToolSummary`'s `open ? calls : []` model.

**Out of scope.** `Hermes.qml` (the list, search, composer and status pill) belongs to root.
`SpeechHighlight`'s marking logic and `MessageTextBlock`'s LaTeX and chunk-fade pipeline
stay as they are; touch them only as the bubble needs. `HermesService`.
