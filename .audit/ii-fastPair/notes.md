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

## The snooze and the mute (follow-up pass)

The user reported both "hide this device for a while" and "hide all of it for a while"
as working sometimes and not others. Four causes, all in `services/FastPair.qml`.

**One address is not one device.** Suppression and `ignoredDevices` were keyed by
`device.address` alone. During discovery BlueZ hands back a separate `Device1` for the
classic inquiry hit and the LE scan hit - different addresses, same name - and an
unbonded LE address is rotated by the peripheral every few minutes. Snoozing the
address the card happened to be showing left the sibling offerable on the next dump,
two seconds later. The live config is the evidence: nine entries in `ignoredDevices`,
several of them random addresses (`41:42:FF:…`, `5C:16:48:…`), and the card was still
coming back. Keys are now the address *and* the name, via `identityKeys`/`suppressed`/
`ignored`; `ignoreCandidate` stores the name, and address entries written by earlier
versions still match.

**A dump landing mid-attempt.** `pickCandidate` refused while `popupShown` but not while
`busy`. Discovery is shared - Quickshell has one D-Bus connection for the whole shell -
so the Bluetooth dialog or blueman can hold the adapter discovering while our attempt
runs. Dismiss the card mid-connect and the next dump overwrote `candidate` and cleared
`busy`, orphaning the pairing and leaking the `bluetoothctl` agent. One guard.

**A mute that died with the process.** `mutedUntil` was a plain property, so a QML
reload or `iiren run` voided it - and this shell reloads on every file save. It is
`Config.options.bluetooth.fastPair.mutedUntil` now, which also means it has to expire on
its own (a 30s poll, because a Qt interval is not the wall clock across a suspend) and
has to be escapable: settings grew an "Unmute pairing popups (muted until HH:MM)" row
next to the "clear ignored devices" one. A mute also drops out of `shouldScan` now, so
six muted hours no longer cost six hours of radio.

**The timeout ran through the options menu.** Opening the chevron to pick "1h" could get
the card snoozed for the default five minutes mid-reach. `autoDismiss` is declarative
now - `popupShown && !busy && !interacting && popupTimeout > 0` - and the card binds
`interacting` to its own hover plus `optionsOpen`. Four hand-written `restart()`/`stop()`
calls deleted.

Measured live: pointer parked on the card, still mapped at 30s against a 20s timeout;
moved away, gone between 15s and 20s; the dismissed device stayed away for the 40s
watched. `tools/check-fastpair.py` is new and covers all four.

**Left alone.** The per-device snooze map is still in memory, so a snooze does not
survive a restart - a map needs a schema in `Config` and the mute is the case the user
named. `ponytail:` comment on the property says so.
