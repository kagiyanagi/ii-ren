#!/usr/bin/env python3
"""Plain lyrics for one track from Genius, for modules/common/utils/GeniusLyrics.qml.

    GENIUS_API_KEY=... genius_lyrics.py ARTIST TITLE

Prints one JSON object, {"artist", "title", "lyrics"}. It names the track it answers, so
the shell can drop an answer that lands after the track has changed; "lyrics" is "" when
Genius has no song by that artist with that title.

The key comes in the environment, never as an argument: any account on the machine can
read another's command line in `ps`, only the owner can read its environment.

Genius's API finds the song but does not serve its lyrics, so they are read off the song's
page. Its search answers any query with something, a web page's title included, and when
the song is missing it offers the artist's best-known one instead; a hit is used only when
both its artist and its title match the track. Standard library only: this replaced a Node
script whose npm package nothing ever installed.
"""
import html.parser
import json
import os
import re
import sys
import unicodedata
import urllib.parse
import urllib.request

API = "https://api.genius.com/search?q="
# Genius serves its pages to a browser; urllib's own agent is refused.
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
TIMEOUT = 15

# "(Remastered 2011)", "[Official Video]", and everything from a "feat." on.
EXTRAS = re.compile(r"\([^)]*\)|\[[^\]]*\]|\s(?:feat|ft|featuring)\.?\s.*$", re.IGNORECASE)


def clean_title(title):
    return " ".join(EXTRAS.sub(" ", title).split())


def squash(text):
    """Letters and digits only, accents dropped, case folded: what two spellings share."""
    text = unicodedata.normalize("NFKD", text)
    return "".join(c for c in text.casefold() if c.isalnum() and not unicodedata.combining(c))


def overlaps(a, b):
    """One contains the other, so "Daft Punk" matches "DaftPunkVEVO" and "Daft Punk, Pharrell"."""
    a, b = squash(a), squash(b)
    return bool(a and b) and (a in b or b in a)


def pick_hit(hits, artist, title):
    """The url of the first song hit by this artist with this title, or None."""
    wanted = clean_title(title) or title
    for hit in hits:
        if hit.get("type") != "song":
            continue
        song = hit.get("result") or {}
        names = [song.get("artist_names") or "", (song.get("primary_artist") or {}).get("name") or ""]
        if not any(overlaps(name, artist) for name in names):
            continue
        if not overlaps(clean_title(song.get("title") or ""), wanted):
            continue
        if song.get("url"):
            return song["url"]
    return None


VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}


class LyricsParser(html.parser.HTMLParser):
    """Text of every `data-lyrics-container` on a song page, `<br>` as a line break.

    A container opens with a header (contributor count, translations, the song's name)
    marked `data-exclude-from-selection`, which is skipped whole.
    """

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.depth = 0  # open elements inside the current container; 0 outside one
        self.skip = 0  # depth at which an excluded element opened; 0 when not in one
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in VOID:
            self.handle_startendtag(tag, attrs)
            return
        attrs = dict(attrs)
        if self.depth:
            self.depth += 1
            if not self.skip and attrs.get("data-exclude-from-selection") == "true":
                self.skip = self.depth
        elif attrs.get("data-lyrics-container") == "true":
            # Ads split the lyrics into several containers, each starting a new line.
            self.depth = 1
            self.parts.append("\n")

    def handle_startendtag(self, tag, attrs):
        if tag == "br" and self.depth and not self.skip:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in VOID or not self.depth:
            return
        if self.skip == self.depth:
            self.skip = 0
        self.depth -= 1

    def handle_data(self, data):
        if self.depth and not self.skip:
            self.parts.append(data)


def lyrics_from_page(page):
    """The lyrics on a song page, without "[Chorus]"-style section names, one blank line
    at most between stanzas; "" for a page with none (an instrumental)."""
    parser = LyricsParser()
    parser.feed(page)
    lines = []
    for line in "".join(parser.parts).split("\n"):
        line = line.strip()
        # A section name starts a stanza, even where a container boundary has no break.
        if line.startswith("[") and line.endswith("]"):
            line = ""
        if line or (lines and lines[-1]):
            lines.append(line)
    return "\n".join(lines).strip()


def get(url, headers):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **headers})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return response.read().decode("utf-8", "replace")


def fetch_lyrics(api_key, artist, title):
    query = f"{clean_title(title) or title} {artist}"
    found = json.loads(get(API + urllib.parse.quote(query), {"Authorization": f"Bearer {api_key}"}))
    url = pick_hit((found.get("response") or {}).get("hits") or [], artist, title)
    return lyrics_from_page(get(url, {})) if url else ""


def main(argv):
    api_key = os.environ.get("GENIUS_API_KEY", "")
    if len(argv) != 3 or not api_key:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    artist, title = argv[1], argv[2]
    try:
        lyrics = fetch_lyrics(api_key, artist, title)
    except Exception as error:  # network, an HTTP error, a page or answer not as expected
        print(f"genius_lyrics: {artist} - {title}: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"artist": artist, "title": title, "lyrics": lyrics}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
