# ii-fastPair — notes

Ran lane 1, not 2. One 307-line file; dispatching a brief this small costs more than
building it.

## What the diff will not show

**The exit did not exist as a separate thing.** Both directions of the slide ran on
`elementMoveEnter` (500ms, default spatial). The exit is now `elementMoveExit` (130ms,
fast effects), picked inside the `x` binding the way `BarComponent` does it, because a
spec read from a binding of its own is a frame late. Measured with `ipc call fastPair
toggle` and a `hyprctl layers` poll: the layer unmaps between 167 and 235ms after the
close. One poll of that loop came back "still mapped at 2s" and a second run did not
reproduce it; the loop was started with `sleep 1.2` after the open, so the likely cause
is the IPC open racing the previous toggle rather than the exit hanging.

**`ydotool` needs half the screen coordinate here**, on a scale-1 1920x1080 monitor:
`mousemove --absolute -x 1607` lands the cursor at x 1918 (clamped); `-x 803` lands it
at 1607. Same 2x correction `ii-dropover` recorded. A held press (`click 0x40`, sleep,
`click 0x80`) opened the options and closed the card first time each.

**`icon` is a final property on `QQuickAbstractButton`.** An alias called `icon` on
anything rooted in `RippleButton` is a qmllint `property-override`; the in-file
`IconButton` uses `symbol`. qmllint also reports every `Appearance.sizes.*` and
`Appearance.animation.*` member as "not found on type QObject" — that is the shadow
tree's view of a `QtObject` and is noise, not a finding.

**agy vision ran on `gemini-3.1-pro-high` in `--mode plan`.** `--dangerously-skip-
permissions` is refused by this account's auto-mode classifier; plan mode reads files
fine and is all the step needs. It writes its answer to
`~/.gemini/antigravity-cli/brain/<id>/design_review.md`, not stdout. Four findings: one
was the hover state on the chip under the cursor, one misread "behind the chevron" as
"in a menu", one was a real gap in the brief (the "never show" chip was not named) and
is fixed in the brief, and one said the reserved 4px progress strip is invisible, which
it is meant to be.

**Swipe to dismiss, added on request after the first commit.** The clipboard toast had
the AOSP `SwipeHelper` transcription inline (offset through a `Translate`, 0.6 width or
500dp/s, escape at the thrown speed) with a comment explaining why `SwipeDismissible`
did not fit. It is `modules/common/widgets/SwipeToDismiss.qml` now, and the toast is
its first caller, 103 lines shorter. Here it sits on a `body` Item *inside* the masked
`card`, because the mask bakes a transform on the item it follows — the widget's
doc comment says so, so the third caller does not rediscover `ii-dropover`'s bug.
Measured with a real `ydotool` drag: the Fast Pair card unmapped 164ms after release,
the toast 46ms after a faster fling. Both re-open clean.

**The chevron sat low in its hover circle.** `anchors.centerIn` on a `MaterialSymbol`
centres a `Text` box that is a line height tall, so the glyph rides below centre.
`IconToolbarButton` already had the answer: fill the button and set both alignments.

## For the cohesion pass

- **The slide-out**, new: `elementMoveExit` where the enter is `elementMoveEnter`. The
  only edge-anchored surface with that exact pairing; the sidebars are the comparison.
- **Chevron rotation** `elementMoveFast` → `elementMoveSmall`.
- **The swipe**, now shared: the toast and this card should feel identical thrown.
- **The busy state** is unmeasured — no pairable device was in range this session, so
  the progress strip fading in and Connect dropping to 0.4 were verified by reading,
  not by pairing.

## Rejected

- **`IconToolbarButton`** for the two icon buttons. It is a `ToolbarButton` with the
  toolbar's toggled tints; the card needs a plain icon button on `colLayer0`, so a
  six-line in-file component on `DialogButton` was smaller than adapting it.
- **Escape to close.** The popup is on the `Overlay` layer without keyboard focus on
  purpose: it appears over whatever the user is doing and must not take the keyboard.
  Written into the brief as a departure from DESIGN 9.
- **A brief-level redesign of the options** into a menu. The `Revealer` is reuse and
  the card growing downward from a fixed top edge is the right direction for a
  top-corner popup.
