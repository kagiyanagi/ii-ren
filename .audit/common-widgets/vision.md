# common-widgets — the vision pass

Step 6 of `.github/AUDIT.md`, run once for the whole tranche instead of twelve times,
because the twelve families ran in parallel and none of them could start the shell.

Model: `gemini-3.1-pro-high` via `agy`, per AUDIT.md's tier table. Cost to this
account's Claude quota: nothing, which is the entire point of the step.

Shots: `.audit/cw-config-rows/shot-after.png` (the settings window — where
`cw-navigation`, `cw-config-rows`, `cw-inputs`, `cw-scaffolding` and `cw-dialogs`
actually render) and `.audit/cw-battery/shot-after.png` (the bar strip).

## Getting agy to see an image at all

Two blockers, both worth writing down because the next vision session hits them:

1. **Give it an absolute path.** With a relative `@path`, agy shells out to
   `find /home/ren -path "*/...png"` to resolve it, which needs the `command`
   permission and is denied in headless `-p` mode. An absolute `@/home/ren/...`
   skips the `find` entirely.
2. **It needs a `read_file` allow-rule.** `~/.gemini/antigravity-cli/settings.json`
   had an allow-list of commands but no `read_file` entry, so every file read was
   auto-denied in headless mode. Added `read_file(/home/ren/Code/ii-ren)`.
   `--dangerously-skip-permissions` also works but grants everything; the narrow
   rule is the better trade.

**Probe before trusting it.** A model that cannot load the image will describe a
plausible desktop anyway. The probe used here: ask for two specific values only the
pixels can supply — "the two-digit number in the pill and the time in the centre" —
and give it an explicit escape hatch ("reply CANNOT SEE IMAGE"). It used the escape
hatch correctly when blocked, and returned `83, 5:19 pm` once unblocked, both
correct. Do this every time; it costs one cheap call.

## Result: 13 findings, 2 real

The honest tally, because AUDIT.md's bet is that vision is cheap *and verifiable at
a glance*, and the verification half is what this run actually exercised.

### Confirmed, and new

- **Separator bars in the bar and the dock.** `modules/ii/bar/Spacebar.qml` paints a
  vertical pipe in `colOutlineVariant` — its own comment says "Matches
  DockSeparator.qml" — and `modules/ii/bar/SysTray.qml` ships
  `showSeparator: true`. `modules/ii/dock/widgets/SectionSeparator.qml` is the dock's
  copy. Design law 11 and DESIGN.md 5.5 forbid separator lines outright.
  **`check-design.py` cannot see these**: its `no-separator-bars` rule matches
  `WindowDialogSeparator` *by name*, so a separator called `Spacebar` walks straight
  past it. Verified in the pixels and in the source. Filed in `FINDINGS.md`.

### Confirmed, already known

- The hand-rolled "No favourites yet" empty state in `QuickConfig`, which DESIGN.md 9
  says should be `PagePlaceholder`. Already in `FINDINGS.md` against
  `settings-QuickConfig`; the pass found it independently.

### False positives, verified against the pixels and the source

- **"The Night schedule rows fail to form a run — all four corners fully rounded."**
  Wrong. Cropped and zoomed: the seam between the two rows is visibly tighter than
  the run's outer corners, which is 5.6 working exactly as written.
  `ContentGroup.qml` implements `runStart`/`runEnd` against `outerRadius` /
  `innerRadius` and it is doing its job.
- **"Unselected theme chips are darker than the card they sit on — tonal inversion."**
  Wrong. There is no card behind them; they sit on the page background and are
  *lighter* than it, which is correct nesting.
- **"The battery digits clip against the pill's top and bottom edges."** Wrong —
  there is clear padding above and below. The related "it doesn't read as a battery,
  there is no icon or % sign" is a design opinion, not a departure: the pill's *fill
  level* is the charge, which is what `CustomBatteryMeter` draws.
- **"The tray and battery are wedged into the middle of the bar next to the window
  title."** Wrong. The pill sits at x≈1690 of 1920, far right, tray after it. The
  model misjudged absolute position on a wide, sparse strip.
- Several softer calls (icon-to-text proportion, workspace gap rhythm, whether the
  nav rail's selected pill out-competes its neighbour) are subjective and were left
  alone rather than actioned on one still frame.

### What it missed

The chip grid in `QuickConfig` is **clipped mid-row** — a real, already-known defect
that is plainly visible in the shot, and the pass did not mention it despite being
asked directly for anything clipped or overflowing.

## What this says about the step

Useful, and cheap, and not to be taken at face value. It found one genuine defect
that the whole checker suite is structurally blind to, which is exactly the value
AUDIT.md claims for it — and it produced four confident-sounding false positives
that took a crop and a grep each to disprove. Both halves are the expected result.
Run it, then verify every finding before acting; never let a vision finding reach a
commit unchecked.

A still frame also cannot judge motion, hover, focus or press, so the prompts say so
explicitly. Everything in DESIGN.md 2 and 3.1 remains unverified by this step.
