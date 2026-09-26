#!/usr/bin/env python3
"""The booru service builds the request each provider actually answers.

Every one of these failed with the same generic "That didn't work" and nothing
else on screen, which is why they went unnoticed:

- **Gelbooru** pages are zero-based (`pid`), so page 1 asked for the second page.
  It also needs `api_key` and `user_id` now; without them it answers 401.
- **waifu.im** moved to `/images` with `IncludedTags`/`PageSize`/`PageNumber`/`IsNsfw`.
  The old `/search` is behind a Cloudflare check.
- **Zerochan** searches by tag path (`/Hatsune+Miku,Blue?json`). The old request put
  the tags in the colour parameter.
- **Alcy** takes one category in the path. With no tag it requested the site root,
  which is an HTML page, and every line of it became an "image".
- **Danbooru** and **Gelbooru** filter SFW with `rating:general`. Danbooru's `s` has
  meant "sensitive" since 2022.
- `getWorkingImageSource` threw on a missing source, which discarded the whole page
  (waifu.im omits it on some images).

constructRequestUrl and getWorkingImageSource are lifted out of the QML and run under
node against stub providers.

    python3 tools/check-booru.py
"""

import json
import re
import subprocess
from pathlib import Path

qml = (Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/services/Booru.qml").read_text()

def lift(name):
    return re.search(rf"^    function {name}\(.*?^    \}}", qml, re.M | re.S).group(0).replace("    function ", "function ", 1)

providers = {name: {"url": url, "api": api} for name, url, api in re.findall(
    r'^        "([\w.]+)": \{\n\s+"name": [^\n]+\n\s+"url": "([^"]+)",\n\s+"api": "([^"]+)"', qml, re.M)}
assert set(providers) == {"yandere", "konachan", "zerochan", "danbooru", "gelbooru", "waifu.im", "t.alcy.cc"}, providers

cases = [
    ("yandere", ["landscape"], False, 1),
    ("gelbooru", ["landscape"], False, 1),
    ("gelbooru", ["landscape"], True, 3),
    ("danbooru", ["landscape"], False, 1),
    ("zerochan", ["hatsune_miku", "blue"], False, 2),
    ("zerochan", [], False, 1),
    ("waifu.im", ["maid", "uniform"], False, 2),
    ("waifu.im", [], True, 1),
    ("t.alcy.cc", ["fj"], False, 1),
    ("t.alcy.cc", [], False, 1),
]
js = f"""
const providers = {json.dumps(providers)};
const root = {{ gelbooruAuth: {{ apiKey: "KEY", userId: "42" }} }};
let currentProvider;
{lift("constructRequestUrl")}
{lift("getWorkingImageSource")}
const urls = {json.dumps(cases)}.map(([p, tags, nsfw, page]) => {{ currentProvider = p; return constructRequestUrl(tags, nsfw, 20, page); }});
console.log(JSON.stringify({{ urls, missing: [getWorkingImageSource(undefined), getWorkingImageSource(null), getWorkingImageSource("")],
    pixiv: getWorkingImageSource("https://i.pximg.net/img-original/img/2020/01/01/00/00/00/82141405_p0.png") }}));
"""
out = json.loads(subprocess.run(["node", "-"], input=js, capture_output=True, text=True, check=True).stdout)
got = dict(zip([f"{p} {' '.join(t)} nsfw={n} page={pg}" for p, t, n, pg in cases], out["urls"]))

expect = {
    "yandere landscape nsfw=False page=1": "https://yande.re/post.json?tags=landscape%20rating%3Asafe&limit=20&page=1",
    "gelbooru landscape nsfw=False page=1": "https://gelbooru.com/index.php?page=dapi&s=post&q=index&json=1&tags=landscape%20rating%3Ageneral&limit=20&pid=0&api_key=KEY&user_id=42",
    "gelbooru landscape nsfw=True page=3": "https://gelbooru.com/index.php?page=dapi&s=post&q=index&json=1&tags=landscape&limit=20&pid=2&api_key=KEY&user_id=42",
    "danbooru landscape nsfw=False page=1": "https://danbooru.donmai.us/posts.json?tags=landscape%20rating%3Ageneral&limit=20&page=1",
    "zerochan hatsune_miku blue nsfw=False page=2": "https://www.zerochan.net/hatsune+miku,blue?json&l=20&s=fav&p=2",
    "zerochan  nsfw=False page=1": "https://www.zerochan.net/?json&l=20&s=fav&t=1&p=1",
    "waifu.im maid uniform nsfw=False page=2": "https://api.waifu.im/images?IncludedTags=maid&IncludedTags=uniform&PageSize=20&PageNumber=2&IsNsfw=False",
    "waifu.im  nsfw=True page=1": "https://api.waifu.im/images?PageSize=20&PageNumber=1&IsNsfw=All",
    "t.alcy.cc fj nsfw=False page=1": "https://t.alcy.cc/fj?json&quantity=20",
    "t.alcy.cc  nsfw=False page=1": "https://t.alcy.cc/ycy?json&quantity=20",
}
for key, url in expect.items():
    assert got[key] == url, f"{key}\n   got {got[key]}\n  want {url}"

assert out["missing"] == [None, None, None], "a missing source must fall through to the caller's fallback, not throw"
assert out["pixiv"] == "https://www.pixiv.net/en/artworks/82141405", out["pixiv"]

# The two messages that replace "That didn't work" when it is not the user's tags.
assert '<title>Just a moment...</title>' in qml, "a Cloudflare check must be reported as one"
assert 'provider === "gelbooru" && !(root.gelbooruAuth.apiKey && root.gelbooruAuth.userId)' in qml, \
    "Gelbooru without a key must say so rather than send a request that 401s"
assert "attempt < root.maxRetries" in qml, "a reset connection (status 0) must be retried; yande.re resets about half"

print("ok: every provider's request is the one it answers, and a missing source no longer throws")
