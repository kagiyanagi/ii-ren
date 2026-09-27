# settings-ServicesConfig — brief

**Purpose.** Configure the shell's background services: calendar feeds, fast pairing,
media, music recognition, networking, resources, lyrics, screen recording and the
keystroke overlay, save paths, LocalSend, search, weather.

**Primary action.** None dominant; a long list of independent service options.

**Hierarchy.** Unchanged order, less one section. The shell-side **Hermes** section moved
to the Hermes page as "In the sidebar". Settings used to have two places called Hermes:
this section, and the page with the agent's own settings.

**Reference.** Android 16 Settings → Apps → (app) → settings: one page per thing.

**Interaction.** Every text field commits on `editingFinished` (Enter or focus-out). They
all wrote their key on every keystroke. For most that was only a config write per
character. Two readers react to the key, though: `LocalSend` restarts its receive server
when `downloadPath` changes, and `Weather` refetches (250ms debounce) when `city` changes,
so typing a city fetched weather for its prefixes.

**Edge states.** Unchanged: the keystroke notices show only on a read error or a missing
`python-xkbcommon`, and the screenshot preview options hide once a save path is set.

**Cost.** Unchanged. The one `PwObjectTracker` tracks audio nodes while the page is open.

**Delete.** The Hermes section (moved), a commented-out System updates section, a
`ConfigRow` wrapping one switch, and trailing whitespace.

**Out of scope.** The recording reset (`Config.resetScreenRecord`) and the services.
