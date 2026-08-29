#!/usr/bin/env python3
"""Assert MprisController still tells a YouTube hover preview from real playback.

Hovering a thumbnail on YouTube opens a media session of its own, which takes over the
plasma-browser-integration bus and keeps its title and art long after the cursor moves
on. The tell is the page URL: real playback always sits on a video page, a preview sits
on whatever listing page it was grazed from. That regex pair is the whole fix, so it gets
checked here rather than by hovering things and squinting at the dock.

Run: python3 tools/check-mpris-hover-preview.py
"""
import pathlib, re, sys

SRC = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/services/MprisController.qml"
BODY = re.search(r"return /(.+?)/\.test\(url\) && !/(.+?)/\.test\(url\);", SRC.read_text())
assert BODY, "isHoverPreview no longer matches on two regexes over xesam:url"

# QML escapes the slashes in its regex literals; Python needs them bare.
on_youtube, is_video_page = (re.compile(g.replace(r"\/", "/")) for g in BODY.groups())
is_preview = lambda url: bool(on_youtube.search(url)) and not is_video_page.search(url)

PREVIEWS = [
    "https://www.youtube.com/results?search_query=andorid+dock",
    "https://www.youtube.com/results?search_query=how+to+watch+movies",
    "https://www.youtube.com/",
    "https://youtube.com/@somechannel/videos",
    "https://m.youtube.com/feed/subscriptions",
]
REAL = [
    "https://www.youtube.com/watch?v=saNJV9nlrMA&list=PLpfQ&index=14",
    "https://www.youtube.com/shorts/abcdefghijk",
    "https://www.youtube.com/embed/abcdefghijk",
    "https://music.youtube.com/watch?v=abcdefghijk",
    "https://youtu.be/abcdefghijk",
    "https://soundcloud.com/artist/track",  # not YouTube, never our business
    "",  # local players expose no url at all
]

for url in PREVIEWS:
    assert is_preview(url), f"hover preview not caught: {url}"
for url in REAL:
    assert not is_preview(url), f"real playback dropped as a preview: {url}"

print(f"ok: {len(PREVIEWS)} previews filtered, {len(REAL)} real players kept")
