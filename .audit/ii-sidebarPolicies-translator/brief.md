# ii-sidebarPolicies-translator — brief

**Purpose.** Type or paste text in one language and read it in another, without leaving the
sidebar.

**Primary action.** Typing into the input card. The translation follows on its own; every
other control is secondary and must look it.

**Hierarchy.** Top to bottom, the order a translation is read in: the language bar (from,
swap, to), the input card, the output card. The two cards split the rest of the page
equally and each scrolls its own text, so the page is full at any content length, as
Hermes is (revised after the first build, which stacked two short cards over a void). The output card's text is what the eye settles
on once there is any. The card actions (paste, clear, copy, search) and the character count
last. The page used to read backwards — result at the top, the text it came from pinned at
the bottom, and the two language choices at opposite ends of the panel with a void between.

**Reference.** Google Translate on Android 16, as it lays out a tall screen: one language bar
with a swap between the two pills, then the source field and the result card sharing the
height. It is the translator every Android user
already knows, and its swap is the control this page never had.

**Interaction.**
- *Language bar.* Two `rounding.full` pills on layer 2 (the page is layer 1), filling the row
  either side of a swap icon button. The source pill keeps its detected-language hint and its
  `Revealer`. Both open the language dialog.
- *Swap.* Exchanges the two languages; with the source on auto it uses the detected language,
  and it is disabled until there is one. A translation that is showing moves into the input,
  as Google's does. The icon turns half a turn per swap on `elementMove` — a rotation is
  spatial.
- *Cards.* Layer 2, text in `colOnLayer2`. The output is a read-only text area, so part of a
  translation can be selected; it was a `Text`. Card buttons are one in-file `GroupButton`
  component on layer-2 films, `rounding.full` at rest and the group's pressed shape; disabled
  is the button's own 0.4, not a second dimming of the icon colour.
- *Copy.* The icon turns to a check for a moment after a copy (`ToolActivityRow`'s pattern),
  since nothing else said the clipboard changed.
- *Language dialog.* `SelectionDialog` is rebuilt on `WindowDialog`, so it gets the scrim
  fade, the enter on `emphasizedDecel` and the exit at half the duration on
  `emphasizedAccel`. It had neither: the `Loader` was bound to the open flag. The host
  latches the `Loader` and releases it once the dialog is no longer visible, and a reopen
  mid-exit reverses on the same dialog. Translator is its only caller (rule 9 checked).

**Edge states.**
- *Empty:* the input shows its placeholder line; the output card holds a `PagePlaceholder`
  (translate icon on a cookie shape, the Hermes empty state's sibling) that also says the
  same language on both sides fixes spelling and grammar, which nothing else revealed. It
  fades out on the first result. Copy and search are disabled.
- *Loading:* `StyledIndeterminateProgressBar` over the top edge of the output card, fading on
  the effects spec, while `trans` or LanguageTool is running. The last result stays under it.
- *Error:* the output card says what failed in `colError` — `trans` missing (exit 127), any
  other failed run, or LanguageTool's own message. A failed run used to leave the
  placeholder, and LanguageTool's error was printed as if it were the corrected text.
- *One language:* same language on both sides still refines, with the fix selector in the
  output card's action row.

**Cost.** No layers or shaders. The output placeholder's cookie is one `ShapeCanvas`, as the
Hermes empty state has, and not in anything that repeats. The progress bar loads only while
busy.

**Delete.** The page-wide scroll, the two language buttons inside the cards, `TextCanvas`'s output `Loader` and
raw `Text`, its `languageClicked` / `language` / `languageHint` / `inputTextArea` API, the
per-button enabled-colour branches, and the off-grid 15 / 10 / 5 paddings.

**Out of scope.** The `trans` and LanguageTool plumbing beyond reporting its failures; the
policies page chrome and tab row (`ii-sidebarPolicies-root`).
