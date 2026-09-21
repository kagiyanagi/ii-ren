pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    // Ensure Idle service is always loaded so the idle inhibitor works in both panel families
    // (e.g. even when "Keep right sidebar loaded" is off in ii).
    Item {
        id: idleServiceAnchor
        property bool _ensureIdleLoaded: Idle.inhibit
    }

    required property Component lockSurface
    property alias context: lockContext
    property Component sessionLockSurface: WlSessionLockSurface {
        id: sessionLockSurface
        color: "transparent"
        Loader {
            active: GlobalStates.screenLocked
            anchors.fill: parent

            // The enter belongs to the surface inside -- it knows which edge its
            // parts grow out of. This is the exit, and it is the only thing the
            // compositor is still holding the lock open for. `active ? 1 : 0`
            // never animated either way: the binding is already 1 on the frame
            // the Loader is created and the item is gone on the frame it turns
            // false, and the animation under it was a ColorAnimation on a real,
            // which snaps.
            opacity: GlobalStates.screenLockExiting ? 0 : 1
            Behavior on opacity {
                animation: Appearance.animation.elementMoveExit.numberAnimation.createObject(this)
            }

            sourceComponent: root.lockSurface
        }
    }

    Process {
        id: unlockKeyringProc
        onExited: (exitCode, exitStatus) => {
            KeyringStorage.fetchKeyringData();
        }
    }
    function unlockKeyring() {
        unlockKeyringProc.exec({
            environment: ({
                "UNLOCK_PASSWORD": lockContext.currentText
            }),
            command: ["bash", "-c", Quickshell.shellPath("scripts/keyring/unlock.sh")]
        })
    }

    // This stores all the information shared between the lock surfaces on each screen.
    // https://github.com/quickshell-mirror/quickshell-examples/tree/master/lockscreen
    LockContext {
        id: lockContext

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                // Both edges, always: a flag that is set and never cleared locks
                // the screen on every start for the rest of the session's life.
                if (Persistent.ready)
                    Persistent.states.lock.locked = GlobalStates.screenLocked;

                if (GlobalStates.screenLocked) {
                    if (GlobalStates.overlayOpen) {
                        GlobalStates.overlayOpen = false;
                    }
                    lockContext.reset();
                    // Every lock starts with a fresh attempt budget, so a
                    // reader given up on last time is listening again.
                    lockContext.resetFingerprint();
                }
            }
        }

        onUnlocked: (targetAction) => {
            // Perform the target action if it's not just unlocking
            if (targetAction == LockContext.ActionEnum.Poweroff) {
                Session.poweroff();
                return;
            } else if (targetAction == LockContext.ActionEnum.Reboot) {
                Session.reboot();
                return;
            }

            // Unlock the keyring if configured to do so
            if (Config.options.lock.security.unlockKeyring) root.unlockKeyring(); // Async

            // The surface leaves before the session does. `screenLocked` is what
            // destroys it -- both the Loader above and the compositor's lock hang
            // off it -- so releasing here would delete the exit animation with no
            // other symptom. Everything past the fade happens in the timer.
            GlobalStates.screenLockExiting = true;
            unlockExitTimer.restart();
        }
    }

    // Dead time between a correct password and a usable desktop, so it is the
    // exit's length and nothing more.
    Timer {
        id: unlockExitTimer
        interval: Appearance.animation.elementMoveExit.duration
        onTriggered: {
            // Unlock the screen before exiting, or the compositor will display a
            // fallback lock you can't interact with.
            GlobalStates.screenLocked = false;
            // Released second, so the surface is already gone rather than
            // animating back to full opacity on its way out. Never left set:
            // the next lock surface would be created invisible.
            GlobalStates.screenLockExiting = false;

            // Reset
            lockContext.reset();

            // Post-unlock actions
            if (lockContext.alsoInhibitIdle) {
                lockContext.alsoInhibitIdle = false;
                Idle.toggleInhibit(true);
            }
        }
    }

    WlSessionLock {
        id: lock
        locked: GlobalStates.screenLocked
        surface: root.sessionLockSurface
    }

    function lock() {
        if (Config.options.lock.useHyprlock) {
            Quickshell.execDetached(["bash", "-c", "pidof hyprlock || hyprlock"]);
            return;
        }
        if (GlobalStates.screenLocked) return; // already locked/locking, avoid re-triggering WlSessionLock
        GlobalStates.screenLocked = true;
    }

    IpcHandler {
        target: "lock"

        function activate(): void {
            root.lock();
        }
        function focus(): void {
            lockContext.shouldReFocus();
        }
    }

    GlobalShortcut {
        name: "lock"
        description: "Locks the screen"

        onPressed: {
            root.lock()
        }
    }

    GlobalShortcut {
        name: "lockFocus"
        description: "Re-focuses the lock screen. This is because Hyprland after waking up for whatever reason"
            + "decides to keyboard-unfocus the lock screen"

        onPressed: {
            lockContext.shouldReFocus();
        }
    }

    function initIfReady() {
        if (!Config.ready || !Persistent.ready) return;
        // A session lock outlives the process that owns it. Kill the shell while
        // the screen is locked -- `pkill qs; qs -c ii` is the usual way -- and
        // the compositor keeps the session locked and puts up its own "your
        // lockscreen crashed" screen, which no password reaches and nothing
        // dismisses. The only way out is a new lock client taking the session
        // over, which Hyprland allows only while `misc:allow_session_lock_restore`
        // is on; it denies the request outright otherwise, and silently, so
        // tools/check-lock.py guards the Hyprland side of this.
        //
        // Whether the session is locked is not something the compositor's IPC
        // will answer, so the shell wrote it down. Same instance only: a
        // different signature is a fresh compositor holding no lock, and a flag
        // left over from a machine that went down locked would otherwise lock
        // every new session -- that case is launchOnStartup's.
        if (Persistent.states.lock.locked && !Persistent.isNewHyprlandInstance) {
            root.lock();
        } else if (Config.options.lock.launchOnStartup && Persistent.isNewHyprlandInstance) {
            root.lock();
        } else {
            KeyringStorage.fetchKeyringData();
        }
    }

    Component.onCompleted: initIfReady()

    Connections {
        target: Config
        function onReadyChanged() {
            root.initIfReady();
        }
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.initIfReady();
        }
    }
}
