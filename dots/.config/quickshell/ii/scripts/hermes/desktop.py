#!/usr/bin/env python3
"""Deterministic desktop control for the Hermes sidebar -- no model is consulted.

Three things the agent was paying a model round trip for, done locally:

  route / do  A catalogue of verified shell actions, matched with regexes.
              "toggle the right sidebar" resolves in ~50ms here against ~6s for
              one agent step, and it cannot pick the wrong IPC call.
  see         Window geometry from hyprctl plus OCR word boxes from tesseract,
              in absolute screen pixels. This replaces screenshot -> vision
              prose -> guess-the-pixel, which missed twice in a row on
              2026-09-21 and cost ~30s per guess.
  click       see + label match + ydotool, so pressing a named button is one
              call instead of two model steps.

`route` is deliberately timid: anything that is a question, names two actions,
or runs long escalates to the agent rather than guessing. A wrong fast answer
costs more than a slow right one.
"""
import difflib
import json
import os
import re
import struct
import subprocess
import sys
import tempfile

SHELL = os.path.expanduser("~/.config/quickshell/ii/shell.qml")


def sh(argv, timeout=20):
    """Run argv; return (rc, stdout, stderr) with output decoded."""
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def qs(target, fn, *args):
    return ["qs", "-p", SHELL, "ipc", "call", target, fn, *[str(a) for a in args]]


def hypr(lua):
    # `hyprctl dispatch <cmd>` is Lua here, not hyprlang: this config routes
    # dispatch through hl.*, so the documented `hyprctl dispatch workspace 1`
    # raises a Lua syntax error. Same form modules/ii/lock/Lock.qml uses.
    return ["hyprctl", "dispatch", lua]


# ── the catalogue ────────────────────────────────────────────────────────────
#
# Every entry is an IPC call `qs -p shell.qml ipc show` actually lists, or a
# hyprctl dispatch. Keep it that way: the check script asserts each target and
# function still exists in the running shell.

VERB = r"(?P<verb>open|show|bring up|pull up|close|hide|dismiss|toggle|flip)?"
_OPEN = {"open", "show", "bring up", "pull up"}
_CLOSE = {"close", "hide", "dismiss"}


def _verb(m, default="toggle"):
    v = (m.groupdict().get("verb") or "").strip().lower()
    if v in _OPEN:
        return "open"
    if v in _CLOSE:
        return "close"
    return default


# Panels that implement open/close/toggle. Order matters: "sidebar" contains
# "bar", so the sidebars have to match first and `bar` excludes them.
PANELS = [
    ("sidebarRight", r"right\s*side\s*bar|right\s*panel"),
    ("sidebarLeft", r"left\s*side\s*bar|left\s*panel|policies\s*panel"),
    ("osk", r"on.?screen\s*keyboard|virtual\s*keyboard|\bosk\b"),
    ("session", r"(?:session|power|logout|shutdown)\s*menu"),
    ("cheatsheet", r"cheat\s*sheet|keybinds?\b|shortcuts?\b"),
    ("mediaControls", r"media\s*controls?"),
    ("search", r"(?:app\s*)?(?:search|launcher)\b"),
    ("immersiveMedia", r"immersive\s*(?:media|player)|full\s*screen\s*player"),
    ("bar", r"(?<!side)\bbar\b"),
]

ROUTES = []


def route(pattern, fn, flags=re.I):
    ROUTES.append((re.compile(pattern, flags), fn))


for _target, _pat in PANELS:
    route(rf"^{VERB}\s*(?:the\s+)?(?:{_pat})$",
          lambda m, t=_target: (qs(t, _verb(m)), f"{t}.{_verb(m)}"))

route(rf"^{VERB}\s*(?:the\s+)?(?:desktop|right.?click)\s*menu$",
      lambda m: (qs("desktopMenu", "toggle"), "desktopMenu.toggle"))
route(rf"^{VERB}\s*(?:the\s+)?(?:wallpaper\s*(?:selector|picker|gallery))$",
      lambda m: (qs("wallpaperSelector", "toggle"), "wallpaperSelector.toggle"))
route(r"^(?:set\s+)?(?:a\s+)?random\s*wallpaper$|^change\s+(?:the\s+)?wallpaper$",
      lambda m: (qs("wallpaperSelector", "random"), "wallpaperSelector.random"))
route(rf"^{VERB}\s*(?:the\s+)?clipboard(?:\s*history)?$",
      lambda m: (qs("search", "clipboardToggle"), "search.clipboardToggle"))

# Theme / appearance
route(r"^(?:toggle|switch|flip)\s*(?:the\s*)?(?:theme|dark\s*mode|light\s*mode)$"
      r"|^(?:dark|light)\s*mode\s*toggle$",
      lambda m: (qs("theme", "toggleLightDark"), "theme.toggleLightDark"))
route(r"^(?:cycle|switch|change)\s*(?:the\s*)?panel\s*(?:family|style)$",
      lambda m: (qs("panelFamily", "cycle"), "panelFamily.cycle"))

# Audio. setVolume takes 0..1 (services/Audio.qml clamps to maxAllowed).
route(r"^(?:set\s*)?(?:the\s*)?volume\s*(?:to|=|at)\s*(?P<n>\d{1,3})\s*%?$",
      lambda m: (qs("audio", "setVolume", min(100, int(m.group("n"))) / 100.0),
                 f"audio.setVolume({min(100, int(m.group('n'))) / 100.0})"))
route(r"^(?:turn\s*)?(?:the\s*)?volume\s*(?:up|louder)$|^louder$|^volume\s*up$",
      lambda m: (qs("audio", "incrementVolume"), "audio.incrementVolume"))
route(r"^(?:turn\s*)?(?:the\s*)?volume\s*(?:down|lower)$|^quieter$|^volume\s*down$",
      lambda m: (qs("audio", "decrementVolume"), "audio.decrementVolume"))
route(r"^(?:toggle\s*)?mute$|^(?:un)?mute\s*(?:the\s*)?(?:volume|audio|sound)$",
      lambda m: (qs("audio", "toggleMute"), "audio.toggleMute"))
route(r"^(?:toggle\s*)?(?:mic|microphone)\s*mute$|^mute\s*(?:the\s*)?(?:mic|microphone)$",
      lambda m: (qs("audio", "toggleMicMute"), "audio.toggleMicMute"))

# Brightness
route(r"^(?:turn\s*)?(?:the\s*)?(?:brightness|screen)\s*up$|^brighter$|^brightness\s*up$",
      lambda m: (qs("brightness", "increment"), "brightness.increment"))
route(r"^(?:turn\s*)?(?:the\s*)?(?:brightness|screen)\s*down$|^dimmer$|^brightness\s*down$",
      lambda m: (qs("brightness", "decrement"), "brightness.decrement"))

# Media
route(r"^(?:play|pause|play\s*/?\s*pause|resume)(?:\s*(?:the\s*)?(?:music|media|song|video))?$",
      lambda m: (qs("mpris", "playPause"), "mpris.playPause"))
route(r"^(?:next|skip)(?:\s*(?:the\s*)?(?:song|track|video))?$",
      lambda m: (qs("mpris", "next"), "mpris.next"))
route(r"^(?:previous|prev|back)(?:\s*(?:the\s*)?(?:song|track|video))?$",
      lambda m: (qs("mpris", "previous"), "mpris.previous"))
route(r"^(?:pause|stop)\s*(?:all|everything)$",
      lambda m: (qs("mpris", "pauseAll"), "mpris.pauseAll"))

# Capture
route(r"^(?:take\s*a\s*)?screenshot$|^(?:snip|capture)(?:\s*the\s*screen)?$",
      lambda m: (qs("region", "screenshot"), "region.screenshot"))
route(r"^ocr$|^(?:read|copy)\s*text\s*(?:from\s*)?(?:the\s*)?screen$",
      lambda m: (qs("region", "ocr"), "region.ocr"))
route(r"^(?:start\s*)?(?:a\s*)?(?:screen\s*)?record(?:ing)?$",
      lambda m: (qs("region", "record"), "region.record"))
route(r"^(?:scan\s*)?(?:a\s*)?qr(?:\s*code)?$",
      lambda m: (qs("region", "qrScan"), "region.qrScan"))

# Session
route(r"^lock(?:\s*(?:the\s*)?(?:screen|session))?$",
      lambda m: (qs("lock", "activate"), "lock.activate"))

# Workspaces
route(r"^(?:go\s*to|switch\s*to|move\s*to|focus)\s*(?:workspace|ws|desktop)\s*(?P<n>\d{1,2})$"
      r"|^workspace\s*(?P<n2>\d{1,2})$",
      lambda m: (hypr(f"hl.dsp.focus({{workspace={m.group('n') or m.group('n2')}}})"),
                 f"workspace {m.group('n') or m.group('n2')}"))
route(r"^(?:go\s*to\s*)?(?:the\s*)?next\s*workspace$",
      lambda m: (hypr('hl.dsp.focus({workspace="r+1"})'), "workspace r+1"))
route(r"^(?:go\s*to\s*)?(?:the\s*)?(?:previous|prev|last)\s*workspace$",
      lambda m: (hypr('hl.dsp.focus({workspace="r-1"})'), "workspace r-1"))


# ── routing ──────────────────────────────────────────────────────────────────

# Escalate rather than guess. A wrong instant answer is worse than a slow right
# one, so anything conversational, compound or long goes to the agent.
_STOP = re.compile(
    r"\?$"                                  # a question
    r"|^(?:what|why|how|who|when|where|which|can|could|would|should|is|are|do|does|did)\b"
    r"|\b(?:and then|then|after that|also|as well as)\b"   # compound
    r"|\b(?:every|whenever|each time|if )\b",              # conditional / rule
    re.I)
MAX_WORDS = 10


def resolve(text):
    """(argv, label) for a catalogue hit, or None to escalate to the agent."""
    t = " ".join((text or "").strip().split())
    t = re.sub(r"^(?:please|hey|ok|okay|now|could you|can you|pls)\s+", "", t, flags=re.I)
    t = re.sub(r"\s*(?:please|for me|thanks|thank you)\s*$", "", t, flags=re.I)
    t = t.rstrip(".!").strip()
    if not t or len(t.split()) > MAX_WORDS or _STOP.search(t):
        return None
    for pattern, fn in ROUTES:
        m = pattern.match(t)
        if m:
            return fn(m)
    return None


# ── perception ───────────────────────────────────────────────────────────────

def clients():
    rc, out, _ = sh(["hyprctl", "clients", "-j"])
    return json.loads(out) if rc == 0 else []


def pick_window(want_class=None, want_title=None, addr=None):
    """One window from hyprctl, or None. Mapped windows only."""
    cs = [c for c in clients() if c.get("mapped")]
    if addr:
        return next((c for c in cs if c.get("address") == addr), None)
    if want_class:
        w = want_class.lower()
        hit = [c for c in cs if w in (c.get("class") or "").lower()]
        if hit:
            return max(hit, key=lambda c: c["size"][0] * c["size"][1])
    if want_title:
        w = want_title.lower()
        hit = [c for c in cs if w in (c.get("title") or "").lower()]
        if hit:
            return max(hit, key=lambda c: c["size"][0] * c["size"][1])
    if want_class or want_title:
        return None
    rc, out, _ = sh(["hyprctl", "activewindow", "-j"])
    try:
        a = json.loads(out)
        return a if a.get("address") else None
    except (ValueError, AttributeError):
        return None


def _png_size(path):
    """(width, height) from the IHDR -- avoids importing PIL for 8 bytes."""
    with open(path, "rb") as fh:
        head = fh.read(24)
    return struct.unpack(">II", head[16:24])


def ocr_words(rect, psm="11", min_conf=55):
    """OCR one screen rect. Returns words with centres in absolute screen px.

    grim takes logical coordinates and writes physical pixels, so the scale is
    measured from the PNG rather than assumed -- a fractional-scale output would
    otherwise land every click off by that factor.
    """
    x, y, w, h = rect
    with tempfile.TemporaryDirectory() as tmp:
        png = os.path.join(tmp, "cap.png")
        rc, _, err = sh(["grim", "-g", f"{x},{y} {w}x{h}", png])
        if rc != 0:
            raise RuntimeError(f"grim failed: {err}")
        pw, _ph = _png_size(png)
        scale = (pw / w) if w else 1.0
        # psm 11 (sparse text) is the UI case: isolated button labels, ~0.9s on
        # a 1920x1080 window. A text-dense window (a full terminal) costs ~8s.
        rc, out, err = sh(["tesseract", png, "-", "--psm", psm, "tsv"], timeout=60)
        if rc != 0:
            raise RuntimeError(f"tesseract failed: {err}")
    words = []
    for line in out.splitlines()[1:]:
        f = line.split("\t")
        if len(f) < 12:
            continue
        text = f[11].strip()
        try:
            conf = float(f[10])
        except ValueError:
            continue
        if not text or conf < min_conf:
            continue
        left, top, bw, bh = (int(f[6]), int(f[7]), int(f[8]), int(f[9]))
        words.append({
            "text": text, "conf": round(conf),
            "line": (int(f[2]), int(f[3]), int(f[4])),
            "x": round(x + (left + bw / 2) / scale),
            "y": round(y + (top + bh / 2) / scale),
            "box": [round(x + left / scale), round(y + top / scale),
                    round(bw / scale), round(bh / scale)],
        })
    return words


def find_label(words, label):
    """Best match for `label`, spanning adjacent words on one OCR line."""
    want = " ".join(label.lower().split())
    lines = {}
    for w in words:
        lines.setdefault(w["line"], []).append(w)
    cands = []
    for group in lines.values():
        group.sort(key=lambda w: w["box"][0])
        n = len(want.split())
        for i in range(len(group)):
            for span in range(1, min(n + 2, len(group) - i + 1)):
                chunk = group[i:i + span]
                phrase = " ".join(c["text"] for c in chunk).lower().strip(":.,")
                score = difflib.SequenceMatcher(None, want, phrase).ratio()
                if want in phrase:
                    score = max(score, 0.95)
                if score >= 0.72:
                    x0 = min(c["box"][0] for c in chunk)
                    y0 = min(c["box"][1] for c in chunk)
                    x1 = max(c["box"][0] + c["box"][2] for c in chunk)
                    y1 = max(c["box"][1] + c["box"][3] for c in chunk)
                    cands.append({
                        "text": " ".join(c["text"] for c in chunk),
                        "score": round(score, 3),
                        "conf": min(c["conf"] for c in chunk),
                        "x": round((x0 + x1) / 2), "y": round((y0 + y1) / 2),
                        "box": [x0, y0, x1 - x0, y1 - y0],
                    })
    cands.sort(key=lambda c: (-c["score"], -c["conf"]))
    return cands


def do_click(x, y, button="0xC0", dry=False):
    """Move and click through ydotool (uinput), which Wayland accepts."""
    if dry:
        return {"moved": False, "x": x, "y": y, "dry_run": True}
    rc, _, err = sh(["ydotool", "mousemove", "--absolute", "-x", str(x), "-y", str(y)])
    if rc != 0:
        raise RuntimeError(f"ydotool mousemove failed: {err}")
    rc, _, err = sh(["ydotool", "click", button])
    if rc != 0:
        raise RuntimeError(f"ydotool click failed: {err}")
    return {"clicked": True, "x": x, "y": y}


# ── cli ──────────────────────────────────────────────────────────────────────

def _rect_of(win):
    return (win["at"][0], win["at"][1], win["size"][0], win["size"][1])


def is_visible(win):
    """True when this window is what is actually on screen at its own rect.

    grim captures the screen, not a window, so OCR of a window parked on an
    inactive workspace silently returns whatever IS displayed at those
    coordinates -- and the click then lands on that. Nothing about the result
    looks wrong; this is the check that makes it wrong loudly.
    """
    if win.get("hidden"):
        return False
    rc, out, _ = sh(["hyprctl", "monitors", "-j"])
    if rc != 0:
        return False
    mon = next((m for m in json.loads(out) if m.get("id") == win.get("monitor")), None)
    return bool(mon) and (mon.get("activeWorkspace") or {}).get("id") == \
        (win.get("workspace") or {}).get("id")


def focus_window(win):
    rc, _, err = sh(hypr(f'hl.dsp.focus({{workspace={(win.get("workspace") or {}).get("id")}}})'))
    if rc != 0:
        raise RuntimeError(f"could not focus workspace: {err}")
    sh(["hyprctl", "dispatch", f'hl.dsp.focus({{address="{win.get("address")}"}})'])


def _target_window(args):
    win = pick_window(want_class=args.get("class"), want_title=args.get("title"),
                      addr=args.get("addr"))
    if win is None:
        raise SystemExit(json.dumps({"error": "no matching mapped window",
                                     "hint": "desktop.py windows"}))
    if not is_visible(win):
        if not args.get("focus"):
            raise SystemExit(json.dumps({
                "error": "target window is not on screen",
                "window": win.get("title"), "class": win.get("class"),
                "workspace": (win.get("workspace") or {}).get("id"),
                "hint": "pass --focus to switch to it first; reading it now would "
                        "capture whatever is displayed at those coordinates instead",
            }))
        focus_window(win)
        win = pick_window(addr=win.get("address")) or win
        if not is_visible(win):
            raise SystemExit(json.dumps({"error": "window still not on screen after focus",
                                         "window": win.get("title")}))
    return win


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip())
        return 1
    cmd, rest = argv[1], argv[2:]
    args, free = {}, []
    i = 0
    while i < len(rest):
        if rest[i].startswith("--"):
            key = rest[i][2:]
            if key in ("dry-run", "json", "focus"):
                args[key] = True
                i += 1
            else:
                args[key] = rest[i + 1] if i + 1 < len(rest) else ""
                i += 2
        else:
            free.append(rest[i])
            i += 1
    text = " ".join(free)

    if cmd == "route":
        hit = resolve(text)
        if hit is None:
            print(json.dumps({"routed": False}))
            return 2
        argvv, label = hit
        print(json.dumps({"routed": True, "action": label, "argv": argvv}))
        return 0

    if cmd == "do":
        hit = resolve(text)
        if hit is None:
            print(json.dumps({"routed": False}))
            return 2
        argvv, label = hit
        rc, out, err = sh(argvv)
        print(json.dumps({"routed": True, "action": label, "ok": rc == 0,
                          "output": out or err}))
        return 0 if rc == 0 else 1

    if cmd == "windows":
        print(json.dumps([{
            "address": c.get("address"), "class": c.get("class"),
            "title": c.get("title"), "workspace": (c.get("workspace") or {}).get("id"),
            "at": c.get("at"), "size": c.get("size"),
            "focused": bool(c.get("focusHistoryID") == 0),
        } for c in clients() if c.get("mapped")], indent=2))
        return 0

    if cmd == "see":
        win = _target_window(args)
        words = ocr_words(_rect_of(win), psm=args.get("psm", "11"))
        if args.get("grep"):
            g = args["grep"].lower()
            words = [w for w in words if g in w["text"].lower()]
        print(json.dumps({
            "window": {"class": win.get("class"), "title": win.get("title"),
                       "at": win["at"], "size": win["size"],
                       "address": win.get("address")},
            "words": words, "count": len(words),
        }, indent=2))
        return 0

    if cmd == "click":
        if not text:
            raise SystemExit(json.dumps({"error": "click needs a label or x y"}))
        win = _target_window(args)
        if len(free) == 2 and all(p.lstrip("-").isdigit() for p in free):
            res = do_click(int(free[0]), int(free[1]), dry=args.get("dry-run", False))
            print(json.dumps({"target": "explicit", **res}))
            return 0
        words = ocr_words(_rect_of(win), psm=args.get("psm", "11"))
        cands = find_label(words, text)
        if not cands:
            print(json.dumps({"error": f"no on-screen text matching {text!r}",
                              "window": win.get("title"),
                              "seen": [w["text"] for w in words][:40]}))
            return 3
        best = cands[0]
        rival = next((c for c in cands[1:]
                      if c["score"] >= best["score"] - 0.05
                      and abs(c["x"] - best["x"]) + abs(c["y"] - best["y"]) > 40), None)
        if rival:
            print(json.dumps({"error": "ambiguous label", "candidates": cands[:5]}))
            return 4
        res = do_click(best["x"], best["y"], dry=args.get("dry-run", False))
        print(json.dumps({"target": best, "window": win.get("title"), **res}))
        return 0

    print(json.dumps({"error": f"unknown command {cmd!r}",
                      "commands": ["route", "do", "see", "click", "windows"]}))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
