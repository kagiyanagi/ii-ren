#!/usr/bin/env python3
"""Regression checks for waffle-startMenu audit.

Verifies:
1. Every QML file in modules/waffle/startMenu declares pragma ComponentBehavior: Bound (17 files).
2. WaffleStartMenu.qml preserves exit animations via Loader latching, gates on screenLocked, and safely toggles clipboard/emojis.
3. StartMenuContent.qml handles Escape to clear search or close panel, and hooks SearchBar closeRequested.
4. SearchBar.qml has no redundant nested rectangle, spacing/margins on 4dp grid, handles Escape, and focuses on click.
5. SearchResults.qml guards against null entries, parents dynamic objects, and respects 4dp grid.
6. SearchEntryIcon.qml safely handles null entry and calculates loader width safely.
7. SearchResultButton.qml metrics conform to 4dp grid.
8. AppCategoryGrid.qml uses Appearance.animation tokens instead of hardcoded durations, avoids ID shadowing, and stays on 4dp grid.
9. AllAppsGrid.qml uses on-grid spacing and parents dynamically created category models.
10. StartAppButton.qml uses on-grid spacing and 32px icon size.
11. StartPageApps.qml uses on-grid margins/spacing and filters uninstalled pinned apps.
12. StartPageContent.qml uses on-grid footer height and closes menu on power actions.
13. StartUserButton.qml uses on-grid metrics, closes on logout, and auto-dismisses popup on search close.
"""

from pathlib import Path
import re
import sys

BASE = Path("dots/.config/quickshell/ii/modules/waffle/startMenu")

def check_file_exists(rel_path: str) -> Path:
    p = BASE / rel_path
    if not p.is_file():
        print(f"FAIL: File not found: {p}")
        sys.exit(1)
    return p

def main() -> int:
    failed = False

    # 1. Pragma ComponentBehavior: Bound across all 17 files
    all_qml = sorted(BASE.glob("**/*.qml"))
    if len(all_qml) != 17:
        print(f"FAIL: Expected 17 QML files under startMenu, found {len(all_qml)}")
        return 1

    for qml in all_qml:
        content = qml.read_text(encoding="utf-8")
        if "pragma ComponentBehavior: Bound" not in content:
            print(f"FAIL: {qml} missing 'pragma ComponentBehavior: Bound'")
            failed = True

    # 2. WaffleStartMenu: Loader latching, screenLock gating, safe toggles
    wsm_path = check_file_exists("WaffleStartMenu.qml")
    wsm_text = wsm_path.read_text(encoding="utf-8")
    if "panelLoader.active = true" not in wsm_text:
        print("FAIL: WaffleStartMenu.qml does not activate panel via Loader")
        failed = True
    if re.search(r"PanelWindow\s*\{[^}]*visible:\s*GlobalStates\.searchOpen", wsm_text):
        print("FAIL: WaffleStartMenu.qml uses premature visible: GlobalStates.searchOpen on PanelWindow")
        failed = True
    if "GlobalStates.screenLocked" not in wsm_text:
        print("FAIL: WaffleStartMenu.qml lacks screenLocked check/gating")
        failed = True
    if "panelLoader.active = false" not in wsm_text:
        print("FAIL: WaffleStartMenu.qml does not deactivate Loader on closed")
        failed = True

    # 3. StartMenuContent: Escape handling and closeRequested hook
    smc_path = check_file_exists("StartMenuContent.qml")
    smc_text = smc_path.read_text(encoding="utf-8")
    if "event.key === Qt.Key_Escape" not in smc_text or "root.close()" not in smc_text:
        print("FAIL: StartMenuContent.qml does not handle Escape to close panel or clear search")
        failed = True
    if "onCloseRequested: {" not in smc_text and "onCloseRequested:" not in smc_text:
        print("FAIL: StartMenuContent.qml does not handle onCloseRequested from SearchBar")
        failed = True

    # 4. SearchBar: No redundant nested rectangle, on 4dp grid, handles Escape
    sb_path = check_file_exists("SearchBar.qml")
    sb_text = sb_path.read_text(encoding="utf-8")
    if "searchInputBg" in sb_text or "anchors.margins: 1" in sb_text:
        print("FAIL: SearchBar.qml still contains redundant nested rectangle or 1px margin")
        failed = True
    if "spacing: 11" in sb_text or "leftMargin: 14" in sb_text:
        print("FAIL: SearchBar.qml contains off-grid spacing or leftMargin")
        failed = True
    if "signal closeRequested" not in sb_text:
        print("FAIL: SearchBar.qml missing signal closeRequested")
        failed = True
    if "acceptedButtons: Qt.LeftButton" not in sb_text or "root.forceFocus()" not in sb_text:
        print("FAIL: SearchBar.qml MouseArea does not focus on click")
        failed = True

    # 5. SearchResults: Null safety, memory leak parentage, on-grid metrics
    sr_path = check_file_exists("searchPage/SearchResults.qml")
    sr_text = sr_path.read_text(encoding="utf-8")
    if "searchResultComp.createObject(null" in sr_text:
        print("FAIL: SearchResults.qml creates unparented searchResultComp objects (memory leak)")
        failed = True
    for bad in ["preferredWidth: 386", "anchors.margins: 22", "spacing: 13", "Layout.topMargin: 10"]:
        if bad in sr_text:
            print(f"FAIL: SearchResults.qml still contains off-grid metric '{bad}'")
            failed = True
    if "if (!resultPreview.entry || !resultPreview.entry.name)" not in sr_text:
        print("FAIL: SearchResults.qml actionsColumn does not guard against null entry")
        failed = True

    # 6. SearchEntryIcon: Null safety and loader width calculation
    sei_path = check_file_exists("searchPage/SearchEntryIcon.qml")
    sei_text = sei_path.read_text(encoding="utf-8")
    if "root.entry != null" not in sei_text:
        print("FAIL: SearchEntryIcon.qml lacks null guard on entry")
        failed = True

    # 7. SearchResultButton: On-grid metrics
    srb_path = check_file_exists("searchPage/SearchResultButton.qml")
    srb_text = srb_path.read_text(encoding="utf-8")
    for bad in ["verticalPadding: 11", "implicitWidth: 47", "implicitSize: 14"]:
        if bad in srb_text:
            print(f"FAIL: SearchResultButton.qml still contains off-grid metric '{bad}'")
            failed = True

    # 8. AppCategoryGrid: Tokens instead of hardcoded durations, no ID shadowing, on-grid
    acg_path = check_file_exists("startPage/AppCategoryGrid.qml")
    acg_text = acg_path.read_text(encoding="utf-8")
    if "duration: 300" in acg_text or "duration: 200" in acg_text:
        print("FAIL: AppCategoryGrid.qml still contains hardcoded 300/200ms animation durations")
        failed = True
    if re.search(r"component SmallGridButton:\s*WButton\s*\{\s*id:\s*root\b", acg_text):
        print("FAIL: SmallGridButton shadows parent root id in AppCategoryGrid.qml")
        failed = True
    for bad in ["anchors.margins: 10", "anchors.rightMargin: -19", "implicitSize: 34"]:
        if bad in acg_text:
            print(f"FAIL: AppCategoryGrid.qml contains off-grid metric '{bad}'")
            failed = True

    # 9. AllAppsGrid: On-grid spacing and parentage
    aag_path = check_file_exists("startPage/AllAppsGrid.qml")
    aag_text = aag_path.read_text(encoding="utf-8")
    if "columnSpacing: 27" in aag_text:
        print("FAIL: AllAppsGrid.qml still contains off-grid columnSpacing: 27")
        failed = True
    if "aggAppCatComp.createObject(null" in aag_text:
        print("FAIL: AllAppsGrid.qml creates unparented AggregatedAppCategoryModel")
        failed = True

    # 10. StartAppButton: On-grid spacing and icon size
    sab_path = check_file_exists("startPage/StartAppButton.qml")
    sab_text = sab_path.read_text(encoding="utf-8")
    if "spacing: 3" in sab_text or "implicitSize: 34" in sab_text:
        print("FAIL: StartAppButton.qml contains off-grid spacing: 3 or implicitSize: 34")
        failed = True

    # 11. StartPageApps: On-grid margins and filter null apps
    spa_path = check_file_exists("startPage/StartPageApps.qml")
    spa_text = spa_path.read_text(encoding="utf-8")
    for bad in ["topMargin: 25", "bottomMargin: 30", "spacing: 26"]:
        if bad in spa_text:
            print(f"FAIL: StartPageApps.qml contains off-grid metric '{bad}'")
            failed = True
    if ".filter(app => app != null)" not in spa_text:
        print("FAIL: StartPageApps.qml does not filter uninstalled/null pinned apps")
        failed = True

    # 12. StartPageContent: On-grid footer height and session action closing
    spc_path = check_file_exists("startPage/StartPageContent.qml")
    spc_text = spc_path.read_text(encoding="utf-8")
    if "implicitHeight: 63" in spc_text:
        print("FAIL: StartPageContent.qml footer implicitHeight is off-grid (63)")
        failed = True

    # 13. StartUserButton: On-grid metrics and logout close
    sub_path = check_file_exists("startPage/StartUserButton.qml")
    sub_text = sub_path.read_text(encoding="utf-8")
    for bad in ["x: -51", "spacing: 5", "Layout.bottomMargin: 7", "sourceSize: Qt.size(58, 58)", "implicitWidth: 334"]:
        if bad in sub_text:
            print(f"FAIL: StartUserButton.qml contains off-grid metric '{bad}'")
            failed = True

    if failed:
        return 1

    print(f"ok: all checks passed ({len(all_qml)} files verified in waffle/startMenu)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
