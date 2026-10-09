#!/usr/bin/env python3
"""A fresh desktop gets its bundled wallpaper independently of the welcome marker.

FirstRunExperience.qml used to launch switchwall.sh before Config was ready, then
record the welcome as complete even if the switcher's config write was lost. The
next boot saw the marker and left an empty wallpaper path black forever.

Run the actual singleton in an isolated, headless Quickshell with mock settings
and captured process launches. Check both config load orders, an existing welcome
marker, existing image/video choices, and an external wallpaper manager. No live
settings or desktop processes are touched. Requires qs.
"""
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
source = (II / "services/FirstRunExperience.qml").read_text()
assert (II / "assets/images/default_wallpaper.png").is_file(), "the default image must ship"
assert "FirstRunExperience.load()" in (II / "shell.qml").read_text(), "startup must load the service"

# Keep the production FileView and Connections; replace only its dependencies and
# process launcher so this check cannot apply a wallpaper to the real desktop.
source = source.replace("import qs.modules.common\n", "").replace("import qs.modules.common.functions\n", "")
source = source.replace("Quickshell.execDetached(", "TestState.execDetached(")

cases = [
    ("fresh, config arrives later", False, False, True, ""),
    ("fresh, config already loaded", False, True, True, ""),
    ("welcome already completed", True, False, True, ""),
    ("existing image", False, False, True, "/pictures/Owner's chosen image.png"),
    ("existing video", False, True, True, "/pictures/chosen video.mp4"),
    ("external wallpaper manager", True, False, False, ""),
    ("blank path", True, True, True, "  "),
]

for name, greeted, ready, enabled, wallpaper in cases:
    with tempfile.TemporaryDirectory(prefix="ii-wallpaper's-check-") as tmp:
        directory = Path(tmp)
        runtime = directory / "runtime"
        runtime.mkdir(mode=0o700)
        state = directory / "state/user"
        state.mkdir(parents=True)
        if greeted:
            (state / "first_run.txt").write_text("Already welcomed")

        (directory / "qmldir").write_text("".join(
            f"singleton {component} 1.0 {component}.qml\n"
            for component in ["Config", "Directories", "FileUtils", "TestState", "FirstRunExperience"]
        ))
        (directory / "FirstRunExperience.qml").write_text(source)
        (directory / "Config.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool ready: false
    property QtObject options: QtObject {
        property QtObject background: QtObject {
            property bool enable: true
            property string wallpaperPath: ""
        }
    }
}
''')
        (directory / "Directories.qml").write_text(f'''pragma Singleton
import QtQuick
QtObject {{
    property string state: {json.dumps((directory / "state").as_uri())}
    property string assetsPath: {json.dumps(str(II / "assets"))}
    property string wallpaperSwitchScriptPath: "captured-switchwall.sh"
}}
''')
        (directory / "FileUtils.qml").write_text(r'''pragma Singleton
import QtQuick
QtObject { function trimFileProtocol(path) { return path.replace(/^file:\/\//, ""); } }
''')
        (directory / "TestState.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property var commands: []
    property string wallpaperAtLaunch: ""
    function execDetached(args) {
        if (args[0] === Directories.wallpaperSwitchScriptPath)
            wallpaperAtLaunch = Config.options.background.wallpaperPath;
        commands = commands.concat([args]);
    }
}
''')
        (directory / "shell.qml").write_text(f'''import QtQuick
import Quickshell
import "."
ShellRoot {{
    id: test
    property bool passed: true
    function check(condition, message) {{
        if (condition) return;
        console.error("ASSERT:", message);
        passed = false;
    }}
    function switches() {{
        return TestState.commands.filter(args => args[0] === Directories.wallpaperSwitchScriptPath);
    }}
    Component.onCompleted: Qt.callLater(() => {{
        // Importing the service in another app must not initialize a wallpaper.
        FirstRunExperience.loaded;
        Config.ready = true;
        check(switches().length === 0, "service acted before shell load()");
        Config.ready = {json.dumps(ready)};
        Config.options.background.enable = {json.dumps(enabled)};
        if (Config.ready) Config.options.background.wallpaperPath = {json.dumps(wallpaper)};
        FirstRunExperience.load();
        if (!Config.ready)
            check(switches().length === 0, "switched before settings loaded");
        // The saved choice arrives with the settings, before ready changes.
        if (!Config.ready) Config.options.background.wallpaperPath = {json.dumps(wallpaper)};
        Config.ready = true;
        FirstRunExperience.load();
        FirstRunExperience.ensureWallpaper();
        FirstRunExperience.handleFirstRun();
        check(JSON.stringify(TestState.commands[TestState.commands.length - 1]) === JSON.stringify([
            "qs", "-p", FirstRunExperience.welcomeQmlPath]), "welcome path must be a separate argument");
        const wanted = {json.dumps(enabled and not wallpaper.strip())};
        check(switches().length === (wanted ? 1 : 0), "wrong number of wallpaper switches");
        check(Config.options.background.wallpaperPath === (wanted ? FirstRunExperience.defaultWallpaperPath : {json.dumps(wallpaper)}),
            "default missing or saved choice overwritten");
        if (wanted) {{
            check(TestState.wallpaperAtLaunch === FirstRunExperience.defaultWallpaperPath, "image unset when switcher launched");
            check(JSON.stringify(switches()[0]) === JSON.stringify([
                Directories.wallpaperSwitchScriptPath, "--image", FirstRunExperience.defaultWallpaperPath]), "wrong switcher arguments");
        }}
        if (test.passed) console.log("WALLPAPER_CHECK_PASS");
        Qt.quit();
    }})
}}
''')
        env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "XDG_RUNTIME_DIR": str(runtime),
               "XDG_CONFIG_HOME": str(directory / "config"), "XDG_CACHE_HOME": str(directory / "cache"),
               "XDG_STATE_HOME": str(directory / "state")}
        result = subprocess.run(["qs", "--no-color", "-p", str(directory / "shell.qml")],
                                env=env, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        assert result.returncode == 0 and "WALLPAPER_CHECK_PASS" in output, f"{name}:\n{output}"
        assert not re.search(r"ReferenceError|TypeError|Unable to assign|is not a type|non-existent property|Syntax error", output), output

print("ok: default wallpaper waits for Config, recovers without welcome, and preserves choices")
