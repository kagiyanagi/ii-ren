# ii-sidebarPolicies-translator — notes

**Opening it.** `qs -c ii ipc call sidebarLeft open`, then the Translator tab (about `217,82`
on this 1920x1080 screen). The panel pins Hermes on open, and a live reload closes the
sidebar and drops what was typed. `ydotool type` drops non-ASCII (`ä`), which is the tool.

**Layout, revised once.** The first build stacked the language bar and two content-sized
cards in one page scroll: correct, but two short cards over half a page of nothing. The
user asked for the page to be used, as Hermes uses it. The cards now split the height
(`fillHeight` + equal `preferredHeight`) and each scrolls its own text through
`TextArea.flickable`, which also keeps the caret in view. The empty output card carries a
`PagePlaceholder`, which is where the refine mode is finally explained.

**Verified live.** Detection hint, swap (languages trade, the translation becomes the input,
config written), the dialog's exit and its release, a failed `trans` (a `~/.local/bin/trans`
shim that fails `-brief`, since removed) in `colError` with copy/search disabled, refine mode
with the fix selector, a click low in the empty input focusing it, and 900 characters
scrolling inside the input card. Config was restored to auto -> English.

**Not verified.** The copy check mark: Copy overwrites the clipboard (see the continuity
notes for restoring it). LanguageTool errors in `colError` (needs it unreachable). The
agy/Gemini vision pass.

**Left alone.** `refineProc` handles its reply in `onStreamFinished`, so a curl killed for a
newer keystroke may flash "LanguageTool is unreachable" until the next reply lands. Moving it
to `onExited` needs the collector's text to be final by then, which was not checked.

**For the cohesion pass (motion).**
- The swap icon turns half a turn per swap on `elementMove`.
- The loading bar fades in on `elementMoveFast` and out on `elementMoveExit`.
- The language dialog enters and exits on `WindowDialog`'s specs; it used to have none.
- The output placeholder fades and spins with `PagePlaceholder`, triggered on the panel
  opening like Hermes'.
