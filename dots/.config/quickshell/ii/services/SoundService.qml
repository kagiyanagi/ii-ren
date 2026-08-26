pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

/**
 * XDG sound theme event player (freedesktop sound theme & naming specs, simplified).
 *
 * Discovers themes from /usr/share/sounds and ~/.local/share/sounds, resolves
 * event names against the configured theme with fallback to inherited themes
 * and freedesktop, and plays them in-process through Qt Multimedia.
 *
 * Playback entry points:
 *  - playEvent(category, events): gated by Config.options.sounds.enable and
 *    Config.options.sounds[category], rate-limited per category, honors
 *    per-event custom file overrides (Config.options.sounds.custom).
 *  - startLoop/stopLoop: continuous ring (alarms); ignores the master switch,
 *    the caller checks its own category toggle. Supports gentle fade-in.
 */
Singleton {
    id: root

    // [{id, dir, name, comment, inherits}]
    property list<var> themes: []
    property bool indexReady: false
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
    // report already-connected devices as "new", lock-on-startup engages late.
    readonly property var _startupGraceMs: ({
        battery: 5000,
        devices: 10000,
        lock: 10000
    })

    readonly property real volume: (Config.options.sounds.volume ?? 100) / 100
    readonly property list<string> _extensions: ["oga", "ogg", "wav"]

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
     *
     * Lists that cross the QML boundary (Repeater models, list properties)
     * arrive as QVariantList sequences where Array.isArray is false, so
     * normalize by shape instead.
     */
    function resolve(events) {
        const names = typeof events === "string" ? [events] : Array.from(events);
        const chain = root._themeChain(Config.options.sounds.theme);
        for (const name of names) {
            for (const dir of chain) {
                const url = root._fileUrl(dir, name);
                if (url !== "") return url;
            }
        }
        return "";
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

    function playEvent(category, events) {
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

        EventPlayer { id: blip; outputDevice: mediaDevices.defaultAudioOutput }

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

    // Login sound: PersistentProperties survives QML live-reloads within the
    // same process, so this only fires once per shell process (= per session).
    PersistentProperties {
        id: session
        reloadableId: "soundServiceSession"
        property bool loginSoundPlayed: false
    }

    function _maybePlayLoginSound() {
        if (session.loginSoundPlayed || !root.indexReady || !Config.ready) return;
        session.loginSoundPlayed = true;
        root.playEvent("session", ["desktop-login", "service-login"]);
    }

    Connections {
        target: Config
        function onReadyChanged() {
            root._maybePlayLoginSound();
        }
    }

    // ── Theme discovery ───────────────────────────────────────────────────
    Process {
        id: themeScanProc
        command: ["bash", "-c", `
            for dir in /usr/share/sounds/* "$HOME/.local/share/sounds"/*; do
                [ -f "$dir/index.theme" ] || continue
                grep -q '^Hidden=true' "$dir/index.theme" && continue
                jq -n --arg id "$(basename "$dir")" --arg dir "$dir" \
                    --arg name "$(sed -n 's/^Name=//p' "$dir/index.theme" | head -1)" \
                    --arg comment "$(sed -n 's/^Comment=//p' "$dir/index.theme" | head -1)" \
                    --arg inherits "$(sed -n 's/^Inherits=//p' "$dir/index.theme" | head -1)" \
                    '{id: $id, dir: $dir, name: (if $name == "" then $id else $name end), comment: $comment, inherits: $inherits}'
            done | jq -s 'sort_by(.name)'
        `]
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
        command: ["bash", "-c", `find -L /usr/share/sounds "$HOME/.local/share/sounds" -maxdepth 3 -type f \\( -name '*.oga' -o -name '*.ogg' -o -name '*.wav' \\) 2>/dev/null`]
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
