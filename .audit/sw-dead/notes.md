# sw-dead — notes

Delete row, no design content. Ran 2026-09-20.

`dead.txt` was regenerated with `python3 tools/audit/reachable.py modules/settings/widgets
--dead` before anything was removed and came back **byte-identical** to the committed list
— 119 paths. Plus the three OSD triplet copies `families.md` names (the tool cannot tell
two files of the same name apart) and `modules/settings/widgets/qmldir`, whose URI
`qs.modules.settings.configs.widgets` is not this directory's.

122 files, 25,531 lines gone. 70 live files remain, which is what `families.md` predicted.

Of the four files importing that URI, three were dead and went with it. The fourth,
`DateDesktopWidgetConfig.qml`, is live: its import line was dropped on its own. The type it
wanted, `DesktopWidgetVisualOptions`, is a directory sibling and resolves with no import —
confirmed by the gate below, which loads it.

## Gates

- `tools/audit/smoke-settings.sh` — ok, window up, log clean. **Not** `smoke.sh`; the
  settings app is a second quickshell process.
- Every `"configPage"` string in `modules/ii/background/widgets/WidgetsRegistry.qml` still
  resolves to a file that exists — a registry string with no file behind it is invisible to
  every other check in this repo, so it is checked here by hand:
  `grep -ohE '"[^"]*widgets/[A-Za-z0-9]+Config\.qml"' …/WidgetsRegistry.qml`
- `check-design.py --diff` — 0, as expected from a diff that only removes lines.

The mechanical debt this removed: 66 of the tranche's 77 `check-design.py` hits, every
effect in the directory, and 486 `Config.options.*` paths that read as `undefined`.
