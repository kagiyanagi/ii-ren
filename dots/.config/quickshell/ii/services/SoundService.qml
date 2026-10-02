pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

/**
 * XDG sound theme event player (freedesktop sound theme & naming specs, simplified).
 *
 * Discovers themes from /usr/share/sounds, ~/.local/share/sounds and the ones the
 * shell ships (assets/sounds), resolves event names against the configured theme
 * with fallback to inherited themes and freedesktop, and plays them in-process
 * through Qt Multimedia.
 *
 * Playback entry points:
 *  - playEvent(category, events): gated by Config.options.sounds.enable and
 *    Config.options.sounds[category], rate-limited per category, honors
 *    per-event custom file overrides (Config.options.sounds.custom). Only the
 *    shell plays these: load() is called from shell.qml alone, so the settings
 *    app, which also instantiates the services that call this, stays quiet.
 *  - preview(key, url): the settings page's play buttons. Ungated.
 *  - startLoop/stopLoop: continuous ring (alarms); ignores the master switch,
 *    the caller checks its own category toggle. Supports gentle fade-in.
 */
Singleton {
    id: root

    // [{id, dir, name, comment, inherits, example}]
    property list<var> themes: []
    property bool indexReady: false
    property bool live: false
    property var _soundFiles: ({})
    property var _lastPlayed: ({})
    readonly property real _initTime: Date.now()
    readonly property var _minIntervalMs: ({
        notifications: 500,
        volumeChange: 150,
        screenshot: 300,
        devices: 1000
    })
    // Suppress categories that misfire while services settle on startup:
    // UPower flips isPluggedIn once real values arrive, Bluetooth/KDE Connect
    // report already-connected devices as "new", lock-on-startup engages late,
    // and the sink's volume arrives as a change from 0.
    readonly property var _startupGraceMs: ({
        battery: 5000,
        charging: 5000,
        devices: 10000,
        lock: 10000,
        volumeChange: 5000
    })

    // What each category plays, first choice first; each one is a switch on the
    // Sounds page and a key in Config.options.sounds (tools/check-sounds.py).
    // Callers with a second event (unlock, unplug, removed) pass their own list.
    readonly property var events: ({
        notifications: ["message-new-instant", "message"],
        alarm: ["alarm-clock-elapsed"],
        pomodoro: ["alarm-clock-elapsed"],
        session: ["desktop-login", "service-login"],
        lock: ["screen-locked", "service-logout"],
        volumeChange: ["audio-volume-change"],
        screenshot: ["screen-capture", "camera-shutter"],
        charging: ["power-plug"],
        battery: ["battery-low", "dialog-warning"],
        devices: ["device-added"]
    })

    readonly property real volume: (Config.options.sounds.volume ?? 100) / 100
    readonly property list<string> _extensions: ["oga", "ogg", "wav"]
    readonly property string _bundledDir: FileUtils.trimFileProtocol(Quickshell.shellPath("assets/sounds"))

    // Called by shell.qml, never by the settings app.
    function load() {
        root.live = true;
        root._maybePlayLoginSound();
    }

    function rescan() {
        root.indexReady = false;
        themeScanProc.running = true;
        fileScanProc.running = true;
    }

    Component.onCompleted: rescan()

    /**
     * Resolve event names to a playable file url.
     * `events` is a name or a list of names ordered by preference: each name is
     * tried across the whole theme chain (selected theme, its Inherits,
     * freedesktop) before the next, so the event's meaning wins over the theme.
     * An absolute path is taken as is: notifications may name their own file.
     *
     * Lists that cross the QML boundary (Repeater models, list properties)
     * arrive as QVariantList sequences where Array.isArray is false, so
     * normalize by shape instead.
     */
    function resolve(events, themeId) {
        const names = typeof events === "string" ? [events] : Array.from(events);
        const chain = root._themeChain(themeId ?? Config.options.sounds.theme);
        for (const name of names) {
            if (name.startsWith("/")) return "file://" + name;
            for (const dir of chain) {
                const url = root._fileUrl(dir, name);
                if (url !== "") return url;
            }
        }
        return "";
    }

    // What a category plays right now: the user's own file, else the theme's.
    function urlFor(category, themeId) {
        return root._customUrl(category) || root.resolve(root.events[category], themeId);
    }

    // The theme a url was found in, for the settings page to say where a sound comes from.
    function themeOf(url) {
        return root.themes.find(t => url.startsWith(`file://${t.dir}/`)) ?? null;
    }

    function _fileUrl(dir, name) {
        for (const ext of root._extensions) {
            const path = `${dir}/stereo/${name}.${ext}`;
            if (root._soundFiles[path]) return "file://" + path;
        }
        return "";
    }

    function _themeChain(themeId) {
        const dirs = [];
        const visited = {};
        const queue = [themeId];
        while (queue.length > 0) {
            const id = queue.shift();
            if (!id || visited[id]) continue;
            visited[id] = true;
            const theme = root.themes.find(t => t.id === id);
            dirs.push(theme?.dir ?? `/usr/share/sounds/${id}`);
            if (theme?.inherits) queue.push(...theme.inherits.split(",").map(s => s.trim()));
        }
        if (!visited["freedesktop"]) dirs.push("/usr/share/sounds/freedesktop");
        return dirs;
    }

    function _customUrl(category) {
        const custom = Config.options.sounds.custom[category] ?? "";
        if (custom === "") return "";
        return custom.startsWith("file://") ? custom : "file://" + custom;
    }

    function playEvent(category, events = root.events[category]) {
        if (!root.live) return;
        if (!Config.options.sounds.enable) return;
        if (!Config.options.sounds[category]) return;

        const now = Date.now();
        if (now - root._initTime < (root._startupGraceMs[category] ?? 0)) return;
        const minInterval = root._minIntervalMs[category] ?? 0;
        if (minInterval > 0 && now - (root._lastPlayed[category] ?? 0) < minInterval) return;

        const url = root._customUrl(category) || root.resolve(events);
        if (url === "") return;
        root._lastPlayed[category] = now;
        // Volume blips restart a dedicated player: rapid changes cut the
        // previous tick short instead of stacking overlapping ones.
        root._playUrl(url, category === "volumeChange" ? "blip" : "");
    }

    property int _poolIndex: 0
    function _playUrl(url, dedicatedPlayerName) {
        const players = root._ensurePlayers();
        let player = dedicatedPlayerName === "blip" ? players.blipPlayer : null;
        if (!player) {
            player = players.pool[root._poolIndex];
            root._poolIndex = (root._poolIndex + 1) % players.pool.length;
        }
        player.stop();
        player.source = url;
        player.play();
    }

    // The settings page's play buttons share the blip player, so a second press
    // cuts the first sound off rather than playing over it. `previewing` names
    // what is playing and `previewProgress` how far along it is.
    property string previewing: ""
    property string previewFailed: ""
    readonly property real previewProgress: root.previewing !== "" && playersLoader.item
        ? playersLoader.item.blipPlayer.position / Math.max(1, playersLoader.item.blipPlayer.duration) : 0

    function preview(key, url) {
        const player = root._ensurePlayers().blipPlayer;
        player.stop();
        root.previewing = "";
        if (!url) return;
        player.source = url;
        player.play();
        root.previewing = key;
        root.previewFailed = "";
    }

    function stopPreview() {
        root.preview("", "");
    }

    // Continuous ring for alarms; bypasses the master switch on purpose:
    // disabling UI blips shouldn't silence a wake-up alarm.
    // fadeSeconds > 0 ramps the volume from silent for a gentle wake.
    function startLoop(category, events, fadeSeconds) {
        const url = root._customUrl(category) || root.resolve(events);
        if (url === "") return;
        const players = root._ensurePlayers();
        players.loopFadeAnim.stop();
        players.loopPlayer.stop();
        players.loopPlayer.volumeScale = 1;
        if (fadeSeconds > 0) {
            players.loopPlayer.volumeScale = 0;
            players.loopFadeAnim.duration = fadeSeconds * 1000;
            players.loopFadeAnim.start();
        }
        players.loopPlayer.source = url;
        players.loopPlayer.play();
    }

    function stopLoop() {
        // Nothing can be looping if the pool was never built.
        if (!playersLoader.item) return;
        playersLoader.item.loopFadeAnim.stop();
        playersLoader.item.loopPlayer.stop();
    }

    // Instantiating MediaPlayer/MediaDevices links QtMultimedia's backend — ffmpeg, VA-API and
    // libpulse — and starts an audio thread, none of which is needed until a sound actually
    // plays. The pool is therefore built on first playback and then kept for the rest of the
    // session, exactly as if it had been created at startup.
    component EventPlayer: MediaPlayer {
        id: eventPlayer

        property real volumeScale: 1
        required property var outputDevice

        audioOutput: AudioOutput {
            // Explicitly follow the system default so event sounds move with
            // output switches instead of sticking to the device at creation.
            device: eventPlayer.outputDevice
            volume: root.volume * eventPlayer.volumeScale
        }
    }

    component SoundPlayers: Item {
        readonly property list<MediaPlayer> pool: [player0, player1, player2]
        readonly property MediaPlayer blipPlayer: blip
        readonly property MediaPlayer loopPlayer: loop
        readonly property NumberAnimation loopFadeAnim: loopFade

        MediaDevices {
            id: mediaDevices
        }

        EventPlayer { id: player0; outputDevice: mediaDevices.defaultAudioOutput }
        EventPlayer { id: player1; outputDevice: mediaDevices.defaultAudioOutput }
        EventPlayer { id: player2; outputDevice: mediaDevices.defaultAudioOutput }

        EventPlayer {
            id: blip
            outputDevice: mediaDevices.defaultAudioOutput
            onPlaybackStateChanged: if (playbackState === MediaPlayer.StoppedState) root.previewing = ""
            onErrorOccurred: {
                root.previewFailed = root.previewing;
                root.previewing = "";
            }
        }

        EventPlayer {
            id: loop
            outputDevice: mediaDevices.defaultAudioOutput
            loops: MediaPlayer.Infinite
        }

        NumberAnimation {
            id: loopFade
            target: loop
            property: "volumeScale"
            from: 0
            to: 1
            easing.type: Easing.InQuad
        }
    }

    Loader {
        id: playersLoader
        active: false
        sourceComponent: SoundPlayers {}
    }

    function _ensurePlayers() {
        playersLoader.active = true;
        return playersLoader.item;
    }

    // Screen lock/unlock. No mainstream theme ships screen-locked/unlocked
    // sounds, so the service login/logout pair acts as the audible fallback.
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            root.playEvent("lock", GlobalStates.screenLocked
                ? ["screen-locked", "service-logout"]
                : ["screen-unlocked", "service-login"]);
        }
    }

    // USB plug and unplug. udev sends one usb_device event per device, a hub's
    // ports included; the devices rate limit folds that burst into one sound.
    // ponytail: internal devices that re-enumerate on resume chime too; filter on
    // sysfs `removable` if that turns out to happen on real hardware.
    Process {
        running: root.live && Config.options.sounds.enable && Config.options.sounds.devices
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=usb/usb_device"]
        stdout: SplitParser {
            onRead: line => {
                const action = line.match(/^UDEV\s+\[[\d.]+\]\s+(add|remove)\s/)?.[1];
                if (action) root.playEvent("devices", action === "add" ? "device-added" : "device-removed");
            }
        }
    }

    // Login sound, once per Hyprland session: the marker lives in the session's
    // runtime dir, so a shell restart or a live reload finds it and stays quiet.
    property bool _loginChecked: false
    function _maybePlayLoginSound() {
        if (!root.live || root._loginChecked || !root.indexReady || !Config.ready) return;
        root._loginChecked = true;
        loginMarker.running = true;
    }

    Process {
        id: loginMarker
        // noclobber: creating it fails if it exists, so only the first shell gets 0.
        command: ["sh", "-c", 'exec 2>/dev/null; set -C; : > "${XDG_RUNTIME_DIR:-/tmp}/ii-login-sound-$HYPRLAND_INSTANCE_SIGNATURE"']
        onExited: exitCode => {
            if (exitCode === 0) root.playEvent("session");
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            root._maybePlayLoginSound();
        }
    }

    IpcHandler {
        target: "sounds"

        // For what the shell does not see happen: the Print key's grim runs in Hyprland.
        function play(category: string): void {
            root.playEvent(category);
        }
    }

    // ── Theme discovery ───────────────────────────────────────────────────
    Process {
        id: themeScanProc
        command: ["bash", "-c", `
            for dir in /usr/share/sounds/* "$HOME/.local/share/sounds"/* "$0"/*; do
                [ -f "$dir/index.theme" ] || continue
                grep -q '^Hidden=true' "$dir/index.theme" && continue
                jq -n --arg id "$(basename "$dir")" --arg dir "$dir" \
                    --arg name "$(sed -n 's/^Name=//p' "$dir/index.theme" | head -1)" \
                    --arg comment "$(sed -n 's/^Comment=//p' "$dir/index.theme" | head -1)" \
                    --arg inherits "$(sed -n 's/^Inherits=//p' "$dir/index.theme" | head -1)" \
                    --arg example "$(sed -n 's/^Example=//p' "$dir/index.theme" | head -1)" \
                    '{id: $id, dir: $dir, name: (if $name == "" then $id else $name end), comment: $comment, inherits: $inherits, example: $example}'
            done | jq -s 'sort_by(.name)'
        `, root._bundledDir]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    // The freedesktop index.theme just says "Name=Default"; label
                    // it like KDE does so users recognize it as the fallback theme.
                    root.themes = JSON.parse(text).map(t => t.id === "freedesktop" ? Object.assign({}, t, {
                        name: "FreeDesktop",
                        comment: Translation.tr("Fallback sound theme from freedesktop.org")
                    }) : t);
                } catch (e) {
                    console.warn("[SoundService] Failed to parse theme list:", e);
                }
            }
        }
    }

    Process {
        id: fileScanProc
        command: ["bash", "-c", `find -L /usr/share/sounds "$HOME/.local/share/sounds" "$0" -maxdepth 3 -type f \\( -name '*.oga' -o -name '*.ogg' -o -name '*.wav' \\) 2>/dev/null`, root._bundledDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const files = {};
                for (const line of text.split("\n")) {
                    if (line !== "") files[line] = true;
                }
                root._soundFiles = files;
                root.indexReady = true;
                root._maybePlayLoginSound();
            }
        }
    }
}
