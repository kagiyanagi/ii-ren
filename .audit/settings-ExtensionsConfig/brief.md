# settings-ExtensionsConfig — brief

**Purpose.** Turn the extension system on, then find, install and manage extensions.

**Primary action.** With extensions off: Enable extensions. With them on: search.

**Hierarchy.**
1. **Enable extensions**, a carded `ConfigSwitch`, first. It used to be a bare switch
   inside the beta `NoticeBox`, below a toolbar that sat greyed out above it.
2. The beta notice, text only.
3. The toolbar (docs, custom URL, search, refresh), shown only while extensions are on,
   and the custom URL row, a `Revealer` under it.
4. Errors, then **Installed** and **Browse Extensions** (`ii-settings` owns both lists).

**Reference.** Android 16 Settings → Developer options: master switch on top, everything
under it appears with it.

**Interaction.** The URL row opens on `Revealer`'s spatial spec and closes on its exit
spec. It was an `implicitHeight` Behavior on `elementMoveFast` (an effects spec on a size)
collapsing to 0 with `clip`, and its field stayed reachable by Tab while hidden.
Turning the switch on runs the same fetch as opening the page.

**Edge states.** Off shows the switch and notice only. On with nothing fetched shows
`ExtensionList`'s own empty line. A fetch or install error shows in `colError` above the
lists.

**Cost.** None.

**Delete.** The switch inside the notice, and `Layout.fillWidth` on the icon buttons.

**Out of scope.** The two lists and their cards (`ii-settings`).
