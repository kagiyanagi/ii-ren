#!/usr/bin/env python3
"""An extension's options write plugins.json only when the user changes one.

Every write rewrites the whole file, and FileView's watch reloads it, so a write
nobody asked for is not free and a write mid-edit resets the row under the user.
None of this shows in a screenshot; all of it was measured with a sandboxed
XDG_CONFIG_HOME (see .audit/ii-settings/notes.md).

* **The slider commits on `moved`.** `valueChanged` fires on every frame of
  StyledSlider's settle animation: the old panel left `gain: 57.3` in a real
  plugins.json from one render, for an extension that was not even installed.
* **Rows get their key and entry at creation.** The old `Loader` wired
  `cfgKey`/`cfgEntry`/`extId` in `onLoaded`, so every row's value arrived after
  creation and its change handler wrote it back.
* **The spinbox reads its bounds.** SpinBox clamps on assignment and `to`
  defaults to 99; a stored 150 evaluated before `to` landed came back as 99 and
  was written. The value binding reads `from` and `to`, and the write waits for
  `Component.onCompleted`.
* **Text commits on `editingFinished`,** not per keystroke -- each write reloads
  the file and the reload resets the text under the caret. `ConfigTextField`
  carries the signal for this; it must not lose it.
* **Remove asks twice.** It deletes the clone and the extension's settings.

Run: python3 tools/check-extension-options.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
II = ROOT / "dots/.config/quickshell/ii"

panel = (II / "modules/ii/settings/ExtensionConfigPanel.qml").read_text()
card = (II / "modules/ii/settings/InstalledExtensionCard.qml").read_text()
field = (II / "modules/common/widgets/ConfigTextField.qml").read_text()

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def code(src):
    return re.sub(r"//[^\n]*", "", src)


def block(src, head):
    """The brace-balanced body after the first match of `head`, or None."""
    m = re.search(head, src)
    if not m:
        return None
    i = src.index("{", m.end() - 1)
    depth = 0
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return src[i:j + 1]
    return None


p = code(panel)

slider = block(p, r"component SliderRow: ConfigSlider\s*")
check(slider is not None, "the slider row must be a ConfigSlider")
if slider:
    check("onMoved:" in slider, "the slider must commit on `moved`")
    check("onValueChanged" not in slider, "the slider must not write on valueChanged "
          "(every frame of the settle animation)")

check("Loader" not in p and "onLoaded" not in p,
      "rows must be built with their data (DelegateChooser), not wired in onLoaded")
check(re.search(r"delegate:\s*DelegateChooser", p), "rows must come from a DelegateChooser")
check(len(re.findall(r"required property var modelData", p)) >= 5,
      "every row type must take `modelData` as a required property")

write = block(p, r"function write\(")
check(write is not None and re.search(r"===\s*value\)\s*return", write),
      "write() must skip a value that is already stored")

spin = block(p, r"ConfigSpinBox\s*")
check(spin is not None, "the int row must be a ConfigSpinBox")
if spin:
    check(re.search(r"value:\s*\{\s*from;\s*to;", spin),
          "the spinbox value must read `from` and `to` so a clamp before the bounds re-runs")
    check(re.search(r"onValueChanged:\s*if\s*\(ready\)", spin)
          and "Component.onCompleted: ready = true" in spin,
          "the spinbox must not write until it has completed")

text = block(p, r"ConfigTextField\s*")
check(text is not None and "onEditingFinished:" in text and "onInputTextChanged" not in text,
      "the text row must commit on editingFinished only")
check(re.search(r"signal editingFinished\(\)", field)
      and "onEditingFinished: root.editingFinished()" in field,
      "ConfigTextField must keep forwarding editingFinished")

rm = re.search(r"ActionButton\s*\{\s*buttonText: root\.confirmRemove[^}]*onClicked:\s*\{(.*?)\n\s{20}\}",
               code(card), re.S)
check(rm is not None, "Remove must be the confirmRemove ActionButton")
if rm:
    body = rm.group(1)
    arm, fire = body.find("root.confirmRemove = true"), body.find("uninstallExtension")
    check(arm != -1 and fire != -1 and arm < fire and "return" in body[arm:fire],
          "the first Remove click must only arm; uninstall only on the second")

if failures:
    print("check-extension-options: FAIL")
    for f in failures:
        print("  -", f)
    sys.exit(1)
print("check-extension-options: ok")
