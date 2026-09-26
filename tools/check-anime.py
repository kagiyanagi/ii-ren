#!/usr/bin/env python3
"""The sidebar's anime grid costs one layer per response, fills its width, opens
its menu out of the click, and does not hand a remote string to a shell.

- **One mask per response.** Every tile had its own `OpacityMask` and a
  `RippleButton` (another mask) for its `more_vert`: forty offscreen passes for a
  page of twenty, in a repeated delegate. `check-effect-budget.py` cannot see it,
  because the tile is its own file (the dock's blind spot), so the ceiling is
  stated per file: the tile carries nothing, the response carries one mask, and
  the mask is drawn from the same rows as the tiles.
- **Justified rows.** The row packer is evaluated under node against random
  aspect ratios: every row fills the width exactly (it stopped one gap short), no
  multi-image row is shorter than the threshold, and every image lands once, in
  order.
- **The menu.** It hangs off a zero-size pivot at the click, flips by where the
  pointer is and clamps inside the list. The clamp is lifted out and swept.
- **Trust boundary.** Image URLs and file names come from a remote API. Download
  passes them as arguments, and `ImageDownloaderProcess` escapes its URL.

    python3 tools/check-anime.py
"""

import json
import random
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
DIR = II / "modules/ii/sidebarPolicies/anime"
strip = lambda text: re.sub(r"(^|\s)// .*", r"\1", text, flags=re.M)  # comments, not regex literals
tile = strip((DIR / "BooruImage.qml").read_text())
resp = strip((DIR / "BooruResponse.qml").read_text())
downloader = (II / "modules/common/utils/ImageDownloaderProcess.qml").read_text()

for effect in ("layer.enabled", "OpacityMask", "MultiEffect", "ShaderEffect", "Shadow", "RippleButton", "Loader"):
    assert effect not in tile, f"{effect} in BooruImage, which repeats once per image"
assert resp.count("OpacityMask {") == 1 and resp.count("layer.enabled") == 1, \
    "the response should round its tiles with exactly one mask"
assert resp.count("model: root.rows") == 2, "the mask must be drawn from the same rows as the tiles"
assert "RowLayout {\n                        id: imageRow" not in resp and "delegate: Row {" in resp, \
    "tiles and mask must both be plain Row/Column, or they stop landing on the same pixels"

assert resp.count("ArrowPopupMotion {") == 1, "one menu per response, on ArrowPopupMotion"
assert not re.search(r"parent:.*QsWindow", resp), \
    "the menu's parent is a binding on QsWindow: it re-fires mid window rebuild and segfaults"
assert re.search(r"onWheel:.*\{[^}]*menu\.close\(\);\s*wheel\.accepted = false", resp, re.S), \
    "a wheel outside the menu must close it and still scroll the list"

# Trust boundary: nothing from the API is interpolated into bash -c.
download = re.search(r'execDetached\(\["bash", "-c", (\'[^\']*\')', resp).group(1)
assert "${" not in download and '"$2"' in download, "Download interpolates the URL into bash again"
assert "shellSingleQuoteEscape(sourceUrl)" in downloader, "ImageDownloaderProcess puts a raw URL in single quotes"
assert '.replace(/\\//g, "_")' in tile, "a decoded file name can carry a / out of the preview directory"

# The row packer and the menu clamp, lifted out of the QML and run under node in one go.
body = re.search(r"readonly property var rows: \{\n(.*?)\n    \}\n", resp, re.S).group(1)
clamp = {axis: re.search(rf"^\s+{axis}: \{{\n(.*?)\n\s+\}}", resp, re.M | re.S).group(1) for axis in ("x", "y")}

random.seed(7)
cases = []
for _ in range(200):
    images = [{"aspect_ratio": random.choice([0.3, 0.56, 0.7, 1, 1.33, 1.78, 2.4, 4]) * random.uniform(0.9, 1.1), "n": i}
              for i in range(random.randint(1, 30))]
    cases.append({"availableWidth": random.choice([300, 413, 520, 700]), "responsePadding": 4, "imageSpacing": 4,
                  "rowTooShortThreshold": 190, "responseData": {"images": images}})

G = 10  # Appearance.sizes.elevationMargin
sweep = [(b0, bs, p, s) for b0, bs in ((8, 530), (120, 780)) for s in (124, 220, 300) for p in range(b0, b0 + bs + 1, 3)]
js = f"""
const pack = root => {{ {body} }};
const place = {{
    x: (menu, pivot, width, gutter) => {{ {clamp["x"]} }},
    y: (menu, pivot, height, gutter) => {{ {clamp["y"]} }},
}};
const cases = {json.dumps(cases)}, sweep = {json.dumps(sweep)};
console.log(JSON.stringify({{
    rows: cases.map(c => pack(c).map(r => ({{h: r.height, a: r.images.map(i => i.aspect_ratio), n: r.images.map(i => i.n)}}))),
    x: sweep.map(([b0, bs, p, s]) => place.x({{bounds: {{x: b0, width: bs}}}}, {{x: p}}, s, {G})),
    y: sweep.map(([b0, bs, p, s]) => place.y({{bounds: {{y: b0, height: bs}}}}, {{y: p}}, s, {G})),
}}));
"""
out = json.loads(subprocess.run(["node", "-"], input=js, capture_output=True, text=True, check=True).stdout)

for case, rows in zip(cases, out["rows"]):
    assert [n for r in rows for n in r["n"]] == list(range(len(case["responseData"]["images"]))), \
        "an image was dropped or reordered"
    inner = case["availableWidth"] - 2 * case["responsePadding"]
    for r in rows:
        filled = sum(r["h"] * a for a in r["a"]) + case["imageSpacing"] * (len(r["a"]) - 1)
        assert abs(filled - inner) < 1e-6, f"a row is {inner - filled:.2f}px short of the width"
        assert len(r["a"]) == 1 or r["h"] >= case["rowTooShortThreshold"] - 1e-9, "a row went under the threshold"

for axis in ("x", "y"):
    for (b0, bs, p, s), offset in zip(sweep, out[axis]):
        edge = p + offset
        assert b0 + G - 1e-9 <= edge <= b0 + bs - G - s + 1e-9, f"{axis}: the menu leaves the list"
        if b0 + G <= p and p + s + G <= b0 + bs:
            assert abs(edge - p) < 1e-9, f"{axis}: room after the click, but the menu did not start there"
        elif b0 + G <= p - s and p <= b0 + bs - G:
            assert abs(edge + s - p) < 1e-9, f"{axis}: flipped, but the menu does not end at the click"

print("ok: one mask per response, rows fill the width, menu grows from the click and clamps, no remote string in a shell")
