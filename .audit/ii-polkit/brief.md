# ii-polkit — brief

**Purpose.** Something just asked for root (`pkexec`, a package manager, a
systemd unit). Type the password, or say no.

**Primary action.** Enter the password. OK and Enter do the same thing; Cancel,
Esc and a press on the scrim all mean no.

**Hierarchy.** Shield icon and "Authentication" first, then polkit's own
sentence saying what is being authorised, then the field. Under the field is
**one status line**, and it only exists when there is something to say. Cancel
and OK are text buttons on the right, as every `WindowDialog` has them.

**Reference.** Android 16's BiometricPrompt falling back to a device credential:
a centred M3 basic dialog with a hero icon over a scrim. It cancels when you tap
outside, and a wrong credential is said in error colour under the field rather
than by clearing it.

**Interaction.** Use `WindowDialog` the way its other callers do: it fills the
window and is the scrim itself. It also has the Esc handler, the outside-press
dismiss and both halves of the motion already: the card grows on
`elementMoveFast`/`emphasizedDecel` and collapses on half of that with
`emphasizedAccel`, and the body fades in on `elementMoveFast` and out on
`elementMoveExit`. The surface has to stay mapped until that exit ends. The
flow object is deleted on the frame it completes, and the `Loader` bound to it
unmapped the window on that same frame. So a success or a cancel never
animated. The dialog also shows what it last said while it leaves, because a
message bound to a deleted flow empties on the exit's first frame and moves the
field up a line.

**Edge states.**
- *Checking* (after submit, including PAM's ~2s failure delay): OK at 0.4 and
  the field disabled, because PAM is not asking for anything yet. The field greys
  in Qt Material's disabled colours rather than 0.4; that is `MaterialTextField`'s,
  owned by `cw-inputs`. Esc still cancels.
- *Wrong password*: "Incorrect password", in error colour, until the next
  attempt. The field is cleared and focused again.
- *PAM says something* (faillock lockout, fprintd's "place your finger"): PAM's
  text goes first, in error colour only when PAM flags it as an error. The lock
  screen uses the same order.
- *Caps Lock on*: the last thing the line says, as on the lock screen.
- *No response needed yet* (fprintd first in the stack): the field stays
  disabled until PAM asks for text. Before, it was enabled as soon as the request
  began, whether or not PAM wanted input.
- *Several requests queued*: the next one follows straight on. The dialog stays
  up and picks up the new message; it does not flash.

**Cost.** None added. `WindowDialog`'s one cached shadow is the only effect,
and the second scrim `Rectangle` goes.

**Delete.** The hand-drawn scrim, both Esc handlers, the 0×0 box the dialog was
centred in, and `PolkitService`'s hand-maintained `interactionAvailable`
writes. It becomes `flow.isResponseRequired`, which is what those writes were
trying to track.

**Out of scope.** `WindowDialog`'s own motion. `WPolkitContent`: waffle uses
the same window and service, but it opts out of the exit latch and is
otherwise unchanged. Choosing a different identity: polkit offers every wheel
member and preselects the first, and this machine has one.
