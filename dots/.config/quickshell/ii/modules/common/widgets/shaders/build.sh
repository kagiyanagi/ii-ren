#!/bin/sh
# Rebake every .frag next to this script. Run after editing a shader; the
# .qsb files are committed so nobody needs qsb just to run the shell.
cd "$(dirname "$0")" || exit 1

# Distros disagree about whether qsb lands on PATH; check.sh already has to do
# the same dance for qml.
qsb=$(command -v qsb6 || command -v qsb || command -v /usr/lib/qt6/bin/qsb)
[ -x "$qsb" ] || { echo "qsb not found (try qt6-shadertools)"; exit 1; }

for f in *.frag; do
    "$qsb" --qt6 -o "$f.qsb" "$f" || exit 1
    echo "baked $f"
done
