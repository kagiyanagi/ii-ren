#!/usr/bin/env python3
"""Assert Genius lyrics are fetched once per real track, for that track, without leaking the key.

The feature never worked, and each way it failed was silent: no lyrics is what the pane
shows for a song Genius lacks too.

- **The fetcher.** It was a Node script importing `genius-lyrics-api`, which no setup step
  installed, so every run died on `ERR_MODULE_NOT_FOUND`. `scripts/lyrics/genius_lyrics.py`
  is standard library only. Its page parser is swept here over the shapes a Genius song
  page takes: the header inside the first container (contributors, translations, the
  song's name) that the old shell code dropped with a blind `.slice(1)`, `<br>` breaks,
  links and entities inside lines, section names, the several containers ads split a song
  into, and an instrumental with none.

- **Which hit.** Genius's search answers anything with something: a browser tab's title
  ("(13) Discord | #general") came back as some song's lyrics, and a song Genius lacks
  comes back as the artist's best-known one. A hit is taken only when its artist and its
  title both match the track; the romanised and translated copies Genius ranks first for
  non-English songs are other "artists" and must lose to the original.

- **The order.** The shell passed artist, title; the script read title, artist. Both ends
  are read out of their sources and compared, not transcribed.

- **The key.** It was an argument, readable by any account on the machine in `ps`. It
  travels in the environment now, which only its owner can read.

- **Once per track.** Two handlers in `LyricsService` reacted to every new title, and one
  of them asked even with no artist, which is how web pages got looked up. One component
  now owns the request, and it requires both names.

Run: python3 tools/check-genius-lyrics.py
"""
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import re

ROOT = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"
SCRIPT = ROOT / "scripts/lyrics/genius_lyrics.py"
spec = importlib.util.spec_from_file_location("genius_lyrics", SCRIPT)
genius = importlib.util.module_from_spec(spec)
spec.loader.exec_module(genius)

# --- The page parser ---------------------------------------------------------------

HEADER = ('<div data-exclude-from-selection="true" class="LyricsHeader"><button><span>249 Contributors'
          '</span></button><div><span>Translations</span><ul><li>Español</li></ul></div>'
          '<h2>Get Lucky Lyrics</h2><div>Read More<br></div></div>')
PAGE = (
    '<html><body><div class="SongHeader"><h1>Get Lucky</h1><br></div>'
    f'<div data-lyrics-container="true" class="Lyrics__Container">{HEADER}'
    '[Intro: Pharrell Williams]<br>Like the legend of the phoenix, huh<br>'
    '<a href="/123"><span>All ends with beginnings</span></a><br><br>'
    '[Verse 1]<br/>We&#x27;ve come too far &amp; back<br><i>To give up</i> who we are</div>'
    '<div class="Ad"><br>Advertisement</div>'
    '<div data-lyrics-container="true" class="Lyrics__Container">[Chorus]<br>She&#8217;s up all night'
    '<img src="x.png"><br>  </div>'
    '<div class="Footer">About<br>Genius</div></body></html>'
)
EXPECTED = ("Like the legend of the phoenix, huh\n"
            "All ends with beginnings\n\n"
            "We've come too far & back\n"
            "To give up who we are\n\n"
            "She’s up all night")
got = genius.lyrics_from_page(PAGE)
assert got == EXPECTED, f"page parsed to:\n{got!r}\nwanted:\n{EXPECTED!r}"
assert genius.lyrics_from_page('<div class="SongDescription">This song is an instrumental</div>') == "", \
    "a page with no lyrics container must give no lyrics"

# --- Which hit -------------------------------------------------------------------------

def song(artist, title, url=None, type_="song"):
    return {"type": type_, "result": {"artist_names": artist, "primary_artist": {"name": artist.split(" (")[0]},
                                      "title": title, "url": url or f"https://genius.com/{artist}-{title}"}}

LUCKY = song("Daft Punk (Ft. Nile Rodgers & Pharrell Williams)", "Get Lucky", "https://genius.com/lucky")
LEMON = song("米津玄師 (Kenshi Yonezu)", "Lemon", "https://genius.com/lemon")
HALO = song("Beyoncé", "Halo", "https://genius.com/halo")
ROMANISED = song("Genius Romanizations", "米津玄師 (Kenshi Yonezu) - Lemon (Romanized)")
FAMOUS = song("Daft Punk", "One More Time", "https://genius.com/one-more-time")
JUNK = song("INVALID ARTIST NAME", "N/A2")
ARTICLE = song("Daft Punk", "Get Lucky", "https://genius.com/a/article", type_="article")

CASES = [
    # (hits, artist, title, url or None)
    ([LUCKY], "Daft Punk", "Get Lucky (Radio Edit) [feat. Pharrell Williams and Nile Rodgers]", LUCKY),
    ([LUCKY], "Daft Punk, Pharrell Williams", "Get Lucky", LUCKY),       # a player joining artists
    ([LUCKY], "DaftPunkVEVO", "Daft Punk - Get Lucky (Official Audio) ft. Pharrell Williams", LUCKY),
    ([ROMANISED, LEMON], "Kenshi Yonezu", "Lemon", LEMON),               # the original, not a copy
    ([ROMANISED, LEMON], "米津玄師", "Lemon", LEMON),
    ([HALO], "Beyonce", "Halo", HALO),                                   # accent dropped
    ([JUNK], "Google", "Google Gemini", None),                           # a web page
    ([JUNK], "", "(13) Discord | #general", None),                       # no artist at all
    ([FAMOUS], "Daft Punk", "A Song Genius Does Not Have", None),        # right artist, wrong song
    ([ARTICLE], "Daft Punk", "Get Lucky", None),                         # not a song
    ([LUCKY], "!!!", "Get Lucky", None),                                 # nothing left to compare
]
for hits, artist, title, want in CASES:
    url = genius.pick_hit(hits, artist, title)
    want = want and want["result"]["url"]
    assert url == want, f"{artist!r} / {title!r}: picked {url!r}, wanted {want!r}"

# --- The command line ----------------------------------------------------------------

def run(argv, env):
    out, err = io.StringIO(), io.StringIO()
    old_env, old_fetch = dict(os.environ), genius.fetch_lyrics
    os.environ.clear()
    os.environ.update(env)
    genius.fetch_lyrics = lambda key, artist, title: f"lyrics by {artist} for {title} with {key}"
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = genius.main(argv)
    finally:
        os.environ.clear()
        os.environ.update(old_env)
        genius.fetch_lyrics = old_fetch
    return code, out.getvalue()

code, out = run(["genius_lyrics.py", "Daft Punk", "Get Lucky"], {"GENIUS_API_KEY": "k3y"})
assert code == 0 and json.loads(out) == {"artist": "Daft Punk", "title": "Get Lucky",
                                         "lyrics": "lyrics by Daft Punk for Get Lucky with k3y"}, out
code, out = run(["genius_lyrics.py", "k3y", "Daft Punk", "Get Lucky"], {})
assert code == 2 and out == "", "the key is read from the environment only, never an argument"

# --- The shell's end -----------------------------------------------------------------

QML = (ROOT / "modules/common/utils/GeniusLyrics.qml").read_text()
command = re.search(r"^\s*command:\s*\[(.*)\]\s*$", QML, re.M)
assert command, "GeniusLyrics.qml no longer has a one-line command: [...]"
args = [a.strip() for a in command.group(1).split(",")]
assert args[-2:] == ["root.artist", "root.title"], f"shell passes {args[-2:]}"
assert re.search(r"artist, title = argv\[1\], argv\[2\]", SCRIPT.read_text()), "script no longer reads artist, title"
assert "apiKey" not in command.group(1), "the API key is back on the command line"
assert re.search(r'environment:.*"GENIUS_API_KEY":\s*root\.apiKey', QML), "the key no longer travels in the environment"
assert re.search(r"fetchKey:.*root\.artist && root\.title", QML), "a fetch no longer needs both an artist and a title"

SERVICE = (ROOT / "services/LyricsService.qml").read_text()
assert SERVICE.count("GeniusLyrics {") == 1 and "fetchLyrics" not in SERVICE and "genius.fetch" not in SERVICE, \
    "LyricsService asks Genius itself again; GeniusLyrics owns when to fetch"

print(f"ok: page parsed, {len(CASES)} hit choices, key off argv, one request per track")
