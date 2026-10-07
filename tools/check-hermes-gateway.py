#!/usr/bin/env python3
"""A remote Hermes gateway is gateway.sh re-run on the host, and it gets there intact.

The script ships itself to the remote as ssh's command string, quoted with
`printf %q`. A quoting slip there does not fail loudly: the remote shell runs
something else, and the sidebar sits on "Connecting" or reports a crash that
has nothing to do with the host. This runs the launcher against a fake `ssh`
that hands the command to a local login shell, the way sshd does, and asserts
the far side runs the *local* branch -- a missing install there must still say
"hermes-agent not found" and exit 127, since that is what the sidebar reads as
"not installed on that gateway". It also pins the ssh options: no prompt can be
answered, `~` in the desktop app's keyPath is expanded, and `--` keeps a host
from being read as an option.
"""
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "dots/.config/quickshell/ii/scripts/hermes/gateway.sh"
SERVICE = ROOT / "dots/.config/quickshell/ii/services/HermesService.qml"

with tempfile.TemporaryDirectory() as tmp:
    tmp = pathlib.Path(tmp)
    fake = tmp / "ssh"
    fake.write_text(
        '#!/usr/bin/env bash\n'
        f'printf "%s\\n" "$@" > {tmp}/args\n'
        # sshd runs the command string through the user's shell, with none of
        # the client's environment.
        f'exec env -i HOME={tmp}/remote-home PATH=/usr/bin:/bin bash -c "${{@: -1}}"\n'
    )
    fake.chmod(0o755)
    env = dict(os.environ, PATH=f"{tmp}:{os.environ['PATH']}", HOME=str(tmp / "home"),
               HERMES_GATEWAY_SSH="user@host", HERMES_GATEWAY_SSH_KEY="~/.ssh/id_rsa")
    run = subprocess.run([str(SCRIPT)], env=env, capture_output=True, text=True, timeout=20)

    assert run.returncode == 127, (run.returncode, run.stderr)
    assert f"hermes-agent not found at {tmp}/remote-home/.hermes/hermes-agent" in run.stderr, run.stderr

    args = (tmp / "args").read_text().splitlines()
    assert "BatchMode=yes" in args, args
    assert args[args.index("-i") + 1] == f"{tmp}/home/.ssh/id_rsa", args
    assert args[-3:-1] == ["--", "user@host"], args

# Local stays local: the env the service passes must be unset, not empty, off ssh.
service = SERVICE.read_text()
assert 'HERMES_GATEWAY_SSH: root.remote ?' in service and ': null,' in service
print("check-hermes-gateway: ok")
