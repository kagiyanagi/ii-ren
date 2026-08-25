#!/usr/bin/env python3
"""Find capitalized identifiers the ported widgets reference that resolve to
nothing in this shell -- singletons or types that only exist in ii-p3drovfx.
This is what caught KdeConnectService; a missing singleton is a hard
ReferenceError, not a silent undefined."""
import re, os, glob, sys

F = os.environ.get('SHELL_DIR', 'dots/.config/quickshell/ii')
TREE = F + '/modules/ii/background/widgets'

known = {os.path.basename(p)[:-4] for p in glob.glob(F + '/**/*.qml', recursive=True)}
known |= {os.path.basename(p)[:-3] for p in glob.glob(F + '/**/*.js', recursive=True)}
# Qt/JS/Quickshell builtins and enum holders reachable without a local file
known |= set('''Qt QtObject Item Rectangle Text Image Loader Repeater Timer Component
Connections Binding Behavior State Transition PropertyChanges AnchorChanges NumberAnimation
PropertyAnimation SequentialAnimation ParallelAnimation ColorAnimation RotationAnimation
Canvas ShaderEffect ShaderEffectSource MouseArea Row Column Grid Flow ListView GridView
ListModel ListElement PathView Path Scale Translate Rotation Shape ShapePath OpacityMask
LinearGradient RadialGradient GradientStop Gradient DropShadow Glow Blur FastBlur
GaussianBlur Desaturate ColorOverlay Colorize BrightnessContrast HueSaturation
LayoutMirroring Layout RowLayout ColumnLayout GridLayout StackLayout Flickable ScrollView
Math JSON Date Array Object String Number Boolean RegExp Error Promise Map Set JSONPath
Quickshell PanelWindow FloatingWindow Variants Scope Singleton ShellRoot Process
StdioCollector SplitParser FileView DataStream SocketServer Socket IpcHandler
GlobalShortcut SystemClock ElapsedTimer Bluetooth BluetoothDevice BluetoothAdapter
Mpris MprisPlayer MprisLoopState MprisPlaybackState Pipewire PwNode PwNodeAudio
Hyprland HyprlandWorkspace HyprlandMonitor HyprlandToplevel Notifications Tray
SystemTray SystemTrayItem QsMenuOpener QsMenuEntry Wayland WlrLayershell WlrLayer
ExclusionMode ScreencopyView Screenshot Easing Font Screen Window Keys Accessible
Drag DragHandler TapHandler PinchHandler HoverHandler WheelHandler PointHandler
FolderListModel XmlListModel Locale Qt5Compat GraphicalEffects LayoutDirection
MaterialShape Appearance Config Translation GlobalStates Persistent Directories
Cache StateLayer StyledText MaterialSymbol RippleButton'''.split())

bad = {}
for d, _, fs in os.walk(TREE):
    for f in fs:
        if not f.endswith(('.qml', '.js')):
            continue
        fp = os.path.join(d, f)
        src = open(fp).read()
        for m in re.finditer(r'\b([A-Z][A-Za-z0-9_]{2,})\s*(?=[.{])', src):
            name = m.group(1)
            if name not in known:
                bad.setdefault(name, set()).add(os.path.relpath(fp, TREE))

print(f'{len(bad)} unresolved capitalized identifiers')
for n in sorted(bad):
    print(f'  MISSING  {n}   ({len(bad[n])} file(s), e.g. {sorted(bad[n])[0]})')
sys.exit(1 if bad else 0)
