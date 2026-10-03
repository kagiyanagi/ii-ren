#!/usr/bin/env python3
"""The left sidebar's frame opens the page each tab names, and its page chrome keeps the
states and bindings it shows.

None of this shows in a still frame of the default config:
- Tabs and pages are two arrays that must list the same pages in the same order. Closet
  anime (`policies.weeb: 2`) has a page with no tab, and it sat in the middle, so with
  Continuity or any extension enabled every later tab opened the page before it. Both
  arrays are lifted out and evaluated for every policy combination.
- The pages are a Repeater over a string, never `contentChildren` of createObject()
  pages. Reassigning contentChildren only clears the model (Qt 6.11); after a live reload
  the content is still incubating, the ListView is not wired to the model yet, and the old
  pages stay parented with the view listening. When the GC frees them each one walks the
  view's currentIndex down by one, to -2, and every tab shows a blank card until a restart.
- The page mask is load-bearing (a message card cut by the transcript's clip squares off
  outside the card's arc) and must mask at the card's own radius, not a tighter one.
- Anime's NSFW switch broke its binding twice: the row wrote `checked`, and the switch
  toggled itself. After one click, zerochan went on showing "on".
- Anime's send button had a MouseArea over it that took the press, so the button never
  showed a ripple or a pressed state.
- The model readout opens `/model` and showed no hover or press (law 6).
- The detached window registered `panelWindow`, the other window's id, and threw on every
  show and hide.
"""
import json
import re
import subprocess
from itertools import product
from pathlib import Path

P = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/ii/sidebarPolicies"
content = (P / "SidebarPoliciesContent.qml").read_text()
frame = (P / "SidebarPolicies.qml").read_text()
anime = (P / "Anime.qml").read_text()
hermes = (P / "Hermes.qml").read_text()
indicator = (P / "ApiInputBoxIndicator.qml").read_text()
scroll = (P / "ScrollToBottomButton.qml").read_text()


def node(js):
    return json.loads(subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout)


# ── Tab i opens page i ───────────────────────────────────────────────
tabs = re.search(r"property var tabButtonList: (\[.*?\n    \])", content, re.S)
pages = re.search(r"readonly property string pages: JSON\.stringify\((\[.*?\n    \])\)", content, re.S)
assert tabs and pages, "SidebarPoliciesContent: tabButtonList / pages not found where expected"
code = re.sub(r"//.*", "", content)
assert "contentChildren" not in code and "createObject" not in code, \
    "SidebarPoliciesContent: pages built into contentChildren go blank after a live reload"
assert "model: JSON.parse(root.pages)" in content, "SidebarPoliciesContent: the page Repeater must read the string"
combos = [dict(weeb=w, translator=t, continuity=c, hermes=h, ext=e)
          for w, t, c, h, e in product([0, 1, 2], [0, 1], [0, 1], [0, 1], [0, 1])]
got = node(f"""
const out = {json.dumps(combos)}.map(p => {{
    const Translation = {{ tr: s => s }};
    const root = {{
        hermesEnabled: !!p.hermes, translatorEnabled: !!p.translator, continuityEnabled: !!p.continuity,
        animeEnabled: p.weeb !== 0, animeCloset: p.weeb === 2,
        extensionPages: p.ext ? [{{ icon: "x", title: "Ext", fullPath: "/x.qml", extensionId: "Ext" }}] : [],
    }};
    root.tabButtonList = {tabs.group(1)};
    const pages = {pages.group(1)}.map(e => e.kind === "extension" ? "ext:" + e.extensionId : e.kind);
    return {{ p, tabs: root.tabButtonList.map(t => t.name), pages }};
}});
console.log(JSON.stringify(out));""")
name_to_page = {"Hermes": "hermes", "Translator": "translator", "Anime": "anime", "Continuity": "continuity", "Ext": "ext:Ext"}
for r in got:
    want = [name_to_page[t] for t in r["tabs"]]
    head, tail = r["pages"][:len(want)], r["pages"][len(want):]
    if not want:
        assert head == [] and tail[:1] == ["placeholder"], f"no tabs must show the placeholder first: {r}"
        tail = tail[1:]
    assert head == want, f"tab {len(head)} opens the wrong page for {r['p']}: tabs {want}, pages {r['pages']}"
    assert tail == (["anime"] if r["p"]["weeb"] == 2 else []), \
        f"only the closet anime page may follow the tabbed pages: {r}"

# ── The page mask clips to the card's arc ────────────────────────────
card = re.search(r"Rectangle \{\s*Layout\.fillWidth: true\s*Layout\.fillHeight: true.*?radius: (Appearance\.rounding\.\w+)", content, re.S)
mask = re.search(r"layer\.effect: OpacityMask \{.*?radius: (Appearance\.rounding\.\w+)", content, re.S)
assert card and mask, "SidebarPoliciesContent: page card or its mask moved"
assert card.group(1) == mask.group(1), f"page mask radius {mask.group(1)} is not the card's {card.group(1)}"

# ── Anime: NSFW row owns the state, send button owns its press ──────
assert "nsfwSwitch.checked =" not in anime and "nsfwSwitch.checked=" not in anime, \
    "Anime: writing the switch's checked breaks its binding"
switch = re.search(r"StyledSwitch \{(.*?)\n                        \}", anime, re.S)
assert switch and "checkable: false" in switch.group(1), "Anime: the NSFW switch must not toggle itself"
assert re.search(r"checked: Persistent\.states\.booru\.allowNsfw", switch.group(1)), "Anime: NSFW switch must read Persistent"
send = re.search(r"RippleButton \{ // Send button(.*?)contentItem:", anime, re.S)
assert send and "MouseArea {" not in send.group(1) and "releaseAction" in send.group(1), \
    "Anime: the send button takes its own press (releaseAction), no MouseArea over it"

# ── Type-anywhere leaves a modifier's key-down alone ─────────────────
for name, qml in [("Anime", anime), ("Hermes", hermes)]:
    assert "root.modifierKeys.indexOf(event.key) === -1" in qml, f"{name}: type-anywhere steals focus on a modifier key"

# ── Clickable readout shows hover and press ─────────────────────────
overlay = re.search(r"StateOverlay \{(.*?)\n            \}", indicator, re.S)
assert overlay and "hover: mouseArea.containsMouse" in overlay.group(1) and "press: mouseArea.pressed" in overlay.group(1), \
    "ApiInputBoxIndicator: a clickable readout needs hover and press films"

# ── Scroll to bottom: asymmetric, grows from its edge ───────────────
assert "transformOrigin: Item.Bottom" in scroll, "ScrollToBottomButton: grows out of the bottom edge it is anchored to"
assert scroll.count("elementMoveExit") >= 2, "ScrollToBottomButton: opacity and scale both need an exit spec"

# ── Frame ────────────────────────────────────────────────────────────
detached = frame[frame.index("detachedSidebarLoader\n"):]
assert "Dismissable(panelWindow" not in detached.split("IpcHandler")[0], \
    "SidebarPolicies: the detached window names `panelWindow`, an id from the other component"
assert re.search(r"Behavior on radius \{", frame), "SidebarPolicies: pin snaps the radius while height springs"
assert not (P / "StatusSeparator.qml").exists() and "StatusSeparator" not in hermes, "no separator dots (DESIGN.md 5.5)"

print("check-sidebar-policies: ok")
