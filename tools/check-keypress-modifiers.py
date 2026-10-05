#!/usr/bin/env python3
"""Assert a released Ctrl stops turning keys into shortcuts in the keystroke overlay.

The reader feeds every evdev key event into an xkb state to know which modifiers
are down. xkb refcounts a modifier once per key-down, and the kernel auto-repeats
a held Ctrl, so passing each repeat in as another down left Ctrl latched after its
single release: every word typed after one slow Ctrl+F showed as `Ctrl+h`,
`Ctrl+e`, ... Same for one press reported by two devices. Drives the real
`Translator` through that sequence. Needs python-evdev and python-xkbcommon.
"""
import pathlib, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent
                       / "dots/.config/quickshell/ii/scripts/videos"))
from keypress_monitor import Translator, xkb  # noqa: E402
from evdev import ecodes  # noqa: E402

assert xkb is not None, "python-xkbcommon missing; cannot check"
t = Translator("us", "", "")
CTRL = ecodes.KEY_LEFTCTRL

t.update(CTRL, True)
for _ in range(20):  # auto-repeat while held, and a second device's copy
    t.update(CTRL, True)
assert t.active_modifiers() == ["Ctrl"], t.active_modifiers()
t.update(CTRL, False)
assert t.active_modifiers() == [], f"Ctrl latched after release: {t.active_modifiers()}"

t.update(ecodes.KEY_H, True)
assert t.label(ecodes.KEY_H, False) == "h"
print("ok: Ctrl released after auto-repeat; next key is plain text")
