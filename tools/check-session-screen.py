#!/usr/bin/env python3
"""The session menu leaves visibly, fires only what is lit, and offers nothing this
machine cannot do.

None of this has a symptom a still frame shows.

* The **exit**. `Loader.active` read `GlobalStates.sessionOpen`, and `rules.lua` gives
  the layer `no_anim`, so the surface mapped and unmapped on the frame the flag changed.
  It is latched now: set on the open edge, released by `WindowDialog` once its collapse
  has played. Measured: unmapped ~110-125ms after the close, against the same frame
  before. `active` must not read the intent even as one half of an `||` -- the binding
  and the handler race on one change signal (measured in `check-osk.py`).
* **Enter fires the one lit tile.** Hover painted the same `colPrimary` as focus, so a
  pointer resting where the grid opened showed two selected tiles, with two different
  names in the tooltip and the subtitle. Focus is the selection now, hover only tints,
  and nothing lets hover take focus: the pointer is usually already where the card opens.
* **One activation per open.** The window keeps the keyboard while it leaves, so a
  second Enter would have fired a second action.
* **The arrows stay on their row.** Right from Task Manager must not reach Logout, and
  no direction may land on a disabled tile. Evaluated from the real expression.
* **An action logind refuses is disabled.** `CanHibernate` is `na` on the machine this
  was written on, and the Hibernate tile closed the menu and did nothing. The parse is
  evaluated against real `busctl` output, and every method named must be one logind has.

Run: python3 tools/check-session-screen.py
"""
import re
import sys
from itertools import product
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
II = ROOT / "dots/.config/quickshell/ii"

screen = (II / "modules/ii/sessionScreen/SessionScreen.qml").read_text()
service = (II / "services/SessionWarnings.qml").read_text()
dialog = (II / "modules/common/widgets/WindowDialog.qml").read_text()
rules = (ROOT / "dots/.config/hypr/hyprland/rules.lua").read_text()

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def block(src, head):
    """The brace-balanced body that follows the first match of `head`."""
    m = re.search(head, src)
    if not m:
        return None
    i = src.index("{", m.end() - 1)
    depth = 0
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return src[i + 1:j]
    return None


def code(src):
    return "\n".join(line.split("//")[0] for line in src.splitlines())


src = code(screen)

# ── the latch ────────────────────────────────────────────────────────────────

active = re.search(r"Loader\s*\{\s*active:\s*(.+)$", src, re.M)
check(active and active.group(1).strip() == "root.rendered",
      f"the window's Loader.active must be the latch alone, got "
      f"{active.group(1).strip() if active else None!r}")
check(re.search(r"property bool rendered:\s*false\s*$", src, re.M),
      "`rendered` must start false and be assigned on the edge, never bound")
sets = re.findall(r"root\.rendered\s*=\s*(\w+)", src)
check(sets.count("true") == 1 and sets.count("false") == 1,
      f"`rendered` is set once on the open edge and cleared once by the exit, got {sets}")
opened = block(src, r"function onSessionOpenChanged\(\)\s*\{")
check(opened and "root.rendered = true" in opened and "SessionWarnings.refresh()" in opened,
      "the open edge must latch the window and refresh the warnings and capabilities")
released = block(src, r"onVisibleChanged:\s*\{")
check(released and re.search(r"!visible && !GlobalStates\.sessionOpen", released)
      and "root.rendered = false" in released,
      "only the dialog's collapse may release the window, and only while the intent is off "
      "(a reopen during the exit must not unmap it)")
check("WindowDialog {" in src and not re.search(r"^\s*show:", src, re.M),
      "the surface is a WindowDialog whose `show` is assigned after creation -- bound, "
      "it is already true when the card is built and the enter never plays")
check(re.search(r"visible:\s*dialogBackground\.implicitHeight > 0", code(dialog)),
      "WindowDialog must still hide itself once the card has collapsed -- that is the "
      "only thing that releases the window")
check(re.search(r'namespace = "quickshell:session" \}, no_anim = true', rules),
      "rules.lua must keep `no_anim` on quickshell:session: the shell animates this "
      "surface, and a Hyprland fade on a full-screen layer would run on top of it")

# ── the window fills the screen it is on ─────────────────────────────────────

window = block(src, r"sourceComponent:\s*PanelWindow\s*\{")
check(window and all(re.search(rf"\b{edge}:\s*true", window) for edge in ("top", "bottom", "left", "right")),
      "the window anchors all four edges, so it fills whichever output it maps on")
check("focusedScreen" not in src,
      "`focusedScreen` sized the window from whichever monitor had focus, not its own")

# ── Enter fires the one lit tile ─────────────────────────────────────────────

check(re.search(r"toggled:\s*tile\.activeFocus\s*$", src, re.M),
      "the lit tile must be the focused one -- `toggled: tile.activeFocus`")
check(not re.search(r"colBackgroundHover:\s*Appearance\.colors\.colPrimary\b", src),
      "hover must not paint the focus colour")
for handler in re.finditer(r"on(Hovered|Entered|ContainsMouse)\w*:\s*", src):
    body = src[handler.end():handler.end() + 200]
    check("forceActiveFocus" not in body.split("\n\n")[0],
          "hover must never take focus: a pointer resting where the card opens would "
          "retarget Enter")
run = block(src, r"function run\(action\)\s*\{")
check(run and re.match(r"\s*if \(!GlobalStates\.sessionOpen\)\s*return;", run),
      "run() must refuse once the menu is closing, or a second Enter fires a second action")
keys = block(src, r"Keys\.onPressed:\s*event\s*=>\s*\{")
check(keys and re.search(r"default:\s*return;", keys),
      "the tile's key handler must pass unknown keys on -- Esc belongs to WindowDialog")

# ── the arrows ───────────────────────────────────────────────────────────────

columns = re.search(r"readonly property int columns:\s*(\d+)", src)
check(columns, "the grid's column count must stay one `readonly property int columns`")
columns = int(columns.group(1)) if columns else 0
actions = re.findall(r"^\s*\{ icon: \"(\w+)\", name: Translation\.tr\(\"([^\"]+)\"\)(?:, can: \"(\w+)\")?, run: \(\) => Session\.(\w+)\(\) \},?$", src, re.M)
check(len(actions) == 8, f"expected the eight actions, one `{{ icon, name, can?, run }}` per line, parsed {len(actions)}")

reach = re.search(r"function inReach\(from, to, step\)\s*\{\s*return (.+);\s*\}", src)
check(reach, "inReach() must stay a single return expression, so this can evaluate it")
if reach and columns and actions:
    expr = reach.group(1)
    for js, py in (("root.actions.length", "COUNT"), ("root.columns", "COLUMNS"),
                   ("Math.floor", "floor"), ("Math.abs", "abs"),
                   ("!==", "!="), ("===", "=="), ("&&", " and "), ("||", " or ")):
        expr = expr.replace(js, py)
    in_reach = eval(compile(f"lambda from_, to, step: {expr.replace('from', 'from_')}", "<inReach>", "eval"),
                    {"floor": lambda v: int(v // 1), "COUNT": len(actions), "COLUMNS": columns})

    def move(frm, step, disabled):
        """grid.move(), with the loop as written and the rule lifted."""
        to = frm + step
        while in_reach(frm, to, step):
            if to not in disabled:
                return to
            to += step
        return frm

    steps = {"Left": -1, "Right": 1, "Up": -columns, "Down": columns}
    n = len(actions)
    for mask in product((False, True), repeat=n):
        disabled = {i for i in range(n) if mask[i]}
        for frm in set(range(n)) - disabled:
            for key, step in steps.items():
                to = move(frm, step, disabled)
                check(to not in disabled, f"{key} from {frm} landed on disabled {to}")
                if abs(step) == 1:
                    check(to // columns == frm // columns,
                          f"{key} from {frm} left its row for {to} ({sorted(disabled)} disabled)")
                check(0 <= to < n, f"{key} from {frm} left the grid for {to}")
    check(move(3, 1, set()) == 3, "Right from Task Manager must not reach Logout")
    check(move(1, 1, {2}) == 3, "Right from Sleep must skip a disabled Hibernate")
    check(move(0, 0 + columns, set()) == 4, "Down from Lock is Logout, one row below")

# ── capabilities ─────────────────────────────────────────────────────────────

pattern = re.search(r"line\.match\(/(.+)/\)", service)
check(pattern, "the capability parse must stay one `line.match(/.../)` regex")
if pattern:
    parse = re.compile(pattern.group(1))
    m = parse.match('CanHibernate s "na"')
    check(m and m.groups() == ("CanHibernate", "na"), f"the parse must read busctl's `s \"na\"`, got {m and m.groups()}")
    check(not parse.match("CanHibernate "), "a failed call prints the name alone and must not parse as an answer")

refused = re.search(r"return !\[(.+?)\]\.includes\(root\.capabilities\[method\]\)", service)
check(refused, "can() must stay `![...].includes(capabilities[method])`")
if refused:
    refused = {v.strip().strip('"') for v in refused.group(1).split(",")}
    check(refused == {"no", "na"},
          f"only `no` and `na` refuse -- `challenge` means polkit will ask; got {sorted(refused)}")

queried = re.search(r"for m in ([\w ]+); do", service)
queried = set(queried.group(1).split()) if queried else set()
LOGIND = {"CanPowerOff", "CanReboot", "CanSuspend", "CanHibernate", "CanHybridSleep",
          "CanSuspendThenHibernate", "CanSleep", "CanRebootParameter", "CanRebootToFirmwareSetup",
          "CanRebootToBootLoaderMenu", "CanRebootToBootLoaderEntry"}
check(queried and queried <= LOGIND,
      f"every queried method must be a logind Manager method: {sorted(queried - LOGIND)}")
NEEDS = {"suspend": "CanSuspend", "hibernate": "CanHibernate", "poweroff": "CanPowerOff",
         "reboot": "CanReboot", "rebootToFirmware": "CanRebootToFirmwareSetup"}
for icon, name, can, fn in actions:
    if fn in NEEDS:
        check(can == NEEDS[fn], f"{name} runs Session.{fn}() and must ask logind {NEEDS[fn]}, got {can or None}")
    check(not can or can in queried, f"{name} asks {can}, which the service never queries")
check("enabled: SessionWarnings.can(action.modelData.can)" in src,
      "each tile must be enabled from logind's answer")

if failures:
    print("check-session-screen: FAIL")
    for f in failures:
        print("  -", f)
    sys.exit(1)
print("check-session-screen: ok")
