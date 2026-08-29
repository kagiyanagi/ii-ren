---
description: Review changed QML against the Android 16 / M3 Expressive design law in .github/DESIGN.md
argument-hint: [git ref, path, or nothing for uncommitted changes]
allowed-tools: Bash(python3 tools/check-design.py:*), Bash(git diff:*), Bash(git status:*), Bash(git log:*), Read, Grep, Glob
---

Review QML against this repo's design law. Do not fix anything — report, then wait.

## Scope

`$ARGUMENTS` decides what to look at:

- empty → uncommitted changes (`git status --short`, `git diff` plus `git diff --cached`)
- a git ref → everything changed since it (`git diff <ref>`)
- a path → that file or directory in full, whether or not it changed

## Step 1 — the deterministic half

Run it and take the output as given; do not re-derive it by reading:

```
python3 tools/check-design.py --diff        # for a diff scope
python3 tools/check-design.py --rule <id>   # to expand a rule
```

For a path scope the script has no path mode — run the bare audit and filter its
output to that path yourself.

## Step 2 — the half a script cannot see

Read `.github/DESIGN.md` first if it is not already in context. Then read the
actual changed QML and judge these, which no regex can:

1. **Spatial vs effects.** Position/size/shape on a spatial spec, opacity/colour
   on an effects spec. Anything that fades must not overshoot.
2. **Speed.** fast/default/slow chosen by travel distance and element size, not
   taste. A screen-sized surface on a fast spec, or a chip on a slow one, is wrong.
3. **Enter and exit both present**, exit faster and accelerating. A component
   that animates in and vanishes instantly is the most common failure here.
4. **Transform origin** set on anything that scales, and pointing at whatever
   opened it — anchor edge, click corner, or centre for press feedback.
5. **Interruption.** Hover- and toggle-driven motion must be reversible
   mid-flight; only one-shot acknowledgements may run to end.
6. **Reset on hide**, so the next open does not animate from stale values.
7. **All four states render** — hover, focus, pressed, disabled. Disabled is
   `opacity: 0.4`, not a grey colour.
8. **State layer source.** `colLayerNHover`/`colLayerNActive` or `StateOverlay`,
   matching the layer actually painted underneath — never a hand-mixed tint.
9. **Layer nesting.** Child on the next layer up from its parent, child radius
   smaller than parent radius.
10. **Reuse.** Did this rebuild something `modules/common/widgets/` already has?
    Name the widget it should have used.
11. **Effect budget.** No `layer.enabled`, `MultiEffect` or `OpacityMask` inside
    a delegate that can repeat; at most one per interactive widget.
12. **Hit area** ≥ 32px, pointing-hand cursor on clickables, Escape closes any
    popup, keyboard can reach everything the mouse can.
13. **Shape morph on press** only opted in per widget, and never on something
    resting at `rounding.full` or `height / 2`.
14. **The anti-patterns in DESIGN.md section 10** — each has shipped and been
    reverted before.

## Step 3 — report

Group by severity. Every finding gets `file:line`, what rule it breaks, and the
concrete fix — the token or widget to use, not "consider using a token".

```
ERROR   — will misbehave: snapping animation, broken binding, crash pattern
WARN    — off-spec: wrong scheme, missing exit, hand-written number
NOTE    — reuse or simplification available
```

Then one line: `N error, N warn, N note` and whether it is clear to ship.

Rules:

- A number transcribed from AOSP with the source named in a comment is correct,
  not a violation. Check the citation is real rather than assumed.
- Legacy debt in files the change did not touch is out of scope. Say so once if
  it is loud; do not enumerate it.
- If nothing is wrong, say that plainly and stop. Do not manufacture findings.
- Do not edit anything. End with the fixes you would make, in priority order,
  and wait for a go-ahead.
