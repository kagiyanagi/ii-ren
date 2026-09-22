#!/usr/bin/env python3
"""Assert a dialog's content still has a card, and not the dialog's own colour.

`Appearance.colors.colLayer1..4` and `colSurfaceContainer*` are not colours, they
are *overlays*: `solveOverlayColor(base, target, 1 - contentTransparency)` returns
the colour that, painted over `base` at that alpha, composites to `target`. Each
one names exactly one base, and the number it produces is only the intended
`target` when it is painted over that base. Painted over anything else it lands
somewhere between the two, and `1 - contentTransparency` decides how far.

`WindowDialog` painted its card `m3surfaceContainerHigh` -- "the opaque version of
layer3". Everything written for a dialog paints one step above that: the Wi-Fi,
Bluetooth, volume and selection list cards are `colSurfaceContainerHigh`, whose
base is `m3surfaceContainer`; `DialogListItem`, `DialogButton` and every
`ContentGroup` card inside a dialog take their fills and state films from layer 3,
off the same base. So the card those tokens solve *to* was the card they were
painted *on*.

While `contentTransparency` fell through to `autoContentTransparency` that was
survivable: at alpha 0.1 a mis-based overlay is nine parts whatever is actually
underneath and one part a colour far past the target, which reads as "a bit
lighter than the thing behind me" no matter what the thing behind is. Measured on
this palette, the Bluetooth list card came out (51, 53, 44) on a (41, 43, 35)
dialog -- the grey body of the card. `14a479e48` made content fills opaque, which
is correct, and the tenth that was holding the two apart went away with it: both
are (41, 43, 35) now. The list, the Wi-Fi list, the volume list and every
`ContentSubsection` card in the night-light and hotspot dialogs painted themselves
onto their own parent, and there is nothing in a screenshot to see -- the rows are
all still there, on a card that is exactly as wide and exactly as visible as no
card at all.

The fix is the base, not the alpha: the dialog is layer 2 now, which is the base
those tokens already declare. That makes the step exact rather than approximate,
so it no longer depends on the transparency setting at all -- which is what this
pins, at both alphas.

Run: python3 tools/check-dialog-layers.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"
appearance = (ROOT / "modules/common/Appearance.qml").read_text()


def one(src: str, pattern: str, what: str) -> str:
    m = re.search(pattern, src)
    assert m, f"{what} no longer matches {pattern!r} -- this check is stale"
    return m.group(1).strip()


# --- the palette --------------------------------------------------------------

M3 = {
    name: tuple(int(hexs[i:i + 2], 16) for i in (0, 2, 4))
    for name, hexs in re.findall(r"property color (m3\w+): \"#([0-9a-fA-F]{6})\"", appearance)
}
assert "m3surfaceContainer" in M3, "the m3colors block no longer declares plain hex -- this check is stale"


def solve(base, target, alpha):
    """ColorUtils.solveOverlayColor, per channel, clamped like the original."""
    return tuple(min(255, max(0, (t - b * (1 - alpha)) / alpha)) for b, t in zip(base, target))


def over(overlay, base, alpha):
    return tuple(round(alpha * o + (1 - alpha) * b) for o, b in zip(overlay, base))


def step(a, b):
    return max(abs(x - y) for x, y in zip(a, b))


# --- what each container token is solved against ------------------------------
#
# Parsed rather than tabulated: a token that is re-based silently changes which
# surface it may be painted on, and that is the whole defect this guards.

def token(name: str):
    """(base, target) for a solveOverlayColor container token, as m3 colour names."""
    expr = one(appearance, rf"(?m)property color {name}: ColorUtils\.solveOverlayColor\(([^;]+?)\)\s*;?\s*$",
               f"the {name} definition")
    base, target = [a.strip() for a in expr.split(",")[:2]]
    def resolve(alias: str) -> str:
        # `colLayerNBase` is usually a plain m3 alias; layer 0's is a mix(), and
        # stays unresolved -- nothing below asks a dialog about layer 0.
        m = re.search(rf"property color {re.escape(alias)}: m3colors\.(\w+)", appearance)
        return m.group(1) if m else alias.removeprefix("m3colors.")

    return resolve(base), resolve(target)


BASE_OF = {n: token(n) for n in (
    "colLayer1", "colLayer2", "colLayer3", "colLayer4",
    "colSurfaceContainerLow", "colSurfaceContainer", "colSurfaceContainerHigh", "colSurfaceContainerHighest",
)}

# --- the dialog card ----------------------------------------------------------

DIALOG_CARD = "colLayer2Base"
card_name = one(appearance, rf"property color {DIALOG_CARD}: m3colors\.(\w+)", f"the {DIALOG_CARD} definition")

for path in ("modules/common/widgets/WindowDialog.qml", "modules/common/widgets/SelectionDialog.qml"):
    src = (ROOT / path).read_text()
    fill = one(src, r"(?m)^\s*color: (Appearance\.\S+)$\n(?=\s*(?:radius|property real targetY))",
               f"{path}'s dialog surface fill")
    assert fill == f"Appearance.colors.{DIALOG_CARD}", (
        f"{path} paints its dialog card {fill}, not Appearance.colors.{DIALOG_CARD}. Its content "
        f"paints layer 3 and colSurfaceContainerHigh, both of which are solved to composite onto "
        f"{card_name}. Paint the dialog in what those tokens resolve *to* and every card inside it "
        f"lands on its own colour and disappears -- with the rows still on it, so nothing looks "
        f"missing. That is what happened when contentTransparency stopped being 0.9")

# The content tokens must name the dialog's own colour as their base, or the step
# above is a guess that only holds at one alpha.
for name in ("colLayer3", "colSurfaceContainerHigh"):
    base, _ = BASE_OF[name]
    assert base == card_name, (
        f"{name} is solved against {base}, but a dialog card is {card_name}. Every dialog's "
        f"content is painted with this token; based anywhere else it composites to something "
        f"between its base and its target, and how far depends on transparency being on")

# --- the step is real, at both alphas -----------------------------------------
#
# Off (0) is the shipped config. On and automatic is autoContentTransparency.

auto = float(one(appearance, r"property real autoContentTransparency: ([\d.]+)", "autoContentTransparency"))
CARD = M3[card_name]

for alpha in (1.0, 1.0 - auto):
    for name in ("colLayer3", "colSurfaceContainerHigh"):
        base, target = BASE_OF[name]
        got = over(solve(M3[base], M3[target], alpha), CARD, alpha)
        assert got == M3[target], (
            f"{name} over a {card_name} dialog resolves to {got} at alpha {alpha:.2f}, not "
            f"{M3[target]}. A correctly based overlay is exact at every alpha; this one is not, "
            f"so the dialog is not painted in this token's base")
        assert step(got, CARD) >= 6, (
            f"{name} is {step(got, CARD)} from the {card_name} dialog it sits on at alpha "
            f"{alpha:.2f}. A content card that close to its parent is not a card")

# --- nothing inside a dialog paints the dialog's own tone ---------------------
#
# The hotspot stat tiles and the keybind editor's capture button were layer 2:
# sunken against the old layer-3 card, invisible against this one. Resting fills
# only -- a state film is meant to be near its parent, and a transparentized
# token paints nothing at all.

COLLIDES = {n for n, (_, target) in BASE_OF.items() if target == card_name}
FILL = re.compile(r"(?m)^\s*(?:color|cardColor|colBackground|colBackgroundHover|colRipple):"
                  r" Appearance\.colors\.(col\w+)$")

dialogs = sorted(p for p in ROOT.rglob("*.qml")
                 if re.search(r"(?m)^\s*WindowDialog \{", p.read_text()))
dialogs.append(ROOT / "modules/common/widgets/SelectionDialog.qml")
assert len(dialogs) >= 8, f"only {len(dialogs)} dialog files found -- this check is stale"

for path in dialogs:
    for name in FILL.findall(path.read_text()):
        assert name not in COLLIDES, (
            f"{path.relative_to(ROOT)} paints {name} inside a dialog. That token resolves to "
            f"{card_name}, which is the dialog's own card, so it paints nothing -- and with its "
            f"contents still drawn on top there is no symptom to see. Use colLayer3 for a tile "
            f"that sits straight on the dialog")

print("check-dialog-layers: ok")
sys.exit(0)
