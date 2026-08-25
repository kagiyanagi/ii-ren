#!/usr/bin/env python3
"""Check members the ported widgets read off shell singletons.

qmllint cannot see through `property QtObject` / JsonObject, so a missing member
is invisible statically AND silent at runtime. This is the check that found the
real breaks last time (BluetoothStatus.toggle, Weather.forecastData, ...).

Deliberately coarse: a name is "declared" if it is declared anywhere in the
singleton's file, at any nesting depth. Screening tool, not a type checker.
"""
import re, os, sys, glob

F = os.environ.get('SHELL_DIR', 'dots/.config/quickshell/ii')
TREE = F + '/modules/ii/background/widgets'
DECL = re.compile(r'\s*(?:readonly\s+)?(?:property\s+(?:list<)?[\w.]+>?|function|signal|enum|component)\s+(\w+)')

def names(path):
    return {m.group(1) for l in open(path) for m in [DECL.match(l)] if m} | \
           {m.group(1) for m in re.finditer(r'^\s*id:\s*(\w+)', open(path).read(), re.M)}

sing = {}
for p in glob.glob(F + '/**/*.qml', recursive=True):
    if '/background/widgets/' in p:
        continue
    if 'pragma Singleton' in open(p).read(4000):
        sing[os.path.basename(p)[:-4]] = p

refs = {}
extra = [F + '/services/WidgetColorScheme.qml', F + '/services/WidgetExtensionManager.qml', F + '/services/AtAGlanceService.qml', F + '/services/CavaService.qml', F + '/services/EmailService.qml', F + '/services/NotesService.qml', F + '/services/TickTickService.qml', F + '/services/WaterReminderService.qml', F + '/modules/common/WeatherIcons.qml']
for fp in [os.path.join(d, f) for d, _, fs in os.walk(TREE) for f in fs
           if f.endswith(('.qml', '.js'))] + extra:
    for m in re.finditer(r'\b([A-Z][A-Za-z0-9_]*)\.([a-z][A-Za-z0-9_]*)(?:\.([A-Za-z0-9_]+))?', open(fp).read()):
        obj, a, b = m.groups()
        if obj in sing and obj != 'Config':   # Config has its own path checker
            refs.setdefault((obj, a, b or ''), set()).add(os.path.relpath(fp, TREE))

bad, seen = [], set()
for (obj, a, b), where in sorted(refs.items()):
    decl = names(sing[obj])
    missing = a if a not in decl else (b if b and b not in decl else None)
    if missing:
        key = f'{obj}.{a}' + (f'.{b}' if missing == b else '')
        if key not in seen:
            seen.add(key)
            bad.append((key, sorted(where)[0]))

print(f'{len(refs)} singleton member paths referenced, {len(bad)} unresolved')
for k, w in bad:
    print(f'  MISSING  {k}   ({w})')
sys.exit(1 if bad else 0)
