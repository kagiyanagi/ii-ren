#!/usr/bin/env bash
# Vendors the ii-p3drovfx bar hover-popup designs and the card library they are
# built from. Re-runnable: point P3 at a fresh p3drovfx clone.
#
# p3drovfx restructured its bar into popups/<area>/, shared/cards/ and
# widgets/<area>/. This shell keeps popups flat in modules/ii/bar with cards in
# modules/ii/bar/cards, so the copies land at the paths our own bar widgets
# already instantiate by name - no wiring changes, and verticalBar keeps working
# through its Bar.* aliases.
set -euo pipefail
P3="${P3:?set P3 to <p3drovfx clone>/dots/.config/quickshell/ii}"
F="${F:-/home/ren/Code/ii-ren/dots/.config/quickshell/ii}"
BAR="$P3/modules/ii/bar"

# 1. The card library the popup designs compose. p3 versions are supersets;
#    AlarmsCard, ClockHeaderCard and WorldClocksCard are new.
mkdir -p "$F/modules/ii/bar/cards"
cp "$BAR"/shared/cards/*.qml "$F/modules/ii/bar/cards/"

# 2. Popups. ExpressiveResourcesPopup lands as ResourcesPopup so Resources.qml
#    and verticalBar/Resources.qml pick it up unchanged.
cp "$BAR/popups/battery/BatteryPopup.qml"                 "$F/modules/ii/bar/BatteryPopup.qml"
cp "$BAR/popups/clock/ClockWidgetPopup.qml"               "$F/modules/ii/bar/ClockWidgetPopup.qml"
cp "$BAR/popups/media/MediaPopup.qml"                     "$F/modules/ii/bar/MediaPopup.qml"
cp "$BAR/popups/resources/ExpressiveResourcesPopup.qml"   "$F/modules/ii/bar/ResourcesPopup.qml"
cp "$BAR/popups/weather/WeatherPopup.qml"                 "$F/modules/ii/bar/weather/WeatherPopup.qml"

# 3. The Docker section of the resources popup, and the two services these
#    designs read. Both services are self-contained; DockerService just shells
#    out to docker/systemctl and sits idle when docker is absent.
cp "$BAR/widgets/resources/DockerSection.qml" "$F/modules/ii/bar/DockerSection.qml"
cp "$P3/services/AlarmService.qml" "$P3/services/DockerService.qml" "$F/services/"

# 4. Rewrite the imports p3's layout implies onto ours.
python3 - "$F" <<'PY'
import re, sys, glob, os
F = sys.argv[1]
flat = [F + '/modules/ii/bar/' + f for f in
        ('BatteryPopup.qml', 'ClockWidgetPopup.qml', 'MediaPopup.qml',
         'ResourcesPopup.qml', 'DockerSection.qml')]
nested = glob.glob(F + '/modules/ii/bar/weather/WeatherPopup*.qml')

for fp in flat + nested:
    src = open(fp).read()
    depth = '../cards' if fp in nested else './cards'
    src = src.replace('import "../../shared/cards"', 'import "%s"' % depth)
    # bar/shared and bar/widgets/resources are both plain modules.ii.bar here
    src = re.sub(r'^import qs\.modules\.ii\.bar\.(shared|widgets\.resources)\s*$',
                 'import qs.modules.ii.bar', src, flags=re.M)
    lines, seen = [], set()
    for l in src.split('\n'):
        # a file inside modules/ii/bar must not import its own module
        if l.strip() == 'import qs.modules.ii.bar' and fp not in nested:
            continue
        if l.startswith('import ') and l.strip() in seen:
            continue
        if l.startswith('import '):
            seen.add(l.strip())
        lines.append(l)
    open(fp, 'w').write('\n'.join(lines))
    print('  imports rewritten:', os.path.relpath(fp, F))
PY

# 5. SoundService, so a ringing alarm can actually make noise. AlarmService calls
#    SoundService.stopLoop() unguarded, so without this a firing alarm throws.
cp "$P3/services/SoundService.qml" "$F/services/"

# 6. ResourceUsage: the new resources popup graphs CPU/GPU history off
#    cpuSampled/gpuSampled signals, and reads gpuUsage/gpuTemp/gpuModel and
#    topProcesses - none of which our 192-line version had. p3's is a superset
#    of it apart from cpuFreq, which nothing in this shell reads.
cp "$P3/services/ResourceUsage.qml" "$F/services/"
cp "$P3/assets/icons/docker.svg" "$F/assets/icons/"
python3 - "$F" <<'PY'
import sys
p = sys.argv[1] + '/services/ResourceUsage.qml'
src = open(p).read()
old = '''    Timer {
        id: diskSpaceTimer
        interval: 30000
        repeat: true
        running: true
'''
if old in src and 'triggeredOnStart' not in src[src.index(old):src.index(old) + 220]:
    open(p, 'w').write(src.replace(old, old + '        triggeredOnStart: true\n', 1))
    print('disk poll: triggeredOnStart restored')
PY

# 7. Battery: the new popup reads cycles, timeToFullEffective and the charge-limit
#    properties. p3's service is a superset of ours; the only thing ours had that
#    theirs does not is soundEnabled, which was internal - theirs routes battery
#    alerts through SoundService, gated on the same sounds.battery option.
cp "$P3/services/Battery.qml" "$F/services/"
python3 - "$F" <<'PY'
import sys
p = sys.argv[1] + '/services/Battery.qml'
src = open(p).read()
old = '''            if (!isNaN(val)) {
                root.cycles = val;'''
if old in src:
    open(p, 'w').write(src.replace(old, '''            if (!isNaN(val) && val > 0) {
                root.cycles = val;''', 1))
    print('cycles: firmware 0 treated as unknown')
PY

# 8. Weather: our 209-line service fetched current conditions only, so the new
#    popup's Hourly and Forecast sections (and the forecast background widgets)
#    had nothing to read - forecastData/hourlyData were empty stubs. p3's fetches
#    both. Every Weather.data.<field> this shell reads exists in its shape; the
#    only thing ours had that theirs lacks is formatCityName, used internally.
cp "$P3/services/Weather.qml" "$F/services/"
