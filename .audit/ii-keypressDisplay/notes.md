# ii-keypressDisplay — notes

**How to drive it.** No keybind. `qs -c ii ipc call keypress enable`, then
`qs -c ii ipc call keypress test "Ctrl+Shift+P"` pushes a chip without touching a
keyboard. `disable` when done, or the evdev reader keeps running.

**`test` only ever pushes a *shortcut* chip** (`pushChip(..., "shortcut")`), and a
shortcut chip is `colPrimaryContainer`, which is the one fill on this surface that is
opaque. So the IPC that exists to make this surface testable is exactly the one that
hides its worst bug. To see a typed-text chip without typing, patch `test` to pass
`"text"` for one run — the shell hot-reloads — or type with the reader running.

## What was wrong

1. **The newest chip was the one the screen cut off.** The row is a horizontal ListView
   and a ListView shows its head; the newest key is appended at the tail. Once the row
   is wider than the screen — twelve keys, or scale 2.0, or merged words on a 1366 —
   the overlay kept four stale keys perfectly legible and clipped the one you pressed.
   Fixed with `contentX: Math.max(0, contentWidth - width)` and a `Behavior` on it.
   `shot-overflow-before.png` / `-after.png` are the same five chips either side of it.
2. **Typed-text chips were painted at 10% opacity.** `colSurfaceContainerHigh` is
   `solveOverlayColor(...)`, whose return alpha is `1 - contentTransparency`, and
   `contentTransparency` falls through to `autoContentTransparency` = 0.9 regardless of
   `transparency.enable`. That is right for a panel drawn over its own layer; this
   window is `color: "transparent"` with the recording underneath. Measured with a
   throwaway `qs -p` probe: `colSurfaceContainerHigh.a = 0.100`,
   `colPrimaryContainer.a = 1.000`. The neutral fill is `m3colors` now, as the
   background widgets do over a wallpaper.

Both are in `tools/check-keypress-display.py`, and both asserts were mutation-tested
(revert the fix, the assert fires with the right message).

## What was wrong with the first pass at this row

The first commit deleted the per-chip `StyledRectangularShadow`, citing design law 8.
That was wrong and is reverted. `pack.py`'s effect census lists *every* effect, cheap
ones included, so a human can look; it is not a verdict. The verdict is DESIGN.md 8,
which names a cached `RectangularShadow` as cheap and sets the delegate limit at ~20
repeats, and `check-effect-budget.py`, which excludes `RectangularShadow` by name with
a comment saying so. `maxKeys` caps at 12. The shadow stays, with a comment on it so
the next reader does not re-delete it, and the check now fails if that slider is ever
raised past 20.

Reading the census as a finding also burned the session's attention on the one thing
that was fine, which is how both real defects survived a full pass of the gates.

**Motion to verify in the cohesion pass.** The row's scroll pin, `Behavior on contentX`
on `elementMoveSmall`: with `maxKeys` at 12 and scale ~1.5, hold a key and watch the row
slide rather than teleport as each chip lands. Nothing else was retimed.
