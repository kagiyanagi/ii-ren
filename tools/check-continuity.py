#!/usr/bin/env python3
"""The Continuity cards react to the pointer, fold only when asked, and stay open.

None of this shows in a still frame:
- A tailnet peer folded shut every 8s. Tailscale.qml rebuilds `peers` from fresh
  objects on each poll and the host's ScriptModel had no key, so every row was
  destroyed and rebuilt with `expanded` back at false.
- The peer toggled on a `TapHandler` on its root, with no press film and nothing
  that said it expanded. Both cards now take the whole-card click on a MouseArea
  *under* their content, so a pill accepts its own press first.
- The peer's actions popped in and out with `visible: expanded` while the height
  animated, painting over the next peer on the way in.
- An out-of-reach phone card was `opacity: 0.55`, which ghosted the one pill that
  fixes it. It drops its accent instead.
"""
import re
from pathlib import Path

P = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/ii/sidebarPolicies"
card = (P / "continuity/DeviceCard.qml").read_text()
peer = (P / "continuity/TailnetPeerItem.qml").read_text()
host = (P / "Continuity.qml").read_text()
tailscale = (P.parents[2] / "services/Tailscale.qml").read_text()

# Keyed peers, on a key the service actually emits.
m = re.search(r"model:\s*ScriptModel\s*\{([^}]*Tailscale\.peers[^}]*)\}", host)
assert m, "Continuity: the peer Repeater no longer reads Tailscale.peers through a ScriptModel"
key = re.search(r'objectProp:\s*"(\w+)"', m.group(1))
assert key, "Continuity: the peer ScriptModel is unkeyed, so every poll rebuilds every row and folds it"
assert re.search(rf"^\s*{key.group(1)}:", tailscale, re.M), \
    f"Tailscale._toPeer no longer emits `{key.group(1)}`, the peer rows' key"

for name, src, content in (("DeviceCard", card, "cardColumn"), ("TailnetPeerItem", peer, "peerColumn")):
    assert "TapHandler" not in src, f"{name}: a TapHandler on the card also catches taps meant for its pills"
    area = src.find("MouseArea {")
    column = src.find(f"id: {content}")
    assert 0 <= area < column, f"{name}: the card's MouseArea must sit under the content, or it eats the pills' clicks"
    body = src[area:src.find("}", area)]
    assert "hoverEnabled: true" in body, f"{name}: the card's MouseArea no longer reports hover"
    assert re.search(r"StateOverlay\s*\{[^}]*hover:\s*cardArea\.containsMouse[^}]*press:\s*cardArea\.pressed", src, re.S), \
        f"{name}: the card lost its hover or pressed film"
    rot = re.search(r"Behavior on rotation\s*\{\s*animation:\s*Appearance\.animation\.(\w+)\.", src)
    assert rot and rot.group(1) == "elementMove", \
        f"{name}: the chevron flips on {rot and rot.group(1)}; a rotation is spatial, and the height rides elementMove"

assert not re.search(r"^\s{4}opacity:", card, re.M), \
    "DeviceCard: the card fades itself again, which ghosts the pill inside it"
assert "StyledProgressBar" in card, "DeviceCard: the battery is hand-built again; the shared bar does not overshoot"
assert re.search(r"text:\s*root\.name\s*\n\s*(//.*\n\s*)*textFormat:\s*Text\.PlainText", card), \
    "DeviceCard: device names render as rich text again"

assert re.search(r"^\s{4}clip:\s*true", peer, re.M), "TailnetPeerItem: without clip the actions paint over the next peer"
flow = peer[peer.find("id: actions"):]
assert "visible: opacity > 0" in flow and "elementMoveExit" in flow, \
    "TailnetPeerItem: the actions must fade out on elementMoveExit before the height drops"
assert not re.search(r"visible:\s*root\.expanded", peer), "TailnetPeerItem: the actions pop on `visible: expanded` again"
action = peer[peer.find("component PeerAction"):peer.find("StateOverlay")]
assert "colLayer2" not in action and "colBackground: Appearance.colors.colLayer3" in action, \
    "TailnetPeerItem: the pills must sit a layer above the layer-2 card, or they have no container at rest"

print("ok: continuity cards are keyed, fold on their own target, and keep their live controls live")
