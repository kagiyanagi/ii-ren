#!/usr/bin/env python3
"""The SDDM theme's Settings.qml generator cannot emit a type QML refuses.

`generate_settings.py` flattens ~/.config/illogical-impulse/config.json into a
QML singleton, and every consumer of the theme -- Colors, Appearance,
CVKeyboard, the login interface -- resolves through it. One bad property
declaration makes the singleton unavailable, every type above it unavailable
in turn, and SDDM silently falls back to its embedded theme. There is no
error on screen: you just get a different login screen.

It shipped that way. `bluetooth.fastPair.mutedUntil` is an epoch-ms timestamp
and the generator declared it `property int`, but QML's int is 32-bit signed,
so any millisecond timestamp since 1970 overflows it. The shell's own
Config.qml declares that field `real`; the generator only saw a Python int.
matugen re-runs the generator on every colour change, so the greeter broke on
a wallpaper switch, hours away from anyone touching SDDM.
"""
import importlib.util
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GEN = REPO / "dots/.config/ii-sddm-theme/generate_settings.py"

INT32_MIN, INT32_MAX = -2**31, 2**31 - 1

spec = importlib.util.spec_from_file_location("gen_settings", GEN)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

# --- the type mapping itself ---

# bool is a subclass of int in Python; the bool branch must stay first.
assert gen.get_qml_type(True) == "bool", "bool must not be typed as a number"
assert gen.get_qml_type(False) == "bool"

assert gen.get_qml_type(0) == "int"
assert gen.get_qml_type(-65) == "int", "rssiThreshold is negative and small"
assert gen.get_qml_type(INT32_MAX) == "int", "the last value int can hold"
assert gen.get_qml_type(INT32_MIN) == "int"

# Anything wider than int32 must widen to real (a double: exact to 2^53).
assert gen.get_qml_type(INT32_MAX + 1) == "real", "int32 overflows one past the max"
assert gen.get_qml_type(INT32_MIN - 1) == "real"
assert gen.get_qml_type(1789999699259) == "real", "epoch ms, the value that broke it"
assert gen.get_qml_type(2**53) == "real"

assert gen.get_qml_type(1.5) == "real"
assert gen.get_qml_type("x") == "string"
assert gen.get_qml_type(None) == "var"

# --- the generated declaration ---

qml, count = gen.generate_qml_content({
    "bluetooth": {"fastPair": {"mutedUntil": 1789999699259, "rssiThreshold": -65, "enable": False}},
    "appearance": {"transparency": 0.4, "theme": "Mocha"},
    "bar": {"layouts": ["clock", "tray"]},
})
assert count == 6, count
assert "property real bluetooth_fastPair_mutedUntil: 1789999699259" in qml
assert "property int bluetooth_fastPair_rssiThreshold: -65" in qml
assert "property bool bluetooth_fastPair_enable: false" in qml

# Every int declaration in any generated output must hold its own literal.
DECL = re.compile(r"^\s*property (\w+) (\w+): (-?\d+)$", re.M)
def sweep(text, where):
    for qml_type, name, literal in DECL.findall(text):
        if qml_type != "int":
            continue
        value = int(literal)
        assert INT32_MIN <= value <= INT32_MAX, f"{where}: {name} = {value} overflows QML int"

sweep(qml, "synthetic")

# The live config is the one that actually reaches the greeter, when present.
live = Path.home() / ".config/illogical-impulse/config.json"
if live.exists():
    sweep(gen.generate_qml_content(json.loads(live.read_text()))[0], str(live))

print("check-sddm-settings-gen: ok")
