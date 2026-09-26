# ii-sidebarPolicies-hermes-thread — notes

Split 1/3 of `ii-sidebarPolicies-hermes`. Ran alone rather than dispatched, so this
session also ran the shell and took the shots itself.

## What landed

- **Your turns are a bubble.** `HermesMessage`'s root is an `Item` now, with its card as
  a background `Rectangle` placed by the turn's role: full width for agent and interface
  turns, and right-aligned at `min(85% of the transcript, content implicitWidth + padding)`
  for yours. The control row (buttons, then the time at the edge) sits above the bubble,
  outside it. The `person` icon and username are gone. `AssistContent.qml` sets only `width`
  and `messageData`, and both still work on an `Item`.
- Measured live on a one-word prompt ("hi", which hugs), a long one (which caps at 85% and
  wraps) and one containing a code fence (which caps too, because the code block now reports
  its code's implicit width, and the code then scrolls sideways inside it). All three are in
  `shot-after.png`. For a one-word prompt the control row is wider than the bubble. It sits
  above the bubble, never over it.
- **Tool row.** The details go into a `Revealer` around a `Loader` that is latched built on
  first open (`built`) and kept. The root's height `Behavior` is deleted. The chevron is on
  `elementMove`.
- **Tool group.** Its rows are latched built the same way (`values: root.built ? …`). The
  chevron is on `elementMove`.
- **Think block.** One `colLayer3` card. The whole header is a `RippleButton`, and the body
  is a `Revealer`. The 22px expand button, the raw `MouseArea`, the random dots and the
  `colSurfaceContainerHighest` header are gone. A `MaterialLoadingIndicator` (20) stands in
  for the icon while it is not `completed`. The header is `enabled: completed` but pinned at
  `opacity: 1`, because RippleButton's disabled 0.4 dimmed the one line saying it is still
  working (seen live, and fixed).
- **Code block.** One `colLayer3` card, with no seams. Line numbers are one `StyledText`
  holding the joined numbers, in the TextArea's own font, render type, hinting and top
  padding, so the lines stay level. Seen live on a 6-line block. Paddings: 4 for the card,
  8 before the language and the numbers. The scroll bar's `padding: 5` became 4.

## Removed at the user's request

- The per-turn "View Markdown source" button (`code` icon) and `HermesMessage.renderMarkdown`,
  which only that button ever changed. The brief listed it in your turns' control row. It is
  gone from every turn, and the blocks keep their own `renderMarkdown: true` default.

## Inline code, at the user's request

- Qt's rich text gives a span a background colour and nothing else: no padding, border
  or radius. So an inline `` `code` `` span is two parts:
  - `MessageTextBlock.styleCodeSpans` rewrites it to an HTML `<span>` in the mono face and
    primary colour, bracketed with U+2063. It puts `gap` px of letter-spacing on the span's
    last character and on the plain character before it, which is real room in the layout
    for the pill's padding. Markdown inside is backslash-escaped, then `& < >` become
    entities (the other order escapes the entities' `;`). The character before is only
    spaced when it is plain text, because a `*`, `)` or `]` there is closing markdown.
  - `InlineCode` (a `z: -1` child of each text view) reads the brackets, removes them from
    the document and draws a rounded, bordered `colLayer4Base` pill (in `colOutlineVariant`)
    behind each range, one per line a span wraps across.
- Checked through PySide6's `QTextDocument.setMarkdown`: with the brackets removed, the
  plain text matches the unstyled markdown for every case tried, so copy, selection,
  search marks and read-aloud positions are unchanged. Bold and links next to a span
  survive.
- Three runtime findings, each now pinned in the check:
  1. The removals' `textChanged` arrives *after* the re-entry guard is released, with the
     brackets gone. Taken as new text, it cleared every pill in the same millisecond it was
     made. Remembering the stripped text and ignoring that one change fixed it.
  2. As the TextArea's `background:`, `InlineCode` is built while the TextArea is, and its
     `Connections` to that half-built view **segfaulted the shell** during a reload
     (SIGSEGV in `QQmlConnections::connectSignalsToMethods` under incubation; coredump at
     13:04, and the shell restarted itself).
  3. `sed -i` on `InlineCode.qml` stopped live reload for that file (known gotcha). Until
     a manual restart, one test was run against stale code.
- Colours tried live: a fill alone (layer 3, then layer 4) was barely visible. The
  secondary-container tint read, but without a border it didn't look like a box. A
  `colOutline` border was too heavy. What stayed: a `colLayer4Base` fill with a
  `colOutlineVariant` border and `m3primary` text, the reference's look. Seen live on a
  reply, on a path wrapping across two lines, on keys in a list of five, and in your
  bubble. Known edge: after `**bold**` the gap before a pill is the plain space only.

## Long tool text and thoughts, at the user's request

- `ClampBox` (new, `modules/common/widgets/`) holds content at `maxHeight` under a fade,
  with Show more / Show less. It clamps by height, because the reported case was one
  JSON line wrapped forty rows deep. It only clamps when opening would show more than the
  button costs. It has no motion of its own: every caller sits in a Revealer, which
  animates the height change. Outside one, Show more snaps.
- Used for a tool call's arguments and its output (12 lines of the mono face each) and for
  the think block's body (12 lines of the reading face). The old line-sliced output
  preview and its "Show all N lines" button are gone. The 8,000-character cap on what is
  laid out stays, and Copy still takes the whole return.
- Arguments are laid out, not printed as JSON (`ToolActivityRow.layoutArgs`). The one
  argument that is the call itself (`content`, `code`, `command`, `new_string`, …) becomes
  the body. The rest are one-line `key value` rows. The service now passes `toolArgs` on
  both the live and the resumed call; `toolFullInput` stays for search and copy.
- `ToolCode` (new, `hermes/`) highlights with the same `SyntaxHighlighter` the code block
  uses. The language comes from the path (`definitionForFileName`), or from the tool
  (Bash for shell tools, Python for `execute_code`, Diff for a patch), or is JSON when the
  text looks like JSON. `read_file`'s `N|` gutter is stripped first, because it breaks
  line-start syntax. `_resultText` returns a `{content}` result's content rather than
  the JSON around it. It is a read-only `TextEdit`, so tool text is selectable now and
  reaches the selection toolbar.
- Seen live on a mock `write_file` of a 130-line C file: path row, C highlighting, clamp,
  fade, Show more and Show less, and highlighted JSON output. A 30-line thought clamps
  the same way.

## Two bugs reported against this row, fixed in it

- **Code cut off mid-block.** `MessageCodeBlock`'s `onTextChanged` wrote `segmentContent =
  text` with no guard. That replaced `HermesMessage`'s `segmentContent: modelData.content`
  binding on the first chunk, so a fence that opened while the reply streamed froze there,
  and the prose after it carried on. It predates this row. Reproduced live with a mock that
  streams `#include <std` and then the rest (exactly the user's screenshot), and the fix
  (`if (!root.editing) return`, as `MessageTextBlock` has) was confirmed the same way. It
  was intermittent because a block created after its fence closed never saw a partial chunk.
- **Pasting an image did nothing but say "No image found in clipboard".** The composer
  checks cliphist's cached newest entry, then asked the gateway's `clipboard.paste`, which
  reads only the live selection. Both environments and the gateway's own save were verified
  working while the selection held an image, so the failing case is a selection that has
  gone (the copying app closed) under an image cliphist still has. The cached list also
  goes stale on an image copied after an image, because it refreshes on a text change.
  `scripts/hermes/clipboard-image.sh` now reads it at paste time: live image first, text
  handed back as a text paste, cliphist only for an empty selection. The result goes
  through `attachImage()`, the same path a file drop takes. `clipboard.paste` has no caller
  left. Verified live: Ctrl+V staged the image and the gateway accepted `image.attach`.
  The check is `tools/check-hermes-paste.py`.

## For the cohesion pass (motion; a still proves none of it)

- Tool row, tool group and think chevrons: `elementMoveFast` → `elementMove`.
- The think fold: `elementMoveEnter` both ways → Revealer (open `elementMove`, close
  `elementMoveExit`).
- The tool row's details: a bare `visible` swap under a root height Behavior → Revealer.
- **Nested Revealers.** Opening a tool row *inside* an open group changes the group's
  Revealer's `childrenRect` every frame, and its `Behavior` restarts toward each new target,
  so the group trails the row by up to one `elementMove`. The row's details are clipped at
  the bottom until the group catches up. The brief asks for exactly this nesting (contract
  1). Seen settling correctly after 1s. Watch it at 60fps. If it reads as lag, the fix
  belongs in `Revealer`: animate only on a `reveal` edge, not on a content-size change. That
  widget has many callers (DESIGN.md 9), so it is not this row's to change.

## Found outside the fence

- `HermesHistoryPanel.qml:132` logs `Binding loop detected for property "implicitHeight"`
  on every open. That is the panels row's file.
- **`scripts/hermes/desktop.py` `do_click` lands at twice the coordinates.** On this
  machine `ydotool mousemove --absolute -x X -y Y` puts the cursor at `(2X, 2Y)`: measured
  228,360 → 457,721, and 114,180 → 229,361, at monitor scale 1. `do_click` passes the OCR
  coordinates straight through, so an agent's click on a named button would land at double
  its position. That is the Hermes desktop row's file, and it wants a fix plus a line in
  `check-hermes-desktop.py`.

## How the shots were taken

The transcript was seeded through a throwaway `mock()` `IpcHandler` function in
`HermesService.qml`, reverted before commit. Clicks went through ydotool at *half*
coordinates (see above), and each one came after a screenshot confirming the Hermes tab
was showing. A reload resets the sidebar to its last tab, and two early clicks landed on
Continuity and on the window behind. Neither changed anything.

## Check

`tools/check-hermes-thread.py`. Mutation-tested: nine single-line breaks (the bubble cap,
the bubble's right alignment, its padding, the tool row's lazy latch, the group's model,
the group chevron's spec, the random dots, the code card's base colour, and the
line-number arithmetic). Each one fails the check.

```
- `python3 tools/check-hermes-thread.py` — one Hermes turn: your own turns are a bubble,
  and every fold goes through `Revealer`. The tool row showed its details with
  `visible: open` and no clip under a height Behavior, so it painted over the next
  paragraph on open and vanished on the first frame of a close. A tool group's rows were
  bound to `open` and destroyed as the fold began closing, and the think block closed on
  its enter spec. None of that shows in a still frame. It pins every fold to `Revealer`,
  latched built and kept, with each chevron on `elementMove`. It holds the code block to
  one `colLayer3` card whose line numbers are one text rather than a `Repeater` (a
  1,600-line block laid out 1,600 items), and runs that text and the bubble's width under
  node: capped at 85%, hugging its text below that, flush right, while the agent's card
  spans the transcript
```
