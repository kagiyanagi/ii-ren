#!/usr/bin/env python3
"""The Hermes sidebar's desktop fast path cannot fire on the wrong thing.

`scripts/hermes/desktop.py` answers a request without consulting a model, so
nothing downstream will catch a mistake it makes: the wrong IPC call just runs.
None of what follows has a symptom you can see in a screenshot.

  * The router is timid on purpose. Questions, compound requests and anything
    long must escalate to the agent. A wrong instant answer is worse than a
    slow right one, and "toggle the bar" vs "toggle the right sidebar" differ
    by a substring.
  * Every action it can emit has to be an IPC target and function the shell
    actually declares. `ipc show` needs a running shell, so this reads the
    IpcHandler blocks out of the QML instead.
  * `hyprctl dispatch <word>` is a Lua syntax error in this config and the
    agent rediscovered that twice in one session. Nothing here may emit it.
  * OCR coordinates must be scaled by what grim actually wrote, not by an
    assumed 1:1 -- a fractional-scale output would otherwise put every click
    off by that factor, consistently and silently.
  * `see`/`click` must refuse a window that is not on screen. grim captures the
    screen, not a window, so reading one parked on another workspace returns
    whatever is displayed at those coordinates and the click lands there. The
    first version of this script shipped without that guard and OCR'd the
    wrong window on the first try.
"""
import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
QS = ROOT / "dots/.config/quickshell/ii"
SCRIPT = QS / "scripts/hermes/desktop.py"
GATEWAY = QS / "scripts/hermes/gateway.sh"
SERVICE = QS / "services/HermesService.qml"

spec = importlib.util.spec_from_file_location("desktop_ctl", SCRIPT)
D = importlib.util.module_from_spec(spec)
spec.loader.exec_module(D)


# ── 1. the router's accuracy contract ────────────────────────────────────────

MUST_ROUTE = [
    ("toggle the right sidebar", "sidebarRight.toggle"),
    ("open the right sidebar", "sidebarRight.open"),
    ("close right sidebar", "sidebarRight.close"),
    ("hide the left sidebar", "sidebarLeft.close"),
    ("show the left panel", "sidebarLeft.open"),
    # "sidebar" contains "bar": these four are the whole reason PANELS is ordered.
    ("toggle the bar", "bar.toggle"),
    ("hide the bar", "bar.close"),
    ("show bar", "bar.open"),
    ("can you toggle the bar", "bar.toggle"),
    ("please toggle the right sidebar", "sidebarRight.toggle"),
    ("switch to workspace 5", "workspace 5"),
    ("go to workspace 10", "workspace 10"),
    ("workspace 7", "workspace 7"),
    ("next workspace", "workspace r+1"),
    ("previous workspace", "workspace r-1"),
    ("volume up", "audio.incrementVolume"),
    ("turn the volume down", "audio.decrementVolume"),
    ("set volume to 40%", "audio.setVolume(0.4)"),
    ("set the volume to 100", "audio.setVolume(1.0)"),
    ("mute", "audio.toggleMute"),
    ("mute the mic", "audio.toggleMicMute"),
    ("brightness up", "brightness.increment"),
    ("dimmer", "brightness.decrement"),
    ("play", "mpris.playPause"),
    ("next song", "mpris.next"),
    ("pause all", "mpris.pauseAll"),
    ("take a screenshot", "region.screenshot"),
    ("ocr", "region.ocr"),
    ("lock the screen", "lock.activate"),
    ("toggle the theme", "theme.toggleLightDark"),
    ("random wallpaper", "wallpaperSelector.random"),
    ("open the on-screen keyboard", "osk.open"),
    ("show the cheatsheet", "cheatsheet.open"),
    ("toggle clipboard history", "search.clipboardToggle"),
    ("cycle panel style", "panelFamily.cycle"),
    ("open the launcher", "search.open"),
    ("toggle the desktop menu", "desktopMenu.toggle"),
]

MUST_ESCALATE = [
    # Questions about the desktop, not commands to it.
    "what's on my bar?",
    "how do I open the right sidebar",
    "why is the volume so low",
    "is the bar hidden",
    "which workspace am I on",
    # Two actions: running only the first is worse than running neither.
    "open the right sidebar and then mute",
    "take a screenshot then send it to my brother",
    "mute and lock the screen",
    # A rule to remember, not an action to take.
    "mute the volume whenever I open a game",
    "every morning switch to workspace 1",
    # Real work that merely mentions a catalogue word.
    "open chess.com in my browser start a match with a bot and win it for me",
    "write a script that toggles the bar every hour",
    "search for the best volume settings",
    "set the volume to whatever you think is best",
    # Ambiguous: sidebar.position makes "the sidebar" either side.
    "toggle the sidebar",
]

for text, want in MUST_ROUTE:
    hit = D.resolve(text)
    assert hit is not None, f"router should have handled {text!r}, escalated instead"
    assert hit[1] == want, f"{text!r} routed to {hit[1]!r}, expected {want!r}"

for text in MUST_ESCALATE:
    hit = D.resolve(text)
    assert hit is None, f"router fired {hit[1]!r} on {text!r} -- it must escalate"

assert D.resolve("") is None and D.resolve("   ") is None, "empty input must escalate"
assert D.MAX_WORDS <= 12, "a long request is a task, not a catalogue entry"

# The escalation guard is defence in depth. Every catalogue pattern is anchored
# today, so no phrase above actually reaches it -- which is precisely why it is
# tested directly here. The day somebody adds one loose pattern, this guard is
# the only thing between a question about the bar and the bar being toggled.
assert D._STOP.search("what's on my bar?"), "a question must trip the guard"
assert D._STOP.search("toggle the bar and then mute"), "a compound request must trip it"
assert D._STOP.search("mute whenever I open a game"), "a standing rule must trip it"
assert not D._STOP.search("toggle the bar"), "a plain imperative must pass"

_loose = (re.compile(r".*\bbar\b.*", re.I), lambda m: (["true"], "loose.probe"))
D.ROUTES.insert(0, _loose)
try:
    assert D.resolve("toggle the bar") is not None, "probe pattern did not fire"
    for text in ("what's on my bar?",
                 "toggle the bar and then mute",
                 "toggle the bar whenever I open a game",
                 "please could you toggle the bar for me on workspace three today"):
        assert D.resolve(text) is None, \
            f"the escalation guard no longer gates resolve(): {text!r} fired"
finally:
    D.ROUTES.remove(_loose)


# ── 2. every emitted action is real ──────────────────────────────────────────

def declared_ipc():
    """{target: {functions}} from the IpcHandler blocks in the QML sources."""
    found = {}
    for qml in QS.rglob("*.qml"):
        text = qml.read_text(errors="ignore")
        for block in re.finditer(r"IpcHandler\s*\{", text):
            # Brace-match the handler body rather than guessing where it ends.
            i = text.index("{", block.start())
            depth, j = 0, i
            while j < len(text):
                if text[j] == "{":
                    depth += 1
                elif text[j] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            body = text[i:j]
            m = re.search(r'target\s*:\s*"([^"]+)"', body)
            if not m:
                continue
            fns = set(re.findall(r"function\s+(\w+)\s*\(", body))
            found.setdefault(m.group(1), set()).update(fns)
    return found


IPC = declared_ipc()
assert IPC, "found no IpcHandler blocks -- the parser broke, not the shell"

emitted = [D.resolve(t)[0] for t, _ in MUST_ROUTE]
for argv in emitted:
    if argv[0] == "qs":
        assert argv[1:4] == ["-p", D.SHELL, "ipc"], f"unexpected qs invocation: {argv}"
        target, fn = argv[4 + 1], argv[4 + 2]
        assert target in IPC, f"IPC target {target!r} is not declared in any QML"
        assert fn in IPC[target], \
            f"{target}.{fn} is not declared; {target} has {sorted(IPC[target])}"
    elif argv[0] == "hyprctl":
        assert argv[1] == "dispatch", f"unexpected hyprctl use: {argv}"
        # The Lua gotcha: `hyprctl dispatch workspace 1` raises a Lua syntax
        # error here. Every dispatch has to be an hl.* expression.
        assert argv[2].startswith("hl."), \
            f"plain hyprlang dispatch {argv[2]!r} -- this config needs hl.dsp.*"
        assert argv[2].count("(") == argv[2].count(")"), f"unbalanced Lua: {argv[2]}"
    else:
        raise AssertionError(f"catalogue emitted an unknown binary: {argv[0]}")

# setVolume is 0..1 (services/Audio.qml clamps to maxAllowed), not a percentage.
vol = D.resolve("set volume to 40%")[0]
assert vol[-1] == "0.4", f"setVolume should send 0.4, sends {vol[-1]!r}"
assert D.resolve("set the volume to 300") is None or \
    float(D.resolve("set the volume to 300")[0][-1]) <= 1.0, "volume must clamp to 1.0"


# ── 3. the source guards that have no visible symptom ────────────────────────

src = SCRIPT.read_text()

assert "def is_visible" in src, "the off-screen window guard is gone"
assert re.search(r"if not is_visible\(win\)", src), \
    "is_visible is defined but nothing calls it -- see/click would OCR the wrong window"
assert "activeWorkspace" in src, "visibility must compare against the monitor's active workspace"

assert re.search(r"scale\s*=\s*\(?pw\s*/\s*w", src), \
    "OCR scale must be measured from the PNG grim wrote, not assumed 1:1"
assert "/ scale" in src, "word boxes must be divided back into logical coordinates"

assert "--absolute" in src, "ydotool mousemove needs --absolute for screen coordinates"
assert "xdotool" not in src, "xdotool does not work on Wayland"

# The catalogue may not grow a plain hyprlang dispatch by hand either.
for bad in re.finditer(r'hypr\(\s*[fr]?["\']([^"\']+)', src):
    assert bad.group(1).startswith("hl."), \
        f"hypr() called with plain hyprlang {bad.group(1)!r}"


# ── 4. the sidebar wiring cannot swallow a message ───────────────────────────

qml = SERVICE.read_text()

assert "_tryRoute" in qml and "_sendOrDefer" in qml, "the fast path is not wired in"
assert re.search(r'command\s*=\s*\["timeout"', qml), \
    "the router must run under `timeout` -- a wedged helper would eat the message"
# Two settle paths, because neither alone is enough: onStreamFinished is the
# only point where the output is complete, and a helper that never starts
# produces no stream at all -- that message would hang forever.
assert "onStreamFinished: root._finishRoute" in qml, \
    "the routed result must be read where the output is known to be complete"
assert re.search(r"onExited:\s*Qt\.callLater\(\(\)\s*=>\s*root\._finishRoute", qml), \
    "process exit must settle the message too, or a helper that never starts eats it"

settle = qml[qml.index("function _finishRoute"):]
settle = settle[:settle.index("\n    }")]
assert "_sendOrDefer(text)" in settle, "a non-routed message must still reach the agent"
assert "routed === true" in settle and "ok === true" in settle, \
    "only a confirmed, successful route may replace the agent's turn"
assert '_routingText = ""' in settle, \
    "the guard that makes the second settle path a no-op is gone -- one message, two sends"
assert "scripts/hermes/desktop.py" in qml, "the service must point at the helper"


# ── 5. the toolset pin stays in sync ─────────────────────────────────────────

gw = GATEWAY.read_text()
m = re.search(r'HERMES_TUI_TOOLSETS:=([a-z_,0-9]+)', gw)
assert m, "gateway.sh no longer pins HERMES_TUI_TOOLSETS"
pinned = m.group(1).split(",")
assert "computer_use" not in pinned, \
    "computer_use is back in the sidebar's toolsets; cua-driver is X11-only and " \
    "reports zero windows under Hyprland"
assert "export HERMES_TUI_TOOLSETS" in gw, "the pin is set but never exported"

# ── 6. the skill descriptions actually survive parsing ───────────────────────
#
# A skill's description is the only part of it that is always in the prompt, so
# it is where this machine's gotchas live. A plain YAML scalar containing ": "
# is a scanner error, which silently yields an EMPTY description rather than a
# loud failure: the skill still lists, the agent just gets no hint and goes back
# to rediscovering the Lua dispatch syntax. That is exactly what shipped here
# once. Nothing about it is visible.
skills = pathlib.Path.home() / ".hermes/skills/desktop"
if skills.is_dir():
    try:
        import yaml
    except ImportError:
        yaml = None
    for skill in sorted(skills.glob("*/SKILL.md")):
        parts = skill.read_text().split("---")
        assert len(parts) >= 3, f"{skill.parent.name}: no YAML frontmatter"
        if yaml is None:
            continue
        try:
            fm = yaml.safe_load(parts[1])
        except Exception as exc:                       # noqa: BLE001
            raise AssertionError(
                f"{skill.parent.name}: frontmatter is not valid YAML ({exc}). "
                'A description containing ": " must be quoted.') from exc
        desc = (fm or {}).get("description") or ""
        assert desc.strip(), \
            f"{skill.parent.name}: description is empty -- the always-loaded hint is gone"
        assert ": " not in desc or (parts[1].count('description: "') == 1), \
            f"{skill.parent.name}: unquoted colon-space in the description"
    # The two facts that cost the agent the most time must stay in the text that
    # is always loaded, not only in the body it has to open the skill to read.
    hypr = (skills / "hyprland-apps/SKILL.md")
    if hypr.exists() and yaml is not None:
        d = (yaml.safe_load(hypr.read_text().split("---")[1]) or {}).get("description", "")
        assert "Lua" in d, "the Lua dispatch gotcha left the always-loaded description"
        assert "computer_use" in d, "the dead computer_use warning left the description"
        assert "desktop.py" in d, "the helper is no longer named in the description"


config = pathlib.Path.home() / ".hermes/config.yaml"
if config.exists():
    text = config.read_text()
    block = re.search(r"^platform_toolsets:\s*\n\s+cli:\s*\n((?:\s+-\s+\S+\n)+)",
                      text, re.M)
    if block:
        cli = re.findall(r"-\s+(\S+)", block.group(1))
        want = [t for t in cli if t != "computer_use"]
        assert pinned == want, (
            "gateway.sh's toolset pin has drifted from config.yaml.\n"
            f"  config (minus computer_use): {want}\n"
            f"  gateway.sh:                  {pinned}")

print(f"OK  router: {len(MUST_ROUTE)} routed, {len(MUST_ESCALATE)} escalated, "
      f"{len(IPC)} IPC targets verified")
