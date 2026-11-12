#!/usr/bin/env python3
"""Comfort View, Reading Mode and Anti-flashbang share one screen shader.

All three wrote Hyprland's single decoration:screen_shader: turning one on
replaced the others, and turning Comfort View or Reading Mode off reset the key
without asking whether Anti-flashbang was on. Each toggle also ran a full
`hyprctl reload` and rewrote .glsl files tracked in git, so a symlinked dev
checkout went dirty and `iiren update` overwrote them.

services/ScreenShader.qml now owns the key. Run it in Quickshell with stub
services and a fake `hyprctl` first on PATH that only records its arguments -
the compositor is never touched - and assert that:

- nothing on at startup leaves the key alone (a user's own shader survives);
- effects stack, and turning one off keeps the others;
- the shader lives in the state directory, one file at a time, and is applied
  with `hyprctl eval`, never a reload; a reload applies it again;
- Anti-flashbang left in shellOverrides/main.lua by the old code carries over.

Every combination the generator can produce also goes through glslangValidator
as a GLSL ES 3.00 fragment shader, since Hyprland only says it failed on screen.

Run: python3 tools/check-screen-shader.py
"""

import itertools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from textwrap import dedent

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
SOURCE = (II / "services/ScreenShader.qml").read_text()


def wait_for(read, predicate, why, seconds=5):
    end = time.monotonic() + seconds
    value = None
    while time.monotonic() < end:
        try:
            value = read()
            if predicate(value):
                return value
        except (subprocess.CalledProcessError, json.JSONDecodeError, FileNotFoundError):
            pass
        time.sleep(0.05)
    raise AssertionError(f"{why}; last value: {value}")


def check_glsl():
    if not shutil.which("glslangValidator"):
        print("skip: glslangValidator not installed, generated GLSL not compiled")
        return
    cases = []
    for comfort, reading, paper, flash in itertools.product((None, 0, 37, 100), (None, 0, 64, 100), (False, True), (False, True)):
        if reading is None and paper:
            continue
        cases.append({"comfort": None if comfort is None else {"intensity": comfort},
                      "reading": None if reading is None else {"intensity": reading, "paperTone": paper},
                      "antiFlashbang": flash})
    sources = json.loads(subprocess.run(
        ["node", "-e", "const S = require(process.argv[1]); console.log(JSON.stringify(JSON.parse(process.argv[2]).map(S.source)))",
         str(II / "services/screenShader.js"), json.dumps(cases)],
        text=True, capture_output=True, check=True).stdout)
    assert sources[0] == "", "nothing on must produce no shader"
    with tempfile.TemporaryDirectory(prefix="ii-screen-shader-glsl-") as directory:
        for case, glsl in zip(cases[1:], sources[1:]):
            path = Path(directory) / "shader.frag"
            path.write_text(glsl)
            result = subprocess.run(["glslangValidator", str(path)], text=True, capture_output=True)
            assert result.returncode == 0, f"{case} does not compile:\n{result.stdout}\n{glsl}"
    print(f"ok: all {len(sources) - 1} effect combinations compile as GLSL ES 3.00")


def run_service(overrides):
    directory = Path(tempfile.mkdtemp(prefix="ii-screen-shader-"))
    state = directory / "state"
    log = directory / "hyprctl.log"
    bin_dir = directory / "bin"
    bin_dir.mkdir()
    (bin_dir / "hyprctl").write_text(f"#!/bin/sh\nprintf '%s\\0' \"$@\" >> {json.dumps(str(log))}\nprintf '\\n' >> {json.dumps(str(log))}\n")
    (bin_dir / "hyprctl").chmod(0o755)

    qml = re.sub(r"^import qs(?:\.[\w.]+)*\n", "", SOURCE, flags=re.M)
    qml = qml.replace('import "screenShader.js" as Shader', f'import {json.dumps(str(II / "services/screenShader.js"))} as Shader')
    (directory / "ScreenShader.qml").write_text(qml.replace("import QtQuick", 'import "."\nimport QtQuick', 1))
    shutil.copyfile(II / "modules/common/utils/RefreshProcess.qml", directory / "RefreshProcess.qml")
    stubs = {
        "Config": "property bool ready: true",
        "Persistent": '''property bool ready: true
            property var states: ({ hyprland: { antiFlashbangShader: false } })''',
        "Directories": f"property string state: {json.dumps('file://' + str(state))}",
        "FileUtils": 'function trimFileProtocol(p) { return String(p).replace(/^file:\\/\\//, ""); }',
        "HyprlandComfortView": "property bool effectiveActive: false\n property int intensity: 24",
        "HyprlandReadingMode": "property bool effectiveActive: false\n property int intensity: 100\n property bool paperTone: true",
        "HyprlandSettings": f'''signal reloaded()
            property bool overridesLoaded: true
            property var overrides: ({json.dumps(overrides)})
            property var resets: []
            function resetKeys(keys) {{ resets = keys; }}''',
    }
    for name, body in stubs.items():
        (directory / f"{name}.qml").write_text(f"pragma Singleton\nimport QtQuick\nQtObject {{\n{body}\n}}\n")
    (directory / "qmldir").write_text("".join(f"singleton {n} 1.0 {n}.qml\n" for n in ["ScreenShader", *stubs])
                                      + "RefreshProcess 1.0 RefreshProcess.qml\n")
    (directory / "shell.qml").write_text(dedent('''\
        import QtQuick
        import Quickshell
        import Quickshell.Io
        import "."

        ShellRoot {
            Component.onCompleted: ScreenShader.load()
            IpcHandler {
                target: "test"
                function set(what: string, on: bool): void {
                    if (what === "comfort") HyprlandComfortView.effectiveActive = on;
                    else if (what === "reading") HyprlandReadingMode.effectiveActive = on;
                    else ScreenShader.setAntiFlashbang(on);
                }
                function intensity(value: int): void { HyprlandComfortView.intensity = value; }
                function reload(): void { HyprlandSettings.reloaded(); }
                function state(): string {
                    return JSON.stringify({ antiFlashbang: ScreenShader.antiFlashbang, resets: HyprlandSettings.resets });
                }
            }
        }
    '''))
    # The stubs hold antiFlashbang in a plain object; make the binding see writes.
    shell = directory / "Persistent.qml"
    shell.write_text(shell.read_text().replace(
        "property var states: ({ hyprland: { antiFlashbangShader: false } })",
        "property QtObject states: QtObject { property QtObject hyprland: QtObject { property bool antiFlashbangShader: false } }"))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", PATH=f"{bin_dir}:{os.environ['PATH']}")
    process = subprocess.Popen(["qs", "-p", str(directory), "--no-color"], env=env,
                               stdout=(directory / "log").open("w"), stderr=subprocess.STDOUT)

    def call(method, *args):
        return subprocess.run(["qs", "ipc", "--pid", str(process.pid), "call", "test", method, *map(str, args)],
                               env=env, text=True, capture_output=True, check=True, timeout=5).stdout.strip()

    def calls():
        if not log.exists():
            return []
        return [line.strip("\0").split("\0") for line in log.read_text().split("\n") if line.strip("\0")]

    def files():
        return sorted(p.name for p in (state / "user/generated/screen-shader").glob("*"))

    return directory, process, call, calls, files


def last_shader(calls):
    assert calls and calls[-1][0] == "eval", f"not applied with hyprctl eval: {calls[-1:]}"
    return re.search(r'screen_shader = "([^"]*)"', calls[-1][1]).group(1), calls[-1][1]


def check_service():
    directory, process, call, calls, files = run_service({})
    try:
        wait_for(lambda: call("state"), bool, "service never answered")
        time.sleep(0.6)
        assert calls() == [], f"nothing on, yet the shader key was touched: {calls()}"

        call("set", "comfort", "true")
        wait_for(calls, lambda c: len(c) == 1, "comfort view was not applied")
        path, lua = last_shader(calls())
        assert path.startswith(str(directory / "state/user/generated/screen-shader/")), path
        assert "vec3(0.964)" in Path(path).read_text() and "damage_tracking = 1" not in lua

        call("set", "flash", "true")
        wait_for(calls, lambda c: len(c) == 2, "anti-flashbang was not applied")
        path, lua = last_shader(calls())
        text = Path(path).read_text()
        assert "screenBrightness" in text and "vec3(0.964)" in text, "anti-flashbang replaced comfort view"
        assert "damage_tracking = 1" in lua
        assert files() == [Path(path).name], f"old shaders left behind: {files()}"

        call("set", "comfort", "false")
        wait_for(calls, lambda c: len(c) == 3, "turning comfort view off was not applied")
        path, _ = last_shader(calls())
        text = Path(path).read_text()
        assert "screenBrightness" in text and "0.964" not in text, "turning comfort view off cleared anti-flashbang"

        call("set", "reading", "true")
        call("set", "comfort", "true")
        for step in range(30, 60):  # a slider drag
            call("intensity", step)
        wait_for(calls, lambda c: len(c) == 4, "reading mode was not applied")
        time.sleep(0.5)
        assert len(calls()) == 4, f"a slider drag applied {len(calls()) - 3} times, not once"
        text = Path(last_shader(calls())[0]).read_text()
        assert "vec3(lum), 1.000" in text and "0.88" in text and "screenBrightness" in text and "vec3(0.911)" in text, "the last slider value, not an earlier one"

        call("reload")
        wait_for(calls, lambda c: len(c) == 5, "a Hyprland reload dropped the shader")
        assert last_shader(calls())[0] == last_shader(calls()[:4])[0]

        for what in ("reading", "comfort", "flash"):
            call("set", what, "false")
        wait_for(calls, lambda c: len(c) == 6 and last_shader(c)[0] == "", "turning everything off left a shader")
        assert "ii_damage_tracking = nil" in calls()[-1][1], "damage tracking was not put back"
        assert files() == [], f"shaders left in the state directory: {files()}"
        assert all(c[0] == "eval" for c in calls()), f"something other than hyprctl eval ran: {calls()}"
        errors = re.findall(r".*(?:TypeError|ReferenceError|Error).*", (directory / "log").read_text())
        assert not errors, "\n".join(errors)
    except BaseException:
        print((directory / "log").read_text(), file=sys.stderr)
        raise
    finally:
        process.terminate()
        process.wait(timeout=5)
        shutil.rmtree(directory)
    print("ok: effects stack, one switched off keeps the rest, applied live without a reload, nothing left behind")


def check_migration():
    legacy = "/home/u/.config/quickshell/ii/services/hyprlandAntiFlashbangShader/anti-flashbang.glsl"
    directory, process, call, calls, _ = run_service({"decoration:screen_shader": legacy, "debug:damage_tracking": "1"})
    try:
        state = wait_for(lambda: json.loads(call("state")), lambda s: s["antiFlashbang"], "old anti-flashbang was not carried over")
        assert state["resets"] == ["decoration:screen_shader", "debug:damage_tracking"], state["resets"]
        wait_for(calls, lambda c: len(c) == 1, "carried-over anti-flashbang was not applied")
        assert "screenBrightness" in Path(last_shader(calls())[0]).read_text()
    finally:
        process.terminate()
        process.wait(timeout=5)
        shutil.rmtree(directory)

    directory, process, call, calls, _ = run_service({"decoration:screen_shader": "/home/u/my-own.glsl"})
    try:
        wait_for(lambda: call("state"), bool, "service never answered")
        time.sleep(0.6)
        state = json.loads(call("state"))
        assert not state["antiFlashbang"] and state["resets"] == [] and calls() == [], "the user's own shader was touched"
    finally:
        process.terminate()
        process.wait(timeout=5)
        shutil.rmtree(directory)
    print("ok: anti-flashbang from main.lua carries over once; a user's own shader is left alone")


check_glsl()
check_service()
check_migration()
