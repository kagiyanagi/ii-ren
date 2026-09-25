#!/usr/bin/env python3
"""The Android quick-toggle grid is centred, and nothing in it breaks the panel it sits in.

`baseCellWidth` took `spacing * columns` off the width, where a row of four tiles has
three gaps, so every row stopped 12px short of the card's right edge and 6px from its
left. The expression is lifted out of AndroidQuickPanel.qml and run, with the real packer
in QuickToggleLayout.js, over the shipped pages and a sweep of widths and column counts.

The rest has no symptom in a still frame:
- ThreeWaySlider walked every ancestor and assigned `interactive` false and then true.
  That destroys the binding it overwrites, so one tap left the panel rubber-banding under
  any drag, and the pager turning in edit mode, for the rest of the session.
  `preventStealing` is the documented way to keep a Flickable off a drag.
- The panel's height animated twice: `flickableContainer` animated its height, and a
  second `Behavior` on the panel's `implicitHeight`, which is derived from it, restarted
  every frame towards a moving target.
- Tile geometry and the three-way knob ran on `elementMoveFast`, the effects spec.
- The icon films were hand-mixed at 0.05 / 0.12, and the 2x2 Wi-Fi tile still laid a
  square `Rectangle` film over a cookie, reading a `radius` `MaterialShape` does not have.
- The Bluetooth icon keyed its colour on `BluetoothStatus.enabled` and was two greys, so
  the tile never looked on unless something was connected.
- The edit toolbar's `+` kept square outer corners whenever its neighbour was hidden.
  That happens with one page and on the last page, which the default screenshot is not.
"""
import json
import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
QT = REPO / "dots/.config/quickshell/ii/modules/ii/sidebarDashboard/quickToggles"
panel = (QT / "AndroidQuickPanel.qml").read_text()
layout_js = (QT / "androidStyle/QuickToggleLayout.js").read_text().replace(".pragma library", "")
tree = {p.relative_to(QT).as_posix(): p.read_text() for p in QT.rglob("*.qml")}
android = {k: v for k, v in tree.items() if not k.startswith("classicStyle/")}


def node(js):
    return json.loads(subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout)


def block(src, start):
    """The brace-balanced block that opens at the first `{` after `start`."""
    i = src.index("{", start)
    depth = 0
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return src[i:j + 1]
    raise AssertionError("unbalanced block")


# --- the grid is centred ---------------------------------------------------------------
cell_expr = re.search(r"readonly property real baseCellWidth: \{(.*?)\n    \}", panel, re.S).group(1)
# The default pages Config.qml ships, which are JSON as written.
config_qml = (REPO / "dots/.config/quickshell/ii/modules/common/Config.qml").read_text()
pages_src = re.search(r"property list<var> pages: (\[.*?\n {24}\])", config_qml, re.S).group(1)
shipped_pages = json.loads(pages_src)
assert shipped_pages and shipped_pages[0], "Config.qml's default quick-toggle pages did not parse"

cases = []
for columns in range(1, 7):
    for width in (300, 424.5, 460, 600):
        for spacing in (0, 4, 6, 8):
            full_row = [{"id": f"t{i}", "sizeW": 1, "sizeH": 1} for i in range(columns)]
            wide = [{"id": "s", "sizeW": columns, "sizeH": 1}]
            cases.append({"columns": columns, "width": width, "spacing": spacing, "items": full_row + wide})
for page in shipped_pages:
    cases.append({"columns": 4, "width": 424.5, "spacing": 6, "items": page})

results = node(layout_js + f"""
const cases = {json.dumps(cases)};
console.log(JSON.stringify(cases.map(c => {{
    const root = {{ width: c.width, padding: 6, spacing: c.spacing, columns: c.columns }};
    const cell = (() => {{{cell_expr}\n}})();
    const placed = positionedItems(c.items, pack(c.items, c.columns), cell, 56, c.spacing);
    return {{
        content: root.width - root.padding * 2,
        left: Math.min(...placed.map(p => p.layoutX)),
        right: Math.max(...placed.map(p => p.layoutX + cell * p.sizeW + c.spacing * (p.sizeW - 1))),
    }};
}})));""")
for case, r in zip(cases, results):
    where = f"{case['columns']} columns, width {case['width']}, spacing {case['spacing']}"
    assert abs(r["left"]) < 1e-6, f"{where}: the first column starts at {r['left']}, not 0"
    assert abs(r["right"] - r["content"]) < 1e-6, \
        f"{where}: the last column ends at {r['right']:.2f} of {r['content']:.2f} -- the grid is off-centre"

# --- nothing writes over a binding it does not own ----------------------------------------
for name, src in android.items():
    assert not re.search(r"\binteractive\s*=[^=]", src), \
        f"{name} assigns `interactive`, which destroys the binding it overwrites (use preventStealing)"
slider = tree["androidStyle/ThreeWaySlider.qml"]
drag_area = block(slider, slider.index("id: dragArea") - 40)
assert "preventStealing: true" in drag_area, "the three-way slider's drag must keep preventStealing"
assert "hoverEnabled: true" in drag_area, "the three-way knob's hover state needs hoverEnabled"
assert re.search(r"colPrimaryActive[\s\S]*colPrimaryHover", block(slider, slider.index("id: knob") - 40)), \
    "the three-way knob lost its pressed/hover states"

# --- one height animation --------------------------------------------------------------
assert panel.count("Behavior on implicitHeight") == 1, "the panel animates implicitHeight exactly once"
container = block(panel, panel.index("id: flickableContainer") - 40)
assert "Behavior on height" not in container.split("Flickable {")[0], \
    "flickableContainer must not animate its height: the panel's implicitHeight already does, and two chase"

# --- spatial motion on spatial specs -----------------------------------------------------
for name, src in android.items():
    for m in re.finditer(r"Behavior on (x|y|width|height|radius)\s*\{", src):
        body = block(src, m.start())
        assert "elementMoveFast" not in body, \
            f"{name}: `Behavior on {m.group(1)}` runs on elementMoveFast, the effects spec"
assert not re.search(r"Easing\.(In|Out)", panel), "the page snap must use an Appearance spec, not an Easing preset"

# --- state films -----------------------------------------------------------------------
for name, src in android.items():
    assert not re.search(r"containsMouse \? 0\.9\d", src), f"{name}: a hand-mixed hover film is back"
    for alpha in re.findall(r"ColorUtils\.mix\([^()]*,\s*([0-9.]+)\)", src):
        assert alpha in ("0.08", "0.10"), f"{name}: a state film at {alpha}; the tokens are 0.08 hover, 0.10 press"
    for shape in re.findall(r"MaterialShape \{\s*id: (\w+)", src):
        assert f"{shape}.radius" not in src, f"{name}: reads {shape}.radius, which a MaterialShape does not have"

# --- Bluetooth looks on when it is on ---------------------------------------------------
bt = tree["androidStyle/AndroidBluetoothToggle.qml"]
assert re.search(r"colIconBase: root\.toggled \? Appearance\.colors\.colPrimary", bt), \
    "the Bluetooth icon must be colPrimary whenever Bluetooth is on"
assert not re.search(r"color: BluetoothStatus\.enabled", bt), "the Bluetooth icon keys its colour on a service flag again"
assert "wide2x2OverrideComponent: btLayout" in bt and "tall1x2OverrideComponent: btLayout" in bt, \
    "both Bluetooth sizes share one layout"
assert "onClicked: root.mainAction()" in bt, "the Bluetooth icon must be its own target, or a 2x2 tile cannot switch it"

# --- edit mode ----------------------------------------------------------------------------
editable = tree["androidStyle/EditableQuickToggleItem.qml"]
assert "id: actionBadge" in editable, "the edit-mode badge (add / remove) is gone"
badge = block(editable, editable.index("id: actionBadge") - 40)
assert not re.search(r"Margin: -", badge), "the edit badge must sit inside the tile, or the panel's clip halves it"
assert '"remove"' in badge, "placed tiles must say that a click removes them"
for name, src in android.items():
    assert "return 0.95" not in src, f"{name}: a dragged tile fades; it should lift (DESIGN.md 3.6)"


def button(onclick):
    return block(panel, panel.rindex("RippleButton {", 0, panel.index(onclick)))


def expr(src, prop):
    # Up to the next line that starts a property, an assignment or a child object.
    end = r"\n\s*(?=(?:readonly )?property \w+ \w+:|\w+[.\w]*:|\w+ \{)"
    m = re.search(rf"{prop}: ((?:.|\n)*?){end}", src)
    assert m, f"no `{prop}` to evaluate -- the edit toolbar's `+` must take the group's outer corners"
    return m.group(1).strip()


plus = button("onClicked: root.addPage()")
visible_next = expr(button("onClicked: root.goToPage(root.currentPage + 1)"), "visible")
visible_del = expr(button("onClicked: root.removePage(root.currentPage)"), "visible")
left, right = (expr(plus, f"readonly property real group{side}Radius") for side in ("Left", "Right"))
states = [{"pages": p, "current": c} for p in range(1, 5) for c in range(p)]
evaluated = node(f"""
const Appearance = {{ rounding: {{ verysmall: 8, full: 9999 }} }};
console.log(JSON.stringify({json.dumps(states)}.map(s => {{
    const root = {{ currentPage: s.current, displayPages: {{ length: s.pages }} }};
    return [{visible_next}, {visible_del}, {left}, {right}];
}})));""")
for s, (has_next, has_del, l, r) in zip(states, evaluated):
    where = f"page {s['current'] + 1} of {s['pages']}"
    assert l == (8 if has_next else 9999), f"{where}: `+` left corner {l}, next to a {'shown' if has_next else 'hidden'} `>`"
    assert r == (8 if has_del else 9999), f"{where}: `+` right corner {r}, next to a {'shown' if has_del else 'hidden'} delete"

# --- the page dots are one 32px target -----------------------------------------------------
dots_row = block(panel, panel.index("id: pageDots") - 40)
assert "MouseArea" not in dots_row, "a MouseArea inside the dot Row is laid out as a dot, and per-dot areas are too narrow"
dot_area = block(panel, panel.index("MouseArea", panel.index("id: pageDots")))
assert "height: 32" in dot_area, "the page-dot target must be 32px tall (DESIGN.md 3.4)"
click = re.search(r"onClicked: mouse => \{(.*?)\n {20}\}", dot_area, re.S).group(1)
dot_cases = [{"pages": n, "current": c} for n in range(2, 6) for c in range(n)]
picked = node(f"""
console.log(JSON.stringify({json.dumps(dot_cases)}.map(c => {{
    // The Row's children: the dots, then the Repeater, which has no index.
    let x = 0;
    const children = [];
    for (let i = 0; i < c.pages; i++) {{
        const w = i === c.current ? 16 : 8;
        children.push({{ index: i, x: x, width: w }});
        x += w + 6;
    }}
    children.push({{}});
    const pageDots = {{ children: children }};
    const width = x - 6;
    const out = [];
    for (let px = -8; px <= width + 8; px++) {{
        let went = null;
        const root = {{ goToPage: p => went = p }};
        const mapToItem = (item, mx, my) => ({{ x: mx - 8, y: my }});
        ((mouse) => {{{click}\n}})({{ x: px + 8 }});
        const hit = children.find(d => d.index !== undefined && px >= d.x && px < d.x + d.width);
        out.push([went, hit ? hit.index : null]);
    }}
    return out;
}})));""")
for case, row in zip(dot_cases, picked):
    for went, hit in row:
        assert went is not None and 0 <= went < case["pages"], f"{case}: a click in the dot row went nowhere ({went})"
        assert hit is None or went == hit, f"{case}: a click on dot {hit} turned to page {went}"

print("check-quick-toggles: ok")
