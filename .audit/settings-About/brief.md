# settings-About — brief

**Purpose.** Say what this shell is, what it is built on and what it runs on, and get the
user to the right place to ask for help about each.

**Primary action.** None dominant: the page is read, not operated. The one thing that
asks for attention is the link row of whichever project the user has a problem with.

**Hierarchy.** Nearest first, the way Android's About phone puts the device on top and the
build details under it:
1. **This shell** — ii-ren, with the easter egg logo.
2. **Built on** — ii-vynx, then illogical-impulse: nearest ancestor first, one grouped run.
3. **System** — the distro from `/etc/os-release`.

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

**Cost.** No effects of its own. Twelve chips at most, each a `RippleButton` with its own mask.
There were thirteen.

**Delete.** The four copy-pasted blocks, which become one in-file `Project` component. The
"Upstream: ii-vynx" chip goes, since its card is directly below. The `#3DDC84` hex goes
too, and the egg now takes the theme. The off-grid 5/10/20 spacings go.

**Out of scope.** `EasterEggWindow.qml` (its own row). `SystemInfo`'s os-release regexes
only match quoted values. They are noted, not changed.
