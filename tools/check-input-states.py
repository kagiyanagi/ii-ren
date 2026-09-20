#!/usr/bin/env python3
"""Assert the shared value controls render focus, press and disabled.

DESIGN.md 3.1 wants hover, focus, pressed and disabled on every interactive
element, and 3.7 says a focused control shows the film "visibly, not just as an
`activeFocus` boolean nothing renders". The inputs family shipped neither: no
slider, switch, radio button, combo box or spin box in the library read
`visualFocus`, and only the combo box dimmed when disabled.

check-design.py cannot see any of it. A missing state is an absence, and an
absence has no line to flag -- which is exactly how these six went ~80 call
sites deep with three states.

Each rule below is the state as that control renders it:

  focus     a binding whose value reads visualFocus or activeFocus. A bare
            mention is not enough; the failure mode this guards is the boolean
            that nothing is bound to.
  press     a slider's press is the M3 Expressive squeeze -- the handle's
            pressed dimension is smaller than its resting one -- so that pair
            is checked instead of a film.
  disabled  opacity: root.enabled ? 1 : 0.4 on the whole control.

Run: python3 tools/check-input-states.py
"""
import pathlib
import re
import sys

WIDGETS = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/modules/common/widgets"

# The QQC2 value controls. Anything rooted in one of these takes input and holds
# a value, so 3.1 applies to it whole.
VALUE_ROOTS = {"Slider", "Switch", "RadioButton", "ComboBox", "SpinBox"}

# A property binding whose value reads the focus flag, e.g. `focused: root.visualFocus`
# or `color: root.activeFocus ? ... : ...`. Not a comment, not a bare mention.
FOCUS_BINDING = re.compile(r"^\s*[\w.]+:\s*[^/\n]*\b(?:visualFocus|activeFocus)\b", re.M)
DISABLED = re.compile(r"opacity:\s*root\.enabled\s*\?\s*1\s*:\s*0\.4")
# handleDefaultWidth / handlePressedHeight / ... -- the resting and pressed sizes.
HANDLE_SIZE = re.compile(r"property real handle(Default|Pressed)(Width|Height):\s*([\d.]+)")


def strip(src: str) -> str:
    """Source without pragmas, imports or comments."""
    body = re.sub(r"^\s*(?:pragma|import)\b.*$", "", src, flags=re.M)
    return re.sub(r"//.*$", "", body, flags=re.M)


def root_type(src: str) -> str:
    m = re.search(r"^\s*(\w+)\s*\{", strip(src), re.M)
    return m.group(1) if m else ""


roots = sorted(p for p in WIDGETS.glob("*.qml") if root_type(p.read_text()) in VALUE_ROOTS)
assert roots, "no QQC2 value control found in the widget library -- did it move?"
assert len(roots) == 7, (
    "the set of shared value controls changed; a new one has to render the same "
    f"states before it is added here: {[p.name for p in roots]}"
)

for path in roots:
    src = path.read_text()
    body = strip(src)
    name = path.name

    assert FOCUS_BINDING.search(body), (
        f"{name}: nothing renders the focus state -- bind a state layer, or a "
        f"colour, to visualFocus (keyboard) or activeFocus (a field being typed "
        f"into). 3.7 calls the unrendered boolean out by name"
    )

    assert DISABLED.search(body), (
        f"{name}: disabled must be `opacity: root.enabled ? 1 : 0.4` on the whole "
        f"control, not a greyed-out colour (3.1)"
    )

    if root_type(src) == "Slider":
        sizes = {m.group(1): float(m.group(3)) for m in HANDLE_SIZE.finditer(body)}
        assert set(sizes) == {"Default", "Pressed"}, (
            f"{name}: a slider's press is the M3 Expressive thumb squeeze, so it "
            f"needs handleDefaultWidth/Height and handlePressedWidth/Height; found "
            f"{sorted(sizes)}"
        )
        assert sizes["Pressed"] < sizes["Default"], (
            f"{name}: the pressed handle ({sizes['Pressed']}) is not smaller than "
            f"the resting one ({sizes['Default']}) -- the press renders nothing"
        )

print(f"ok: {len(roots)} shared value controls render focus, press and disabled")
