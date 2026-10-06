#!/usr/bin/env python3
"""The sidebar translator says when a translation failed, swaps to a real language,
and lets its language dialog finish leaving.

None of this shows in a still frame:
- A failed `trans` left the placeholder, as if nothing had been typed. The exit
  handler now reports it, but it must stay quiet for a run killed by the next
  keystroke, or every fast typist sees the error flash between results.
- One `trans -dump` answers everything: Google's raw JSON, still in HTTP chunks,
  carries the translation, the detected language (a code, with Google's legacy iw/jw),
  the romanisation and the "did you mean". Its parser runs on captured answers here.
- Swap with the source on auto trades in the *detected* language, a code, while the
  language list is endonyms. The lookup is evaluated.
- The dialog's Loader was bound to the open flag, so it was destroyed before its
  exit played. It is latched now and released once the dialog stops being visible.
- The two cards split the page under the language bar, as Google Translate does on
  a tall screen, and each scrolls its own text with the caret kept in view. Back in
  one page-wide scroll, the page is two short cards over a void.
- The pills share the row equally. Sized by their text, the detected hint growing
  into the source pill moved the swap button out from under the pointer.
"""
import json
import re
import subprocess
from pathlib import Path

P = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/ii/sidebarPolicies"
qml = (P / "Translator.qml").read_text()


def node(js):
    return json.loads(subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout)


# The dump parser, lifted and run on real answers, chunk framing included.
m = re.search(r"function parseDump\(raw: string\): var \{(.*?)\n    \}", qml, re.S)
assert m, "Translator: parseDump is gone"
PARSE = f"const parseDump = raw => {{{m.group(1)}}};"
seg = lambda t, s: [t, s, None, None, 3]
helo = [[seg("hello wrld", "helo wrld")], None, "nl", None, None, None, 0.75,
        ["<b><i>hello</i></b> <b><i>world</i></b>", "hello world", [1]]]
ja = [[seg("こんにちは世界", "Bonjour le monde"), [None, None, "Kon'nichiwa sekai"]], None, "fr"]
two = [[seg("C'est une phrase. ", "This is a sentence. "), seg("Et un autre.", "And another.")], None, "en"]
he = [[seg("Hello world", "שלום עולם"), [None, None, None, "shlum olam"]], None, "iw"]
chunk = lambda d: f"{len(json.dumps(d)):x}\r\n{json.dumps(d)}\r\n0\r\n\r\n"
dumps = [chunk(helo), chunk(ja), chunk(two), chunk(he), json.dumps(two), "", "Error: no connection\n"]
got = node(f"{PARSE} console.log(JSON.stringify({json.dumps(dumps)}.map(parseDump)));")
assert got[0] == {"translation": "hello wrld", "transliteration": "", "detected": "nl", "correction": "hello world"}, got[0]
assert got[1] == {"translation": "こんにちは世界", "transliteration": "Kon'nichiwa sekai", "detected": "fr", "correction": ""}, got[1]
assert got[2]["translation"] == "C'est une phrase. Et un autre." and got[4] == got[2], "Translator: segments must join, framed or not"
assert got[3]["detected"] == "he" and got[3]["transliteration"] == "", f"Translator: iw must map to he, source romanisation is not ours: {got[3]}"
assert got[5] is None and got[6] is None, "Translator: an unreadable dump must be null, not an empty translation"


# The exit handler, lifted and run against each way a run ends.
m = re.search(r"onExited: \(exitCode, exitStatus\) => \{(.*?)\n        \}", qml, re.S)
assert m, "Translator: translateProc no longer takes (exitCode, exitStatus); a killed run is indistinguishable"
cases = [[1, 15, "partial"], [0, 127, ""], [0, 2, ""], [0, 0, "  "], [0, 0, chunk(helo)]]
got = node(f"""
{PARSE}
const f = new Function("root", "translateProc", "Translation", "exitStatus", "exitCode", {json.dumps(m.group(1))});
const T = {{ tr: s => s }};
console.log(JSON.stringify({json.dumps(cases)}.map(([status, code, buffer]) => {{
    const root = {{ translatedText: "old", translateError: "", parseDump, inputField: {{ text: "helo wrld" }}, sourceLanguage: "auto" }};
    f(root, {{ buffer }}, T, status, code);
    const {{ parseDump: _, inputField, sourceLanguage, ...out }} = root;
    return out;
}})));""")
assert got[0] == {"translatedText": "old", "translateError": ""}, \
    f"Translator: a run killed for a newer keystroke changed the output: {got[0]}"
assert "trans" in got[1]["translateError"], "Translator: exit 127 must say `trans` is missing"
assert got[2]["translateError"] and got[3]["translateError"], "Translator: a failed or empty run must say so"
assert got[4] == {"translatedText": "hello wrld", "translateError": "", "transliteration": "", "correction": "hello world",
                  "detectedLanguage": "nl"}, f"Translator: a good run did not land: {got[4]}"

# Swap resolves auto to the detected language's endonym.
m = re.search(r"detectedEndonym: (Object\.keys.*?\?\? \"\")", qml, re.S)
assert m, "Translator: detectedEndonym is gone; swap cannot resolve auto"
aliases = {"Deutsch": "de German", "Français": "fr French", "English": "en English"}
got = node(f"""
const root = {{ languageAliases: {json.dumps(aliases)} }};
console.log(JSON.stringify(["fr", "de", "tlh", ""].map(d => (root.detectedLanguage = d, {m.group(1)}))));""")
assert got == ["Français", "Deutsch", "", ""], f"Translator: detected-language lookup gave {got}"
assert re.search(r'swapTarget: root\.sourceLanguage === "auto" \? root\.detectedEndonym : root\.sourceLanguage', qml), \
    "Translator: swapTarget no longer falls back to the detected language on auto"
assert "enabled: root.swapTarget.length > 0" in qml, "Translator: swap must be disabled until auto has detected something"

# The language row cannot shift under the pointer.
bar = qml[qml.find("// From, swap, to"):qml.find("TextCanvas { // Content input")]
assert bar.count("Layout.preferredWidth: 1") == 2, "Translator: the two pills must share the row equally"
assert 'hintText: root.sourceLanguage === "auto" ? root.detectedEndonym' in bar, "Translator: a hand-picked source still shows the detected hint"

# The cards split the height and scroll their own text.
for card in ("TextCanvas { // Content input", "TextCanvas { // Content translation"):
    body = qml[qml.find(card):][:400]
    assert "Layout.fillHeight: true" in body and "Layout.preferredHeight: 1" in body, \
        f"Translator: `{card}` must take an equal share of the page's height"
assert "StyledFlickable" not in qml, "Translator: the page scrolls as a whole again; the cards split it"
canvas = (P / "translator/TextCanvas.qml").read_text()
assert "TextArea.flickable: StyledTextArea" in canvas, \
    "TextCanvas: the text must scroll inside the card, attached so the caret stays in view"
assert "PagePlaceholder" in canvas and 'emptyIcon: "translate"' in qml, "Translator: the empty output card lost its placeholder"
assert re.search(r"buttonRadius: Appearance\.rounding\.full\n\s*buttonRadiusPressed: Appearance\.rounding\.full", qml), \
    "Translator: a round card button must not morph on press (DESIGN.md 4.3)"

# The dialog is latched, not bound.
loader = qml[qml.find("id: languageDialog"):]
assert re.search(r"^\s*active: false", loader, re.M), "Translator: the dialog Loader must be latched, not bound"
assert "if (!visible && !show) languageDialog.active = false" in loader, \
    "Translator: the dialog must be released only once its exit has played, and not on a reopen"
dialog = (P.parents[1] / "common/widgets/SelectionDialog.qml").read_text()
assert re.search(r"^WindowDialog \{", dialog, re.M), "SelectionDialog: lost WindowDialog's scrim, enter and exit"
assert "onDismiss: root.canceled()" in dialog, "SelectionDialog: an outside click or Escape no longer cancels"

subprocess.run(["node", str(P / "translator/test_refine.js")], check=True, capture_output=True)
print("ok: translator reports failures, swaps to a real language, and its dialog leaves visibly")
