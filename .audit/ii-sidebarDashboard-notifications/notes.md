# ii-sidebarDashboard-notifications — notes

**Opening it.** `qs -c ii ipc call sidebarRight open`. It's the centre card, between the quick
panel and the Calendar/To Do/Timer group. About `1470,410` to `1920,660` on this 1920x1080
screen. `notify-send` is broken on this machine (a libnotify symbol lookup error), so the
shot uses whatever is already in `~/.cache/quickshell/notifications/notifications.json`.

**The list is the user's real notifications.** Nothing here pressed Clear all or swiped a
card, so the empty state is **unverified live**: the count fading out and Clear all dimming
to 0.4, one binding each. To see it, copy `notifications.json` aside first, and restore it
before restarting the shell (the service loads it on start).

**The "ki…" bug was a rounding error, not the layout.** Measured under
`/usr/lib/qt6/bin/qml` with the shell's font (Space Grotesk 12px, wght 450). Output is only
visible with `QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORMTHEME=`, because the KDE platform
theme swallows `console.*`. Results: "kitty" implicit 26.11 vs `TextMetrics.width` 26, and
"Beeper" 41.44 vs 42. `width` rounds, so a name is cut exactly when its width rounds down.
`advanceWidth` equals the Text's own `implicitWidth`. Two other files use a TextMetrics
`.width` as a size, `waffle/looks/WTextWithFixedWidth.qml` and `ii/bar/Resource.qml`. They're
out of this row, and neither has been seen eliding.

**Reverted on review: the Android-shade stack.** The first commit joined the sidebar's
groups into one stack: `rounding.small` at the ends, `unsharpenmore` at the joins, 4 apart,
and all `small` while swiped. The owner prefers the original separate `rounding.large`
cards 8 apart, so those radii, the gap, the `normal` clip and the 5 insets are back as they
were. The 5s are off the 4dp grid, and check-design warns on them. That is deliberate: do
not "fix" them back to 4 in a later row, and do not propose the stack again.
`check-notification-app-name.py` covers only the name cap now.

**Rejected.** Hiding Clear all when the list is empty, as the Android shade does. `visible`
snaps, and fading `opacity` would fight RippleButton's own disabled fade. Disabled at 0.4 is
the shell's convention and animates by itself. Choosing the count label's fade spec from
`root.count` was also dropped: that binding and the Behavior hang off the same change, in an
undefined order (2.9). It fades on `elementMoveFast` both ways, matching the button.

**Vision pass (agy, gemini-3.1-pro-high).** Run on the stack version. It misread the joins
as square (they were about 6px), because the tonal step from `colLayer2` to `colLayer1` is
small. It also mistook the brief's order of visual weight for a left-to-right order. It has
not been rerun on the reverted cards.

**For the cohesion pass (motion).** The count label fades on
`elementMoveFast`, and the silent icon's colour now follows its background on
`elementMoveFast`.
