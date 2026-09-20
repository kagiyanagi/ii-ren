#!/usr/bin/env python3
"""Check the bar card kit's two pieces of arithmetic.

Both are things only a running shell would otherwise show, and both have a
shape that looks guarded and is not:

1. `HourlyForecast`'s bar geometry. A forecast entry with a missing or
   unparseable temperature makes `normalized` NaN, and NaN survives
   `Math.max`/`Math.min` -- `Math.max(0, Math.min(1, NaN))` is NaN, exactly the
   trap `check-desktop-parallax.py` was written for. A NaN bar height draws
   nothing and warns every frame. The card must also survive a chart shorter
   than its own time label, which makes the available space negative.

2. The kit's entrance stagger. `staggerStep * min(i, staggerCap)` must stay
   monotone and flat-topped for any list length, so a 24-hour forecast does not
   trail its last bar in three quarters of a second after the first.

Pure asserts, no framework. Run it after touching either.

  python3 tools/check-bar-cards.py
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CARDS = ROOT / "dots/.config/quickshell/ii/modules/ii/bar/cards"


# --- the expressions, lifted from HourlyForecast.qml -------------------------

def normalized(temp, tmin, tmax):
    """barItem.normalized -- clamped to [0, 1], never NaN."""
    span = max(tmax - tmin, 1)
    n = (temp - tmin) / span
    return max(0.0, min(1.0, n)) if math.isfinite(n) else 0.0


def bar_height(chart_height, label_height, temp, tmin, tmax):
    """barItem.barHeight -- 45% of the available space at the bottom of the
    range, 100% at the top."""
    available = max(0, chart_height - label_height + 10)
    return available * (0.45 + normalized(temp, tmin, tmax) * 0.55)


def stagger(i, step=30, cap=6):
    """The one stagger rule (Appearance.animation.staggerStep/staggerCap)."""
    return step * min(i, cap)


def main():
    failures = []

    # 1. A finite, non-negative bar for every input the service can hand over.
    nan = float("nan")
    cases = [
        # (chart, label, temp, min, max)
        (144, 20, 12, 5, 25),      # ordinary
        (144, 20, 5, 5, 5),        # every hour the same temperature -> span 0
        (144, 20, nan, 5, 25),     # tempC missing -> parseInt() is NaN
        (144, 20, 12, nan, nan),   # the whole range unparseable
        (144, 200, 12, 5, 25),     # label taller than the chart
        (0, 0, 12, 5, 25),         # laid out before the popup has a size
        (144, 20, -40, 5, 25),     # below the range
        (144, 20, 99, 5, 25),      # above it
    ]
    for chart, label, temp, tmin, tmax in cases:
        h = bar_height(chart, label, temp, tmin, tmax)
        if not math.isfinite(h):
            failures.append(f"bar height is not finite for {(chart, label, temp, tmin, tmax)}: {h}")
        elif h < 0:
            failures.append(f"bar height is negative for {(chart, label, temp, tmin, tmax)}: {h}")
        elif h > max(0, chart - label + 10):
            failures.append(f"bar height overflows its space for {(chart, label, temp, tmin, tmax)}: {h}")

    # A real range still spreads the bars: 45% at the bottom, 100% at the top.
    lo = bar_height(144, 20, 5, 5, 25)
    hi = bar_height(144, 20, 25, 5, 25)
    if not lo < hi:
        failures.append(f"the coldest hour ({lo}) is not shorter than the warmest ({hi})")
    if abs(lo / hi - 0.45) > 1e-9:
        failures.append(f"the bottom of the range is not 45% of the top: {lo / hi}")

    # 2. The stagger is monotone, flat past the cap, and bounded.
    delays = [stagger(i) for i in range(24)]
    if delays != sorted(delays):
        failures.append("stagger delays are not monotone")
    if max(delays) != 30 * 6:
        failures.append(f"stagger is not capped at staggerCap steps: {max(delays)}")
    if delays[0] != 0:
        failures.append("the first sibling is delayed")

    # 3. The tokens the expressions above assume still say what they said.
    appearance = (ROOT / "dots/.config/quickshell/ii/modules/common/Appearance.qml").read_text()
    for name, want in (("staggerStep", 30), ("staggerCap", 6)):
        m = re.search(rf"property int {name}:\s*(\d+)", appearance)
        if not m:
            failures.append(f"Appearance.animation.{name} is gone")
        elif int(m.group(1)) != want:
            failures.append(f"Appearance.animation.{name} is {m.group(1)}, this check assumes {want}")

    # 4. The divider SectionCard used to paint stays gone (design law 11).
    section = (CARDS / "SectionCard.qml").read_text()
    if "showDivider" in section:
        failures.append("SectionCard.showDivider is back -- design law 11 / DESIGN.md 5.5")

    # 5. No effect inside a repeated delegate anywhere in the kit (law 8).
    for path in sorted(CARDS.glob("*.qml")):
        # A comment naming an effect that was removed is not an effect.
        text = re.sub(r"//.*", "", path.read_text())
        if "delegate:" not in text and "Repeater" not in text:
            continue
        for marker in ("layer.enabled", "OpacityMask", "MaskedBlur"):
            # Only the ones that sit after a delegate opens; the kit has no
            # per-widget effect left outside ClockHeaderCard's own card clip.
            first_delegate = min(
                (text.index(k) for k in ("delegate:", "Repeater") if k in text),
                default=len(text),
            )
            if marker in text and text.index(marker) > first_delegate:
                failures.append(f"{path.name}: {marker} inside a repeated delegate (DESIGN.md 8)")

    for f in failures:
        print(f"FAIL {f}")
    if failures:
        return 1
    print("bar cards: bar geometry finite, stagger capped, no divider, no effect in a delegate")
    return 0


if __name__ == "__main__":
    sys.exit(main())
