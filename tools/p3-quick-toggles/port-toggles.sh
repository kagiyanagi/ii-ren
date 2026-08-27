#!/usr/bin/env bash
# Vendors ii-p3drovfx's Android quick-toggle panel: the 2D packed grid, the
# drag/resize/page editor, and the slider + media widgets that live in it.
# Re-runnable: point P3 at a fresh p3drovfx clone.
#
# p3drovfx ships toggles for services this shell does not have (tailscale, vpn,
# dns-over-tls, soundcore, localsend, modes, ...). Only toggles whose
# QuickToggleModel exists under modules/common/models/quickToggles are vendored;
# the catalog and the delegate chooser are filtered to match, so an unknown type
# can never reach a missing delegate.
#
# The entrance animations that ship with these files stay dormant: the panel
# never bumps entranceTrigger, so _entranceDone is true from construction.
set -euo pipefail
P3="${P3:?set P3 to <p3drovfx clone>/dots/.config/quickshell/ii}"
F="${F:-/home/ren/Code/ii-ren/dots/.config/quickshell/ii}"
SRC="$P3/modules/ii/sidebarDashboard/quickToggles"
DST="$F/modules/ii/sidebarDashboard/quickToggles"

# Toggle types this shell can back with a model. Keep in sync with SUPPORTED in
# the python block below.
TOGGLES=(Network Bluetooth IdleInhibitor EasyEffects NightLight DarkMode
         CloudflareWarp GameMode ScreenSnip ColorPicker OnScreenKeyboard Mic
         Audio Notification PowerProfile AntiFlashbang
         VolumeSlider MicSlider BrightnessSlider GammaSlider MediaWidget)

mkdir -p "$DST/androidStyle"

# 1. The grid, the editor and the shared widget bases.
for f in QuickToggleCatalog.js QuickToggleLayout.js StableQuickToggleModel.qml \
         QuickToggleEditController.qml EditableQuickToggleItem.qml \
         AndroidQuickToggleButton.qml AndroidToggleDelegateChooser.qml \
         AndroidSliderWidgetBase.qml ThreeWaySlider.qml; do
    cp "$SRC/androidStyle/$f" "$DST/androidStyle/$f"
done

# 2. The toggles themselves, plus the panel that lays them out.
for t in "${TOGGLES[@]}"; do
    cp "$SRC/androidStyle/Android${t}Toggle.qml" "$DST/androidStyle/"
done
cp "$SRC/androidStyle/AndroidMusicRecognition.qml" "$DST/androidStyle/"
cp "$SRC/AndroidQuickPanel.qml" "$DST/AndroidQuickPanel.qml"

# 3. The now-playing popup the media widget opens, and the vertical slider a
#    tall slider tile turns into.
cp "$P3/modules/ii/mediaControls/AndroidMediaPopup.qml" "$F/modules/ii/mediaControls/"
cp "$P3/modules/common/widgets/StyledVerticalSlider.qml" "$F/modules/common/widgets/"

# 4. Drop everything that needs a service we do not ship.
python3 - "$DST" "$F/modules/ii/mediaControls/AndroidMediaPopup.qml" "$F/modules/common/widgets/StyledVerticalSlider.qml" <<'PY'
import re, sys

DST, MEDIA_POPUP, VERTICAL_SLIDER = sys.argv[1], sys.argv[2], sys.argv[3]
SUPPORTED = {
    "network", "bluetooth", "idleInhibitor", "easyEffects", "nightLight",
    "darkMode", "cloudflareWarp", "gameMode", "screenSnip", "colorPicker",
    "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile",
    "musicRecognition", "antiFlashbang",
    "volumeSlider", "micSlider", "brightnessSlider", "gammaSlider",
    "mediaWidget",
}
# Dialogs this shell has. AbstractQuickPanel declares exactly these signals.
KEPT_SIGNALS = {
    "openAudioOutputDialog", "openAudioInputDialog", "openBluetoothDialog",
    "openNightLightDialog", "openWifiDialog",
}

# --- catalog: one entry per line, so line filtering is enough -----------------
path = DST + "/androidStyle/QuickToggleCatalog.js"
src = open(path).read()
entry = re.compile(r"^\s{4}(\w+):\s*\{")
kept = []
for line in src.split("\n"):
    hit = entry.match(line)
    if hit and hit.group(1) not in SUPPORTED:
        continue
    kept.append(line)
src = "\n".join(kept)
# mediaWidget is the only multi-line entry; it survives as a block.
open(path, "w").write(src)

# --- delegate chooser: keep only choices we have a delegate for --------------
path = DST + "/androidStyle/AndroidToggleDelegateChooser.qml"
src = open(path).read()
head, *blocks = src.split("    DelegateChoice {")
# The chooser's own closing brace rides on the last choice; the last choice is
# not necessarily one we keep, so detach it and re-append unconditionally.
blocks[-1] = blocks[-1].rstrip().removesuffix("}").rstrip() + "\n"
kept = []
for block in blocks:
    role = re.search(r'roleValue:\s*"(\w+)"', block)
    if not role or role.group(1) not in SUPPORTED:
        continue
    # A kept toggle may still point at a dialog we do not host.
    block = re.sub(
        r"\n\s*onOpenMenu: \{\s*root\.(open\w+Dialog)\(\);\s*\}",
        lambda m: "" if m.group(1) not in KEPT_SIGNALS else m.group(0),
        block)
    kept.append(block)
head = "\n".join(l for l in head.split("\n")
                 if not (l.strip().startswith("signal open")
                         and l.strip()[7:] not in KEPT_SIGNALS))
body = "    DelegateChoice {" + "    DelegateChoice {".join(kept)
open(path, "w").write(head + body.rstrip() + "\n}\n")

# --- panel: same signal trim, and no entrance trigger ------------------------
path = DST + "/AndroidQuickPanel.qml"
src = open(path).read()
src = re.sub(r"\n *on(Open\w+Dialog): root\.(open\w+Dialog)\(\)",
             lambda m: "" if m.group(2) not in KEPT_SIGNALS else m.group(0), src)
# Entrance animations are p3drovfx's, not ours. Without a trigger bump the
# vendored delegates construct with _entranceDone already true.
src = re.sub(r"\n *entranceTrigger: root\.entranceTrigger", "", src)
src = src.replace("""    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) {
                root.triggerContentEntrance();
            } else if (editController.active) {
                editController.cancel();
            }
        }
    }

    Component.onCompleted: {
        if (GlobalStates.sidebarRightOpen) {
            root.triggerContentEntrance();
        }
    }
""", """    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen && editController.active)
                editController.cancel();
        }
    }
""")
src = re.sub(r"\n    // Entrance animation trigger\n    property int entranceTrigger: -1\n\n"
             r"    function triggerContentEntrance\(\) \{\n        entranceTrigger\+\+;\n    \}\n", "", src)
# p3drovfx draws a second, non-editable slider column above the grid, driven by
# sidebar.quickSliders. Our preset carries the sliders as grid tiles instead, so
# that column would only ever duplicate them. quickSliders keeps driving the
# standalone row the classic style uses.
start = src.index("        Column {\n            id: fixedSlidersColumn")
end = src.index("        // Horizontal paging container", start)
src = src[:start] + src[end:]
assert "fixedSliders" not in src

# The edit-mode drawer makes the panel far taller than the sidebar. Put the
# whole panel body in our StyledFlickable so it clips and scrolls instead of
# spilling over the widgets below it.
src = src.replace("implicitHeight: contentItem.implicitHeight", "implicitHeight: panelContent.implicitHeight")
# The paging MouseArea swallows every wheel event. With one page that leaves the
# outer scroll unreachable over the grid, so only claim the wheel when there is
# actually somewhere to page to.
old_wheel = """                        wheelEvent.accepted = true;
                    }
                }"""
assert src.count(old_wheel) == 1
src = src.replace(old_wheel, """                        wheelEvent.accepted = root.displayPages.length > 1;
                    }
                }""", 1)
head = """    Column {
        id: contentItem
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: 8
"""
start = src.index(head)
# Walk to the Column's closing brace so the wrapper can be closed after it.
depth, i = 0, src.index("{", start)
while True:
    if src[i] == "{":
        depth += 1
    elif src[i] == "}":
        depth -= 1
        if depth == 0:
            break
    i += 1
end = i + 1
body = src[start + len(head):end]
# One extra nesting level now, so keep the generated file readable.
body = "\n".join(("    " + l) if l.strip() else l for l in body.split("\n"))
src = src[:start] + """    StyledFlickable {
        id: panelScroll
        anchors {
            fill: parent
            margins: root.padding
        }
        clip: true
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        contentHeight: panelContent.implicitHeight
        interactive: contentHeight > height

        Column {
            id: panelContent
            width: panelScroll.width
            spacing: 8
""" + body + """
    }
""" + src[end:]
assert "id: contentItem" not in src
open(path, "w").write(src)

# --- editable item: let a tile drag win over the panel's vertical scroll -----
path = DST + "/androidStyle/EditableQuickToggleItem.qml"
src = open(path).read()
old = """        hoverEnabled: true
        acceptedButtons: Qt.LeftButton

        onPressed: event => {"""
assert src.count(old) == 1
src = src.replace(old, """        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        preventStealing: true

        onPressed: event => {""", 1)
open(path, "w").write(src)

# --- slider base: our StyledSlider has no valueAnimationDuration -------------
# It animates value with a SmoothedAnimation of its own, and p3 only drives that
# property from the entrance animation we do not run.
path = DST + "/androidStyle/AndroidSliderWidgetBase.qml"
src = open(path).read()
src = re.sub(r"\n *valueAnimationDuration: root\._activeValueAnimDuration", "", src)
open(path, "w").write(src)

# --- media popup: this shell has no pinned media-controls state -------------
# p3drovfx pins its hover-dismissed MediaControls window open; ours has no such
# window, so the pin button would toggle nothing.
src = open(MEDIA_POPUP).read()
src = re.sub(r"\n {16}RippleButton \{(?:(?!\n {16}RippleButton \{)[\s\S])*?mediaControlsPinned[\s\S]*?\n {16}\}\n",
             "\n", src, count=1)
assert "mediaControlsPinned" not in src, "pin button block did not match"
open(MEDIA_POPUP, "w").write(src)

# --- vertical slider: our StyledSlider has no colorfulScrollbar option -------
src = open(VERTICAL_SLIDER).read()
src = src.replace(
    "Config.options.appearance.colorfulScrollbar ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer",
    "Appearance.colors.colSecondaryContainer")
assert "colorfulScrollbar" not in src, "trackColor line did not match"
open(VERTICAL_SLIDER, "w").write(src)
PY

echo "vendored $(ls "$DST/androidStyle" | wc -l) files into $DST/androidStyle"
