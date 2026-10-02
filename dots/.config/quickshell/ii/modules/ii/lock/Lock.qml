pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

LockScreen {
    id: root

    // Monitor name -> workspace id to restore on unlock (set when locking)
    property var savedWorkspaces: ({})

    // Locking parks each monitor on the mirror of its workspace, so the windows
    // are not sitting behind a transparent lock surface. INT32_MAX is Hyprland's
    // last valid id, and the mirror of a mirror is the original.
    readonly property int lockWorkspaceBase: 2147483647

    // The `workspaces` animation as configured, read when locking: the rise
    // below borrows that node, and Hyprland can only be told values, not to
    // forget an override, so this is what gets put back.
    property var workspacesAnim: null
    Process {
        id: animProc
        command: ["hyprctl", "animations", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const all = JSON.parse(text)[0];
                const a = all.find(a => a.name === "workspaces" && a.overridden) ?? all.find(a => a.name === "global");
                // Locked again inside a rise: that is the borrowed value, not the user's.
                if (a && a.bezier !== "iiUnlockRise")
                    root.workspacesAnim = a;
            }
        }
    }

    // Android's keyguard exit (KeyguardUnlockAnimationController): the surface
    // behind starts UNLOCK_ANIMATION_SURFACE_BEHIND_START_DELAY_MS after the
    // unlock, 5% of its height low (SURFACE_BEHIND_START_TRANSLATION_Y), and
    // rises into place over UNLOCK_ANIMATION_DURATION_MS on TOUCH_RESPONSE,
    // while the lock is still fading -- session_lock_xray draws it under the lock.
    // slidefadevert also fades it in; the 0.95 scale-up has no Hyprland equivalent.
    Timer {
        id: restoreTimer
        interval: 67
        onTriggered: {
            let lua = "";
            const a = root.workspacesAnim;
            if (a) {
                // Speed is tenths of a second for a bezier: 3 is the 300ms.
                lua += 'hl.curve("iiUnlockRise", { type = "bezier", points = {{0.3, 0}, {0.1, 1}} }); ';
                lua += 'hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "iiUnlockRise", style = "slidefadevert bottom 5%" }); ';
            }
            for (const screen of Quickshell.screens) {
                const wsId = root.savedWorkspaces[screen.name];
                if (wsId !== undefined)
                    lua += `hl.dispatch(hl.dsp.focus({ monitor = "${screen.name}" })); hl.dispatch(hl.dsp.focus({ workspace = ${wsId} })); `;
            }
            if (a) {
                const curve = a.bezier.startsWith("spring:") ? `spring = "${a.bezier.slice(7)}"` : `bezier = "${a.bezier}"`;
                lua += `hl.timer(function() hl.animation({ leaf = "workspaces", enabled = ${a.enabled}, speed = ${a.speed}, ${curve}, style = "${a.style}" }) end, { timeout = 400, type = "oneshot" })`;
            }
            Quickshell.execDetached(["hyprctl", "eval", lua]);
        }
    }

    lockSurface: LockSurface {
        context: root.context
    }

    // Single batch for lock and unlock so we don't race multiple hyprctl calls
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                animProc.running = true
                // Lock: save workspace per monitor and move all to temp workspace in one batch
                var next = {}
                var batch = "keyword animation workspaces,1,7,menu_decel,slidevert; "
                for (var i = 0; i < Quickshell.screens.length; ++i) {
                    var mon = Quickshell.screens[i].name
                    var mData = HyprlandData.monitors.find(m => m.name === mon)
                    if (mData?.activeWorkspace == undefined) {
                        return;
                    }
                    var ws = (mData?.activeWorkspace?.id ?? 1)
                    if (ws > root.lockWorkspaceBase / 2) {
                        // Already parked: this is the shell restarting under a
                        // lock it did not place, so the map it saved is gone.
                        // Saving the parked id as the one to come back to would
                        // strand every window on the workspace it is hiding.
                        next[mon] = root.lockWorkspaceBase - ws
                        continue
                    }
                    next[mon] = ws
                    batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${mon}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${root.lockWorkspaceBase - ws}})';`
                }
                root.savedWorkspaces = next
                Quickshell.execDetached(["bash", "-c", batch])
            } else {
                // The workspaces came back under the lock, where Hyprland refuses
                // windows keyboard focus, and its unlock refocus picks whatever is
                // under the pointer. Give it back to the window that had it, without
                // throwing the pointer there, as the old after-unlock switch did.
                Quickshell.execDetached(["hyprctl", "eval", 'local w = hl.get_active_workspace().last_window; if w then local warps = hl.get_config("cursor.no_warps"); hl.config({ cursor = { no_warps = true } }); hl.dispatch(hl.dsp.focus({ window = w })); hl.config({ cursor = { no_warps = warps } }) end'])
            }
        }
        // Unlock: the windows come back as the lock leaves, not after it.
        function onScreenLockExitingChanged() {
            if (GlobalStates.screenLockExiting)
                restoreTimer.restart()
        }
    }
}
