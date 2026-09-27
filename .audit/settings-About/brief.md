# settings-About — brief

**Purpose.** Say what this machine is and what is in it, what shell it runs and what that
is built on, and get the user to the right place to ask for help about each.

*Revised after the first build:* the user wanted the machine's specs on the page, not only
the lineage. The distro card became the device hero, and a hardware grid went under it.

**Primary action.** None dominant: the page is read, not operated. The one thing that
asks for attention is the link row of whichever project the user has a problem with.

**Hierarchy.** Nearest first, the way Android's About phone puts the device on top and the
build details under it:
1. **Device hero**, with no header. It shows the distro logo, the hostname at `hugeass`, the
   distro name and `Linux <kernel> · Up <uptime>`. The distro's os-release links are its chips.
2. **Hardware** — a 2x2 grid of tiles: Processor (threads, max clock), Graphics
   (resolution of each screen in physical pixels), Memory and Storage (a
   `StyledProgressBar` of use, with the amount used). The grid's outer corners take
   `rounding.large` and its seams `rounding.verysmall`, which is how `ContentGroup` rounds a
   list. The tiles bleed 8 so they meet the edges of the cards above and below.
3. **This shell** — ii-ren, with the easter egg logo.
4. **Built on** — ii-vynx, then illogical-impulse: nearest ancestor first, one grouped run.

It used to be the reverse: distro, then "Parent-Dots", then "Preset-Dots", with the shell
actually running last and below the fold. Those two headers were jargon.

Every project is the same card: an 80 logo, then name (`title`), byline (`smaller`,
`colSubtext`) and repo link, then a `Flow` of link chips. The cards are
`ContentGroup` rows (`wantsCard`), so they are `colSurfaceContainerHigh` with seam radii
in a run, the material of every other settings row. They used to float bare on the pane.
Chips sit on the card, so they take `colSurfaceContainerHighest` and its hover and
active tokens. `colLayer2` resolves against a base the card does not have.

**Reference.** Android 16 Settings → About phone, and its Android version page, where
repeated taps on the version open the easter egg.

**Interaction.** Chips and the egg are `RippleButton`s, with all four states. The egg was a
bare `MouseArea` with no feedback. It is now a round `colPrimaryContainer` badge like the two
real logos beside it, and it takes keyboard focus. Three presses within the timer open the
`EasterEggWindow`. There is no motion here beyond the widgets' own.

**Edge states.** os-release fields are optional. A distro with no `HOME_URL` shows no link
line, and a chip whose URL is empty is not drawn. It used to be drawn and open nothing.
The distro card always has a name ("Unknown" at worst) and a logo (`SystemInfo` falls back
to `distroIcon`).

**Cost.** No effects of its own. The specs come from `ResourceUsage`, which polls on its
own timer while the settings app is open, and from three `/proc` files read once. Twelve chips at most, each a `RippleButton` with its own mask.
There were thirteen.

**Delete.** The four copy-pasted blocks, which become one in-file `Project` component. The
"Upstream: ii-vynx" chip goes, since its card is directly below. The `#3DDC84` hex goes
too, and the egg now takes the theme. The off-grid 5/10/20 spacings go.

**Out of scope.** `EasterEggWindow.qml` (its own row). `SystemInfo`'s os-release regexes
only match quoted values. They are noted, not changed.
