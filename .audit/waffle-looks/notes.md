# waffle-looks — notes

**Opening it.**
- Active under `Config.options.panelFamily: "waffle"`.
- Imported by every Waffle surface (`modules/waffle/*`).
- Standalone controls can be previewed or verified in-process.

**Measured and fixed.**
- **Escape dismissal ReferenceError:** Fixed `content.close()` to `root.close()` in `WBarAttachedPanelContent.qml`.
- **NaN dimension resolution:** Fixed `upArea.containsPress` to `upArea.pressed` in `VerticalPageIndicator.qml`.
- **Tab click hijacking:** Removed full-surface `pressDetector` MouseArea in `WToolbarTabBar.qml`, deriving press micro-interaction from `root.currentItem`.
- **Empty menu safety:** Added `0` seed to `reduce()` accumulator in `WMenu.qml`.
- **Transparency gating:** Gated `contentTransparency` and `panelLayerTransparency` on `Config.options.appearance.transparency.enable` in `Looks.qml`.
- **GPU effect budget:** Removed offscreen `layer.enabled` and `OpacityMask` in `WIndeterminateProgressBar.qml`.
- **User avatar root crash fix:** Wrapped `StyledImage` in `Item` in `WUserAvatar.qml` to provide mutable `implicitWidth` and `implicitHeight`, preventing a fatal runtime crash where `WaffleLock` assigning `implicitHeight: 144` failed because `Image`'s `implicitHeight` is read-only.
- **Null-safety & clean imports:** Added battery availability guards in `WIcons.qml`, bound `longestTextMetrics.font` to `textItem.font` in `WTextWithFixedWidth.qml`, removed dead `FluentWinUI3` import in `WTextField.qml`, and removed circular `waffle.bar` import from `CloseButton.qml`.
- **4dp grid alignment:**
  - `WMenu.qml`: padding `3` -> `4`.
  - `WSlider.qml`: tooltip verticalPadding `3` -> `4`.
  - `WPopupToolTip.qml`: visualMargin `11` -> `12`.
  - `WSwitch.qml`: indicatorPressedWidth `17` -> `16`.
  - `WChoiceButton.qml`: verticalPadding `11` -> `12`, indicator `3` -> `4`, offset `18*2` -> `16*2`.
  - `CloseButton.qml`: `30x30` -> `32x32`.
  - `WMenuItem.qml`: horizontalPadding `11` -> `12`, indicator `3` -> `4`, offset `18*2` -> `16*2`.
  - `WToolbar.qml`: padding `9` -> `8`, implicitHeight `50` -> `48`.
  - `WToolbarIconTabButton.qml`: implicitWidth `38` -> `36`.
  - `FooterRectangle.qml`: `358x47` -> `360x48`.
  - `WTextButton.qml`: content margin `30` -> `32`.
  - `WAppIcon.qml`: implicitSize `26` -> `28`.
  - `WScrollBar.qml`: literal `9999` -> `Appearance.rounding.full`.
  - `WStackView.qml`: moveDistance `30` -> `32`.
- **Pragma Bound:** Added `pragma ComponentBehavior: Bound` across all 48 files.

**Automated verification.**
- Created `tools/check-waffle-looks.py` (passes).
- Ran `python3 tools/check-design.py --diff` (0 findings, 0 errors).
- Ran `python3 tools/check-effect-budget.py` (passes).
- Ran `python3 tools/check-content-transparency.py` (passes).
- Ran `python3 tools/check-mask-regions.py` (passes).
