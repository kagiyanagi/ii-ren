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
