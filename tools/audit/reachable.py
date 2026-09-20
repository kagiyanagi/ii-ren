#!/usr/bin/env python3
"""Which QML files in a directory are reached from outside it, transitively.

pack.py's "Used by" answers the question one file at a time. This answers it for a
whole directory and follows the chain: a file reached only by a file that nothing
reaches is dead too. Two reference forms count, because settings sub-pages use the
second one exclusively:

    Type { ... }                      instantiation
    "…/Type.qml"                      Qt.resolvedUrl / Loader.source / a registry string

It cannot see import shadowing: two directories holding a file of the same name both
look reached, and only one of them is. Check any duplicate name by hand.

    python3 tools/audit/reachable.py modules/settings/widgets [--dead]
"""
import argparse, pathlib, re, sys

SHELL = pathlib.Path(__file__).resolve().parents[2] / "dots/.config/quickshell/ii"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("surface", help="directory under the shell dir")
    ap.add_argument("--dead", action="store_true", help="print only the dead paths, one per line")
    args = ap.parse_args()

    target = SHELL / args.surface
    if not target.is_dir():
        sys.exit(f"not a directory: {target}")

    names = sorted(p.stem for p in target.glob("*.qml"))
    if not names:
        sys.exit(f"no qml directly under {target}")
    alt = "|".join(sorted(names, key=len, reverse=True))  # longest first: a name that is a
    #                                                       prefix of another must not shadow it
    pat = re.compile(rf'(?<![\w.])({alt})\s*\{{|["\'](?:[\w./]*/)?({alt})\.qml["\']')
    src = {p: p.read_text(errors="replace") for p in SHELL.rglob("*.qml")
           if "user_widgets" not in p.parts}
    refs = lambda text: {a or b for a, b in pat.findall(text)}

    reached, frontier = {}, []
    for p, text in src.items():
        if p.parent == target:
            continue
        for n in refs(text) - reached.keys():
            reached[n] = str(p.relative_to(SHELL))
            frontier.append(n)
    while frontier:
        n = frontier.pop()
        for m in refs(src[target / f"{n}.qml"]) - reached.keys():
            reached[m] = n
            frontier.append(m)

    lines = lambda n: src[target / f"{n}.qml"].count("\n") + 1
    dead = [n for n in names if n not in reached]
    if args.dead:
        print("\n".join(f"{args.surface}/{n}.qml" for n in sorted(dead, key=lines, reverse=True)))
        return
    live = sorted(reached, key=lines, reverse=True)
    print(f"LIVE {len(live)} files / {sum(map(lines, live))} lines")
    for n in live:
        print(f"  {lines(n):5}  {n}  <- {reached[n]}")
    print(f"DEAD {len(dead)} files / {sum(map(lines, dead))} lines")
    for n in sorted(dead, key=lines, reverse=True):
        print(f"  {lines(n):5}  {n}")


if __name__ == "__main__":
    main()
