# common-widgets — the family split

`modules/common/widgets` is a tranche, not a session: 169 files, 14,176 lines. It is cut
into the 15 families below, each its own queue row and its own session, each under the
2,500-line rule in `.github/AUDIT.md`. Membership is by what a widget *is*, not where it
sits in the directory, because the design law is applied per component kind.

Regenerate any family's pack with the regex in its row:

```
python3 tools/audit/pack.py modules/common/widgets --only '<regex>' --id <id>
```

Excluded: `shapes/**` (git submodule, not ours) and `shaders/check*.qml` (dev harness
windows, not shipped widgets).

| family | files | lines | `--only` regex |
|---|---:|---:|---|
| `cw-inputs` | 16 | 1648 | `^(StyledSlider|StyledVerticalSlider|StyledComboBox|StyledComboBoxSearch|StyledSpinBox|StyledSwitch|StyledRadioButton|MaterialTextField|MaterialTextArea|StyledTextInput|StyledTextArea|WindowDialogSlider|KeyboardKey|AddressBar|AddressBreadcrumb|SearchHandler)\.qml$` |
| `cw-config-rows` | 12 | 1517 | `^(ConfigListView|ConfigListViewEntry|ConfigSubPageHost|ConfigSelectionArray|ConfigSpinBox|ConfigSlider|ConfigTextField|ConfigSwitch|ConfigRow|MonitorPicker|MonitorRect|MonitorCanvas)\.qml$` |
| `cw-buttons` | 21 | 1471 | `^(RippleButton|StateLayer|StateOverlay|HighlightOverlay|RippleButtonWithIcon|RippleButtonWithShape|FloatingActionButton|DialogButton|MenuButton|ColorPreviewButton|ColorPreviewGrid|LightDarkPreferenceButton|GroupButton|GroupButtonWithIcon|GroupButtonWithTextField|SelectionGroupButton|ButtonGroup|VerticalButtonGroup|FlowButtonGroup|PointingHandInteraction|PointingHandLinkHover)\.qml$` |
| `cw-progress` | 13 | 1060 | `^(StyledProgressBar|StyledIndeterminateProgressBar|ClippedProgressBar|CircularProgress|ClippedFilledCircularProgress|MaterialLoadingIndicator|Graph|DashedBorder|MaterialCookie|SineCookie|WaveVisualizer|RadialWaveVisualizer|WavyLine)\.qml$` |
| `cw-scaffolding` | 14 | 1044 | `^(ContentPage|ContentGroup|ContentSection|ContentSubsection|ContentSubsectionLabel|PagePlaceholder|StyledFlickable|StyledScrollBar|ScrollEdgeFade|StyledListView|WheelScrollHandler|FocusedScrollMouseArea|Revealer|FadeLoader)\.qml$` |
| `cw-battery` | 1 | 1040 | `^(CustomBatteryMeter)\.qml$` |
| `cw-primitives` | 18 | 1017 | `^(StyledText|MaterialSymbol|OptionalMaterialSymbol|SqueezedAnnotationStyledText|MarqueeText|StyledImage|ThumbnailImage|DirectoryIcon|Favicon|CustomIcon|StyledRectangle|Circle|Pill|MaterialShape|MaterialShapeWrappedMaterialSymbol|RoundCorner|CliphistImage|FileSearchImage)\.qml$` |
| `cw-media` | 8 | 1007 | `^(Player|PlayerControls|PlayerControlsLyrics|MaterialMusicControls|Lyrics|LyricsStatic|LyricScroller|LyricLine)\.qml$` |
| `cw-dialogs` | 14 | 929 | `^(WindowDialog|WindowDialogTitle|WindowDialogParagraph|WindowDialogSectionHeader|WindowDialogSeparator|WindowDialogButtonRow|SelectionDialog|DialogListItem|StyledToolTip|StyledToolTipContent|PopupToolTip|NoticeBox|ShortcutBox|FullscreenPolkitWindow)\.qml$` |
| `cw-motion` | 15 | 858 | `^(transitions/RevealWipe|transitions/Wipe|transitions/Crossfade|transitions/Slash|transitions/Outer|transitions/Diamond|transitions/Radial|transitions/Wave|animations/PlaceholderOpeningAnimation|animations/BounceAnimation|animations/DelayedPropertyAnimation|animations/TriggerAnimation|ErrorShakeAnimation|TransitionImage|Carousel)\.qml$` |
| `cw-navigation` | 13 | 830 | `^(SecondaryTabBar|SecondaryTabButton|NavigationRail|NavigationRailButton|NavigationRailTabArray|NavigationRailExpandButton|Toolbar|ToolbarButton|IconToolbarButton|ToolbarTabBar|ToolbarTabButton|ToolbarTextField|ToolbarPairedFab)\.qml$` |
| `cw-notifications` | 6 | 612 | `^(NotificationItem|NotificationGroup|NotificationAppIcon|NotificationGroupExpandButton|NotificationActionButton|NotificationListView)\.qml$` |
| `cw-misc` | 4 | 463 | `^(CalendarView|WeekRow|AttachedFileIndicator|AndroidClock)\.qml$` |
| `cw-gestures` | 6 | 446 | `^(DragManager|SwipeDismissible|ResizeHandler|widgetCanvas/WidgetCanvas|widgetCanvas/AbstractWidget|widgetCanvas/AbstractOverlayWidget)\.qml$` |
| `cw-effects` | 8 | 234 | `^(FlutedGlass|WallpaperFilter|SubjectMatte|Colorizer|MaskMultiEffect|StyledBlurEffect|StyledDropShadow|StyledRectangularShadow)\.qml$` |

**Total** 169 files / 14176 lines.
