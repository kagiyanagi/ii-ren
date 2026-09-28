#!/usr/bin/env python3
"""One Hermes turn: your own turns are a bubble, and every fold goes through Revealer.

None of it shows in a still frame:
- The tool row animated its own height but showed its details with
  `visible: root.open` and no clip, so on open the card painted over the next
  paragraph while the height grew, and on close it vanished on the first frame
  and the height shrank over nothing.
- A tool group's rows were `open ? calls : []`, destroyed on the frame the fold
  started closing, so its Revealer collapsed over nothing.
- The think block closed on its own enter spec, and its "Thinking" printed a
  `Math.random()` number of dots, evaluated once, that never moved.
- The code block's line numbers were a Repeater of a Text per line.
- The code block wrote its text back into `segmentContent` unguarded, which
  replaced the caller's `segmentContent: modelData.content` binding on the first
  streamed chunk, so a fence that opened mid-reply froze at whatever had arrived.
- Tool arguments printed as JSON, so a written file was one escaped string wrapped
  across the whole sidebar, and nothing long stopped at a height.
The bubble's width, the clamp rule and the argument layout are arithmetic, so they
are lifted out and run under node.
"""
import json
import re
import subprocess
from pathlib import Path

P = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/ii/sidebarPolicies"
msg = (P / "hermes/HermesMessage.qml").read_text()
row = (P / "hermes/ToolActivityRow.qml").read_text()
group = (P / "hermes/HermesToolSummary.qml").read_text()
think = (P / "aiChat/MessageThinkBlock.qml").read_text()
code = (P / "aiChat/MessageCodeBlock.qml").read_text()


def node(js):
    return json.loads(subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout)


def expr(src, name):
    m = re.search(rf"property \w+ {name}:\s*(.+)", src)
    assert m, f"`{name}` is gone"
    return m.group(1).strip()


# Folds: one recipe, built lazily and kept.
for name, src in (("ToolActivityRow", row), ("HermesToolSummary", group), ("MessageThinkBlock", think)):
    assert "Revealer {" in src, f"{name}: its fold no longer goes through Revealer"
    rot = re.search(r"Behavior on rotation\s*\{\s*animation:\s*Appearance\.animation\.(\w+)\.", src)
    assert rot and rot.group(1) == "elementMove", \
        f"{name}: the chevron flips on {rot and rot.group(1)}; a rotation is spatial (elementMove)"
for name, src in (("ToolActivityRow", row), ("HermesToolSummary", group)):
    assert re.search(r"onOpenChanged:\s*if \(root\.open\) root\.built = true", src), \
        f"{name}: the fold's content is no longer latched built on first open"
assert not re.search(r"^\s{4}Behavior on implicitHeight", row, re.M), \
    "ToolActivityRow: the root animates its own height again, a second motion around the Revealer"
assert not re.search(r"visible:\s*root\.open", row), "ToolActivityRow: the details pop on `visible: open` again"
assert re.search(r"active:\s*root\.built", row), "ToolActivityRow: the details are no longer built lazily"
assert "values: root.open" not in group and "values: root.built ?" in group, \
    "HermesToolSummary: the rows are bound to `open` again, destroyed as the fold starts closing"

# Think block: one button for a header, no fake motion, no wrong base.
assert "MouseArea" not in think, "MessageThinkBlock: a raw MouseArea is back on the header"
assert "Math.random" not in think, "MessageThinkBlock: the label fakes motion with random dots again"
assert re.search(r"MaterialLoadingIndicator\s*\{[^}]*visible:\s*!root\.completed", think, re.S), \
    "MessageThinkBlock: nothing says the model is still thinking"
assert re.search(r"RippleButton\s*\{\s*id:\s*header", think), "MessageThinkBlock: the header is not one RippleButton"

# Code block: one card on the right base, one text for the numbers.
for name, src in (("MessageThinkBlock", think), ("MessageCodeBlock", code)):
    assert "colSurfaceContainer" not in src, \
        f"{name}: a colSurfaceContainer token sits on a colLayer card; each is solved for one base"
assert re.search(r"onTextChanged:\s*\{\s*if \(!root\.editing\) return\s*segmentContent = text", code), \
    "MessageCodeBlock: an unguarded write-back replaces the caller's binding, and a block that opened mid-reply freezes"
assert "Repeater {" not in code, "MessageCodeBlock: the line numbers are a Repeater again, one item per line"
assert "unsharpen" not in code, "MessageCodeBlock: split back into separately rounded pieces, whose seams draw dividers"
numbers = re.search(r"text:\s*(Array\.from\(\{ length: codeTextArea\.text\.split\(\"\\n\"\)\.length \}.+)", code)
assert numbers, "MessageCodeBlock: the joined line-number text is gone"
for text, want in (("x", "1"), ("a\nb\nc", "1\n2\n3")):
    got = node(f"const codeTextArea = {{ text: {json.dumps(text)} }}; console.log(JSON.stringify({numbers.group(1)}))")
    assert got == want, f"MessageCodeBlock: line numbers for {text!r} came out {got!r}"

# Long tool text and thoughts stop at a height, and a call's arguments are laid out to read.
clamp = (P.parents[1] / "common/widgets/ClampBox.qml").read_text()
rule = expr(clamp, "clamped")
for content, cap, want in ((100, 240, False), (260, 240, False), (300, 240, True)):
    got = node(f"""const root = {{ contentHeight: {content}, maxHeight: {cap} }};
        const moreButton = {{ implicitHeight: 32 }}; console.log(JSON.stringify({rule}))""")
    assert got is want, f"ClampBox: {content}px under a {cap}px cap clamps={got}; it must only when opening shows more than the button"
assert "Behavior" not in clamp, "ClampBox: animates its own height, a second motion inside the Revealer that carries it"
assert row.count("ClampBox {") == 2, "ToolActivityRow: the arguments and the output must each stop at a height"
assert "ClampBox {" in think, "MessageThinkBlock: a long thought no longer stops at a height"
assert "ToolCode {" in row and "moreOutputButton" not in row, "ToolActivityRow: tool text is not highlighted ToolCode"

m = re.search(r"(    function layoutArgs\(args, name, fallback\) \{.*?\n    \})", row, re.S)
assert m, "ToolActivityRow: layoutArgs is gone"
fn = m.group(1).replace("function layoutArgs", "function layoutArgs", 1)


def layout(args, name, fallback=""):
    return node(f"{fn}\nconsole.log(JSON.stringify(layoutArgs({json.dumps(args)}, {json.dumps(name)}, {json.dumps(fallback)})))")


got = layout({"path": "/tmp/snake.c", "content": "#include <stdio.h>\nint main(){}"}, "write_file")
assert got["body"].startswith("#include") and got["file"] == "/tmp/snake.c" and got["lines"] == [{"key": "path", "value": "/tmp/snake.c"}], \
    f"layoutArgs: a written file must be its own body, highlighted by its path: {got}"
got = layout({"command": "ls -la", "timeout": 30}, "terminal")
assert got["body"] == "ls -la" and got["kind"] == "Bash" and got["file"] == "" and got["lines"] == [{"key": "timeout", "value": "30"}], \
    f"layoutArgs: a shell call is its command, as Bash: {got}"
got = layout({"path": "/tmp/a.txt", "content": "hello"}, "write_file")
assert got["body"] == "hello", f"layoutArgs: a one-line file is still the body, not a key row: {got}"
got = layout({"script": "echo hi"}, "bash")
assert got["kind"] == "Bash", f"layoutArgs: whatever a shell tool runs is Bash, whatever its argument is called: {got}"
got = layout({"code": "print(1)"}, "execute_code")
assert got["kind"] == "Python" and got["body"] == "print(1)", f"layoutArgs: execute_code runs Python: {got}"
got = layout({"path": "/a.py", "old_string": "x = 1", "new_string": "x = 2"}, "patch")
assert got["body"] == "x = 2" and got["file"] == "/a.py" and {"key": "old_string", "value": "x = 1"} in got["lines"], \
    f"layoutArgs: an edit's body is its new text, in the file's language: {got}"
got = layout({"path": "/a.py", "offset": 1}, "read_file")
assert got["body"] == "" and len(got["lines"]) == 2, f"layoutArgs: a call with no body is only its key rows: {got}"
got = layout(None, "terminal", "  ls ")
assert got == {"lines": [], "body": "ls", "file": "", "kind": "Bash"}, f"layoutArgs: a resumed call without args falls back to its text: {got}"

strip = re.search(r"const body = (root\.resultLines\.every\(.+?)\n\s*return", row, re.S).group(1).rstrip(";")
got = node(f"""const root = {{ resultLines: ["1|#include <a>", "2|int x;"], resultText: "raw" }};
    console.log(JSON.stringify({strip}))""")
assert got == "#include <a>\nint x;", f"ToolActivityRow: read_file's `N|` gutter must come off before highlighting: {got!r}"
got = node(f"""const root = {{ resultLines: ["1|a", "plain"], resultText: "1|a\\nplain" }};
    console.log(JSON.stringify({strip}))""")
assert got == "1|a\nplain", "ToolActivityRow: text that is not all gutter lines must be shown as it came"

# Inline `code` is a pill: the text styled as HTML Qt's markdown import keeps, bracketed
# for InlineCode to find, with letter-spacing as the room its padding sits in.
text = (P / "aiChat/MessageTextBlock.qml").read_text()
pills = (P / "aiChat/InlineCode.qml").read_text()
m = re.search(r"(    function styleCodeSpans\(.*?\n    \})", text, re.S)
assert m, "MessageTextBlock: styleCodeSpans is gone, so inline code is plain text in another face"
style_fn = re.sub(r"\((md): string, (foreground): string, (family): string, (gap): real\): string",
                  r"(\1, \2, \3, \4)", m.group(1))
assert "root.styleCodeSpans(modelData.text" in text and "InlineCode {" in text, \
    "MessageTextBlock: the text no longer goes through styleCodeSpans, or nothing draws the pills"


def styled(md):
    return node(f"{style_fn}\nconsole.log(JSON.stringify(styleCodeSpans({json.dumps(md)}, '#ff8080', 'Mono', 8)))")


OPEN = "<span style=\"color:#ff8080; font-family:'Mono';\">\u2063"
LS = '<span style="letter-spacing:8px;">'
assert styled("saved to `/a/b.c`.") == f"saved t{LS}o</span> {OPEN}\\/a\\/b\\.{LS}c</span>\u2063</span>.", \
    "styleCodeSpans: a path must be one bracketed span, escaped, spaced after its last character and the word before"
assert styled("`a_b*c <T> & d`") == f"{OPEN}a\\_b\\*c &lt;T&gt; &amp; {LS}d</span>\u2063</span>", \
    "styleCodeSpans: markdown inside must be escaped (`a_b_c` became 'abc'), and entities after, or their `;` is"
assert styled("``x ` y``") == f"{OPEN}x \\` {LS}y</span>\u2063</span>", "styleCodeSpans: a double-backtick span holds a backtick"
assert styled("not \\`code\\` here") == "not \\`code\\` here", "styleCodeSpans: an escaped backtick is not a span"
assert styled("```\n`kept`\n```") == "```\n`kept`\n```", "styleCodeSpans: a fence is code already and must be left alone"
assert styled("**b** `x`").startswith("**b** <span"), \
    "styleCodeSpans: the `*` closing emphasis before a span must stay markdown, not be wrapped for spacing"

# LaTeX: an image opening a list item is drawn above its line, over the heading
# before it, unless a visible character leads it (a zero-width one does not); and
# MicroTeX does not wrap, so only max-width keeps a long one on screen.
img = re.search(r"const markdownImage = `(.+)`;", text)
assert img and img.group(1).startswith("\\u200A<img ") and img.group(1).endswith(" />"), \
    "MessageTextBlock: a LaTeX image must be hair-space led (or it overlaps the line above in a list) and " \
    "self-closed (or Qt's importer swallows the rest of the text waiting for </img>)"
assert 'style="max-width:100%"' in img.group(1), \
    "MessageTextBlock: a LaTeX image must be capped at its line's width, or a long formula runs off the sidebar"
split = re.findall(r"const tokens = \w+(?:\.\w+)?\.split\((/.+/)\);", text)
assert len(split) == 2 and split[0] == split[1], "MessageTextBlock: the two word splits of the reveal must agree"
got = node(f"console.log(JSON.stringify('a <img src=\"p\" align=\"middle\" /> b'.split({split[0]}).filter(t => t.trim())))")
assert got == ["a", '<img src="p" align="middle" />', "b"], \
    f"MessageTextBlock: the reveal cuts inside a tag, so a half-shown LaTeX <img> prints as raw text: {got}"

strip = re.search(r"for \(let k = 0; k \+ 1 < marks\.length; k \+= 2\)\s*ranges\.push\((\[.+?\])\);", pills)
assert strip, "InlineCode: the bracket-to-range arithmetic is gone"
sample = "to \u2063/a\u2063 and \u2063b\u2063."
got = node(f"""const text = {json.dumps(sample)}; const marks = [];
    for (let at = text.indexOf("\\u2063"); at !== -1; at = text.indexOf("\\u2063", at + 1)) marks.push(at);
    const plain = text.replace(/\\u2063/g, ""); const ranges = [];
    for (let k = 0; k + 1 < marks.length; k += 2) ranges.push({strip.group(1)});
    console.log(JSON.stringify(ranges.map(([a, b]) => plain.slice(a, b))))""")
assert got == ["/a", "b"], f"InlineCode: brackets must map to their spans in the stripped text, got {got}"
assert "view.remove(" in pills and "root.stripping" in pills, \
    "InlineCode: the brackets must be removed from the document, or copying a command copies U+2063 into the shell"
assert "background: InlineCode" not in text, \
    "MessageTextBlock: as the view's background, InlineCode is built while the view is, and its Connections to that " \
    "half-built view segfaulted the shell on reload"
assert re.search(r"if \(text === root\.stripped\)\s*return;", pills) and "root.stripped = view.getText" in pills, \
    "InlineCode: the removals report their textChanged late, with the brackets gone; unguarded, that cleared every pill"

# Your turns: a bubble that hugs its text, at the right, capped.
assert '"person"' not in msg and "SystemInfo.username" not in msg, \
    "HermesMessage: your turns carry the person icon and username again; the bubble says whose turn it is"
cap, width = expr(msg, "bubbleMaxWidth"), expr(msg, "bubbleWidth")
m = re.search(r"Rectangle \{ // The turn's card, or your bubble\s*\n\s*x:\s*(.+)\n\s*y:.+\n\s*width:\s*(.+)", msg)
assert m, "HermesMessage: the card no longer places itself"
x, w = m.group(1), m.group(2)
for rw, content in ((400, 18), (400, 280), (400, 5000), (300, 0)):
    got = node(f"""
        const messageContentColumnLayout = {{ implicitWidth: {content} }};
        const root = {{ width: {rw}, messagePadding: 12, isUser: true }};
        root.bubbleMaxWidth = {cap};
        root.bubbleWidth = {width};
        const width = {w};
        console.log(JSON.stringify({{ w: width, x: {x} }}))""")
    assert got["w"] <= rw * 0.85 + 1e-9, f"HermesMessage: a {content}px prompt makes a bubble wider than its cap"
    assert got["w"] == min(rw * 0.85, content + 24), f"HermesMessage: a {content}px prompt does not hug its text"
    assert got["x"] + got["w"] == rw, "HermesMessage: the bubble is not flush with the transcript's right edge"
got = node(f"""
    const root = {{ width: 400, height: 90, isUser: false }};
    const width = {w};
    console.log(JSON.stringify({{ w: width, x: {x} }}))""")
assert got == {"w": 400, "x": 0}, "HermesMessage: the agent's card no longer spans the transcript"

print("ok: a turn's folds reveal and keep their content, and your turns are a bubble that hugs its text")
