# TASTE.md — what "better" means in this shell

`DESIGN.md` is the law: tokens, motion, states, shape, spacing, and every number traced to
AOSP. A script can check most of it. This file is the half a script cannot check: what a
surface should *be*, what should not be on it, how it behaves when it is empty or wrong,
and the calls the owner has already made. It is distilled from the audit of 2026-09-20
to 09-27: 110 queue rows, their briefs and notes, and every call the owner made on them.

Every rule names the audit rows it came from. The audit's working files were removed
from the tree afterwards, so each row's brief (the worked example) and notes (what was
tried) are read from history: `git show 6cc240c9a:.audit/<id>/brief.md`. When a rule and
one of the owner's recorded calls (§9) disagree, the call wins.

**Read this before designing a feature, restructuring a surface, or auditing a UI.** A
request like "make this better" means this file first, then `DESIGN.md` for the numbers.

Scope: the ii family, which is Android 16. Waffle is Windows 11 on purpose. Its visuals
answer to Windows 11, but §3, §4, §6 and §7 apply to it unchanged.

---

## 1. Who this is for

- **Feel over feature count.** The owner turned down a sibling fork's whole feature list
  with "it's all bloat". The shell's own history is interaction polish: click bounce, the
  snip preview, drag-to-wallpaper. A new feature has to earn its space, and "no one asked"
  is a reason not to build one [ii-verticalBar: `showNetwork` left out].
- **Lean.** Prefer deleting to adding. The shell came out of the audit about 22k lines
  smaller, and what it gained was behaviour, not chrome [sw-dead alone deleted 25.5k].
  Reuse a widget that exists before writing one.
- **A real daily desktop.** It runs on one 1920×1080 laptop screen with integrated
  graphics. The owner also uses it to study: the periodic table was rebuilt on request
  because a table that shows four facts is worse than a poster [ii-cheatsheet].
- **The owner reviews what ships and reverses what feels wrong.** Their calls are in §9.
  Read them before proposing something that sounds like one.
- **An audit repairs; it does not add features.** A shortcut, a new mode or a new service
  is its own row [ii-sidebarDashboard-notifications: no History button;
  ii-onScreenDisplay: no mono-audio feature]. A surface that already reads as its
  reference, or that is the owner's own design, gets repaired, not redesigned
  [ii-sidebarDashboard-quickToggles, ii-sidebarDashboard-root, ii-sidebarPolicies-root].
- **Check the history before deleting something that looks odd.** The calendar's Google
  Calendar tap looked like a stray hard-coded link and was the owner's feature
  (`git log -S`) [ii-sidebarDashboard-calendar].

## 2. Composition: deciding what a surface is

1. **One sentence of purpose, one primary action.** Everything else is secondary and
   looks it. In Fast Pair, Connect is the one filled control and Close moved to the corner
   X that Android uses [ii-fastPair]. On the drop shelf the tiles are the surface, the
   count moves into the header and Copy is the one filled control [ii-dropover]. The
   pomodoro's start/pause is the one filled button, in the same place on both tabs
   [ii-sidebarDashboard-pomodoro].
2. **Some surfaces have no primary action. Say so, and make them quiet.** The bar is
   status: nothing in it may pull more attention than the windows below it, and only the
   workspace indicator gets an accent fill [ii-bar]. The same goes for the desktop plane,
   the screen corners and the wrapped frame: "nothing here should be noticed"
   [ii-background-root, ii-screenCorners].
3. **Allow one loud thing.** "Only one thing on screen is `colPrimary`, and it is round:
   the focused tile" [ii-sessionScreen]. The lock screen's confirm circle is the only
   saturated thing on it [ii-lock]. When the agent is blocked, the approval card is the
   only loud thing on the page [ii-sidebarPolicies-hermes-composer]. Accent is a budget of
   one.
4. **Order things the way the task happens.** The translator runs top to bottom: the
   language bar, then the source, then the result. It used to read backwards
   [ii-sidebarPolicies-translator]. About goes nearest first: this machine, then this
   shell, then what it is built on [settings-About]. The resources popup has its meters,
   then graphs, then an identity footer, with Docker last [ii-bar-resources]. The weather
   grid comes last because "nobody opens a weather popup to read humidity first"
   [ii-bar-weather].
5. **The content is the control.** An anime tile's image opens the menu, where it used to
   need a 30px `more_vert` over the art [ii-sidebarPolicies-anime]. A Bluetooth or Wi-Fi
   row connects on tap, with no expanding first [ii-sidebarDashboard-bluetoothDevices,
   ii-sidebarDashboard-wifiNetworks]. An extension row expands itself, and a browse row
   opens its repo the way a store list item does [ii-settings].
6. **Use the space; never strand it.** Fill it with real content, or shrink to fit.
   Never decoration, never a void. On the translator, two short cards over half a page of
   nothing was rejected, so the cards now split the height and each scrolls its own text
   [ii-sidebarPolicies-translator]. Continuity was filled with Saved devices and This
   device, and a decorative device-orbit hero was declined [ii-sidebarPolicies-continuity].
   The immersive player's card is as wide as its square art is tall [ii-immersiveMedia].
   In the audio dialog, device rows replaced about 350px of nothing
   [ii-sidebarDashboard-volumeMixer].
7. **A popup is small.** A hero, at most three sections, then nothing: "a popup that needs
   a fourth section is a sidebar" [ii-bar-popups].
8. **Merge what belongs together; un-nest what does not.** Keep one level of subsection
   everywhere [settings-BarConfig, settings-HyprlandConfig]. General went from ten
   sections to eight [settings-GeneralConfig]. A section holding one switch folds into its
   neighbour, and two places called Hermes became one [settings-HyprlandConfig,
   settings-ServicesConfig]. Three sections pulled together with negative margins became
   one section [settings-QuickConfig].
9. **Cut chrome down to what the reference has.** The power menu's title, instructions,
   subtitle pill and tooltip went, because Android's has none [ii-sessionScreen]. The OSD's
   toggle labels became icons in a connected group with the text in the tooltip, as in
   AOSP's volume dialog [ii-onScreenDisplay]. The immersive player lost its "Media Player"
   label [ii-immersiveMedia]. The hotspot dialog's subsection headers went, and so did the
   field labels that repeated their placeholders [ii-sidebarDashboard-hotspot].
10. **Separate with whitespace and tone, never lines.** Every divider the audit found was
    deleted: `WindowDialogSeparator`, `SectionCard.showDivider`, the dock menu rules, the
    OSK rail bar, the line under the search field, the `---` rail entry and the `•` dots.
    The 2px seams between separately rounded rectangles counted too
    [cw-dialogs, ii-bar-cards, ii-dock, ii-onScreenKeyboard, ii-overview,
    ii-sidebarPolicies-hermes-thread].
11. **Siblings read as one family.** Things that do the same job look and behave the same
    everywhere. The five sidebar dialogs share one row, one switch row and one status line
    [ii-sidebarDashboard-*]. The two freeze-the-screen surfaces put their FAB in the same
    place [ii-screenTranslator]. The three corner cards swipe away identically
    [ii-regionSelector]. The lock screen and the polkit dialog explain a failed password in
    the same order [ii-polkit]. Three in-file copies of one icon button became
    `HermesIconButton` [ii-sidebarPolicies-hermes-panels]. For the vertical bar: "where the
    two differ and the vertical one is not forced by its axis, the vertical one is wrong"
    [ii-verticalBar].
    The same applies to text fields and empty states [cohesion].

## 3. Honesty: the UI tells the truth

1. **A control shows the real state, not its own guess.** A switch that toggles itself
   breaks its binding: a hotspot that failed to start went on showing as on. The row owns
   the state, the switch is non-checkable, and the service's value flows back
   [ii-sidebarDashboard-hotspot, ii-sidebarDashboard-nightLight,
   ii-sidebarPolicies-root: the NSFW switch]. The Bluetooth tile follows `toggled`, like
   every other tile [ii-sidebarDashboard-quickToggles].
2. **Write only on a real change by the user.** A handler that fires on build must be
   gated. The vertical-parallax switch reloaded Hyprland on build, and the eye-protection
   switches called their services on build [settings-BackgroundConfig,
   settings-QuickConfig]. Text commits on `editingFinished`, not per keystroke; typing a
   city used to fetch weather for every prefix [settings-ServicesConfig]. A slider writes
   on `moved`: one settle animation left `gain: 57.3` in a real file [ii-settings]. A
   slider that reloads the compositor is debounced [ii-sidebarDashboard-nightLight].
3. **No control bound to nothing.** A control whose key nothing reads is deleted, or wired
   up if the feature is real. The window-rounding switch and the stereo/mono toggle went
   [settings-AdvancedConfig, ii-onScreenDisplay]. "Show widgets only in one monitor" was
   wired up [settings-WidgetsConfig]. The same applies to a chip with an empty URL
   [settings-About], an Install that only leaves a clone [ii-settings], and a Hibernate
   tile that did nothing [ii-sessionScreen].
4. **Say why, where the user is already looking.** Use one status line under the thing it
   is about, and only when there is something to say.
   - Passwords: PAM first (pam_faillock sends the lockout as *info*), then the failure, then
     Caps Lock, in that order on the lock screen and in polkit [ii-lock, ii-polkit].
   - Radio rows: "Connected", "Saved", "Wrong password", "Couldn't connect"
     [ii-sidebarDashboard-wifiNetworks].
   - Hotspot: "Not supported by this Wi-Fi adapter", "Disconnects from %1"
     [ii-sidebarDashboard-hotspot].
   - Schedules: "On until 06:30", "Turns on at 19:00" [ii-sidebarDashboard-nightLight].
   - A run killed by the next keystroke says nothing; a real failure says so in `colError`
     [ii-sidebarPolicies-translator].
   - An informational error line is `colOnSurfaceVariant`, "not `colError` shouting"
     [ii-bar-cards].
5. **Never "loading forever".** A fetch that can fail needs a failure the user sees, and a
   retry (hovering again is enough). Placeholder data that looks real is worse than none:
   the weather popup stated four wrong numbers out of a shipped placeholder
   [ii-bar-weather].
6. **Disabled means "can't", not "busy".** Opacity 0.4 is disabled. A row that is working
   stays at full strength and says what it is doing in its status line
   [ii-sidebarDashboard-bluetoothDevices, ii-sidebarDashboard-wifiNetworks]. Choose between
   disabled and hidden:
   - Disabled, with the reason, is better than hidden with none.
   - Hide when a choice does not exist at all: Enabled with one display, the OSK's layout
     cycle with one layout, the player picker with one player [settings-HyprlandConfig,
     ii-onScreenKeyboard, ii-mediaControls].
   - Dim once. A control inside a widget that already dims must not add its own 0.4, which
     came out as 0.16 [settings-BackgroundConfig, settings-BarConfig].
7. **Don't offer what this machine cannot do.** Gate on the real capability: logind's
   `Can*`, adapter support, a pairing agent, fprintd [ii-sessionScreen,
   ii-sidebarDashboard-hotspot, ii-fastPair].
8. **The placeholder names what Enter will do.** With a power action armed, the lock
   field says so instead of "Enter password" [ii-lock].
9. **Safety is part of honesty.** A remote string never goes into `bash -c`
   [ii-sidebarPolicies-anime, ii-wallpaperSelector]. What is on the clipboard is nobody's
   business while the screen is locked [ii-clipboardToast]. The keyboard cannot type
   through a lock [ii-onScreenKeyboard].

## 4. Stability: nothing moves under the pointer

1. **A card that re-centres must not change height while it is open.** The sidebar
   dialogs are a fixed 0.6 of the sidebar. The owner chose this after fit-to-content moved
   rows about 57px under the pointer [ii-sidebarDashboard-wifiNetworks,
   ii-sidebarDashboard-volumeMixer, ii-sidebarDashboard-nightLight]. Dim a field that does
   not apply in place rather than hiding it [ii-sidebarDashboard-hotspot]. Make pills equal
   width so a hint appearing cannot push the swap button away
   [ii-sidebarPolicies-translator]. Reserve the progress bar's row
   [ii-fastPair], and hold slots at their final size while icons and images load
   [ii-dock, ii-sidebarPolicies-anime].
2. **Lists survive a poll.** A list fed by a service that replaces its array gets a keyed
   `ScriptModel`. Without one, every row rebuilds: carets drop, expanded rows fold shut and
   entrances replay [ii-sidebarDashboard-todo, ii-sidebarPolicies-continuity,
   ii-sidebarPolicies-hermes-panels, ii-sidebarDashboard-wifiNetworks: keyed on SSID].
3. **Hover tints; it never takes focus.** A resting pointer must never show two
   "selected" things [ii-sessionScreen, ii-wallpaperSelector]. The one exception is Alt+Tab,
   where hovering a tile selects it, because that is exactly what the keyboard does there
   [ii-altTab].
4. **Switching a tab moves nothing under the pointer**, so both tabs share one button
   component [ii-sidebarDashboard-pomodoro].
5. **A dismissal clock stops under the pointer**, and restarts in full when it leaves
   [ii-clipboardToast, ii-fastPair].
6. **A click does what it looks like it will.** Click and drag are told apart on Qt's
   drag threshold [ii-regionSelector]. A whole-card target sits *under* its content, so
   pressing a pill never also toggles the card [ii-sidebarPolicies-continuity]. A click on
   nothing does nothing, and the surface stays open [ii-regionSelector]. Tapping the
   connected row does not bounce the link [ii-sidebarDashboard-wifiNetworks].
7. **Never trap the user.**
   - Everything dismisses with Escape or an outside press, unless it has to stay out of
     the way of the app underneath. Fast Pair and notifications take no keyboard. The drop
     shelf has no outside-press dismiss, because you drag into the window behind it. Each
     brief says so [ii-fastPair, ii-dropover, ii-notificationPopup].
   - Escape works on the first frame. The cheatsheet ignored it for 2s [ii-cheatsheet].
   - A masked item never scales. The drop shelf rendered correctly and could not be clicked
     at all [ii-dropover].
   - A shell that dies with the screen locked can take its session back [ii-lock].
   - No layer outlives its content [ii-overlay].

## 5. Motion: taste on top of the law

The tokens are in `DESIGN.md`. These are the calls about when to use which.

1. **Every surface leaves visibly.** This was the most common defect in the audit.
   `Loader.active` or `visible` bound to the open flag unmaps the surface on the frame the
   flag clears, so the exit plays to nobody and nothing looks broken. Keep intent and
   mapping apart, with a latch that the finished exit releases. It turned up in more than
   a dozen rows, in both families.
2. **Grow out of whatever opened it.**
   - A menu grows from the corner nearest the click or drop point. Compare the point with
     the card's midpoint, not with where the edge clamp left the card
     [ii-desktopMenu, ii-dropover].
   - A card that gets clamped hangs off a zero-size pivot at the opener
     [ii-sidebarDashboard-calendar, ii-sidebarPolicies-hermes-composer].
   - Bar popups grow from the bar edge, and dock menus from the dock edge.
   - Use the screen centre only when a keybind opened it and nothing on screen did
     [ii-sessionScreen, ii-cheatsheet, ii-overlay].
3. **Popups pop; panels slide.** An anchored popup is `ArrowPopupMotion` (0.5 → 1.02 → 1),
   not a notification-shade slide [ii-bar]. For the power menu the owner chose a pop from
   the centre over `WindowDialog`'s slide [ii-sessionScreen].
4. **Scale travel follows size.** A 0.92 scale that suits a 400px card is a 112px lurch on
   a 1400px sheet, and the owner did not like it. Big surfaces use a smaller delta (0.96)
   on the default spatial duration [ii-cheatsheet].
5. **Planes of one gesture move on one spec.** The wallpaper, the widget canvas and the
   overview zoom run on the same timing, or they slide apart [ii-background-root,
   ii-overview].
6. **A toggle-driven move reverses mid-flight.** A dodge or a reposition is on
   `elementMove`, never on the run-to-end enter spec [ii-clipboardToast,
   ii-notificationPopup].
7. **Recording overlays do not animate their own appearance**, because a fade lands in
   the footage [ii-keypressDisplay]. Ambient motion such as weather keeps its AOSP timing
   [ii-background-root].
8. **Corner cards swipe away like Android cards.** The toast, the Fast Pair card and the
   screenshot preview all go through `SwipeToDismiss` and throw the same way
   [ii-fastPair, ii-regionSelector].
9. **Don't retime existing motion unasked.** The owner declined a motion pass on
   2026-09-27. New motion still follows the law [cohesion].

## 6. Edge states: designed, never discovered

1. Every brief states **empty, loading, error, one item and many**, one sentence each.
   If one of them cannot be written, that is the finding.
2. **An empty state is `PagePlaceholder`**: a shape-backed icon, a title, and one sentence
   saying what to do and where [cohesion-empty-favourites]. There are three exceptions. A
   small card takes one line of subtext ("No apps are playing sound"), not a cookie in a
   void [ii-sidebarDashboard-volumeMixer]. A surface that unmaps when empty has no empty
   state [ii-notificationPopup]. A section with no rows does not render at all
   [settings-widgets].
3. **Empty text is specific and changes with the state.** Bluetooth shows "Searching for
   devices", then "No devices found", or "Bluetooth unavailable"
   [ii-sidebarDashboard-bluetoothDevices]. Wi-Fi shows "Searching for networks", "No
   networks found" or "Wi-Fi is off" [ii-sidebarDashboard-wifiNetworks]. The notification
   list says "No notifications", where it used to say "Nothing"
   [ii-sidebarDashboard-notifications].
4. **One item must not look broken or collapse to its chrome.** Alt+Tab's title cell is
   never narrower than three tiles [ii-altTab]. A one-option selector still draws chips
   [settings-widgets]. One image is full width at the same radius [ii-sidebarPolicies-anime].
5. **Overflow keeps the newest item and shows everything.** Keypress chips pin to the
   tail [ii-keypressDisplay]. The cheatsheet continues a category into the next column with
   its heading repeated, and never cuts it off [ii-cheatsheet]. The calendar says "+N
   more" instead of dropping events [ii-sidebarDashboard-calendar]. Alt+Tab wraps into a
   balanced grid with no orphan tile [ii-altTab].
6. **Loading keeps the layout.** Rows fill in; the page is never a spinner over a greyed
   list [sw-extensions]. Tiles are held at their final size [ii-sidebarPolicies-anime]. Use
   a determinate indicator whenever the duration is known [cw-progress].
7. **NaN is an edge state.** `0/0` passes straight through `Math.max`/`Math.min`. Guard
   the division at its source and leave a check [ii-background-root, ii-bar-weather].

## 7. Cost: integrated graphics is the target

- **At most one offscreen pass per widget, and none inside anything that repeats**,
  counting a delegate that is its own file, which `check-effect-budget.py` cannot see.
  Every dock icon paid three passes, the calendar grid 49 masks, the anime page forty and
  the audio dialog a `Desaturate` per app row [ii-dock, ii-sidebarDashboard-calendar,
  ii-sidebarPolicies-anime, ii-sidebarDashboard-volumeMixer].
- **Take the cheap shape.**
  - Use one mask per grid, drawn from the same rows as the tiles
    [ii-sidebarPolicies-anime, ii-wallpaperSelector].
  - Round an element's own corners instead of masking its parent. Doing that on the
    overlay turned seven passes into three [ii-overlay].
  - Delete a mask that rounds what `radius` and `clip` already round [ii-bar-resources,
    ii-cheatsheet].
  - Give a plain rounded rectangle `StyledRectangularShadow`, not a drop shadow that
    re-renders every frame [ii-onScreenDisplay].
- **Nothing ticks faster than anyone sees it.** The stopwatch's 10ms timer became 100ms,
  plus a frame clock that runs only while the readout is on screen
  [ii-sidebarDashboard-pomodoro]. A 16ms `Timer` becomes a `FrameAnimation`
  [settings-EasterEggWindow]. Infinite pulses go, and so do polling timers once a real
  signal exists [ii-regionSelector, ii-onScreenDisplay].
- **One process, not one per item.** The translator started a Python process per box to
  pick its colour [ii-screenTranslator].
- **A heavy thing may stay when it *is* the feature**, with the argument written down: the
  effect previews are the picker [settings-WallpaperEffectPreview].

## 8. Copy: how the shell talks

- Sentence case and plain words that say what happens: "Add a task", "Clear all", "Play on
  several devices", "Tap a device to add or remove it".
- Status lines are short, present-tense states: "Connected", "Connecting…", "Saved",
  "Wrong password", "Couldn't connect", "On until 06:30".
- No jargon headers: "Parent-Dots" and "Preset-Dots" became "Built on" [settings-About].
  No prefix the section title already says, such as "Terminal:" [settings-AdvancedConfig].
  No label that repeats its placeholder [ii-sidebarDashboard-hotspot].
- Only the status that asks for action. "Update available" stays; "Up to date" and
  "Checking update…" went [ii-settings].
- Every icon-only control has a tooltip [ii-overlay, ii-onScreenDisplay]. Plurals are
  right ("1 notification").
- Every string goes through `Translation.tr`. Keep existing strings where you can, so the
  translations still apply [ii-sessionScreen].

## 9. The owner's calls on record: do not relitigate

- **Notification cards** stay separate `rounding.large` cards, 8 apart. A joined
  Android-shade stack was built and reverted. Don't "fix" its 5px insets, and don't propose
  the stack again [ii-sidebarDashboard-notifications].
- **Sidebar dialogs** have a fixed height, 0.6 of the sidebar, not fit-to-content
  [ii-sidebarDashboard-wifiNetworks, -volumeMixer, -nightLight].
- **The power menu** pops from the centre on `ArrowPopupMotion` [ii-sessionScreen].
- **The cheatsheet** uses 0.96 on the spatial duration and keeps its page slide rather
  than a crossfade, and no column may run past the bottom. A fade with no transform, and
  0.98 at the old timing, were offered and declined [ii-cheatsheet].
- **The pomodoro** buttons are a compact 32px pair, centred and sized to their labels. The
  neutral button is tonal so that it still shows when disabled; a 0.4 `colLayer2` pill read
  as "a gradient at each end" [ii-sidebarDashboard-pomodoro].
- **The owner's own designs** stay: the quick-toggle tile shapes, the three-way sliders,
  gamma folded into brightness, the earbud art, and the calendar's Google Calendar tap
  [ii-sidebarDashboard-quickToggles, ii-sidebarDashboard-calendar].
- **Use the whole page** on the translator and on Continuity. About leads with the
  machine's specs [ii-sidebarPolicies-translator, ii-sidebarPolicies-continuity,
  settings-About].
- **Corner cards** swipe to dismiss [ii-fastPair].
- **No stretch overscroll.** It was removed once watched on a real desktop, and it is the
  shell's one deliberate departure from Android 16 (DESIGN.md 3.6).
- **Divider styles** on the dock and bar exist only because the owner's config picked
  them. New code never adds a divider.
- **No new imports from ii-p3drovfx**: no features, motion or looks, because its feature
  list is "all bloat". What is vendored from it (the background widgets, the bar popups
  and cards, the quick toggles) arrives only through the port scripts in `tools/p3-*`.
- **No motion retiming** for now (2026-09-27).
- **A maximized floating window** sits where a lone tiled window would, inside `gaps_out`
  with its border and rounded corners, not edge to edge as KWin's and Mutter's do
  [ii-floatingMode].

## 10. Which widget for which job

| Job | Use | Precedent |
|---|---|---|
| Empty state | `PagePlaceholder` | ii-sidebarPolicies-translator |
| Fold or disclosure | `Revealer`, content built on first open and kept | ii-sidebarPolicies-hermes |
| Popover or menu | `ArrowPopupMotion` on a zero-size pivot | ii-sidebarDashboard-calendar |
| Corner card dismissal | `SwipeToDismiss` | ii-fastPair |
| Dialog | `WindowDialog`, `WindowDialogTitle`, `WindowDialogButtonRow`, `DialogButton` | ii-polkit |
| Dialog row with a status line | `DialogListItem`; a switch row takes a non-checkable `StyledSwitch` | ii-sidebarDashboard-hotspot |
| Settings rows | `Config*` rows in a `ContentGroup` run; a sub-page is `ConfigNavRow` | settings-LockConfig |
| Hover, focus and press films | `StateOverlay`, or `colLayerNHover`/`colLayerNActive` | ii-sidebarPolicies-continuity |
| A list that animates | `StyledListView` plus a keyed `ScriptModel` | ii-sidebarDashboard-todo |
| A warning in the flow | `NoticeBox` | ii-sessionScreen |
| Two to four exclusive options | connected `SelectionGroupButton`s, never a combo box | ii-sidebarDashboard-hotspot |
| Progress and battery | `StyledProgressBar`, which never overshoots; `MaterialLoadingIndicator` inline | ii-sidebarPolicies-continuity |
| Button | `RippleButton` and its descendants; never a bare `MouseArea` | cw-buttons |

If two surfaces solve one job two ways, that is a cohesion finding in itself [cohesion].

## 11. The questions: for a feature brief or a UI audit

Answer them in order, one sentence each. A question you cannot answer is the finding.

1. What is this for, and what is the one primary action? (§2)
2. Which Android 16 or Google surface does this job? What does it have that this lacks,
   and what does this have that it doesn't? (§2)
3. What is the one loud thing, and is anything competing with it for accent, size or
   fill? (§2)
4. What can go? Chrome the reference lacks, labels that repeat placeholders, controls
   bound to nothing, sections of one row, dividers, dead properties. (§2, §3)
5. Does it tell the truth? Real state, a reason on failure, disabled vs busy vs hidden,
   and no writes on build or per keystroke. (§3)
6. Does anything move under the pointer? Height changes, lists that rebuild, hover
   stealing focus, fields that hide. (§4)
7. Are empty, loading, error, one item and many each designed? (§6)
8. Where does it grow from, and does it leave visibly? (§5)
9. What does it cost per frame, and per repeated item, counting delegates that live in
   their own files? (§7)
10. Which widget in §10 already does this?
11. Has the owner already decided this (§9)?

Then write the brief, one page, before any code:

```markdown
**Purpose.** One sentence: what the user came here to do.
**Primary action.** The one thing it exists for. Everything else is secondary and looks it.
**Hierarchy.** What the eye hits first, second and third, by name.
**Reference.** Which Android 16 or Google surface this imitates, and why that one.
**Interaction.** States, motion per element, and what it grows out of. Tokens by name.
**Edge states.** Empty, loading, error, one item, many. A sentence each.
**Cost.** Which effects it keeps and which it drops.
**Delete.** What goes away.
**Out of scope.** What this deliberately does not touch.
```

Then the code, then `/design-check`. Leave one `tools/check-*.py` behind for any logic a
still frame cannot show.
