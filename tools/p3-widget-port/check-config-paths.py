#!/usr/bin/env python3
"""Check every Config.options.* path the ported widgets read against Config.qml.

A missing member on a JsonObject is SILENT at runtime (undefined, no warning) and
qmllint cannot see it either, so this is the only thing that catches typos and
config keys that exist in p3drovfx but never got spliced in.
"""
import re, sys, os

F = os.environ.get('SHELL_DIR', 'dots/.config/quickshell/ii')

def parse_tree(path, root_re):
    """Nested dict of declared property names, keyed by indentation depth."""
    lines = open(path).read().split('\n')
    start = next(i for i, l in enumerate(lines) if re.search(root_re, l))
    base = len(lines[start]) - len(lines[start].lstrip())
    tree = {}
    stack = [(base, tree)]
    depth = 0
    for l in lines[start:]:
        if not l.strip():
            continue
        ind = len(l) - len(l.lstrip())
        m = re.match(r'\s*(?:readonly\s+)?property\s+(?:list<)?(\w+)>?\s+(\w+)\s*:', l)
        if m and ind > base:
            while len(stack) > 1 and stack[-1][0] >= ind:
                stack.pop()
            typ, name = m.groups()
            node = {} if typ in ('JsonObject', 'JsonAdapter') else None
            stack[-1][1][name] = node
            if node is not None:
                stack.append((ind, node))
        depth += l.count('{') - l.count('}')
        if depth <= 0 and ind <= base and '}' in l and l.strip() != '{':
            pass
    return tree

cfg = parse_tree(F + '/modules/common/Config.qml', r'JsonAdapter\s*\{|property alias options')

def resolve(path):
    node = cfg
    for part in path:
        if node is None:          # leaf reached; deeper access is a plain JS value
            return 'leaf'
        if part not in node:
            return False
        node = node[part]
    return True

refs = {}
targets = [F + '/modules/ii/background/widgets', F + '/modules/ii/background/Background.qml'] + [F + '/services/WidgetColorScheme.qml', F + '/services/WidgetExtensionManager.qml', F + '/services/AtAGlanceService.qml', F + '/services/CavaService.qml', F + '/services/EmailService.qml', F + '/services/NotesService.qml', F + '/services/TickTickService.qml', F + '/services/WaterReminderService.qml', F + '/modules/common/WeatherIcons.qml']
for t in targets:
    files = ([os.path.join(d, f) for d, _, fs in os.walk(t) for f in fs
              if f.endswith(('.qml', '.js'))] if os.path.isdir(t) else [t])
    for fp in files:
        for m in re.finditer(r'Config\.options\.([A-Za-z0-9_.]+)', open(fp).read()):
            refs.setdefault(m.group(1).rstrip('.'), set()).add(os.path.relpath(fp, F))

bad = {p: f for p, f in refs.items() if resolve(p.split('.')) is False}
print(f'{len(refs)} distinct Config.options paths referenced, {len(bad)} unresolved')
for p in sorted(bad):
    print(f'  MISSING  Config.options.{p}')
    for f in sorted(bad[p])[:3]:
        print(f'             {f}')
sys.exit(1 if bad else 0)
