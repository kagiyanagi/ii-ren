# AUDIT.md — the repo-wide quality and design pass

A standing process for bringing all ~190k lines of this shell up to the design law in
`.github/DESIGN.md` and to a code standard worth keeping, one surface at a time.

Two hard constraints shape every choice below:

- **Claude does the design.** No other tier available here produces briefs or layouts
  worth keeping. Implementation can sometimes be pushed down a tier; judgement cannot.
- **Claude's quota is borrowed and must not spike.** The process is built to run slow and
  steady, to be stopped after any surface at zero cost, and to be resumed weeks later
  without re-reading anything.

Read this before starting or resuming audit work. The tooling is built and 17 of the
96 queue rows are done; what is left to build is in **Not built yet**.

## Why a process instead of just doing it

Two failures, both observed:

- **A session that holds the whole repo designs badly.** Not because the context is full,
  but because mechanics crowd out composition. The model spends its attention on getting
  tokens and bindings right and ships a default layout.
- **One feature at a time, with a small focused brief, comes out well.** That is the
  result worth industrialising.

`DESIGN.md` already locks the mechanical half — tokens, motion, states, shape — and
`tools/check-design.py` proves it. What no file in this repo says is what a surface should
*be*: its hierarchy, its one primary action, what should not be there at all. That
artifact is missing, so it gets improvised in the same breath as the code, which is where
"sloppy" comes from.

So: **decide the design before the code, in writing, as its own cheap artifact.**

## Burn control

The quota matters as much as the result, so understand where the tokens actually go.

**A conversation resends its whole context every turn.** A thirty-turn session that has
accumulated twenty files of tool output pays for those files thirty times. So short
sessions are not only better work — already known from experience — they are *cheaper for
the same work*, and by a wide margin. Every rule below follows from that one fact.

| Rule | Why |
|---|---|
| **One surface per session, then stop and `/clear`.** | Context never grows past one surface. Two surfaces in one session costs far more than two sessions. |
| **Or one session that only dispatches.** | The fifteen `cw-*` rows ran twelve at once as subagents, each fenced to its own files, with the parent holding no surface itself — it owned only git, the shell and the merge. Same rule underneath: no context holds two surfaces. See `.audit/common-widgets/notes.md` for the four fences that make it safe. |
| **Read the pack, not the repo.** | `.audit/<id>/pack.md` is script-generated and ~150 lines. The surface itself is 1–3k. Read actual QML only for files being edited. |
| **Read line ranges, not whole files.** | `sed -n '400,520p'` on a 2,000-line file like `ResourcesPopup.qml`. Whole-file reads are the single largest avoidable cost. |
| **Checks run in Bash, never by reading.** | `check-design.py --diff` output is twenty lines. Deriving the same by reading is hundreds. |
| **No repo-wide scans inside a session.** | Scans are scripts; their output is committed to `.audit/` and read back later for free. |
| **Design on Opus, mechanical follow-through on Sonnet.** | Deciding a layout needs the better model. Applying an already-written brief with three checkers gating it does not. Switch with `/model`. |
| **Commit every session.** | A stop is then free, and a resume reads one queue row instead of reconstructing anything. |

**Cadence is yours to set, not mine to assume.** A sane default is two or three surfaces a
day with gaps, never a marathon — ~80 surfaces then lands over a couple of months of light
use rather than as a visible spike. The queue logs the date of each finished surface so
the pace is visible at a glance. Stop whenever; the next session starts from the queue.

## Decisions taken

| Decision | Choice |
|---|---|
| How aggressive | **Restructure freely.** A brief may change layout, move or merge controls, delete what does not earn its space, rebuild a surface outright. Expect some surfaces to stop looking familiar, and expect to revert a few. |
| Who designs | **Claude, on Opus.** Briefs are written per cluster, not per surface, so a family of surfaces comes out coherent. |
| Who implements | **Lane 1 Claude, lane 2 Sonnet-via-agy behind the gates.** See **Two lanes**. |
| Who verifies | Scripts first, then Claude reading its own diff against the brief. |
| agy | Vision, shell driving, and lane 2 implementation. See **The tiers**. |
| Vendored trees | **Out, permanently.** See **The re-port hazard**. |
| Motion verification | **Once, in the cohesion pass**, not per row. A row that retimes something names it in `notes.md`; the cohesion session runs the shell at 60fps against that list. Twelve parallel sessions could not each drive the shell, and one pass over a list costs less than twelve that each re-derive what to look at. |

## The tiers, as actually measured

| Tier | Availability | What it is good for |
|---|---|---|
| **Deterministic scripts** | Free, unlimited | Every mechanical fact. Exact, repeatable, cannot invent anything. First choice for anything expressible as code. |
| **Gemini via agy** (`gemini-3.1-pro-high`, Flash tiers) | Plentiful — the account's own quota, spendable in full | **Vision.** Looking at `shot-after.png` and listing where it departs from the brief's hierarchy and edge states. Describing a render is far easier than designing one, and the output is checkable in seconds. Also: driving `iiren run`, `grim`, `magick montage`, running the checker batch. |
| **Sonnet 4.6 via agy** | Intermittent — works sometimes, hits the limit often | Implementing an **already-written brief** behind all four gates. Never design. When the tier is down, the row waits or escalates. |
| **Opus 4.6 via agy** | Unusable — exhausts before finishing one task | Nothing. Closed; do not retry. |
| **Claude Code (this account)** | Borrowed. Best quality, must not spike | Briefs, diff review, and implementing the surfaces that carry the shell. |

A weak model summarising *code* is where a false premise enters and gets trusted
downstream — that job goes to scripts. A weak model describing a *picture* is safe, because
the claim is verifiable at a glance. That distinction is the whole of agy's role here.

## Two lanes

Not every surface deserves the same spend.

**Lane 1 — Claude end to end.** Brief, implement, verify, commit, all here. The surfaces
that carry the shell: `modules/common/widgets/`, bar, dock, both sidebars, OSD,
notifications, overview. Roughly 20 of 80.

**Lane 2 — Claude briefs, Sonnet-via-agy implements, Claude reviews the diff.** The long
tail: settings pages, minor surfaces, anything whose brief leaves few real choices. Roughly
60 of 80. The four gates plus a diff review are what make this safe; a sloppy
implementation fails a gate or fails review.

**Escalation is one-way.** A lane 2 row that fails its gates twice, or fails review, moves
to lane 1 and stays there. Do not spend three Sonnet attempts on what one Claude session
would have finished — that is a net loss of quota, not a saving.

Which lane a surface belongs to is a column in `QUEUE.md`, decided when the brief is
written, because that is the moment it becomes clear how much judgement the
implementation still needs.

## Scope

In: `modules/common/`, `modules/common/widgets/`, `modules/ii/`, `modules/waffle/`,
`modules/settings/`, `services/`, `panelFamilies/`. About 1,130 files / 190k lines.

Out: `user_widgets/` (426 files / 108k lines of third-party extensions — not ours to
redesign), `modules/common/widgets/shapes/` (submodule).

**The re-port hazard — decided 2026-09-20: they stay out.** `modules/ii/background/widgets/`,
`modules/ii/bar/cards/` and the bar popups are vendored from ii-p3drovfx by
`tools/p3-widget-port/` and `tools/p3-bar-popups/`; `port-widgets.sh` rsyncs the widget
tree with `--delete`, so a redesign there is reverted by the next re-port. Re-porting is
worth more than redesigning 27.7k lines that are not ours: the tranche keeps flowing from
upstream, and `ii-background-widgets` is marked `skip` in the queue rather than `todo`.
What that costs, accepted with eyes open: the eight `[undefined]` assignments and the 21
effects-in-delegates in `FINDINGS.md` that live in that tree stay unfixed, and
`check-effect-budget.py`'s `KNOWN` set is what keeps them from growing. Reverse this only
by stopping the re-port first. See `tools/p3-widget-port/README.md`.

## Unit of work

One **surface** — a user-visible thing, normally one directory. 43 surface dirs exist in
`modules/ii` + `modules/waffle` at a median of ~900 lines, which is already the right
size. Four are too big and split; anything over ~2,500 lines splits again.

| Node | Files | Lines | Split into |
|---|---:|---:|---|
| `modules/ii/background` | 125 | 29,058 | `widgets/` (122 files — its own tranche, see re-port hazard) + the 3 loose top-level files |
| `modules/ii/bar` | 52 | 13,078 | loose top level (36 files) splits by widget group; `cards/` (14); `weather/` (2) |
| `modules/ii/sidebarPolicies` | 41 | 11,239 | `hermes/` (4.5k), `aiChat/`, `anime/`, `continuity/`, `translator/`, loose top level (4.4k) |
| `modules/ii/sidebarDashboard` | 72 | 7,999 | `quickToggles/` (47 files, 4.7k — splits again), then `pomodoro`, `calendar`, `todo`, `hotspot`, `volumeMixer`, `nightLight`, `bluetoothDevices`, `wifiNetworks`, `notifications`, loose |
| `modules/settings` | 209 | 46,311 | 15 pages, one each; `widgets/` (191 files, 35k) joins the shared-widget tranche |

Roughly 80 surfaces once split, excluding the background widget library.

Every surface row carries **how to open it**. Most major surfaces declare an `IpcHandler`
(`shell.qml`, `Bar.qml`, `Overview.qml`, `SidebarDashboard.qml`, `AltTab.qml`,
`OnScreenDisplay.qml`, and ~15 more), so `qs -c ii ipc call <target> <fn>` opens them
unattended. The rest need a keybind or a manual trigger — record it once, in the queue.

## State

State lives in the repo. No session needs to remember another one.

```
.audit/
  QUEUE.md                 # id · path · cluster · how-to-open · status · date done
  <surface-id>/
    pack.md                # script-generated facts. No model wrote this
    brief.md               # what it should be — written per cluster, on Opus
    shot-before.png  shot-after.png
    notes.md               # anything the next session needs and the diff won't show
```

## The pack (script, no model)

`tools/audit/pack.py <surface-dir>` emits ~150 lines that replace reading the surface:

- file tree with per-file line counts
- every `property`, `signal`, `function` declared, per file
- every `Config.options.*` path read, checked against `Config.qml` for paths that do not
  exist — a missing member on a `JsonObject` reads as `undefined` with no warning at all
- every component type instantiated, flagged when a same-named widget exists in
  `modules/common/widgets/` — the reuse-miss heuristic
- reverse dependencies: who imports or instantiates this surface
- an **effect budget**: every `layer.enabled` / `MultiEffect` / `OpacityMask` /
  `ShaderEffect` / shadow / `Canvas` and every sub-100ms `Timer`, flagged when it sits
  inside something that repeats. Until 2026-09-20 no session saw a single perf fact
  unless it read the QML itself
- `check-design.py` output filtered to the path, and qmllint via
  `tools/p3-widget-port/mkshadow.sh`
- the IPC call or keybind that opens it

Deterministic, so it is regenerated rather than maintained, and it cannot invent a fact.

## The brief (Claude, Opus, one session per cluster)

Briefs are written for a **cluster** — the OSD family, the quick toggles, the bar popups,
the settings pages — because eight briefs written together come out coherent and eight
written weeks apart do not. Cohesion is the whole goal; this is where it is bought.

Input is the packs and the before-shots for that cluster, nothing else. One page each:

```markdown
# <surface> — brief

**Purpose.** One sentence. What the user came here to do.
**Primary action.** The single thing this surface exists for. Everything else is secondary
  and must look it.
**Hierarchy.** What the eye hits first, second, third. Name the elements.
**Reference.** Which Android 16 / M3E surface this imitates, and why that one.
**Interaction.** States, motion spec per element (spatial vs effects, enter and exit),
  transform origin and what it grows out of. Tokens by name, never numbers.
**Edge states.** Empty, loading, error, and one-item. Each gets a sentence.
**Cost.** Which effects the surface keeps, from the pack's *Effect budget*, and what
  it drops. One layer or effect per widget, never inside something that repeats (8).
**Delete.** What goes away. Restructuring is authorised; say what dies.
**Out of scope.** What this brief deliberately does not touch.
```

## Session protocol (one surface, start to finish)

1. `/clear`. Always start cold.
2. Read `.audit/<id>/pack.md` and `.audit/<id>/brief.md`. Nothing else yet.
3. Read only the files to be edited, by line range where the file is large.
4. Implement the brief.
5. `python3 tools/check-design.py --diff` → qmllint → `tools/audit/smoke.sh`. Fix, repeat.
6. `iiren run`, screenshot to `shot-after.png`. Hand the shot and the brief to agy on a
   Gemini vision model and have it list every departure from the brief's hierarchy and edge
   states. This is the step that catches what the checkers cannot see, and it costs none of
   this account's quota.
7. Commit: one surface, one commit.
8. Update the `QUEUE.md` row with status and date; anything the next session needs that
   the diff will not show goes in `notes.md`.
9. **Stop.** Do not begin another surface in this session.

If a surface turns out to be bigger than expected, commit what is finished, split the
remainder into a new queue row, and stop. A half-finished surface left uncommitted is the
only state this process cannot resume from.

## Stopping and resuming

The process is expected to sit idle for weeks at a time. Two invariants make that free:

- **The tree is clean between sessions.** Everything a later session needs is in a
  committed file, never in a conversation.
- **The shell boots at every commit.** `~/.config/quickshell/ii` is a symlink into this
  repo, so whatever is committed *is* the running desktop. A commit that does not start is
  not a stopping point, it is an outage. `tools/audit/smoke.sh` is what makes this a rule
  rather than a hope.

Four artefacts carry the state, and each answers one question a cold session would
otherwise have to re-derive:

| Artefact | Answers |
|---|---|
| `QUEUE.md` row | Where were we, and what is next |
| The commit log | What is actually done |
| `brief.md` | What was decided, and why — written before the code, so it survives the code |
| `notes.md` | What was tried and rejected. Without it a later session repeats the same dead end |

**Resuming**, in order:

1. `git status` — a dirty tree means a previous session was cut off. Deal with that before
   anything else: finish it, commit it as partial, or `git checkout .` to discard it.
2. `QUEUE.md` — take the next row.
3. `git log --oneline -5` — what landed most recently, for continuity of style.
4. Read that row's `pack.md` and `brief.md`, and start.

Three small reads before useful work begins.

**If a session is cut off mid-surface** — quota, crash, closed terminal — the edits are
already on disk and the desktop may be mid-redesign. `git checkout .` restores the last
good shell immediately and costs only the unfinished surface. The queue row simply stays
open.

**Work on `main`.** A branch would not isolate anything: the symlink means the checked-out
branch is the running desktop, so evaluating a redesign requires living with it. One commit
per surface, and `git revert <sha>` is the undo for a redesign that turns out wrong.

**What ages across a long pause.** Briefs do not: they name tokens and widgets rather than
numbers, and the shared-widget tranche lands before any of them are written, so their
foundation is already stable. What does age is upstream — a merge from `upstream`
(vaguesyntax/ii-vynx) can conflict with redesigned surfaces, and the vendored p3drovfx
trees will overwrite them outright. Merge upstream *between* surfaces, never mid-surface.

## Gates

Unattended or interrupted work without gates is how you end up with a shell that will not
start and no memory of which change did it.

| Gate | Catches |
|---|---|
| `python3 tools/check-design.py --diff` (exit 1) | Every mechanical design-law rule |
| qmllint via `mkshadow.sh`, using `/usr/lib/qt6/bin/qmllint` | Assigning a property a widget does not have — the one failure that stops the shell booting. `/usr/bin/qmllint` is a Qt5 stub that prints nothing and exits 255, which looks exactly like a clean run |
| `tools/check-m3-tokens.py`, `check-mpris-hover-preview.py`, `p3-widget-port/check-*.py` | Their own concerns; run what the change touches |
| `tools/audit/smoke.sh` *(to build)* | Start `qs -c ii`, watch stderr for N seconds, fail on any QML error |

## Order

1. **`modules/common/widgets/` first** (172 widgets), then `modules/settings/widgets/`
   (191). Fixing the shared base lifts every surface at once and stops 80 sessions each
   inventing their own button. `DESIGN.md` rule 9 applies hard here: check every caller
   before changing a shared widget — that is how a pressed-shape default once squared 58
   pill buttons.
2. High traffic: bar, dock, sidebars, OSD, notifications, overview.
3. Settings pages.
4. The long tail.
5. The background widget library, if the re-port question was answered yes.

## Cohesion pass

At the end, `magick montage` every `shot-after.png` into one contact sheet and review it in
a single session. This is also where **motion** gets verified: every row that retimed
something left the specific thing to watch in its `notes.md`, and a still frame proves
none of it. The standing list so far is in `.audit/DECISIONS.md`. Naming the outliers is what makes a shell read as one person's work
rather than 80 surfaces that are each fine alone. Cheapest session in the plan and the one
that delivers the actual goal.

## Pilot first

Run the whole protocol end to end on one small surface — `clipboardToast` (478 lines) or
`altTab` (242) — before generating the rest of the queue. It calibrates what one surface
actually costs, which is the number the cadence depends on.

## Not built yet

- `/audit` command that reads the queue and starts the next surface under this protocol

Built since, and in use: `.audit/QUEUE.md` (hand-edited, generated once), `tools/audit/pack.py`
(now including the effect budget) and `tools/audit/smoke.sh`.
