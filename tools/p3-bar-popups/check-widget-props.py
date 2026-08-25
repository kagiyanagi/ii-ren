#!/usr/bin/env python3
"""Find assignments to properties that p3drovfx's shared widgets have and ours do not.

This is the failure mode that stops the shell from starting outright:

    StyledSwitch { sizeScale: 0.75 }    # p3 renamed our `scale` to `sizeScale`
    -> Cannot assign to non-existent property "sizeScale"

qmllint does not report it when the assignment sits inside a Component, and no
runtime check helps because the shell simply fails to load. So: parse the ported
files, attribute every property assignment to its *enclosing type*, and compare
that type's property list between the two shells.

Matching on property names alone is useless - `spacing` on a ColumnLayout looks
like a hit against any p3 widget that happens to declare `spacing`. The
enclosing type is the whole point.

Usage:
    SHELL_DIR=... P3_DIR=... python3 check-widget-props.py [files...]
"""
import os
import re
import sys
import glob

F = os.environ.get('SHELL_DIR', 'dots/.config/quickshell/ii')
P3 = os.environ.get('P3_DIR', '')

TYPE_OPEN = re.compile(r'^(\s*)(?:\w+\s*:\s*)?([A-Z]\w*)\s*\{\s*$')
ASSIGN = re.compile(r'^(\s*)(\w+)\s*:\s*\S')
SKIP = re.compile(r'^\s*(?:property|readonly|signal|function|component|enum|required)\b')


def declared_props(path):
    """Property names a QML file declares on its own root."""
    src = open(path).read()
    return set(re.findall(r'property\s+(?:alias\s+|list<[\w.]+>\s+|\w+\s+)(\w+)', src))


def assignments(path):
    """(line, enclosing type, property) for each direct property assignment."""
    out = []
    stack = []  # (indent, type)
    for n, line in enumerate(open(path), 1):
        if not line.strip() or line.lstrip().startswith('//'):
            continue
        indent = len(line) - len(line.lstrip())
        while stack and indent <= stack[-1][0]:
            stack.pop()
        m = TYPE_OPEN.match(line.rstrip())
        if m:
            stack.append((len(m.group(1)), m.group(2)))
            continue
        if stack and not SKIP.match(line):
            a = ASSIGN.match(line)
            # a direct assignment sits one level inside its type's brace
            if a and a.group(2) and not a.group(2)[0].isupper():
                out.append((n, stack[-1][1], a.group(2)))
    return out


def main():
    if not P3:
        sys.exit('set P3_DIR to <p3drovfx clone>/dots/.config/quickshell/ii')
    targets = sys.argv[1:] or (
        glob.glob(F + '/modules/ii/bar/cards/*.qml')
        + glob.glob(F + '/modules/ii/bar/*Popup.qml')
        + glob.glob(F + '/modules/ii/bar/weather/*Popup*.qml')
        + [F + '/modules/ii/bar/DockerSection.qml'])

    # property sets per shared widget, on both sides
    ours, theirs = {}, {}
    for pat in ('/modules/common/widgets/*.qml', '/modules/common/widgets/**/*.qml'):
        for p in glob.glob(F + pat, recursive=True):
            ours[os.path.basename(p)[:-4]] = declared_props(p)
        for p in glob.glob(P3 + pat, recursive=True):
            theirs[os.path.basename(p)[:-4]] = declared_props(p)

    findings = []
    for fp in targets:
        if not os.path.exists(fp):
            continue
        for line, typ, prop in assignments(fp):
            if typ in ours and typ in theirs:
                if prop in theirs[typ] and prop not in ours[typ]:
                    findings.append((os.path.relpath(fp, F), line, typ, prop))

    print(f'assignments to p3-only properties of our shared widgets: {len(findings)}')
    for f, line, typ, prop in sorted(findings):
        print(f'  {f}:{line}  {typ}.{prop}')
    if not findings:
        print('  none - nothing here can fail to load for this reason')
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
