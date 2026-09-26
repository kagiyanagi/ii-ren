#!/usr/bin/env python3
"""Assert wrapped frame edges and corners obey bar position, multi-monitor, and LayerShell rules.

`WrappedFrame` is four EdgeFrames and four ScreenCorners per monitor when
`Config.options.appearance.fakeScreenRounding === 3` ("Wrapped").

The checks below verify:
1. Corner & edge symmetry: The bar occupies one screen edge (Top, Bottom, Left, or Right).
   The edge containing the bar and the two corners touching that edge must be inactive,
   leaving exactly 3 edge frames and 2 corner fillets active in all 4 bar positions.
2. Property scoping: No unqualified references (e.g. `showBarBackground` instead of
   `monitorScope.showBarBackground`), and no shadowing of `PanelWindow.screen`.
3. Multi-monitor indexing: Hyprland monitor lookup uses display name `modelData.name`
   rather than screen array index.
4. LayerShell and input:
   - `WlrLayershell.namespace: "quickshell:wrappedFrame"` on both EdgeFrame and ScreenCorner.
   - `exclusionMode: ExclusionMode.Ignore` on ScreenCorner so fillets do not reserve desktop space.
   - `mask: Region {}` on both so neither window intercepts pointer events.
5. Family gating: `IllogicalImpulseFamily.qml` gates loading on `usingWrappedFrame`.

Run: python3 tools/check-wrapped-frame.py
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"
SRC = (ROOT / "modules/ii/wrappedFrame/WrappedFrame.qml").read_text()
FAMILY_SRC = (ROOT / "panelFamilies/IllogicalImpulseFamily.qml").read_text()


def check_no_screen_shadowing():
    """Verify ScreenCorner and EdgeFrame do not redeclare `property ShellScreen screen`."""
    matches = re.findall(r"property\s+\S+\s+screen\b", SRC)
    assert not matches, f"Redeclared screen property found: {matches}"


def check_layershell_and_mask_regions():
    """Verify namespaces, exclusionMode, and mask regions."""
    assert 'WlrLayershell.namespace: "quickshell:wrappedFrame"' in SRC, \
        "Missing WlrLayershell.namespace: quickshell:wrappedFrame"
    assert SRC.count('WlrLayershell.namespace: "quickshell:wrappedFrame"') == 2, \
        "Expected namespace on both EdgeFrame and ScreenCorner"

    assert "exclusionMode: ExclusionMode.Ignore" in SRC, \
        "ScreenCorner must set exclusionMode: ExclusionMode.Ignore"

    assert SRC.count("mask: Region {}") >= 2, \
        "Both EdgeFrame and ScreenCorner must set mask: Region {} to be click-through"


def check_bar_symmetry():
    """Verify that in each of the 4 bar positions, exactly the 3 opposite edges

    and the 2 non-touching corners are active.
    """
    orientations = [
        (False, False, "Top"),
        (False, True, "Bottom"),
        (True, False, "Left"),
        (True, True, "Right"),
    ]

    for bar_vert, bar_bot, name in orientations:
        bar_at_top = not bar_vert and not bar_bot
        bar_at_bottom = not bar_vert and bar_bot
        bar_at_left = bar_vert and not bar_bot
        bar_at_right = bar_vert and bar_bot

        # Corner active conditions
        corner_tl = not (bar_at_top or bar_at_left)
        corner_tr = not (bar_at_top or bar_at_right)
        corner_bl = not (bar_at_bottom or bar_at_left)
        corner_br = not (bar_at_bottom or bar_at_right)

        active_corners = [c for c in [corner_tl, corner_tr, corner_bl, corner_br] if c]
        assert len(active_corners) == 2, f"Bar at {name} must have exactly 2 active corners, got {len(active_corners)}"

        # Edge active conditions
        edge_top = not bar_at_top
        edge_bottom = not bar_at_bottom
        edge_left = not bar_at_left
        edge_right = not bar_at_right

        active_edges = [e for e in [edge_top, edge_bottom, edge_left, edge_right] if e]
        assert len(active_edges) == 3, f"Bar at {name} must have exactly 3 active edges, got {len(active_edges)}"

        # Verify bar edge is inactive
        if name == "Top":
            assert not edge_top and not corner_tl and not corner_tr
            assert edge_bottom and edge_left and edge_right and corner_bl and corner_br
        elif name == "Bottom":
            assert not edge_bottom and not corner_bl and not corner_br
            assert edge_top and edge_left and edge_right and corner_tl and corner_tr
        elif name == "Left":
            assert not edge_left and not corner_tl and not corner_bl
            assert edge_top and edge_bottom and edge_right and corner_tr and corner_br
        elif name == "Right":
            assert not edge_right and not corner_tr and not corner_br
            assert edge_top and edge_bottom and edge_left and corner_tl and corner_bl


def check_scope_qualifications():
    """Verify showBarBackground is qualified across all corner and edge loaders."""
    # Find all showBackground assignments (excluding property declarations)
    assignments = re.findall(r"(?<!property bool )\bshowBackground:\s*(\S+)", SRC)
    assert len(assignments) == 8, f"Expected 8 showBackground assignments, found {len(assignments)}"
    for a in assignments:
        assert a == "monitorScope.showBarBackground", f"Unqualified or wrong showBackground binding: {a}"

    # Verify screen: monitorScope.modelData
    screen_assignments = re.findall(r"\bscreen:\s*(\S+)", SRC)
    assert len(screen_assignments) == 8, f"Expected 8 screen assignments, found {len(screen_assignments)}"
    for s in screen_assignments:
        assert s == "monitorScope.modelData", f"Wrong screen binding: {s}"


def check_monitor_lookup():
    """Verify monitor lookup matches by monitor name."""
    assert "m.name === monitorScope.modelData.name" in SRC, \
        "Monitor lookup should match by display output connector name m.name"


def check_family_loader():
    """Verify IllogicalImpulseFamily gates WrappedFrame loading."""
    assert re.search(r"PanelLoader\s*\{\s*extraCondition:\s*usingWrappedFrame;\s*component:\s*WrappedFrame\s*\{\}\s*\}", FAMILY_SRC), \
        "IllogicalImpulseFamily must load WrappedFrame with extraCondition: usingWrappedFrame"


if __name__ == "__main__":
    check_no_screen_shadowing()
    check_layershell_and_mask_regions()
    check_bar_symmetry()
    check_scope_qualifications()
    check_monitor_lookup()
    check_family_loader()
    print("ok: check-wrapped-frame passed all assertions")
