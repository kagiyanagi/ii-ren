pragma Singleton
import Quickshell
import qs.services
import qs.modules.common

Singleton {
    id: root

    function changePassword() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.changePassword}`]);
    }

    function lock() {
        Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.global("quickshell:lock")']);
    }

    function suspend() {
        Quickshell.execDetached(["bash", "-c", "systemctl suspend || loginctl suspend"]);
    }

    function logout() {
        Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/session/logout.py")]);
    }

    function launchTaskManager() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.taskManager}`]);
    }

    function hibernate() {
        Quickshell.execDetached(["bash", "-c", `systemctl hibernate || loginctl hibernate`]);
    }

    function poweroff() {
        Quickshell.execDetached(["systemctl", "poweroff"]);
    }

    function reboot() {
        Quickshell.execDetached(["systemctl", "reboot"]);
    }

    function rebootToFirmware() {
        Quickshell.execDetached(["systemctl", "reboot", "--firmware-setup"]);
    }
}
