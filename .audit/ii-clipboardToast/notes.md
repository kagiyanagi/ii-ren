# ii-clipboardToast — notes

## How to open it

`wl-copy "some text"`. There is no IpcHandler. Three things make it awkward to
drive from a script, all of them cost a session if rediscovered:

- **Cliphist is polled, not pushed.** `Cliphist.delayedUpdateTimer` means the
  card appears ~1s after `wl-copy` returns, not immediately.
- **A duplicate copy may not be a new entry**, so `onEntriesChanged` returns
  early and nothing shows. Use a `$RANDOM` suffix every time.
- **The first refresh after a shell restart is swallowed** on purpose
  (`firstRefresh`), so the copy right after `smoke.sh` never shows the card.

Poll `hyprctl layers | grep clipboardToast`, then sleep another ~0.8s before
`grim`: the layer maps before Hyprland has faded it in, and a shot taken at
`a: 0` comes out empty. That is what made the first three after-shots blank.

## Driving the pointer on this machine

The hover-hold change is only verifiable with a cursor on the card, and
**Hyprland's cursor dispatchers do not work here** — the config is Lua, so
`hyprctl dispatch movecursor 1865 90` is parsed as Lua and rejected, and
`hyprctl eval 'hl.dsp.cursor.move({x=,y=})'` returns `ok` without moving
anything. `ydotool` works, but:

- `--absolute` lands somewhere else entirely (uinput maps to its own resolution).
- Relative moves are scaled ~2x by pointer acceleration, and not linearly.

So warp by closing the loop against `hyprctl cursorpos` — home with
`mousemove -x -4000 -y -4000`, then step by half the remaining delta until it
is within 2px. That is what verified: hover holds the card past its 3s timeout,
and leaving restarts the clock.

## The live config is not the default

`~/.config/illogical-impulse/config.json` has `corner: top_right` and
`dismissAfter: 3`, against the shipped `bottom_left` / `6`. The card is at the
top right of the screen here, below whatever the notification stack reserves.
Both corners share one code path, but a shot taken against the default corner
will not match this machine's.

## Rejected

- **A `tools/check-*.py` for the hover hold.** The logic is a three-condition
  guard; a script could only assert on the source text, not the behaviour, and
  the behaviour is what breaks. Runtime-verified instead, recipe above.
- **Deriving `previewBox` from `card.tileSize`.** It would cross from the root
  scope into the window's, for a constant. The comment naming the arithmetic is
  the cheaper guard.
