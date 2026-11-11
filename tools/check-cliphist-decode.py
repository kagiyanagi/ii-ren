#!/usr/bin/env python3
"""Clipboard actions must decode literal entries, never printf format strings.

Evaluate Cliphist.qml's real action builders under node, then execute their
commands with fake clipboard tools. Percent signs, backslashes, quotes and shell
syntax must survive copy, paste, link opening, image saving and superpaste. Stash
must keep decoding by ID. Everything is confined to a temporary directory.
"""
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
src = (II / "services/Cliphist.qml").read_text()
strings = (II / "modules/common/functions/StringUtils.qml").read_text()


def function(source, name):
    match = re.search(rf"    function {name}\([^\n]+\{{\n.*?\n    \}}", source, re.S)
    assert match, f"missing {name}"
    return re.sub(r"(\w+): string", r"\1", match.group())


entry = "7\t100% %s %b \\n \\t \\path ' $(touch SHOULD_NOT_EXIST) `false`"
with tempfile.TemporaryDirectory(prefix="ii-cliphist-decode-") as directory:
    path = Path(directory)
    fake = path / "cliphist"
    fake.write_text('''#!/usr/bin/env python3
import os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
if name == "stash":
    assert sys.argv[1:] == ["decode", "7"], sys.argv
    sys.stdout.write(os.environ["CLIPHIST_ENTRY"])
elif name == "cliphist":
    assert sys.argv[1:] == ["decode"]
    sys.stdout.buffer.write(sys.stdin.buffer.read())
elif name in ("wl-copy", "wl-paste"):
    if name == "wl-copy": Path(os.environ["CLIPHIST_OUTPUT"]).write_bytes(sys.stdin.buffer.read())
else:
    Path(os.environ["CLIPHIST_OUTPUT"]).write_text(sys.argv[1])
''')
    fake.chmod(0o755)
    for name in ("stash", "wl-copy", "wl-paste", "xdg-open"):
        (path / name).symlink_to(fake)
    names = ("decodeCommand", "copy", "paste", "openLink", "saveImage", "superpaste")
    if "function decodeArguments(" in src:
        names += ("decodeArguments",)
    script = "\n".join(function(src, name) for name in names)
    script += '\nconst root = {' + ','.join(names) + ''' , entries: [entry], pasteDelay: 0, pressPasteCommand: 'true' };
const StringUtils = {shellSingleQuoteEscape};
const Config = {options: {screenSnip: {savePath: directory}}};
const entries = root.entries;
const commands = [];
const Quickshell = {execDetached: c => commands.push(c)};
for (const binary of ['cliphist', 'stash']) {
    root.cliphistBinary = binary;
    for (const name of ['copy', 'paste', 'openLink', 'saveImage']) root[name](entry);
    root.superpaste(1);
}
console.log(JSON.stringify(commands));
'''
    script = f"const entry = {json.dumps(entry)}, directory = {json.dumps(directory)};\n" + function(strings, "shellSingleQuoteEscape") + "\n" + script
    commands = json.loads(subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True).stdout)
    for i, command in enumerate(commands):
        output = path / "output"
        output.unlink(missing_ok=True)
        result = subprocess.run(command, cwd=path, capture_output=True, text=True, timeout=4,
                                env=dict(os.environ, PATH=directory + os.pathsep + os.environ["PATH"],
                                         CLIPHIST_OUTPUT=str(output), CLIPHIST_ENTRY=entry))
        assert result.returncode == 0, f"action {i}: {result.stderr}"
        actual = next(path.glob("clipboard-*.*")).read_text() if i % 5 == 3 else output.read_text()
        assert actual == entry, f"action {i} mangled entry: {actual!r}, want {entry!r}"
        assert not (path / "SHOULD_NOT_EXIST").exists(), "clipboard content ran a command"
print("ok: five clipboard actions preserve literal bytes for both cliphist and stash")
