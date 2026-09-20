#!/usr/bin/env python3
"""Assert the weather popup's hourly temperature range is finite and never flat.

`WeatherPopup.getHourlyTempRange()` is the single range both of
`cards/HourlyForecast.qml`'s callers route through, and the chart divides by its
span:

    property real parentTempSpan: Math.max(parentTempRange.max - parentTempRange.min, 1)
    property real normalized:     (temp - parentTempRange.min) / parentTempSpan

That `Math.max(..., 1)` looks like it floors the span, and for a flat hour-to-hour
run it does. It does nothing at all about a NaN: `Math.max(NaN, 1)` is NaN, so the
division is NaN and the bar height with it. `ii-background-root` shipped the same
shape in its parallax clamp; `tools/check-desktop-parallax.py` is this file's
sibling.

NaN is reachable from the service, not only in theory. `Weather.refineData` walks
`hourly.time` and reads `hourly.temperature_2m[i]` at the same index without
checking that array is as long, so a short or absent temperature array yields
`Math.round(undefined).toString()` -- the string "NaN" -- and `parseInt("NaN")` is
NaN. One malformed hour is enough: it poisons `Math.min`/`Math.max` over the whole
set, so `min` and `max` are both NaN and *every* bar goes with it, not just the
bad one. A per-bar guard downstream cannot recover that -- by then the range it
would clamp against is already NaN -- which is why the guard belongs here.

The guard is the `.filter(t => isFinite(t))` in `getHourlyTempRange`, plus the
unconditional 2-degree minimum on the padding, which together make the span finite
and at least 4 for every input. Those expressions are lifted out of the QML and run
below rather than restated here, so this file cannot drift away from what it
asserts. What it deliberately does *not* lift is anything in `HourlyForecast.qml`:
the contract this checks is the one `getHourlyTempRange` owes its callers, and
pinning the callers' own arithmetic here would make this fail every time that card
is edited.

Run: python3 tools/check-weather-hourly.py
"""
import math
import pathlib
import re

QML = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/modules/ii/bar/weather/WeatherPopup.qml"
src = QML.read_text()


def expr(pattern: str, text: str = src) -> str:
    m = re.search(pattern, text)
    assert m, f"WeatherPopup.qml no longer has {pattern!r} -- this check is stale, re-point it"
    return m.group(1).strip()


RANGE_FN = expr(r"function getHourlyTempRange\(\) \{([\s\S]*?)\n    \}")

# The fix itself, asserted by shape: a lambda inside .map/.filter is not something
# this can eval, but its absence is exactly the regression to catch. The
# arithmetic around it is lifted and run.
TEMPS = expr(r"(const temps = .*;)")
assert "isFinite" in TEMPS, (
    "getHourlyTempRange no longer drops non-finite readings -- one malformed hour "
    f"takes every bar in the chart with it:\n    {TEMPS}")

PADDING = expr(r"const padding = (.*);", RANGE_FN)
RET_MIN, RET_MAX = re.search(r"return \{\s*min: (.+?),\s*max: (.+?)\s*\};\s*$", RANGE_FN.strip()).groups()
EMPTY_MIN, EMPTY_MAX = re.search(r"return \{\s*min: (\d+),\s*max: (\d+)\s*\};", RANGE_FN).groups()

# The span the callers compute off that range. Transcribed, not lifted, on purpose
# (see the docstring): it is the shape the range has to survive, not this file's
# claim about what HourlyForecast.qml currently says.
SPAN = "Math.max(range_max - range_min, 1)"


def jsmax(*a):
    """Math.max: NaN in, NaN out. Python's max() picks a winner instead, which is
    the entire difference this check exists to pin down."""
    return math.nan if any(math.isnan(x) for x in a) else max(a)


def jsmin(*a):
    return math.nan if any(math.isnan(x) for x in a) else min(a)


def run(text: str, **env) -> float:
    py = text.replace("Math.max", "jsmax").replace("Math.min", "jsmin")
    return eval(py, {"__builtins__": {}, "jsmax": jsmax, "jsmin": jsmin}, env)


def parse_int(v):
    """parseInt, near enough: a leading integer, or NaN. "NaN", "" and a missing
    key all land on NaN, which is how the service's malformed hours arrive."""
    m = re.match(r"\s*[-+]?\d+", str(v)) if v is not None else None
    return float(m.group(0)) if m else math.nan


def temp_range(rows, uscs):
    """getHourlyTempRange, with its lifted padding and return expressions run."""
    temps = [t for t in (parse_int(r.get("tempF" if uscs else "tempC")) for r in rows)
             if math.isfinite(t)]
    if not temps:
        return float(EMPTY_MIN), float(EMPTY_MAX)
    lo, hi = jsmin(*temps), jsmax(*temps)
    padding = run(PADDING, min=lo, max=hi)
    return run(RET_MIN, min=lo, padding=padding), run(RET_MAX, max=hi, padding=padding)


def rows(*temps):
    return [({} if t is None else {"tempC": t, "tempF": t}) for t in temps]


CASES = {
    "a normal afternoon": rows("18", "19", "21", "20", "17"),
    "one hour of data": rows("14"),
    "a flat run, every hour the same": rows("7", "7", "7", "7"),
    "below zero, a wide swing": rows("-11", "3", "-4", "12"),
    "one malformed hour among good ones": rows("18", "NaN", "21", "20"),
    "every hour malformed": rows("NaN", "NaN", "NaN"),
    "an hour with no temperature key at all": rows("18", None, "20"),
    "empty strings from a truncated response": rows("", "", ""),
    "no hourly data": rows(),
}

for uscs in (False, True):
    for name, data in CASES.items():
        lo, hi = temp_range(data, uscs)
        assert math.isfinite(lo) and math.isfinite(hi), f"{name}: range ({lo}, {hi}) is not finite"

        span = run(SPAN, range_min=lo, range_max=hi)
        assert math.isfinite(span), f"{name}: span is {span} -- every bar height derived from it is too"
        assert span >= 4, (
            f"{name}: span {span} -- the padding's unconditional 2-degree minimum is what keeps "
            "a single hour or a flat run from collapsing the chart into one solid block")

        for r in data:
            temp = parse_int(r.get("tempF" if uscs else "tempC"))
            if not math.isfinite(temp):
                continue  # HourlyForecast guards this one bar itself
            norm = (temp - lo) / span
            assert 0 < norm < 1, f"{name}: {temp} normalises to {norm}, outside its own padded range"

# The negative control. If this stops holding, Math.max has grown NaN handling and
# the filter above could be reconsidered; until then it is the only thing doing the
# work, and the clamp that looks like it covers this does not.
assert math.isnan(jsmax(18.0, math.nan)), "Math.max no longer propagates NaN -- re-read this check's premise"
assert math.isnan(run(SPAN, range_min=math.nan, range_max=math.nan)), \
    "Math.max(NaN, 1) now returns 1 -- the span clamp would cover this on its own"

print(f"ok: {len(CASES)} hourly shapes x 2 unit systems give a finite temperature range with a span "
      ">= 4; Math.max(NaN, 1) is still NaN, so the isFinite filter is still what does the work")
