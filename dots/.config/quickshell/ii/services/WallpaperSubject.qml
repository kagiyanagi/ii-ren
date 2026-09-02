pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Subject depth: the wallpaper's foreground subject, cut out so the shell can
 * draw it back on top of the desktop widgets.
 *
 * This is the Linux answer to the ML Kit Subject Segmentation call that Iconify
 * and the depth-wallpaper ROMs make. Same shape - hand it the wallpaper, get a
 * same-sized RGBA image holding only the subject - but the model runs out of
 * process in the venv, because a 176MB ONNX net has no business inside the
 * compositor's shell.
 *
 * One cutout per wallpaper, cached on disk. The script reuses a finished one,
 * so asking for the same wallpaper twice costs a process spawn and nothing
 * else; only a genuinely new wallpaper pays the couple of seconds of CPU.
 */
Singleton {
    id: root

    // The cutout is one shared resource, so it is worth having the moment
    // either desktop or lock screen wants it.
    readonly property bool enabled: Config.ready
        && (Config.options.background.depth.desktop.enable
            || (Config.options.background.depth.lock.sync
                ? Config.options.background.depth.desktop.enable
                : Config.options.background.depth.lock.enable))

    readonly property bool wallpaperIsVideo: Wallpapers.isVideoFile((Config.options.background.wallpaperPath ?? "").toLowerCase())
    readonly property bool wallpaperUsable: (Config.options.background.wallpaperPath ?? "").length > 0
    readonly property string wallpaperFile: FileUtils.trimFileProtocol(Config.options.background.wallpaperPath ?? "")

    // The user cancelled this one's bake. It stays uncut until they ask again.
    readonly property bool declined: (Config.options.background.depth.declined ?? []).includes(root.wallpaperFile)

    property string cutoutPath: ""
    property real coverage: 0
    property bool working: false
    property string error: ""

    // Video only, and only while a bake is in flight. A wallpaper that really
    // moves is recut every frame, which is half an hour of CPU - long enough
    // that saying nothing reads as a hang rather than as work.
    property int progressFrames: 0
    property int progressTotal: 0
    property int etaSeconds: 0
    // The cutout the run in flight is making. A result for anything else is
    // from a wallpaper we have already moved on from.
    property string pendingOutput: ""

    // A subject that is the whole frame, or none of it, has no depth in it. The
    // ROMs quietly fall back to a flat wallpaper in both cases and so do we.
    readonly property bool hasSubject: root.cutoutPath.length > 0
        && root.coverage > 0.01 && root.coverage < 0.92

    readonly property bool ready: root.enabled && root.hasSubject

    // What the background draws for a still wallpaper: an RGBA cutout.
    readonly property string source: (root.ready && !root.wallpaperIsVideo) ? `file://${root.cutoutPath}` : ""

    // What it draws for a video: the packed file, every frame stacked over its
    // own matte. The shell plays this instead of the original, which is also
    // what makes the matte impossible to desync - see the shader.
    readonly property string packedVideo: (root.ready && root.wallpaperIsVideo) ? `file://${root.cutoutPath}` : ""

    function cutoutPathFor(wallpaper: string): string {
        // Video stays video: the packed frames have to survive as frames.
        const suffix = root.wallpaperIsVideo ? "mp4" : "png";
        return `${Directories.wallpaperSubjects}/${Qt.md5(wallpaper)}.${suffix}`;
    }

    // No force flag: the model is deterministic, so re-cutting an image the
    // cache already holds returns the same pixels. The one thing worth retrying
    // is a run that failed outright - usually the first one, which has a 176MB
    // model to fetch - and that leaves no cache entry to get in the way.
    function generate(force = false): void {
        if (!root.enabled || !root.wallpaperUsable)
            return;
        if (root.declined && !force)
            return;

        const wallpaper = FileUtils.trimFileProtocol(Config.options.background.wallpaperPath);
        const target = root.cutoutPathFor(wallpaper);

        // Already making exactly this one - let it finish, unless the user has
        // explicitly asked for it again.
        if (proc.running && root.pendingOutput === target && !force)
            return;
        // The wallpaper changed under a bake in flight. Its result would arrive
        // claiming to be the subject of a wallpaper that is no longer set, and
        // meanwhile it is minutes of every core spent on an image nobody is
        // looking at. reapStrayBakes below stops it, once the target has moved.
        proc.running = false;

        root.pendingOutput = target;
        // Stop drawing the old cutout before starting the run that replaces
        // it. It also means the path is never published before the file behind
        // it is complete, which matters more than it sounds: point an Image at
        // a file that is not there yet and Qt caches the failure for good.
        root.cutoutPath = "";
        root.coverage = 0;
        root.working = true;
        root.error = "";
        root.progressFrames = 0;
        root.progressTotal = 0;
        root.etaSeconds = 0;
        proc.command = [
            // Lowest priority: this is a background bake, and on a video it
            // saturates every core for minutes. The desktop it is decorating
            // should not stutter for it.
            "nice", "-n", "19",
            Directories.subjectCutoutScriptPath,
            "--image", wallpaper,
            "--output", target,
            "--json"
        ].concat(force ? ["--force"] : []);
        proc.running = true;
        root.reapStrayBakes();
    }

    // Stop whatever is being made for this wallpaper.
    //
    // Every process still working on it, not just the one we spawned: the bake
    // is deliberately left a grandchild so a shell reload cannot kill it, which
    // also puts it out of reach of stopping our own child. And there is usually
    // more than one - a second window asking for the same cutout is parked on
    // the lock, so killing only the worker just promotes the waiter into
    // becoming the new one. The output path is in every one of their command
    // lines and in nothing else.
    // Stops every bake rather than only the one this window happens to be
    // tracking, which after a reload may be none of them.
    function stopWork(): void {
        Quickshell.execDetached(["pkill", "-f", "images/subject_cutout\\.py"]);
        root.pendingOutput = "";
        root.working = false;
        root.progressTotal = 0;
    }

    // Cancel is a decision about this wallpaper, so it is remembered. Switching
    // the whole feature off is not - that only calls stopWork, or turning depth
    // back on would find every wallpaper you had ever waited on now refusing to
    // cut itself.
    function cancel(): void {
        root.stopWork();
        if (root.wallpaperFile.length === 0 || root.declined)
            return;
        const declined = (Config.options.background.depth.declined ?? []).slice();
        declined.push(root.wallpaperFile);
        Config.options.background.depth.declined = declined;
    }

    // The one way back. Clears the refusal and recuts even if a finished cutout
    // is already sitting in the cache, which is the point: the button exists to
    // redo one you are not happy with.
    function rebake(): void {
        const declined = (Config.options.background.depth.declined ?? [])
            .filter(path => path !== root.wallpaperFile);
        Config.options.background.depth.declined = declined;
        root.generate(true);
    }

    // Kill every bake that is not for the cutout we want now.
    //
    // A bake is left a grandchild on purpose, so that a shell reload cannot
    // take minutes of work with it - but that also means a reloaded shell no
    // longer has a handle on it. Change wallpaper a few times across a couple
    // of reloads and there are several bakes going at once, each saturating
    // the machine for an image nobody is looking at. Nothing but those
    // processes carries the output path in its command line, so the set to
    // spare is exactly the set that matches the one we are waiting for.
    function reapStrayBakes(): void {
        if (root.pendingOutput.length === 0)
            return;
        Quickshell.execDetached(["bash", "-c",
            "comm -23 <(pgrep -f 'images/subject_cutout\\.py' | sort) "
            + `<(pgrep -f '${root.pendingOutput}' | sort) | xargs -r kill`]);
    }

    // Both paths matter: the flag flipping while the shell runs, and the shell
    // starting with it already on. Nothing references this singleton until the
    // background draws, by which point Config is usually ready and the change
    // handler has already missed its moment.
    // Turning it off stops the work too. A video bake is minutes of every core,
    // and finishing one for a feature that has just been switched off is heat
    // and battery spent on nothing anyone asked for.
    onEnabledChanged: root.enabled ? root.generate() : root.stopWork()
    // Reselecting a declined wallpaper must not quietly restart it, and neither
    // must a shell restart - generate() checks `declined` on every path in.
    onDeclinedChanged: if (root.declined) root.stopWork()
    Component.onCompleted: root.generate()

    // ── mpvpaper handover ────────────────────────────────────────────────────
    // A video wallpaper is normally drawn by mpvpaper, on its own layer below
    // the shell. Subject depth needs the shell to draw it instead, because the
    // matte has to come out of the same decoder as the frame it belongs to. So
    // while depth owns a video, mpvpaper stands down; the moment it does not,
    // switchwall.sh's own restore script puts it back exactly as it was.
    onPackedVideoChanged: {
        if (root.packedVideo.length > 0) {
            Quickshell.execDetached(["pkill", "-f", "-9", "mpvpaper"]);
        } else if (root.wallpaperIsVideo) {
            Quickshell.execDetached(["bash", Directories.videoWallpaperRestoreScript]);
        }
    }

    Connections {
        target: Config.options.background
        function onWallpaperPathChanged() {
            // The old wallpaper's subject must stop drawing immediately, or it
            // hangs over the new one until the new cutout lands.
            root.cutoutPath = "";
            root.coverage = 0;
            root.generate();
        }
    }

    // Whoever is actually doing the work publishes here; every window watching
    // this wallpaper reads the same numbers, including the ones queued behind.
    FileView {
        id: statusFile
        path: root.pendingOutput.length > 0 ? `${root.pendingOutput}.status` : ""
        // Absent until a bake starts writing one, and absent again for every
        // cutout already cached. That is the normal case, not an error.
        printErrors: false
        watchChanges: true
        onFileChanged: this.reload()
        onLoaded: {
            let status;
            try {
                status = JSON.parse(statusFile.text());
            } catch (e) {
                return;
            }
            if (status.state === "working") {
                root.progressFrames = status.frames ?? 0;
                root.progressTotal = status.total ?? 0;
                root.etaSeconds = status.eta ?? 0;
                return;
            }

            // The result arrives here rather than on our own stdout, so a
            // window that only queued behind someone else's bake still gets it.
            root.progressTotal = 0;
            root.working = false;
            if (status.state === "error") {
                root.error = status.error ?? Translation.tr("Segmentation failed");
                return;
            }
            if (status.output !== root.pendingOutput)
                return; // a straggler from the previous wallpaper
            root.cutoutPath = status.output;
            root.coverage = status.coverage;
        }
    }

    Process {
        id: proc

        // Line at a time rather than one collected blob: a video bake reports
        // progress as it goes, and the result is simply the last line.
        stdout: SplitParser {
            onRead: line => {
                if (line.length === 0)
                    return;
                let message;
                try {
                    message = JSON.parse(line);
                } catch (e) {
                    root.error = Translation.tr("Could not read the segmenter's reply");
                    return;
                }
                // Progress arrives through the status file instead, so that a
                // window queued behind someone else's bake still sees it.
                if (message.progress)
                    return;
                if (message.output !== undefined && message.output !== root.pendingOutput)
                    return; // a straggler from the previous wallpaper
                root.working = false;
                if (!message.ok) {
                    root.error = message.error ?? Translation.tr("Segmentation failed");
                    return;
                }
                root.cutoutPath = message.output;
                root.coverage = message.coverage;
            }
        }
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => {
            root.working = false;
            if (exitCode !== 0 && root.error.length === 0)
                root.error = stderr.text.trim().split("\n").pop() || Translation.tr("Segmentation failed");
        }
    }
}
