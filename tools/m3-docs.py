#!/usr/bin/env python3
"""Mirror m3.material.io -- every guideline page and the token database -- as greppable text.

m3.material.io is an Angular app, so a plain fetch of a page returns an empty shell.
The prose comes from /_dsm/content/m3/<version>/<file>.json and the token tables from
/_dsm/data/dsdb-m3/<version>/<TYPE>.<id>.json; the page index and <version> are baked
into the app's main.js. This reads all three and writes:

  ~/.cache/m3-docs/<version>/pages/<slug>.md    one file per page, tabs as "## [TAB]"
  ~/.cache/m3-docs/<version>/tokens/<name>.txt  "token = value   [context]", references resolved:
      motion-shape-state, spacing, typography, elevation, color, component-<slug>

.github/M3.md is the distilled version for this shell. Use this when M3.md does not
cover something, or to check a number in it:

  python3 tools/m3-docs.py              # fetch once per site version, print the path
  python3 tools/m3-docs.py --force      # refetch the current version
  grep -ri "pressed.container.shape" "$(python3 tools/m3-docs.py)"/tokens
"""
import concurrent.futures as cf, html.parser, json, pathlib, re, sys, urllib.request

SITE = "https://m3.material.io"
CACHE = pathlib.Path.home() / ".cache/m3-docs"


def get(path):
    req = urllib.request.Request(SITE + path, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode()


def site_index():
    """(version, pages) from the app bundle; pages is the router table with file ids."""
    main = re.search(r'src="(/static/angular/main\.[0-9a-f]+\.js)"', get("/")).group(1)
    js = get(main)
    version = re.search(r'carbonVersion:"([^"]+)"', js).group(1)
    tables = []
    for m in re.finditer(r"JSON\.parse\('", js):
        try:
            obj, _ = json.JSONDecoder().raw_decode(js[m.end():].replace("\\'", "'"))
        except ValueError:
            continue
        if isinstance(obj, dict) and isinstance(obj.get("v"), list):
            tables.append(obj["v"])
    pages = [p for p in max(tables, key=len) if p.get("exportedCarbonFileId")]
    assert len(pages) > 50, f"page index shrank to {len(pages)}: the bundle layout changed"
    return version, pages


class Markdown(html.parser.HTMLParser):
    """Just enough HTML -> markdown for the CMS output: headings, lists, tables, bold."""

    def __init__(self):
        super().__init__()
        self.out, self.depth, self.cell = [], 0, False

    def handle_starttag(self, tag, attrs):
        if tag in ("h1", "h2", "h3", "h4", "h5"):
            self.out.append("\n\n" + "#" * (int(tag[1]) + 1) + " ")
        elif tag in ("p", "br"):
            self.out.append(" " if self.cell else ("\n\n" if tag == "p" else "\n"))
        elif tag in ("ul", "ol"):
            self.depth += 1
        elif tag == "li":
            self.out.append("\n" + "  " * (self.depth - 1) + "- ")
        elif tag == "tr":
            self.out.append("\n| ")
        elif tag in ("td", "th"):
            self.cell = True
        elif tag in ("strong", "b"):
            self.out.append("**")
        elif tag == "code":
            self.out.append("`")

    def handle_endtag(self, tag):
        if tag in ("ul", "ol"):
            self.depth -= 1
            self.out.append("\n")
        elif tag in ("td", "th"):
            self.cell = False
            self.out.append(" | ")
        elif tag in ("strong", "b"):
            self.out.append("**")
        elif tag == "code":
            self.out.append("`")

    def handle_data(self, data):
        self.out.append(data)


def md(fragment):
    p = Markdown()
    p.feed(fragment or "")
    text = re.sub(r"\*\*\s*\*\*", "", "".join(p.out))
    return re.sub(r"\n{3,}", "\n\n", re.sub(r"[ \t]+\n", "\n", text)).strip()


def page_markdown(d):
    """The page as markdown, plus the token tables it embeds as (type, resource) pairs."""
    out, tables = [f"# {d.get('headerTitle') or d.get('title')}\n\n{d.get('description', '')}"], []
    for s in d.get("sections", []):
        if not s.get("isVisible", True):
            continue
        out.append(f"\n\n## [TAB] {s['name']}")
        for b in s.get("contentBlocks", []):
            if b.get("isHidden"):
                continue
            if b.get("title"):
                out.append(f"\n\n### {md(b['title'])}")
            for c in b.get("contentChunks", []):
                kind = c.get("contentChunkType")
                if kind == "TEXT":
                    out.append("\n\n" + md(c.get("htmlValue")))
                elif kind in ("IMAGE", "VIDEO"):
                    # Captions carry the DO / DON'T / CAUTION verdicts; bare alt text is noise.
                    mod, cap = c.get("captionModifier"), md(c.get("footer"))
                    if mod or cap:
                        tag = f"**{(c.get('captionModifierCustomName') or mod).upper()}** " if mod else ""
                        out.append("\n\n> " + (tag + cap).replace("\n", " "))
                elif kind == "RESOURCE":
                    kind, res = c.get("libraryModuleType"), c.get("resourceName", "")
                    out.append(f"\n\n[token table: {kind}]")
                    if kind == "TOKEN_TABLE":
                        tables.append((kind, res.split("components/")[1]))
                    elif kind != "STATUS_TABLE":
                        tables.append((kind, res.split("/")[1]))
    return re.sub(r"\n{3,}", "\n\n", "".join(out)) + "\n", tables


def fmt(v):
    """One token value as text. Proto3 omits zeros, hence the .get(k, 0) everywhere."""
    if "tokenName" in v:
        return "->" + v["tokenName"]
    if "color" in v:
        c = v["color"]
        hexa = "#%02x%02x%02x" % tuple(round(c.get(k, 0) * 255) for k in ("red", "green", "blue"))
        return hexa + ("" if c.get("alpha", 1) == 1 else f" alpha {c['alpha']}")
    dp = lambda x: f"{x.get('value', 0)}dp"
    simple = {
        "length": lambda x: dp(x), "elevation": lambda x: dp(x),
        "opacity": lambda x: f"opacity {x}", "durationMs": lambda x: f"{x}ms",
        "numeric": str, "fontWeight": lambda x: f"weight {x}",
        "fontSize": lambda x: f"size {x.get('value')}", "lineHeight": lambda x: f"line-height {x.get('value')}",
        "fontTracking": lambda x: f"tracking {x.get('value', 0)}",
        "fontNames": lambda x: "font " + ", ".join(x["values"]),
        "axisValue": lambda x: f"axis {x.get('tag')}={x.get('value')}",
        "cubicBezier": lambda x: "bezier(%s)" % ", ".join(str(x.get(k, 0)) for k in ("x0", "y0", "x1", "y1")),
        "svgPath": lambda x: "path " + x, "textTransform": str,
        "type": lambda x: "typescale " + x.get("fontSizeTokenName", "").rsplit(".", 1)[0],
        "customComposite": lambda x: "spring " + ", ".join(f"{k} ->{p.get('tokenName')}" for k, p in x["properties"].items()),
    }
    for key, f in simple.items():
        if key in v:
            return f(v[key])
    if "shape" in v:
        s = v["shape"]
        corners = {k: s[k].get("value", 0) for k in ("topLeft", "topRight", "bottomRight", "bottomLeft") if k in s}
        size = dp(s["defaultSize"]) if "defaultSize" in s else ""
        return " ".join(x for x in ("shape", s.get("family", "").replace("SHAPE_FAMILY_", "").lower(), size,
                                    json.dumps(corners) if corners else "") if x)
    return "undefined" if v.get("undefined") else "?"


def token_lines(system, resolved):
    tags = {t["name"]: t["displayName"] for t in system.get("tags", [])}
    names = {t["name"]: t["tokenName"] for t in system.get("tokens", [])}
    rows = set()
    for v in system.get("values", []):
        name = names.get(v["name"].split("/values/")[0])
        if not name:
            continue
        val = fmt(v)
        if val.startswith("->") and val[2:] in resolved:
            val += f" = {resolved[val[2:]]}"
        ctx = [tags.get(c, c.rsplit("/", 1)[-1]) for c in v.get("contextTags", [])]
        rows.add(f"{name} = {val}" + (f"   [{', '.join(ctx)}]" if ctx else ""))
    return sorted(rows)


def main():
    version, pages = site_index()
    root = CACHE / version
    if (root / "done").exists() and "--force" not in sys.argv:
        print(root)
        return
    (root / "pages").mkdir(parents=True, exist_ok=True)
    (root / "tokens").mkdir(exist_ok=True)

    def fetch_page(p):
        text, tables = page_markdown(json.loads(get(f"/_dsm/content/m3/{version}/{p['exportedCarbonFileId']}")))
        (root / "pages" / ((p["slug"] or "home").replace("/", "__") + ".md")).write_text(text)
        return p["slug"].rsplit("/", 1)[-1], tables

    with cf.ThreadPoolExecutor(8) as ex:
        found = list(ex.map(fetch_page, pages))
    tables = {(kind, ident): slug for slug, ts in found for kind, ident in ts}

    def fetch_table(item):
        (kind, ident), slug = item
        return kind, slug, json.loads(get(f"/_dsm/data/dsdb-m3/{version}/{kind}.{ident}.json"))["system"]

    with cf.ThreadPoolExecutor(8) as ex:
        systems = list(ex.map(fetch_table, tables.items()))

    # System tokens first, so a component's "->md.sys.shape.corner.large" can say "= 16dp".
    resolved = {}
    for kind, _, system in systems:
        if kind == "TOKEN_TABLE":
            continue
        names = {t["name"]: t["tokenName"] for t in system.get("tokens", [])}
        for literal in (True, False):
            for v in system.get("values", []):
                name = names.get(v["name"].split("/values/")[0])
                if not name or v.get("contextTags") or ("tokenName" in v) == literal:
                    continue
                if literal:
                    resolved.setdefault(name, fmt(v))
                elif v["tokenName"] in resolved:
                    resolved.setdefault(name, resolved[v["tokenName"]])
    for kind, slug, system in systems:
        name = f"component-{slug}" if kind == "TOKEN_TABLE" else \
            {"TOKEN_TYPE_UNSPECIFIED": "motion-shape-state", "MEASUREMENT": "spacing"}.get(kind, kind.lower())
        lines = token_lines(system, resolved)
        path = root / "tokens" / f"{name}.txt"
        prior = path.read_text().splitlines() if path.exists() and kind == "TOKEN_TABLE" else []
        path.write_text("\n".join(sorted(set(prior) | set(lines))) + "\n")  # app-bars embeds two tables

    assert any("md.sys.motion.spring" in p.read_text() for p in (root / "tokens").glob("*.txt")), \
        "no spring tokens: the token DB layout changed"
    (root / "done").touch()
    print(root)


if __name__ == "__main__":
    main()
