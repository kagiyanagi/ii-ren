# ii-sidebarDashboard-notifications — notes

**Opening it.** `qs -c ii ipc call sidebarRight open`. It's the centre card, between the quick
panel and the Calendar/To Do/Timer group. About `1470,410` to `1920,660` on this 1920x1080
screen. `notify-send` is broken on this machine (a libnotify symbol lookup error), so the
shot uses whatever is already in `~/.cache/quickshell/notifications/notifications.json`.

**The list is the user's real notifications.** Nothing here pressed Clear all or swiped a
card. Two things are therefore **unverified live**: the empty state, where the count fades
and Clear all dims to 0.4, and the drag rounding a card's joins to `small`. Both are one
binding. If you need to see them, copy `notifications.json` aside first, and restore it before
restarting the shell (the service loads it on start).

**The "ki…" bug was a rounding error, not the layout.** Measured under
`/usr/lib/qt6/bin/qml` with the shell's font (Space Grotesk 12px, wght 450). Output is only
visible with `QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORMTHEME=`, because the KDE platform
theme swallows `console.*`. Results: "kitty" implicit 26.11 vs `TextMetrics.width` 26, and
"Beeper" 41.44 vs 42. `width` rounds, so a name is cut exactly when its width rounds down.
`advanceWidth` equals the Text's own `implicitWidth`. Two other files use a TextMetrics
`.width` as a size, `waffle/looks/WTextWithFixedWidth.qml` and `ii/bar/Resource.qml`. They're
out of this row, and neither has been seen eliding.

**Why the stack lives in the shared card.** `NotificationGroup` only knows whether it's a
popup. The list passes `stackTop`/`stackBottom` from `index` and `count`. Both default to
true, so any other caller still gets a standalone card. The popup is always standalone,
because `standalone` includes `popup`. `check-notification-stack.py` holds that rule and the
`ceil(advanceWidth)` cap. Both were mutation-tested.

**Rejected.** Hiding Clear all when the list is empty, as the Android shade does. `visible`
snaps, and fading `opacity` would fight RippleButton's own disabled fade. Disabled at 0.4 is
the shell's convention and animates by itself. Choosing the count label's fade spec from
`root.count` was also dropped: that binding and the Behavior hang off the same change, in an
undefined order (2.9). It fades on `elementMoveFast` both ways, matching the button.

**Vision pass (agy, gemini-3.1-pro-high).** It claimed that the outer corners stayed large,
that the joins were square, and that the footer order was reversed. The first two are wrong
when you zoom in: about 12px at the ends and about 6px at the joins. The tonal step from
`colLayer2` to `colLayer1` is small enough that it misread them. The third mistook the brief's
order of visual weight for a left-to-right order.

**For the cohesion pass (motion).** New: a sidebar card's join corners round to `small` on
`elementMoveSmall` when a swipe starts, and back when it ends. The count label fades on
`elementMoveFast`, and the silent icon's colour now follows its background on
`elementMoveFast`.
