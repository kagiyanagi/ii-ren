pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import "floatingMode.js" as FM

/**
 * Floating mode: every window floats and is managed the way KWin and Mutter manage theirs
 * (placement, maximize, focus and stacking: floatingMode.lua, the half that runs inside
 * Hyprland). The windows that draw no close, maximize or minimize of their own get a bar
 * or a rail with them (hyprbars, or modules/ii/floatingRails).
 *
 * Hyprland emits nothing when a window moves -- a Super+drag or an edge resize is
 * silent -- so while the mode is on a Lua timer inside the compositor walks the
 * visible windows every frame and sends one custom event when anything changed.
 * The mode's on/off lives in Persistent; Hyprland's half is installed again after
 * every config reload, because a reload starts a fresh Lua state.
 */
Singleton {
    id: root

    readonly property bool enabled: Persistent.ready && Persistent.states.hyprland.floatingMode
    // Android's caption is 40dp (AOSP desktop_mode_freeform_decor_caption_height) with
    // 32dp buttons 12dp apart; shrunk a step so it sits with KDE's Breeze title bars
    // (the owner's call), buttons still inset evenly. The side rail is the same caption
    // stood on its end.
    readonly property int railWidth: 36
    readonly property int buttonSize: 28
    readonly property int buttonGap: 8
    // "top", Android 16's caption bar, or "right", a rail down the side.
    readonly property string railSide: Config.options?.windows?.floatingControls === "right" ? "right" : "top"
    // Moving the controls to the other side can put them off screen, so every window
    // gets checked against its monitor again, and the Lua learns where they are now.
    onRailSideChanged: {
        root.fitted = ({});
        if (root.enabled)
            root.hyprEval(root.installExpr());
        root.loadBars();
        root.refresh();
        root.fitNew();
    }
    readonly property string luaPath: FileUtils.trimFileProtocol(Qt.resolvedUrl("floatingMode.lua"))

    function installExpr() {
        return FM.installExpr(root.luaPath, {
            barClasses: root.barClasses.filter(c => !root.ownControlsClass(c)),
            side: root.railSide,
            size: root.railWidth
        });
    }

    // The top bar is drawn by hyprbars, inside Hyprland, so it opens, closes, moves and
    // swipes in the same frame as its window: this layer-over-the-windows, told where
    // a window is over IPC, could only ever follow a frame or more behind. The layer
    // stays for the side rail, and for the top bar whenever the plugin cannot load.
    property bool barsLoaded: false
    readonly property bool pluginBars: root.enabled && root.railSide === "top" && root.barsLoaded
    onPluginBarsChanged: root.syncBars()
    // address -> tagged for a bar.
    property var barred: ({})
    // Known before a window of the class opens: the window is tagged as it opens and
    // has its bar on its first frame. A class seen for the first time waits for the
    // probe, about four frames (measured at 60fps).
    readonly property var barClasses: Persistent.states.hyprland.floatingBarClasses
    readonly property string barsConfig: FM.barsLua({
        height: root.railWidth,
        color: root.hyprColor(Appearance.colors.colLayer2),
        text: root.hyprColor(Appearance.colors.colOnLayer2),
        font: Appearance.font.family.main,
        chip: root.hyprColor(Appearance.colors.colLayer3),
        closeHover: root.hyprColor(Appearance.colors.colErrorContainer),
        textSize: Appearance.font.pixelSize.small,
        padding: root.buttonGap,
        gap: root.buttonGap,
        button: root.buttonSize
    })
    onBarsConfigChanged: {
        if (root.pluginBars)
            root.hyprEval(root.barsConfig);
    }

    function hyprColor(c) {
        const q = Qt.color(c);
        const h = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return "rgba(" + h(q.r) + h(q.g) + h(q.b) + h(q.a) + ")";
    }

    function loadBars() {
        if (root.enabled && root.railSide === "top" && !root.barsLoaded && !barsLoader.running)
            barsLoader.running = true;
    }

    function syncBars() {
        root.hyprEval(root.pluginBars ? root.barsConfig : FM.BARS_OFF_LUA);
        root.refresh();
    }

    // Tagged whether or not the plugin is up yet, so its bars are there the moment it is.
    function tagBars() {
        for (const w of root.state.windows) {
            if (root.barred[w.address] || !w.floating || !root.hasRail(w))
                continue;
            root.barred[w.address] = true;
            Hyprland.dispatch(FM.barTagExpr(w.address));
            const expr = FM.barClassExpr(w.cls);
            if (expr && !root.barClasses.includes(w.cls)) {
                Persistent.states.hyprland.floatingBarClasses = root.barClasses.concat([w.cls]);
                Hyprland.dispatch(expr);
            }
        }
    }

    Process {
        id: barsLoader
        command: ["bash", FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/hyprbars.sh`)]
        onExited: code => {
            root.barsLoaded = code === 0;
            if (code !== 0)
                console.warn("[FloatingMode] hyprbars could not be built or loaded; the shell draws the bars instead");
        }
    }
    readonly property int tickMs: FM.TICK_MS

    // The watcher's last report, with a rail drag laid over it.
    property var state: FM.parse("")
    // What FloatingRails draws: one entry per rail, plus the ones still fading out.
    property var rails: []
    // pid -> whether that app draws its own window controls.
    property var ownControlsByPid: ({})
    // address -> true once a window has been kept from pushing its rail off screen.
    property var fitted: ({})
    // { address, x, y } while a rail is dragging its window.
    property var drag: null
    property bool floatAllPending: false
    property var probeQueue: []

    readonly property var ownControlsPatterns: (Config.options?.windows?.ownControls ?? []).map(p => {
        try {
            return new RegExp(p);
        } catch (e) {
            console.warn("[FloatingMode] bad ownControls pattern:", p);
            return null;
        }
    }).filter(Boolean)

    function toggle() {
        root.setEnabled(!root.enabled);
    }

    function setEnabled(on) {
        if (!Persistent.ready || on === root.enabled)
            return;
        Persistent.states.hyprland.floatingMode = on;
        if (on) {
            root.start(true);
            return;
        }
        root.floatAllPending = false;
        root.drag = null;
        root.hyprEval(FM.disableExpr());
        root.state = FM.parse("");
        root.fitted = ({});
        root.barred = ({});
        root.refresh();
    }

    // floatAll: float what is tiled now. Only on a real enable or a fresh Hyprland
    // session: after a reload, a window that is tiled was tiled on purpose.
    function start(floatAll) {
        root.hyprEval(root.installExpr());
        root.loadBars();
        if (root.barsLoaded)
            root.syncBars();
        if (!floatAll)
            return;
        root.floatAllPending = true;
        root.detect(HyprlandData.windowList.map(w => w.pid));
        if (!probe.running && root.probeQueue.length === 0)
            root.floatAll();
    }

    function floatAll() {
        root.floatAllPending = false;
        const railed = HyprlandData.windowList.filter(w => !w.floating && root.hasRail({ pid: w.pid, cls: w.class })).map(w => w.address);
        root.hyprEval(FM.floatAllExpr(railed));
    }

    function hyprEval(lua) {
        Quickshell.execDetached(["hyprctl", "eval", lua]);
    }

    function hasRail(w) {
        if (root.ownControlsByPid[w.pid] !== false)
            return false; // draws its own, or not probed yet
        return !root.ownControlsClass(w.cls);
    }

    // The shell's own windows (the settings app) draw their close button while
    // windows.showTitlebar is on, as the listed apps always do.
    function ownControlsClass(cls) {
        return (cls === "org.quickshell" && Config.options.windows.showTitlebar) || root.ownControlsPatterns.some(re => re.test(cls));
    }

    function railOutline(width, height) {
        return FM.railOutline(width, height, root.state.rounding, root.state.border, root.state.power, 10, root.railSide);
    }

    function windowFor(address) {
        return root.state.windows.find(w => w.address === address) ?? null;
    }

    function withDrag(state, drag) {
        if (!drag)
            return state;
        return Object.assign({}, state, {
            windows: state.windows.map(w => w.address === drag.address ? Object.assign({}, w, { x: drag.x, y: drag.y }) : w)
        });
    }

    function update(data) {
        root.state = root.withDrag(FM.parse(data), root.drag);
        root.detect(root.state.windows.map(w => w.pid));
        root.refresh();
        root.fitNew();
        root.tagBars();
    }

    // A rail whose window closed, went fullscreen or left the screen keeps its entry,
    // marked leaving, until its fade has played: no layer outlives its content, and
    // no content vanishes on the frame it goes (TASTE.md 4.7, 5.1).
    function refresh() {
        const now = Date.now();
        const exitMs = Appearance.animation.elementMoveExit.duration;
        const live = root.pluginBars ? [] : FM.rails(root.state, w => root.hasRail(w), root.railWidth, root.railSide);
        const seen = {};
        for (const r of live)
            seen[r.address] = true;
        const leaving = root.rails.filter(r => !seen[r.address] && now - (r.leavingSince ?? now) < exitMs)
            .map(r => Object.assign({}, r, { leaving: true, leavingSince: r.leavingSince ?? now }));
        root.rails = live.concat(leaving);
        if (leaving.length > 0)
            purgeTimer.restart();
    }

    // Once per window: a new window as wide as the screen would put its rail off it.
    function fitNew() {
        const s = root.state;
        for (const w of s.windows) {
            if (root.fitted[w.address] || !w.floating || w.fullscreen || w.maximized || !root.hasRail(w) || !s.areas[w.monitor])
                continue;
            root.fitted[w.address] = true;
            const box = FM.fit(w, s.areas[w.monitor], s.border, root.railWidth, root.railSide);
            if (box)
                root.place(w.address, box);
        }
    }

    function place(address, box) {
        Hyprland.dispatch(FM.resizeExpr(address, box.w, box.h));
        Hyprland.dispatch(FM.moveExpr(address, box.x, box.y));
    }

    // Pressing a rail is pressing that window's title bar: focus alone does not
    // raise a floating window here, so it is brought to the front as well.
    function focus(address) {
        Hyprland.dispatch(FM.focusExpr(address));
        Hyprland.dispatch(FM.raiseExpr(address));
    }

    function close(address) {
        Hyprland.dispatch(FM.closeExpr(address));
    }

    function minimize(address) {
        Hyprland.dispatch(FM.minimizeExpr(address));
    }

    // The dock's and Alt+Tab's way back for a minimized window; false for any other, which
    // they activate as usual.
    function restoreMinimized(address) {
        if (!root.enabled || HyprlandData.windowByAddress[address]?.workspace?.name !== FM.MINIMIZED)
            return false;
        root.hyprEval(FM.activateExpr(address));
        return true;
    }

    // Hyprland's own toggle: floatingMode.lua turns it into the mode's maximize, the one
    // path every maximize takes.
    function toggleMaximize(address) {
        Hyprland.dispatch(FM.maximizeExpr(address));
    }

    // A drag on a maximized window's rail brings it out under the pointer before moving it.
    function beforeDrag(address) {
        const expr = FM.beforeDragExpr(address);
        if (expr)
            root.hyprEval(expr);
    }

    // The rail follows the pointer itself and the window is moved to match once per
    // event-loop turn. no_anim for the length of the drag: every move would otherwise
    // restart the window's 500ms spring and leave it trailing the rail.
    function dragTo(address, x, y) {
        if (!root.drag)
            Hyprland.dispatch(FM.noAnimExpr(address, true));
        root.drag = { address: address, x: x, y: y };
        root.state = root.withDrag(root.state, root.drag);
        root.refresh();
        Qt.callLater(root.flushDrag);
    }

    function flushDrag() {
        if (root.drag)
            Hyprland.dispatch(FM.moveExpr(root.drag.address, root.drag.x, root.drag.y));
    }

    function endDrag() {
        const d = root.drag;
        if (!d)
            return;
        root.drag = null;
        Hyprland.dispatch(FM.moveExpr(d.address, d.x, d.y));
        Hyprland.dispatch(FM.noAnimExpr(d.address, false));
    }

    // One process per batch of new pids, never one per window or per tick.
    function detect(pids) {
        const fresh = pids.filter(p => Number.isInteger(p) && p > 0 && root.ownControlsByPid[p] === undefined && !root.probeQueue.includes(p));
        if (fresh.length === 0)
            return;
        root.probeQueue = root.probeQueue.concat(fresh);
        if (!probe.running)
            root.runProbe();
    }

    function runProbe() {
        probe.command = ["sh", "-c", FM.OWN_CONTROLS_PROBE, "sh"].concat(root.probeQueue.map(String));
        root.probeQueue = [];
        probe.running = true;
    }

    Process {
        id: probe
        stdout: StdioCollector {
            onStreamFinished: {
                const known = Object.assign({}, root.ownControlsByPid);
                for (const line of text.split("\n")) {
                    const f = line.split(" ");
                    if (f.length === 2)
                        known[f[0]] = f[1] === "1";
                }
                root.ownControlsByPid = known;
                if (root.floatAllPending && root.probeQueue.length === 0)
                    root.floatAll();
                if (root.enabled) {
                    root.refresh();
                    root.fitNew();
                    root.tagBars();
                }
            }
        }
        onExited: {
            if (root.probeQueue.length > 0)
                root.runProbe();
        }
    }

    Timer {
        id: purgeTimer
        interval: Appearance.animation.elementMoveExit.duration
        onTriggered: root.refresh()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "custom") {
                if (root.enabled && event.data.startsWith(FM.EVENT + ">>"))
                    root.update(event.data.slice(FM.EVENT.length + 2));
            } else if (event.name === "closewindow") {
                // Hyprland hands a closed window's address to the next window it opens,
                // which then read as already tagged and never got its bar.
                const address = "0x" + event.data;
                delete root.barred[address];
                delete root.fitted[address];
            } else if (event.name === "configreloaded") {
                root.startOrOff(false);
            }
        }
    }

    // A property, not a Connections on Persistent: the shell crashed once in
    // QQmlConnections::connectSignalsToMethods() on the reload that first loaded this
    // file (DESIGN.md 2.9), and a change handler has no connection to make.
    readonly property bool persistentReady: Persistent.ready
    onPersistentReadyChanged: root.startOrOff(Persistent.isNewHyprlandInstance)
    Component.onCompleted: root.startOrOff(Persistent.isNewHyprlandInstance)

    // A reload puts a loaded hyprbars back to its defaults, enabled and without the
    // no_bar rules: with the mode off, it would bar every window, tiled ones too.
    function startOrOff(floatAll) {
        if (!Persistent.ready)
            return;
        if (root.enabled)
            root.start(floatAll);
        else
            root.hyprEval(FM.BARS_OFF_LUA);
    }

    GlobalShortcut {
        name: "floatingModeToggle"
        description: "Toggles floating mode: every window floats, with controls beside the ones that have none"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "floatingMode"

        function toggle(): void {
            root.toggle();
        }
    }
}
