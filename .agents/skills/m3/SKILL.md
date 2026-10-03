---
name: m3
description: >-
  Build, re-audit, or look up a UI in the ii-ren shell against Material 3 (M3
  Expressive). Use when the user asks to build or design a widget or surface
  "with M3", to audit, redesign or "make better" an existing surface against
  Material 3, or asks what M3 says about a component, motion, colour, type,
  shape, spacing, icons or copy.
---

Three modes, from the first word of the argument:

- `spec <topic>` — what M3 says about something, mapped onto this shell. No edits.
- `audit <surface or path>` — check an existing surface against M3, report, wait.
- `build <what>` — design and build something new the M3 way.

No mode word: a question is `spec`, an existing surface or path is `audit`, a new
thing is `build`.

## Sources — read only what the task touches, in this order

1. `.github/TASTE.md` — the owner's calls (§9 beats everything below) and the §11
   questions every brief and audit answers.
2. `.github/DESIGN.md` — the law: which `Appearance` token, which widget.
3. `.github/M3.md` — M3 distilled and mapped onto this shell. **Always read §1
   (departures) first**, then the sections the task touches: §3 motion, §4 states
   and keyboard, §5 colour, §6 type, §7 shape, §8 spacing, §9 elevation, §10 icons,
   the §11 entry for each component involved, §12 writing, §13 accessibility.
4. The live spec, for anything M3.md does not cover or to verify a number:
   `python3 tools/m3-docs.py` prints the cache path; grep its `pages/` (guidelines,
   do/don't captions) and `tokens/` (`component-<name>.txt`, `motion-shape-state.txt`,
   `typography.txt`, `spacing.txt`). Quote what you found; never fill a gap from
   memory of M2 or of the web.

M3 measures in dp for a 48dp-target touch UI; this shell is denser (M3.md §1.1).
Translate M3 proportions to the nearest `Appearance` token — never paste a dp
literal. A literal with no token gets its source in a comment
(`// M3: md.comp.menus.menu-item.height`), which `check-design.py` accepts.

## spec

Answer from M3.md, then the cache. Give the M3 rule with its numbers or token
names, what this shell maps it to (token, widget), and whether the shell departs
from it (M3.md §1). If M3.md and the cache disagree, the cache is newer: say so and
offer to update M3.md.

## audit

1. **Read the surface whole** — its QML, and any shared widget whose behaviour the
   findings depend on. Name the M3 components it is built from and the Android 16
   or Google surface it imitates.
2. **Run the mechanical half**: `python3 tools/check-design.py` (filter to the
   path), and every `tools/check-*.py` that greps its files.
3. **Walk M3.md against it**, one layer at a time:
   - composition (§2, §11.1): one primary action, the emphasis ladder, one loud thing;
   - each component against its §11 entry: size, padding, radius step, type role,
     colour roles, elevation, states, keyboard;
   - colour (§5.3): on-X pairing, accent budget, surface steps, outline vs variant;
   - type (§6): the right style per text slot, emphasized for selection, tabular figures;
   - shape (§7): scale step, optical roundness, inner corners in groups, morph per size;
   - motion (§3): spring for reactions vs curve for transitions, the right pattern,
     speed by size, enter/exit easing, clean fades, reduced motion;
   - states (§4): containers don't light up, selection by two cues, disabled rules,
     Tab/arrows/initial and returned focus;
   - copy (§12) and accessibility (§13);
   - then TASTE §11's questions.
4. **Filter.** Drop anything that is an M3.md §1 departure or would undo a TASTE §9
   call; say once that it was considered. Legacy debt in untouched files is out of
   scope.
5. **Report**, most severe first, each with `file:line`, the M3 rule broken (M3.md
   section or token name) and the concrete fix (the token or widget):

   ```
   ERROR — misbehaves: wrong state, broken keyboard path, contrast failure, crash pattern
   WARN  — off-spec against M3 or DESIGN: wrong role, size, pattern, missing exit
   NOTE  — reuse, simplification, or an M3 refinement worth having
   ```

   If the surface needs restructuring rather than repairs, add the one-page brief
   from TASTE §11. Then offer **one bolder M3 Expressive direction** — a distinctive
   use of size, shape or morph — clearly marked optional, beside the repairs.
6. **Stop and wait** for a go-ahead. On it, make the fixes, then run the checks and
   `/design-check`.

## build

1. **Brief first** — TASTE §11's questions and its brief template, plus: the M3
   components it is made of (M3.md §11.1 for which action component), and the M3
   transition pattern it enters and leaves by (§3.3). Ask the user only what the
   brief cannot answer from TASTE and the code.
2. **Per component**, read its M3.md §11 entry and reuse the widget named there. If
   none exists, read the full tokens in the cache and build the smallest thing that
   meets the spec; a new shared widget goes in `modules/common/widgets/` only when a
   second caller needs it (DESIGN rule 1).
3. **Numbers** from `Appearance` (DESIGN), M3 proportions mapped per §1.1.
4. **Motion**: component reactions on the spring-backed specs (§3.1), surface
   changes on the transition curves and pattern (§3.2–3.4); enter and exit both,
   exit faster; transform origin at the opener.
5. **States, keyboard, copy, edge states**: §4, §12, TASTE §6 — empty, loading,
   error, one item, many.
6. **Verify**: `python3 tools/check-design.py --diff`, the matching
   `tools/check-*.py`, `bash tools/smoke.sh` for a new surface, then `/design-check`.
   Leave a `tools/check-*.py` for logic a still frame cannot show. Measure motion at
   60fps; never eyeball it.
