# p3drovfx widget port tooling

Scripts used to bring the desktop widget library over from
[ii-p3drovfx](https://github.com/P3DROVFX/ii-p3drovfx), kept so it can be redone
when that fork adds widgets.

```sh
git clone --depth 1 https://github.com/P3DROVFX/ii-p3drovfx /tmp/p3
P3=/tmp/p3/dots/.config/quickshell/ii ./port-widgets.sh
```

`port-widgets.sh` only copies files. Everything that wires them into this shell —
the config schema, the instance model, the shims in `services/` and
`modules/common/` — is committed source, so re-running it never loses that work,
but it will overwrite local edits inside `modules/ii/background/widgets/`.

## Checks

The three checkers exist because the failure modes here are mostly silent:

| script | catches |
| --- | --- |
| `check-config-paths.py` | `Config.options.*` paths that do not exist. A missing member on a `JsonObject` reads as `undefined` with no warning at all. |
| `check-singletons.py` | members read off shell singletons that this shell does not declare — `BluetoothStatus.toggle`, `Weather.forecastData` and friends. |
| `check-unknown-types.py` | identifiers that resolve to nothing, i.e. whole singletons p3drovfx has and this shell does not. These are hard `ReferenceError`s. |

```sh
SHELL_DIR=$PWD/../../dots/.config/quickshell/ii python3 check-config-paths.py
```

None of them reach zero, and they are not supposed to. What is left over is
guarded (`x || ({})`, `x !== 0`, `x === "literal"`), harmless when `undefined`
reads as falsy, or a depth-2 access on a `var` that no static check can resolve.
Read a new finding before fixing it.

`mkshadow.sh` builds the qmllint import tree, since qmllint neither
auto-registers directory modules nor knows the synthetic `qs` module:

```sh
./mkshadow.sh ../../dots/.config/quickshell/ii /tmp/shadow
/usr/lib/qt6/bin/qmllint -I /tmp/shadow <file.qml>
```

Use `/usr/lib/qt6/bin/qmllint`. Plain `/usr/bin/qmllint` is a Qt5 stub that
prints nothing and exits 255, which looks exactly like a clean run.

qmllint is the only check here that sees the one failure mode that stops the
shell from starting at all: assigning a property a shared widget does not have.
Expect noise from it too — `Member "..." not found on type "QObject"` for
`Appearance.*`, the same for `qs::io::JsonObject` on `Config.options.*`, and
`Loader.item` — the shell's own files produce all three.
