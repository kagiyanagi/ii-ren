#!/usr/bin/env bash
# Vendors the ii-p3drovfx desktop widget library into the ii-vynx fork.
# Re-runnable: point P3 at a fresh p3drovfx clone when re-syncing.
set -euo pipefail
P3="${P3:?set P3 to <p3drovfx clone>/dots/.config/quickshell/ii}"
F="${F:-/home/ren/Code/ii-vynx/dots/.config/quickshell/ii}"

# 1. widgetCanvas: p3 versions are supersets of the fork ones
#    (grid overlay, snap guide lines, animDuration). Straight replacement.
cp "$P3/modules/common/widgets/widgetCanvas/AbstractWidget.qml" \
   "$P3/modules/common/widgets/widgetCanvas/WidgetCanvas.qml" \
   "$F/modules/common/widgets/widgetCanvas/"

# 2. The widget tree. p3 is a strict superset except clock/ClockWidget.qml, the
#    fork unified clock wrapper that per-style *Widget.qml files replace.
rsync -a --delete "$P3/modules/ii/background/widgets/" "$F/modules/ii/background/widgets/"

# 3. Everything the widget tree reaches outside itself. All of these import only
#    modules this shell already has, so they drop straight in.
cp "$P3/services/WidgetColorScheme.qml" \
   "$P3/services/WidgetExtensionManager.qml" \
   "$P3/services/AtAGlanceService.qml" \
   "$P3/services/CavaService.qml" \
   "$P3/services/EmailService.qml" \
   "$P3/services/NotesService.qml" \
   "$P3/services/TickTickService.qml" \
   "$P3/services/WaterReminderService.qml" \
   "$F/services/"
cp "$P3/modules/common/WeatherIcons.qml" "$F/modules/common/"

# 4. Assets the widgets ship with: google-weather icon set, the Nothing/Nagasaki
#    display fonts, and the bluetooth device renders.
mkdir -p "$F/assets/icons/google-weather" "$F/assets/fonts" "$F/assets/images/devices"
rsync -a "$P3/assets/icons/google-weather/" "$F/assets/icons/google-weather/"
rsync -a "$P3/assets/fonts/" "$F/assets/fonts/"
rsync -a "$P3/assets/images/devices/" "$F/assets/images/devices/"

# 5. Repoint widget card fills at opaque M3 colours.
#    Appearance.colors.colSurfaceContainer* are OVERLAY colours: solveOverlayColor
#    returns extrapolated RGB carrying alpha = 1 - contentTransparency, to be
#    painted over an opaque panel. Widgets paint onto the wallpaper, where that
#    reads as a ~10% ghost in the wrong hue (#1a8e8d84 instead of #2b2a2a).
#    Undo this step if ii-vynx ever gates contentTransparency on
#    appearance.transparency.enable the way ii-p3drovfx does.
python3 - "$F" <<'PY'
import re, os, sys
F = sys.argv[1]
files = [F + '/services/WidgetColorScheme.qml']
files += [os.path.join(d, f) for d, _, fs in os.walk(F + '/modules/ii/background/widgets')
          for f in fs if f.endswith('.qml')]
n = 0
for fp in files:
    src = orig = open(fp).read()
    for name in ('SurfaceContainerHighest', 'SurfaceContainerHigh', 'SurfaceContainerLow', 'SurfaceContainer'):
        src = re.sub(r'Appearance\.colors\.col%s(?![A-Za-z])' % name,
                     'Appearance.m3colors.m3%s%s' % (name[0].lower(), name[1:]), src)
    if src != orig:
        open(fp, 'w').write(src)
        n += 1
print(f'opaque card fills: {n} files')
PY
