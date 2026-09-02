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
# The matte shader is checked by assertion rather than by difference: what
# matters is that alpha actually reaches both ends, which an RMSE against a
# baseline cannot tell you.
"$qml" "$here/check-matte.qml" || { echo "FAIL: matte renderer exited non-zero"; exit 1; }
m=shader-check/subject-matte.png
[ -f "$m" ] || { echo "FAIL: no matte rendered"; exit 1; }
alpha_at() { magick "$m" -crop "1x1+$1+$2" +repage -format "%[fx:a]" info:; }
left=$(alpha_at 8 64)
right=$(alpha_at 248 64)
mid=$(alpha_at 128 64)
if [ "$(echo "$left > 0.02" | bc -l)" = "1" ]; then
    echo "FAIL: subject-matte clear band is not clear (alpha $left)"; fail=1
elif [ "$(echo "$right < 0.98" | bc -l)" = "1" ]; then
    echo "FAIL: subject-matte opaque band is not opaque (alpha $right)"; fail=1
elif [ "$(echo "$mid < 0.3 || $mid > 0.7" | bc -l)" = "1" ]; then
    echo "FAIL: subject-matte lost the ramp (alpha $mid at halfway)"; fail=1
else
    echo "ok:   subject-matte (clear $left, halfway $mid, opaque $right)"
fi

# The weather shaders get their own renderer and their own baseline: they draw
# over a pattern without the vertical rules the wallpaper cases use, so the two
# baselines are not interchangeable.
"$qml" "$here/check-weather.qml" || { echo "FAIL: weather renderer exited non-zero"; exit 1; }
wbase=shader-check/weather-00-baseline.png
[ -f "$wbase" ] || { echo "FAIL: no weather baseline rendered"; exit 1; }

for f in shader-check/weather-*.png; do
    case "$f" in *weather-00-baseline.png) continue ;; esac
    diff=$(magick compare -metric RMSE "$wbase" "$f" null: 2>&1 | sed 's/.*(\([0-9.]*\)).*/\1/')
    if [ "$(echo "$diff < 0.01" | bc -l)" = "1" ]; then
        echo "FAIL: $(basename "$f" .png) is indistinguishable from the baseline (RMSE $diff)"
        fail=1
    else
        echo "ok:   $(basename "$f" .png) (RMSE $diff)"
    fi
done

# A `time` uniform that stopped reaching the GPU still renders rain - it just
# renders the same rain forever, which no baseline comparison can see.
moved=$(magick compare -metric RMSE shader-check/weather-01-rain.png \
    shader-check/weather-02-rain-later.png null: 2>&1 | sed 's/.*(\([0-9.]*\)).*/\1/')
if [ "$(echo "$moved < 0.01" | bc -l)" = "1" ]; then
    echo "FAIL: rain does not move over time (RMSE $moved between t=3 and t=9)"
    fail=1
else
    echo "ok:   rain moves over time (RMSE $moved)"
fi

[ "$fail" = 0 ] && echo "all shader branches changed the image" || exit 1
