#!/bin/sh
# Render every shader branch and assert each one actually changed the image.
# Catches a stale .qsb, a renamed uniform, or a branch gone no-op - none of
# which Qt reports as an error. Needs a running compositor.
#   ./check.sh
set -e
cd "$(dirname "$0")"
here=$(pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/shader-check"
cd "$work"

qml=$(command -v qml6 || command -v /usr/lib/qt6/bin/qml || command -v qml)
"$qml" "$here/check.qml" || { echo "FAIL: renderer exited non-zero"; exit 1; }

base=shader-check/00-baseline.png
[ -f "$base" ] || { echo "FAIL: no baseline rendered"; exit 1; }

fail=0
for f in shader-check/*.png; do
    case "$f" in *00-baseline.png) continue ;; esac
    # RMSE against the baseline; anything under 1% means the branch did nothing.
    diff=$(magick compare -metric RMSE "$base" "$f" null: 2>&1 | sed 's/.*(\([0-9.]*\)).*/\1/')
    if [ "$(echo "$diff < 0.01" | bc -l)" = "1" ]; then
        echo "FAIL: $(basename "$f" .png) is indistinguishable from the baseline (RMSE $diff)"
        fail=1
    else
        echo "ok:   $(basename "$f" .png) (RMSE $diff)"
    fi
done
[ "$fail" = 0 ] && echo "all shader branches changed the image" || exit 1
