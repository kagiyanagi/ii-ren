"""What read-aloud says for a message: what the transcript shows, as a person would say it.

The transcript renders the model's markdown and LaTeX, so `**`, `#`, `$` and
`\\frac` never reach the screen; handed to a voice as written, they are read
out -- espeak says "$x^2$" as "dollar ex two dollar" and "## Plan" as "hash
hash plan", and the word mark then waits on words nobody can see. This turns a
message into the words a reader would say: markup gone, a formula in words, a
link as its label, a code block skipped. What shapes the voice stays -- full
stops, commas, colons, and a stop at the end of every line, so a heading or a
list item ends on a pause rather than running into the next.

Every spoken character carries where it came from in the message, which is
what tts_marks.marks hands the transcript; every word of a formula points at
the formula, which is one image on screen.

Pure stdlib, so tools/check-read-aloud-text.py runs it on its own.
"""
import html
import re

# What the transcript renders as a formula, as one pattern with what it skips
# over: inline code and an escaped dollar are matched first so that nothing
# inside them starts a formula. The same pattern as services/speechMatch.js
# formulaPattern(), which MessageTextBlock renders with; check-read-aloud-text.py
# holds the two equal. A lone `$` opens a formula only before a non-space and
# closes one only after a non-space, not before a digit -- pandoc's rule -- so
# "$5 and $10" stays prose.
FORMULAS = (r"(`+)(?!`)[\s\S]*?[^`]\1(?!`)|\\\$|\$\$[\s\S]+?\$\$|\$(?=[^\s$`])[^$`]*?[^\s$`]\$(?!\d)"
            r"|\\\[[\s\S]+?\\\]|\\\([\s\S]+?\\\)")

# Blocks the transcript does not show as text: a code block (its own view,
# not prose to read out) and a model's folded-away thinking.
# StringUtils.splitMarkdownBlocks, open-ended while a reply is still arriving.
_HIDDEN = re.compile(r"```[\s\S]*?(?:```|$)|<think>[\s\S]*?(?:</think>|$)")
_ATOM = re.compile(FORMULAS)

# A whole line of no text: a rule, a table's delimiter row, a setext underline.
_RULE_LINE = re.compile(r"[ \t|:]*(?:[-*_][ \t|:]*){3,}|[ \t]*=+[ \t]*")
# What opens a line as layout: a heading's hashes, quote bars, a bullet and a
# task box. An ordered list's number is drawn too, and is read with it.
_LINE_OPENER = re.compile(r"[ \t]{0,3}#{1,6}(?:[ \t]+|$)|[ \t]*>[ \t]?|[ \t]*[-*+][ \t]+(?:\[[ xX]\][ \t]+)?")
# An ordered list's number, which is drawn beside the item: said, with a comma
# rather than its full stop, which would end a sentence before the item began.
_ORDERED = re.compile(r"[ \t]*(\d{1,9})[.)][ \t]+")
_HEADING_CLOSE = re.compile(r"[ \t]+#+[ \t]*$")

_INLINE = re.compile(
    r"(?P<image>!\[[^\]\n]*\]\([^)\n]*\))"
    r"|(?P<link>\[(?P<label>[^\]\n]+)\](?:\([^)\n]*\)|\[[^\]\n]*\]))"
    r"|(?P<footnote>\[\^[^\]\n]+\])"
    r"|<(?P<autolink>(?:https?|ftp)://[^\s<>]+|mailto:[^\s<>]+)>"
    r"|(?P<url>(?:https?|ftp)://[^\s<>()\[\]]*[^\s<>()\[\].,;:!?'\"])"
    r"|(?P<tag></?[A-Za-z][\w-]*(?:\s[^<>]*)?/?>)"
    r"|(?P<entity>&(?:#\d+|#[xX][0-9a-fA-F]+|[A-Za-z]+);)"
    r"|\\(?P<escaped>[!-/:-@\[-`{-~])"
    r"|(?P<arrow>->|→)"
    r"|(?P<about>~(?=\d))"
    r"|(?P<times>(?<=\s)\*(?=\s))"
    r"|(?P<emphasis>[*_]+|~~+)"
    r"|(?P<pipe>\|)"
    r"|(?P<emoji>[\U0001F000-\U0001FAFF☀-➿⬀-⯿️‍⃣])"
)

_PAUSES = ".!?:;,"


class _Said:
    """Spoken characters, each with the message offset it stands for."""

    def __init__(self):
        self.chars, self.at = [], []
        # Whitespace waiting for the next word: a space, or a line's end, which
        # is said as a stop if the line did not end on one of its own.
        self._gap, self._gap_at = "", 0

    def word(self, text: str, at) -> None:
        """`text` said; `at` is one offset for all of it, or one per character."""
        for i, c in enumerate(text):
            where = at if isinstance(at, int) else at[i]
            if c.isspace():
                self.gap("\n" if c == "\n" else " ", where)
                continue
            if self._gap and self.chars:
                if self._gap == "\n" and self.chars[-1] not in _PAUSES:
                    self._put(".", self._gap_at)
                # No space before a stop: "the image ." is said with a gap in it.
                if self._gap == "\n" or c not in _PAUSES:
                    self._put(" ", self._gap_at)
            self._gap = ""
            if c in _PAUSES and self.chars and self.chars[-1] in _PAUSES and c != ".":
                continue  # a pause already said: "a,," or ":," from a cell after a colon
            self._put(c, where)

    def mid_line(self) -> bool:
        """Whether something has been said since the last line ended."""
        return bool(self.chars) and self._gap != "\n"

    def gap(self, kind: str, at: int) -> None:
        if kind == "\n" or not self._gap:
            self._gap, self._gap_at = kind, at

    def _put(self, c: str, at: int) -> None:
        self.chars.append(c)
        self.at.append(at)

    def done(self) -> tuple:
        if self.chars and self.chars[-1] not in _PAUSES:
            self._put(".", self._gap_at if self._gap else self.at[-1])
        return "".join(self.chars), self.at


def speech(text: str) -> tuple:
    """``(said, at)``: what to say for `text`, and the offset in `text` of each
    character of `said`. Empty when nothing in it is readable."""
    text = text or ""
    out = _Said()
    pos = 0
    for hidden in _HIDDEN.finditer(text):
        _blocks(text, pos, hidden.start(), out)
        out.gap("\n", hidden.start())
        pos = hidden.end()
    _blocks(text, pos, len(text), out)
    return out.done()


def spoken(text: str) -> str:
    return speech(text)[0]


def _blocks(text: str, start: int, end: int, out: _Said) -> None:
    """The prose between hidden blocks: its code spans and formulas as units,
    the text around them line by line."""
    pos = start
    for atom in _ATOM.finditer(text, start, end):
        _lines(text, pos, atom.start(), out)
        whole = atom.group(0)
        if whole.startswith("`"):  # code: shown as written, without its backticks
            ticks = len(atom.group(1))
            inner = whole[ticks:-ticks]
            lead = len(inner) - len(inner.lstrip(" "))
            out.word(inner.strip(" "), list(range(atom.start() + ticks + lead, atom.end())))
        elif whole == "\\$":
            out.word("$", atom.start() + 1)
        else:
            out.gap(" ", atom.start())
            out.word(math_words(_formula_body(whole)), atom.start())
            out.gap(" ", atom.end())
        pos = atom.end()
    _lines(text, pos, end, out)


def _formula_body(whole: str) -> str:
    for opener, closer in (("$$", "$$"), ("$", "$"), ("\\[", "\\]"), ("\\(", "\\)")):
        if whole.startswith(opener) and whole.endswith(closer):
            return whole[len(opener):len(whole) - len(closer)]
    return whole


def _lines(text: str, start: int, end: int, out: _Said) -> None:
    pos = start
    while pos < end:
        newline = text.find("\n", pos, end)
        stop = end if newline < 0 else newline
        line_start = text.rfind("\n", 0, pos) + 1
        line_end = text.find("\n", pos)
        line_end = len(text) if line_end < 0 else line_end
        if pos == line_start:
            if _RULE_LINE.fullmatch(text, line_start, line_end):
                pos = stop
            else:
                heading = False
                while (opener := _LINE_OPENER.match(text, pos, stop)) and opener.end() > pos:
                    heading = heading or "#" in opener.group(0)
                    pos = opener.end()
                number = _ORDERED.match(text, pos, stop)
                if number:
                    out.word(number.group(1) + ",", number.start(1))
                    out.gap(" ", number.end())
                    pos = number.end()
                closing = _HEADING_CLOSE.search(text, pos, stop) if heading else None
                if closing:
                    _inline(text, pos, closing.start(), out)
                    pos = stop
        if pos < stop:
            _inline(text, pos, stop, out)
        if newline >= 0:
            out.gap("\n", newline)
        pos = stop + 1 if newline >= 0 else end


def _inline(text: str, start: int, end: int, out: _Said) -> None:
    pos = start
    for m in _INLINE.finditer(text, start, end):
        if m.start() > pos:
            out.word(text[pos:m.start()], list(range(pos, m.start())))
        pos = m.end()
        kind = m.lastgroup
        if kind == "link":  # its label, which is what is shown
            _inline(text, m.start("label"), m.end("label"), out)
        elif kind in ("autolink", "url"):
            _url(m.group(kind), m.start(kind), out)
        elif kind == "tag":
            if re.match(r"<br\b", m.group(0), re.I):
                out.gap("\n", m.start())
        elif kind == "entity":
            char = html.unescape(m.group(0))
            out.word(" " if char == "\xa0" else char, m.start())
        elif kind == "escaped":
            out.word(m.group(kind), m.start(kind))
        elif kind == "arrow":
            out.word(" to ", m.start())
        elif kind == "about":
            out.word("about ", m.start())
        elif kind == "times":
            out.word("times", m.start())
        elif kind == "emphasis":
            if not _is_markup(text, m.start(), m.end()):
                out.word(m.group(0), list(range(m.start(), m.end())))
        elif kind == "pipe":
            # A table's cell wall: a pause between two cells, nothing at the row's ends.
            line_end = text.find("\n", m.end())
            after = text[m.end():len(text) if line_end < 0 else line_end]
            if out.mid_line() and out.chars[-1] not in _PAUSES and after.strip(" \t|"):
                out.word(",", m.start())
            out.gap(" ", m.start())
        # image, footnote, emoji: not words on the page
    if pos < end:
        out.word(text[pos:end], list(range(pos, end)))


def _is_markup(text: str, start: int, end: int) -> bool:
    """Whether a run of `*`, `_` or `~~` opens or closes emphasis (CommonMark's
    flanking rule) rather than being a literal one -- 2 * 3, snake_case."""
    before = text[start - 1] if start > 0 else " "
    after = text[end] if end < len(text) else " "
    opens = not after.isspace() and (after.isalnum() or not before.isalnum())
    closes = not before.isspace() and (before.isalnum() or not after.isalnum())
    if text[start] == "_" and before.isalnum() and after.isalnum():
        return False  # inside a word, an underscore is a character
    return opens or closes


def _url(url: str, at: int, out: _Said) -> None:
    """A link's host, which is the part a reader says: "github.com"."""
    host = re.match(r"(?:[a-z]+://|mailto:)(?:[^@/\s]*@)?(?:www\.)?([^/?#:\s]+)", url)
    if not host:
        out.word(url, list(range(at, at + len(url))))
        return
    out.word(host.group(1), list(range(at + host.start(1), at + host.end(1))))


# ── LaTeX ────────────────────────────────────────────────────────────────

_GREEK = {name: name for name in (
    "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau "
    "upsilon phi chi psi omega").split()}
_GREEK.update({name.capitalize(): name for name in _GREEK})
_GREEK.update({"var" + name: name for name in ("epsilon", "theta", "pi", "rho", "sigma", "phi", "kappa")})

_WORDS = {
    **_GREEK,
    "cdot": "times", "times": "times", "ast": "times", "div": "divided by", "pm": "plus or minus",
    "mp": "minus or plus", "leq": "is less than or equal to", "le": "is less than or equal to",
    "geq": "is greater than or equal to", "ge": "is greater than or equal to", "neq": "is not equal to",
    "ne": "is not equal to", "approx": "is approximately", "sim": "is similar to", "simeq": "is approximately",
    "equiv": "is equivalent to", "cong": "is congruent to", "propto": "is proportional to", "ll": "is much less than",
    "gg": "is much greater than", "infty": "infinity", "to": "to", "rightarrow": "to", "longrightarrow": "to",
    "mapsto": "maps to", "Rightarrow": "implies", "implies": "implies", "Leftrightarrow": "if and only if",
    "iff": "if and only if", "leftarrow": "from", "in": "in", "notin": "not in", "ni": "contains",
    "subset": "is a subset of", "subseteq": "is a subset of", "supset": "is a superset of", "cup": "union",
    "cap": "intersection", "setminus": "minus", "emptyset": "the empty set", "varnothing": "the empty set",
    "forall": "for all", "exists": "there exists", "neg": "not", "land": "and", "wedge": "and", "lor": "or",
    "vee": "or", "partial": "partial", "nabla": "nabla", "prime": "prime", "circ": "composed with",
    "degree": "degrees", "ldots": "and so on", "cdots": "and so on", "dots": "and so on", "vdots": "and so on",
    "therefore": "therefore", "because": "because", "angle": "angle", "triangle": "triangle",
    "perp": "is perpendicular to", "parallel": "is parallel to", "hbar": "h bar", "ell": "l",
    "sin": "sine", "cos": "cosine", "tan": "tangent", "sec": "secant", "csc": "cosecant", "cot": "cotangent",
    "arcsin": "arc sine", "arccos": "arc cosine", "arctan": "arc tangent", "sinh": "hyperbolic sine",
    "cosh": "hyperbolic cosine", "tanh": "hyperbolic tangent", "log": "log", "ln": "natural log", "lg": "log",
    "exp": "exp", "det": "determinant", "dim": "dimension", "ker": "kernel", "gcd": "gcd", "lcm": "lcm",
    "deg": "degree", "arg": "arg", "max": "max", "min": "min", "sup": "sup", "inf": "inf", "Pr": "probability",
    "%": "percent", "$": "dollars", "&": "and", "#": "number", "{": "", "}": "", "|": "",
}
# Take an argument and say only it: type and font changes, sizing, bare grouping.
_SAY_ARGUMENT = set(
    "text textrm textbf textit textsf texttt textnormal mathrm mathbf mathit mathsf mathtt mathcal mathbb "
    "mathfrak mathscr mathnormal operatorname boldsymbol bm mbox emph underline".split())
_SILENT = set("left right big Big bigg Bigg bigl bigr Bigl Bigr biggl biggr Biggl Biggr limits nolimits "
              "displaystyle textstyle scriptstyle quad qquad , ; : ! nonumber notag label tag".split())
_ACCENTS = {"hat": "hat", "widehat": "hat", "bar": "bar", "overline": "bar", "tilde": "tilde",
            "widetilde": "tilde", "dot": "dot", "ddot": "double dot", "vec": "vector", "overrightarrow": "vector"}
_BIG = {"sum": "the sum", "prod": "the product", "int": "the integral", "iint": "the double integral",
        "iiint": "the triple integral", "oint": "the contour integral", "lim": "the limit",
        "bigcup": "the union", "bigcap": "the intersection"}
_SYMBOL = {"+": "plus", "-": "minus", "=": "equals", "<": "is less than", ">": "is greater than", "/": "over",
           "*": "times", "!": "factorial", "'": "prime", "×": "times", "·": "times", "−": "minus",
           "≤": "is less than or equal to", "≥": "is greater than or equal to", "≠": "is not equal to",
           "≈": "is approximately", "→": "to", "∞": "infinity", "±": "plus or minus", "&": "", "~": "",
           "(": "", ")": "", "[": "", "]": "", "{": "", "}": "", "|": "", ".": "", ":": "", ";": ",", ",": ","}
_POWERS = {"2": "squared", "3": "cubed", "T": "transpose", "\\top": "transpose", "\\circ": "degrees",
           "-1": "inverse", "\\prime": "prime", "'": "prime", "''": "double prime", "*": "star", "\\ast": "star",
           "+": "plus", "-": "minus", "\\dagger": "dagger"}

_TEX = re.compile(r"\\[A-Za-z]+|\\.|\d+(?:\.\d+)?|[A-Za-z]|\s+|.", re.S)


def math_words(tex: str) -> str:
    """A formula as words: "E = mc^2" is "E equals m c squared"."""
    tokens = [t for t in _TEX.findall(tex) if not t.isspace()]
    words = _MathReader(tokens).run()
    said = re.sub(r"\s+", " ", " ".join(w for w in words if w))
    return re.sub(r"(?:\s*,)+", ",", said).strip(" ,")


class _MathReader:
    def __init__(self, tokens: list):
        self.tokens, self.pos = tokens, 0

    def run(self) -> list:
        return self.sequence(closing=None)

    def peek(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def take(self):
        token = self.peek()
        self.pos += 1
        return token

    def sequence(self, closing) -> list:
        words = []
        while self.peek() is not None and self.peek() != closing:
            words += self.item()
        if closing is not None and self.peek() == closing:
            self.pos += 1
        return words

    def argument(self) -> list:
        """A command's or a script's argument: a {group}, or the next item."""
        if self.peek() == "{":
            self.pos += 1
            return self.sequence("}")
        if self.peek() is None:
            return []
        return self.item(scripts=False)

    def raw_argument(self) -> str:
        """The argument as written, for comparing against _POWERS."""
        if self.peek() != "{":
            return self.peek() or ""
        depth, end = 0, self.pos
        for end in range(self.pos, len(self.tokens)):
            depth += {"{": 1, "}": -1}.get(self.tokens[end], 0)
            if depth == 0:
                break
        return "".join(self.tokens[self.pos + 1:end])

    def text_argument(self) -> list:
        """\\text{...}: words as written, not letters each a variable."""
        if self.peek() != "{":
            return [self.take() or ""]
        self.pos += 1
        depth, parts = 1, []
        while self.peek() is not None:
            token = self.take()
            depth += {"{": 1, "}": -1}.get(token, 0)
            if depth == 0:
                break
            parts.append(token)
        return ["".join(parts)]

    def item(self, scripts: bool = True) -> list:
        token = self.take()
        big = None
        if token == "{":
            words = self.sequence("}")
        elif token.startswith("\\") and len(token) > 1:
            name = token[1:]
            if name in ("frac", "dfrac", "tfrac", "cfrac"):
                words = self.argument() + ["over"] + self.argument() + [","]
            elif name == "binom":
                words = self.argument() + ["choose"] + self.argument()
            elif name == "sqrt":
                root = ""
                if self.peek() == "[":
                    self.pos += 1
                    while self.peek() not in (None, "]"):
                        root += self.take()
                    self.pos += 1
                head = {"": "the square root of", "3": "the cube root of"}.get(root, f"the {root}th root of")
                words = [head] + self.argument() + [","]
            elif name in ("begin", "end"):
                self.text_argument()
                words = [","]
            elif name in _ACCENTS:
                words = self.argument() + [_ACCENTS[name]]
            elif name in ("text", "textrm", "textbf", "textit", "mbox", "operatorname", "mathrm", "texttt", "textsf"):
                words = self.text_argument()
            elif name in _SAY_ARGUMENT:
                words = self.argument()
            elif name in _BIG:
                words, big = [_BIG[name]], name
            elif name in _SILENT:
                words = []
            elif name == "\\":
                words = [","]
            elif name in _WORDS:
                words = [_WORDS[name]]
            else:
                words = []  # a symbol with no common reading: its arguments, if any, follow
        elif token in ("^", "_"):
            words = []  # a script with nothing before it
            self.pos -= 1
            return self.scripts([], None)
        else:
            words = [_SYMBOL.get(token, token)]
        return self.scripts(words, big) if scripts else words

    def scripts(self, words: list, big) -> list:
        """Super- and subscripts after an item: x^2 is "x squared"; on a sum or a
        limit they are its bounds."""
        lower, upper = [], None
        while self.peek() in ("^", "_"):
            kind = self.take()
            if kind == "_":
                lower += self.argument()
            else:
                raw = self.raw_argument()
                upper = (raw, self.argument())
        if big:
            if lower:
                words = words + (["as"] if big == "lim" else ["from"]) + lower
            if upper:
                words = words + ["to"] + upper[1]
            return words + ["of"]
        # A word written as a subscript (x_{max}) is said as one; i j stays two.
        if len(lower) >= 3 and all(len(w) == 1 and w.isalpha() for w in lower):
            lower = ["".join(lower)]
        words = words + lower
        if upper:
            raw, said = upper
            words = words + ([_POWERS[raw]] if raw in _POWERS else ["to the power of"] + said + [","])
        return words
