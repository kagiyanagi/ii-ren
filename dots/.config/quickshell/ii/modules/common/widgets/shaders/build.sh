#!/bin/sh
# Rebake every .frag next to this script. Run after editing a shader; the
# .qsb files are committed so nobody needs qsb just to run the shell.
cd "$(dirname "$0")" || exit 1
for f in *.frag; do
    qsb --qt6 -o "$f.qsb" "$f" || exit 1
    echo "baked $f"
done
