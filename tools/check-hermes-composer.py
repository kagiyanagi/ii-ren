#!/usr/bin/env python3
"""What sits around the Hermes composer: the two cards the agent blocks on, and
the three popovers.

None of it shows in a still frame:
- The three popovers each assembled Launcher3's ArrowPopup by hand, and each got
  it wrong differently: the mode menu inside a QQC2 Popup with its origin at the
  top-left of a card the clamp shifted, the context card with its origin at its
  own bottom, and the selection toolbar with `visible: shown`, which deleted its
  own fade-out. Two of them are one `HermesPopover` now, on ArrowPopupMotion from
  a zero-size pivot at the opener, and the toolbar has its own pivot.
- The popover focuses its card so Escape closes it. Invisible items cannot take
  focus, and the card is at opacity 0 when `open()` runs, so with `visible` read
  off the opacity alone, Escape fell through and closed the sidebar (seen live).
- The sidebar window is wider than the panel and masks input to the panel, so a
  card clamped to the window's edges can sit where clicks go to the app behind.
- A clarify batch replaced mid-answer opened at the old question index.
The clamps, the toolbar's in-view guard and the clarify reset are lifted out and
run under node.
"""
import json
import re
import subprocess
from pathlib import Path

H = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/ii/sidebarPolicies/hermes"
pop = (H / "HermesPopover.qml").read_text()
menu = (H / "HermesApprovalModeMenu.qml").read_text()
meter = (H / "HermesContextMeter.qml").read_text()
sel = (H / "HermesSelectionActions.qml").read_text()
approval = (H / "HermesApprovalCard.qml").read_text()
clarify = (H / "HermesClarifyCard.qml").read_text()
console = (H / "HermesConsole.qml").read_text()


def node(js):
    return json.loads(subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout)


def prop(src, name):
    m = re.search(rf"^\s*{name}:\s*(.+)$", src, re.M)
    assert m, f"`{name}:` is gone"
    return m.group(1).strip()


def block(src, head):
    """The body of the `{ ... }` that follows `head`."""
    i = src.index(head)
    i = src.index("{", i) + 1
    depth = 1
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return src[i:j]
    raise AssertionError(f"unbalanced after {head!r}")


def card_of(src, ident):
    """The body of the object that declares `id: ident`."""
    i = re.search(rf"\bid:\s*{ident}\b", src).start()
    depth = 0
    while True:
        i -= 1
        depth += {"}": 1, "{": -1}.get(src[i], 0)
        if depth < 0:
            break
    return block(src[i:], "{")


# One recipe: nothing here transcribes the ArrowPopup numbers by hand any more.
for name, src in (("HermesPopover", pop), ("HermesApprovalModeMenu", menu), ("HermesContextMeter", meter), ("HermesSelectionActions", sel)):
    assert "arrowPopupScaleDuration" not in src and "enter: Transition" not in src, \
        f"{name}: the ArrowPopup animation is hand-assembled again; use ArrowPopupMotion"
    assert "Appearance.colors.colSurfaceContainer" not in src, f"{name}: a colSurfaceContainer token; each is solved for one base, not a floating card"
assert "ArrowPopupMotion {" in pop and "ArrowPopupMotion {" in sel
assert not re.search(r"^\s*Popup\s*\{", menu, re.M), "HermesApprovalModeMenu: back in a QQC2 Popup"
assert "HermesPopover {" in menu and "HermesPopover {" in meter, "a popover no longer goes through HermesPopover"
assert re.search(r"HermesPopover\s*\{[^}]*opensUp:\s*true", meter), "HermesContextMeter: the breakdown must open upward, out of the composer"
assert not re.search(r"HermesPopover\s*\{[^}]*opensUp:\s*true", menu), "HermesApprovalModeMenu: the menu hangs below the status pill"
assert "popoverComponent" not in meter and "QsWindow" not in meter,"HermesContextMeter: the card is created by hand again, and outlives the page"
assert "extraVisibleCondition: true" not in meter, "HermesContextMeter: the always-true tooltip condition is back"
assert "colLayer2Hover" not in card_of(menu, "modeRow"), \
    "HermesApprovalModeMenu: a mode row paints colLayer2Hover, which is solved for a layer the opaque card is not"

# HermesPopover: reparented from a function, bounded by the panel, focusable on open.
assert not re.search(r"^\s*parent:", pop, re.M), \
    "HermesPopover: a `parent:` binding; CalendarPopup records that one segfaulted the shell on sidebar open"
assert "root.parent = host;" in block(pop, "function open("), "HermesPopover: open() no longer reparents to the window"
assert "panel.parent !== host" in pop, "HermesPopover: the card is no longer bounded by the panel, and can leave the input mask"
assert re.search(r"^    visible:\s*root\.shown \|\|", pop, re.M), \
    "HermesPopover: `visible` must hold from `shown`, or the card cannot take focus in open() and Escape closes the sidebar"
assert "Connections {" not in pop, \
    "HermesPopover: a Connections is built while the page incubates, which is where one segfaulted the shell on reload"
assert "Keys.onEscapePressed: root.close()" in pop

# The popover card stays in the panel, centred on the opener whenever it fits.
cx, cy = prop(card_of(pop, "card"), "x"), prop(card_of(pop, "card"), "y")
got = node(f"""
const out = [];
const gutter = 8, gap = 4, width = 340, height = 220;
for (const bounds of [{{x: 0, y: 0, width: 400, height: 900}}, {{x: 30, y: 40, width: 460, height: 700}}])
  for (const opensUp of [true, false])
    for (let px = bounds.x; px <= bounds.x + bounds.width; px += 5)
      for (const py of [bounds.y + 30, bounds.y + bounds.height / 2, bounds.y + bounds.height - 30]) {{
        const root = {{bounds, opensUp}}, pivot = {{x: px, y: py}};
        const x = {cx}, y = {cy};
        out.push({{px, py, opensUp, bounds, x: px + x, y: py + y, cx: x}});
      }}
console.log(JSON.stringify(out));
""")
for c in got:
    b = c["bounds"]
    assert b["x"] + 8 - 1e-6 <= c["x"] and c["x"] + 340 <= b["x"] + b["width"] - 8 + 1e-6, f"HermesPopover: card leaves the panel sideways at {c}"
    fits = b["x"] + 8 <= c["px"] - 170 and c["px"] + 170 <= b["x"] + b["width"] - 8
    assert not fits or abs(c["cx"] + 170) < 1e-6, f"HermesPopover: a card that fits is not centred on its opener at {c}"
    assert b["y"] + 8 - 1e-6 <= c["y"], f"HermesPopover: card leaves the panel's top at {c}"
    if c["opensUp"] and c["py"] - 224 >= b["y"] + 8:
        assert abs(c["y"] + 220 - (c["py"] - 4)) < 1e-6, f"HermesPopover: an upward card does not hang off its opener at {c}"
    if not c["opensUp"]:
        assert c["y"] + 220 <= b["y"] + b["height"] - 8 + 1e-6, f"HermesPopover: card leaves the panel's bottom at {c}"

# Selection toolbar: latched, pivoted, and off when the text is out of view.
assert not re.search(r"^    visible:\s*root\.shown", sel, re.M), \
    "HermesSelectionActions: `visible: shown` again, which deletes the fade-out"
assert re.search(r"onLiveRectChanged:\s*\{\s*if \(root\.shown\)\s*root\.selectionRect = root\.liveRect", sel), \
    "HermesSelectionActions: the rect is not latched, so the exit drags the pivot to the corner"
assert sel.count("focusPolicy: Qt.NoFocus") == 3, "HermesSelectionActions: a button takes focus, and the selection it acts on vanishes"
assert "radius: Appearance.rounding.full" in card_of(sel, "toolbar"), "HermesSelectionActions: the toolbar is not a pill"
shown = prop(sel, "readonly property bool shown")
tx = prop(card_of(sel, "toolbar"), "x")
got = node(f"""
const cases = [[-60, 20, false], [-10, 20, true], [100, 20, true], [490, 20, true], [500, 20, false], [700, 20, false]];
const shown = cases.map(([y, h, _]) => {{ const root = {{selecting: true, height: 500, liveRect: {{y, height: h}}}}; return {shown}; }});
const xs = [];
for (let px = -40; px <= 460; px += 7) {{ const root = {{edgeMargin: 4, width: 420}}, pivot = {{x: px}}, width = 120; xs.push(px + {tx}); }}
console.log(JSON.stringify({{shown, want: cases.map(c => c[2]), xs}}));
""")
assert got["shown"] == got["want"], f"HermesSelectionActions: in-view guard gave {got['shown']}, want {got['want']}"
assert all(4 - 1e-6 <= x and x + 120 <= 416 + 1e-6 for x in got["xs"]), "HermesSelectionActions: the toolbar leaves the transcript"

# Approval card: stacked, full width, the grant filled, Deny not red.
assert "FlowButtonGroup" not in approval and "FlowButtonGroup" not in clarify, "a card's choices flow in a row again"
assert "colError" not in block(approval, "delegate: RippleButton"), \
    "HermesApprovalCard: Deny is red again; it is the safe answer"
assert re.search(r"toggled:\s*choiceButton\.modelData === \"once\"", approval), "HermesApprovalCard: Allow once is not the filled choice"
assert "Layout.fillWidth: true" in block(approval, "delegate: RippleButton"), "HermesApprovalCard: choices are not full width"
cmd = card_of(approval, "commandText")
assert "readOnly: true" in cmd and "selectByMouse: true" in cmd, "HermesApprovalCard: the command can no longer be selected"

# Clarify card: a replaced batch starts over; rows, not chips.
reset = block(clarify, "onRequestChanged:")
answer = block(clarify, "function answer(")
got = node(f"""
const answered = [];
const HermesService = {{ respondToClarify: (t, q) => answered.push([t, q]) }};
const answerField = {{ text: "draft" }};
const root = {{ shown: true, request: null, latched: null, questionIndex: 0, selected: [], questions: [1, 2, 3], isBatch: true, questionId: "q" }};
function answer(text) {{ {answer} }}
root.questionIndex = 2; root.selected = ["x"];
root.request = {{ questions: [1, 2] }};
(function () {{ {reset} }})();
const afterReplace = [root.questionIndex, root.selected.length, answerField.text];
answer("a");
const afterAnswer = root.questionIndex;
console.log(JSON.stringify({{afterReplace, afterAnswer}}));
""")
assert got["afterReplace"] == [0, 0, ""], f"HermesClarifyCard: a replaced batch opens at {got['afterReplace']}, not its first question"
assert got["afterAnswer"] == 1, "HermesClarifyCard: answering a batch no longer walks to the next question"
assert re.search(r"onCurrentChanged:\s*root\.focusIfTyped\(\)", clarify), "HermesClarifyCard: a typed-only question no longer takes the caret"

# The cards are fed by server->client requests: a frame with an id AND a method.
# Hermes dropped the old `clarify.request` / `approval.request` events and
# `clarify.respond`; routed as a reply, the request was dropped and no card opened.
svc = (H.parents[3] / "services/HermesService.qml").read_text()
frame = block(svc, "function _handleFrame(")
assert frame.index("_handleServerRequest") < frame.index("_pendingCalls"), \
    "HermesService: a server request (clarify, approval) is taken for a reply and dropped"
assert '"clarify.respond"' not in svc and '"approval.request"' not in svc, "HermesService: the pre-server-request protocol is back"
assert '"clarify.lock"' in svc and 'case "request.cancel"' in svc, "HermesService: batch answers or withdrawals are not handled"

# Attachment chips: a token is one character to the editor. Backspace into it takes
# all of it (and unstages it); typing inside it lands after it. A half-deleted token
# is text the model reads and a chip nobody can remove.
chips = (H / "HermesAttachmentChips.qml").read_text()
got = node(f"""
const T = "\\u2063\\u2007\\u2007\\u2007image.png\\u2063";
const HermesService = {{ composerMarkers: {{ [T]: {{}} }} }};
const dropped = [];
HermesService.dropMarker = t => dropped.push(t);
const Qt = {{ callLater: f => f() }};
const target = {{ text: "", cursorPosition: 0 }};
const root = {{ target, previous: "", layoutRects() {{}} }};
root.tokenRanges = function (text) {{ {block(chips, "function tokenRanges(")} }};
root.onEdit = function () {{ {block(chips, "function onEdit(")} }};
function edit(before, after, cursor) {{ root.previous = before; target.text = after; target.cursorPosition = cursor ?? 0; root.onEdit(); return target.text; }}
const base = "look at " + T + " now";
const back = edit(base, base.slice(0, 8 + T.length - 1) + base.slice(8 + T.length));
const droppedAfterBack = dropped.length;
const typed = edit(base, base.slice(0, 12) + "x" + base.slice(12));
// Two chips with nothing between them: a backspace after the first must take the
// first, though a bare diff lines the deletion up with the second one's opening.
const U = "\\u2063\\u2007\\u2007\\u2007tool.py\\u2063";
HermesService.composerMarkers[U] = {{}};
dropped.length = 0;
const pair = "a " + T + U + " b";
const cut = 2 + T.length - 1;
const adjacent = edit(pair, pair.slice(0, cut) + pair.slice(cut + 1), cut);
console.log(JSON.stringify({{ back, droppedAfterBack, typed, T, U, adjacent, droppedAdjacent: dropped }}));
""")
assert got["back"] == "look at  now" and got["droppedAfterBack"] == 1, \
    f"HermesAttachmentChips: a backspace into a chip left {got['back']!r} and unstaged {got['droppedAfterBack']}"
assert got["typed"] == "look at " + got["T"] + "x now", f"HermesAttachmentChips: typing inside a chip broke it: {got['typed']!r}"
assert got["adjacent"] == "a " + got["U"] + " b" and got["droppedAdjacent"] == [got["T"]], \
    f"HermesAttachmentChips: a backspace after one chip took its neighbour: {got['adjacent']!r}, unstaged {got['droppedAdjacent']!r}"

# A sent bubble draws the same chips: the reference the model read becomes an
# icon and the name, bracketed for InlineCode's pill. Never an inline `<img>`:
# Qt breaks a line after one whatever joins it to the name.
message = (H / "HermesMessage.qml").read_text()
got = node(f"""
const Appearance = {{ font: {{ pixelSize: {{ normal: 16 }}, family: {{ iconMaterial: "Material Symbols Rounded" }} }} }};
const root = {{ chipGap: 8 }};
function withChips(content, attachments) {{ {block(message, "function withChips(")} }}
const items = [
    {{ kind: "image", name: "shot 1.png", send: "[Image: shot 1.png]", thumb: "/tmp/shot 1.png", icon: "image" }},
    {{ kind: "file", name: "notes_a.txt", send: "@file:notes_a.txt", thumb: "", icon: "description" }},
    {{ kind: "file", name: "gone.txt", send: "@file:gone.txt", thumb: "", icon: "description" }}
];
console.log(JSON.stringify({{
    out: withChips("look [Image: shot 1.png] and @file:notes_a.txt now", items),
    plain: withChips("no refs here", items)
}}));
""")
out = got["out"]
assert "[Image:" not in out and "@file:" not in out, f"HermesMessage.withChips: a reference is left as text: {out!r}"
assert out.count("\u2063") == 4, f"HermesMessage.withChips: each chip needs its pair of U+2063 for the pill: {out!r}"
assert "<img" not in out and ">image</span>" in out, f"HermesMessage.withChips: a chip holds an inline picture, which a wrap splits off its name: {out!r}"
assert "notes\\_a" in out, f"HermesMessage.withChips: a name's markdown is not escaped, `a_b_c` renders as emphasis: {out!r}"
assert got["plain"] == "no refs here", "HermesMessage.withChips: a turn without its references changed"
got = node(f"""
const Appearance = {{ font: {{ pixelSize: {{ normal: 16 }}, family: {{ iconMaterial: "Material Symbols Rounded" }} }} }};
const root = {{ chipGap: 8 }};
function withChips(content, attachments) {{ {block(message, "function withChips(")} }}
const item = {{ kind: "file", name: "a.txt", send: "@file:a.txt", thumb: "", icon: "description" }};
console.log(JSON.stringify({{ start: withChips("@file:a.txt then", [item]), mid: withChips("see @file:a.txt", [item]) }}));
""")
assert got["start"].startswith("\u2063&nbsp;"), f"HermesMessage.withChips: a chip opening the turn is indented: {got['start']!r}"
assert got["mid"].startswith('se<span style="letter-spacing:4px;">e</span> \u2063&nbsp;'), \
    f"HermesMessage.withChips: the word before a chip is not spaced off it: {got['mid']!r}"

# A plain TextArea hands U+00A0 back as a space, so a token holding one read as
# an edit inside it and was deleted: a second paste of one name never stayed.
assert "\\u00a0" not in block((H.parents[3] / "services/HermesService.qml").read_text(), "function _addMarker("), \
    "HermesService._addMarker: a token holds U+00A0, which the composer reads back as a plain space"

# node runs these, but the shell's JS engine has no matchAll, flatMap, flat,
# replaceAll or at: one of them threw on every resumed chat and emptied it.
for name in ("services/HermesService.qml", "modules/ii/sidebarPolicies/hermes/HermesAttachmentChips.qml",
             "modules/ii/sidebarPolicies/hermes/HermesAttachmentStrip.qml", "modules/ii/sidebarPolicies/hermes/HermesMessage.qml"):
    found = re.findall(r"\.(matchAll|flatMap|flat|replaceAll|at)\(", (H.parents[3] / name).read_text())
    assert not found, f"{name}: {sorted(set(found))} do not exist in the shell's JS engine"

# A resumed turn rebuilds its chips from the text the gateway stored.
svc_text = (H.parents[3] / "services/HermesService.qml").read_text()
got = node(f"""
const FileUtils = {{
    fileNameForPath: p => p.split("/").pop(),
    folderNameForPath: p => p.replace(/\\/$/, "").split("/").pop(),
    iconForFile: n => n.endsWith(".py") ? "code" : "draft"
}};
const root = {{}};
root._marker = function (kind, name, send, paths) {{ {block(svc_text, "function _marker(")} }};
root._restoredTurn = function (body) {{ {block(svc_text, "function _restoredTurn(")} }};
const body = "look [Image: shot.png] and [PDF: doc.pdf] @file:/x/tool-5.py @folder:\\"/tmp/my dir\\" now\\n\\n--- Context Warnings ---\\n- @file:/x/tool-5.py: path is outside the allowed workspace\\n@image:/tmp/pdf_p1_a.png\\n@image:/tmp/shot.png";
console.log(JSON.stringify(root._restoredTurn(body)));
""")
assert got["text"] == 'look [Image: shot.png] and [PDF: doc.pdf] @file:/x/tool-5.py @folder:"/tmp/my dir" now', \
    f"HermesService._restoredTurn: the gateway's warnings or image lines are left in the bubble: {got['text']!r}"
kinds = [(a["kind"], a["name"], a["thumb"]) for a in got["attachments"]]
assert kinds == [("image", "shot.png", "/tmp/shot.png"), ("pdf", "doc.pdf", "/tmp/pdf_p1_a.png"),
                 ("file", "tool-5.py", ""), ("folder", "my dir", "")], f"HermesService._restoredTurn: {kinds}"

# Each file type's icon must exist in the older Material Symbols build, the one Qt
# resolves the family to; a missing ligature renders as its name, not an icon.
utils = (H.parents[3] / "modules/common/functions/FileUtils.qml").read_text()
icons = set(re.findall(r'\["(\w+)", "[\w ]+"\]', block(utils, "function iconForFile(")))
icons.add("draft")
old_font = next(Path("/usr/share/fonts/ii-sddm-theme-fonts/MaterialSymbols").glob("MaterialSymbolsRounded*.ttf"), None) \
    if Path("/usr/share/fonts/ii-sddm-theme-fonts/MaterialSymbols").is_dir() else None
if old_font:
    from fontTools.ttLib import TTFont
    ligatures = set()
    def walk(st):
        if st is None:
            return
        if hasattr(st, "ExtSubTable"):
            return walk(st.ExtSubTable)
        for first, ligs in getattr(st, "ligatures", {}).items():
            for lig in ligs:
                ligatures.add("".join([first] + list(lig.Component)).replace("underscore", "_"))
    for lookup in TTFont(old_font)["GSUB"].table.LookupList.Lookup:
        for st in lookup.SubTable:
            walk(st)
    missing = sorted(icons - ligatures)
    assert not missing, f"FileUtils.iconForFile: not in the Material Symbols build Qt loads: {missing}"

# Console: nothing inert, the shared scroll bar.
assert "transformOrigin" not in console, "HermesConsole: a transformOrigin on something that never scales"
assert "StyledScrollBar" in console and not re.search(r":\s*ScrollBar\s*\{", console), "HermesConsole: a raw ScrollBar again"

print("ok")
