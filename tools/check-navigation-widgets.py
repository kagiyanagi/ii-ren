#!/usr/bin/env python3
"""Assert the navigation widgets keep the states and the directions they got.

Two things here are invisible when broken, and neither existing check can see
them:

1. `check-button-states.py` walks QQC2 `Button` roots, which is how every
   toolbar button inherits its four states from `RippleButton`. The two tab
   buttons are rooted in `TabButton` and the search field in `TabField`'s
   cousin `TextField` -- all `AbstractButton`/`TextInput`, none of them
   `Button` -- so all three sat outside that net with no focus layer at all
   (DESIGN.md 3.1, and 3.7 on the boolean nothing renders).

2. The rail's expand and its collapse are different moves (2.5) and the easy
   "simplification" is one shared spec. The anchor halves take their direction
   from a state's `to:`; the width and the chevron cannot, so they use 2.9's
   assign-from-the-driving-binding shape, which reads backwards and invites
   being "fixed" into the ternary-inside-the-Behavior that 2.9 exists to
   forbid.

Plus the one literal `check-design.py` structurally cannot catch: the tab
indicator's durations arrive as `idx1Duration:`/`idx2Duration:`, which the
`\\bduration:` rule does not match, so a hand-picked 50 there is invisible.

Run: python3 tools/check-navigation-widgets.py
"""
import pathlib
import re
import sys

WIDGETS = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/modules/common/widgets"

# A property binding whose value reads the focus flag -- `focused: root.visualFocus`,
# not a comment and not a bare mention of the word.
FOCUS_BINDING = re.compile(r"^\s*[\w.]+:\s*[^/\n]*\b(?:visualFocus|activeFocus)\b", re.M)
SPEC = re.compile(r"Appearance\.animation\.(\w+)")
TAB_INDICATOR_DURATION = re.compile(r"idx\dDuration:\s*(.+)$", re.M)
DISABLED = re.compile(r"opacity:\s*\w+\.enabled\s*\?\s*1\s*:\s*0\.4")


def strip(src: str) -> str:
    """Source without pragmas, imports or comments."""
    body = re.sub(r"^\s*(?:pragma|import)\b.*$", "", src, flags=re.M)
    return re.sub(r"//.*$", "", body, flags=re.M)


def root_type(src: str) -> str:
    m = re.search(r"^\s*(\w+)\s*\{", strip(src), re.M)
    return m.group(1) if m else ""


def body(name: str) -> str:
    return strip((WIDGETS / f"{name}.qml").read_text())


def overlay_block(src: str) -> str:
    """The first StateOverlay { ... } block, or "" if there is none."""
    i = src.find("StateOverlay {")
    if i < 0:
        return ""
    depth = 0
    for k in range(src.index("{", i), len(src)):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                return src[i:k + 1]
    return ""


# --- 1. the widgets outside check-button-states.py's net render their states --

tab_buttons = sorted(p.stem for p in WIDGETS.glob("*.qml") if root_type(p.read_text()) == "TabButton")
assert tab_buttons == ["NavigationRailButton", "SecondaryTabButton"], (
    "the set of TabButton-rooted widgets changed. A new one inherits nothing from "
    f"RippleButton, so it renders 3.1's four states itself before it is added here: {tab_buttons}"
)

for name in tab_buttons + ["ToolbarTextField"]:
    src = body(name)
    overlay = overlay_block(src)
    assert overlay, f"{name}: no StateOverlay -- 3.1's states have nowhere to composite"
    assert FOCUS_BINDING.search(overlay), (
        f"{name}: the StateOverlay does not bind focus. 3.7 wants the 0.10 film "
        f"rendered, not an activeFocus boolean nothing reads"
    )

# SecondaryTabButton has no RippleButton under it, so hover and press are its own
# job too. NavigationRailButton drives those off colLayer1Hover/Active in its
# colour, which is 3.1's first-choice mechanism; only focus needs the film.
secondary = overlay_block(body("SecondaryTabButton"))
for state in ("hover:", "press:"):
    assert state in secondary, (
        f"SecondaryTabButton: the StateOverlay dropped `{state}` -- nothing else in "
        f"the file renders that state since the hand-mixed background tint went"
    )

# The field is switched off mid-unlock on the lock screen and used to look live.
assert DISABLED.search(body("ToolbarTextField")), (
    "ToolbarTextField: disabled must be `opacity: enabled ? 1 : 0.4` on the whole "
    "control, not a greyed-out colour (3.1)"
)

# --- 2. expand and collapse are not the same move ----------------------------

rail = body("NavigationRailButton")
pairs = re.findall(r"(RailEnter|RailExit)\s*\{\s*to:\s*\"(\w*)\"", rail)
assert pairs, "NavigationRailButton: no directional transitions -- 2.5 wants one per direction"
enter_targets = {to for comp, to in pairs if comp == "RailEnter"}
exit_targets = {to for comp, to in pairs if comp == "RailExit"}
assert enter_targets == {"expanded"}, (
    f"NavigationRailButton: the enter transition should run toward \"expanded\"; got {enter_targets}"
)
assert exit_targets and "expanded" not in exit_targets, (
    f"NavigationRailButton: the exit transition should run away from \"expanded\"; got {exit_targets}"
)

enter_spec = set(SPEC.findall(re.search(r"component RailEnter:.*?\n    \}", rail, re.S).group(0)))
exit_spec = set(SPEC.findall(re.search(r"component RailExit:.*?\n    \}", rail, re.S).group(0)))
assert enter_spec and exit_spec and enter_spec != exit_spec, (
    f"NavigationRailButton: expand and collapse share a spec ({enter_spec}) -- 2.5 "
    f"wants the exit faster, on the effects one"
)

# 2.9: the two animations with no state to read their direction from assign the
# spec inside the binding that drives them. A ternary in the Behavior instead
# bakes whichever value happened to be current, which is the trap 2.9 documents.
for name, driver in (("NavigationRailButton", "railSpec"), ("NavigationRailExpandButton", "turnSpec")):
    src = body(name)
    assert re.search(rf"^\s*root\.{driver}\s*=\s*.*\?", src, re.M), (
        f"{name}: {driver} is not assigned from inside the binding that drives the "
        f"animation. Read from a binding of its own, the exit runs on the enter's "
        f"spec -- DESIGN.md 2.9, Revealer is the worked example"
    )
    behavior = re.search(rf"Behavior on \w+ \{{.*?{driver}.*?\n    (?:    )?\}}", src, re.S)
    assert behavior, f"{name}: nothing consumes {driver} in a Behavior"
    assert "?" not in behavior.group(0), (
        f"{name}: the Behavior picks its spec with a ternary. That is the 2.9 trap: "
        f"it bakes the spec when the write lands, not when the trigger changes"
    )

# --- 3. the indicator durations are tokens, which the duration: rule misses ---

for name in ("SecondaryTabBar", "ToolbarTabBar"):
    durations = TAB_INDICATOR_DURATION.findall(body(name))
    assert durations, f"{name}: no AnimatedTabIndexPair durations -- did the indicator move?"
    for value in durations:
        assert "Appearance.animation." in value, (
            f"{name}: indicator duration `{value.strip()}` is a literal. check-design.py's "
            f"`duration:` rule cannot see idxNDuration, so this is the only thing that can"
        )

print(f"ok: {len(tab_buttons) + 1} navigation widgets render focus, the rail names both "
      f"directions, and both tab indicators ride tokens")
