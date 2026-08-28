pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "combineStream.js" as Combine

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    // Misc props
    property bool ready: Pipewire.defaultAudioSink?.ready ?? false
    property PwNode sink: Pipewire.defaultAudioSink
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00 // People keep joking about setting volume to 5172% so...
    property string audioTheme: Config.options.sounds.theme
    property real value: sink?.audio.volume ?? 0
    
    function friendlyDeviceName(node) {
        return (node.nickname || node.description || Translation.tr("Unknown"));
    }
    function appNodeDisplayName(node) {
        return (node.properties["application.name"] || node.description || node.name)
    }

    // Lists
    function correctType(node, isSink) {
        // Our own combined device and its per-member streams are plumbing, not
        // something to pick or show a slider for.
        return (node.isSink === isSink) && node.audio && !root.isCombineNode(node)
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
            return root.correctType(node, isSink) && node.isStream
        })
    }
    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream
        })
    }
    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)

    // Signals
    signal sinkProtectionTriggered(string reason);

    // Controls
    function toggleMute() {
        Audio.sink.audio.muted = !Audio.sink.audio.muted
    }

    function toggleMicMute() {
        Audio.source.audio.muted = !Audio.source.audio.muted
    }

    function incrementVolume() {
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02 || 0.2;
        Audio.sink.audio.volume = Math.min(1, Audio.sink.audio.volume + step);
    }
    
    function decrementVolume() {
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02 || 0.2;
        Audio.sink.audio.volume -= step;
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // Playing to (or recording from) several devices at once. The member list is
    // the whole state: none is a plain default device, one is multi-device mode
    // with a single member, two or more get a combined virtual device.
    readonly property list<string> combinedSinkNames: Config.options.audio.combinedSinks
    readonly property list<string> combinedSourceNames: Config.options.audio.combinedSources
    readonly property PwNode combineSink: Pipewire.nodes.values.find(node => node.name === Combine.nodeName(true)) ?? null
    readonly property PwNode combineSource: Pipewire.nodes.values.find(node => node.name === Combine.nodeName(false)) ?? null

    function isCombineNode(node) {
        return (node?.name ?? "").includes(Combine.NODE_PREFIX);
    }
    function combinedNames(isSink) {
        return isSink ? root.combinedSinkNames : root.combinedSourceNames;
    }
    function multiDeviceEnabled(isSink) {
        return root.combinedNames(isSink).length > 0;
    }
    function isActiveDevice(node, isSink) {
        if (root.multiDeviceEnabled(isSink)) return root.combinedNames(isSink).includes(node.name);
        return node.id === (isSink ? Pipewire.defaultAudioSink?.id : Pipewire.defaultAudioSource?.id);
    }
    function deviceByName(isSink, name) {
        return root.devices(isSink).find(device => device.name === name) ?? null;
    }
    function setDefaultDevice(node, isSink) {
        if (!node) return; // a null default is a metadata write quickshell chokes on
        if (isSink) root.setDefaultSink(node);
        else root.setDefaultSource(node);
    }
    // One master for the lot: members play at unity and the combined device carries the
    // level, so no device has to be cranked up by hand before switching this on. A device
    // dropping out of the set keeps the level it was last playing at.
    function combineProcess(isSink) {
        return isSink ? combineSinkProcess : combineSourceProcess;
    }
    function setNodeVolume(node, volume) {
        // wpctl rather than node.audio, which is only writable for a tracked node
        if (node) Quickshell.execDetached(["wpctl", "set-volume", `${node.id}`, `${Math.max(0, Math.min(1, volume))}`]);
    }
    function levelToCarry(isSink) {
        const current = isSink ? root.sink : root.source;
        return root.isCombineNode(current) ? (current.audio?.volume ?? 1) : root.combineProcess(isSink).seedVolume;
    }

    // ponytail: quickshell 0.2.1 (PwDefaultTracker) drops its "node destroyed" watch on a
    // default change and then segfaults on the stale pointer, so the default has to move
    // onto a real device while the combined one is still alive. Drop the dance once fixed.
    function setCombinedNames(isSink, names) {
        const previous = root.combinedNames(isSink);
        const level = root.levelToCarry(isSink);
        if (previous.length < 2 && names.length > 1) // the level in use becomes the master
            root.combineProcess(isSink).seedVolume = (isSink ? root.sink : root.source)?.audio?.volume ?? 1;
        const leaving = names.length < 2 ? previous : previous.filter(name => !names.includes(name));
        leaving.forEach(name => root.setNodeVolume(root.deviceByName(isSink, name), level));
        if (names.length < 2) {
            const keep = root.deviceByName(isSink, names[0] ?? root.combinedNames(isSink)[0] ?? "");
            if (keep) root.setDefaultDevice(keep, isSink);
        }
        if (isSink) Config.options.audio.combinedSinks = names;
        else Config.options.audio.combinedSources = names;
    }

    // A click picks one device, or adds/drops a member while multi-device mode is on.
    function pickDevice(node, isSink) {
        if (!node) return;
        if (!root.multiDeviceEnabled(isSink)) {
            root.setDefaultDevice(node, isSink);
            return;
        }
        const names = Combine.toggleMember(root.combinedNames(isSink), node.name);
        if (names) root.setCombinedNames(isSink, names);
    }

    function setMultiDeviceEnabled(isSink, enabled) {
        if (enabled) {
            const current = isSink ? root.sink : root.source;
            // Seed with the device in use, never with a leftover combined one
            root.setCombinedNames(isSink, (current && !root.isCombineNode(current)) ? [current.name] : []);
            return;
        }
        root.setCombinedNames(isSink, []);
    }

    onCombinedSinkNamesChanged: combineSinkProcess.sync()
    onCombinedSourceNamesChanged: combineSourceProcess.sync()
    onCombineSinkChanged: if (root.combineSink) Pipewire.preferredDefaultAudioSink = root.combineSink;
    onCombineSourceChanged: if (root.combineSource) Pipewire.preferredDefaultAudioSource = root.combineSource;

    // Internals
    component CombineStream: Process {
        id: stream
        required property bool isSink
        property list<string> loadedNames: [] // what the running module was started with
        property real seedVolume: 1 // the master level to hand the combined device
        property bool restarting: false
        readonly property PwNode node: stream.isSink ? root.combineSink : root.combineSource

        // Held off a moment: a fresh node drops a volume set that lands too early, and a
        // member raised while it is still the default gets reverted by the protection.
        property Timer levelTimer: Timer {
            interval: 300
            onTriggered: {
                root.setNodeVolume(stream.node, stream.seedVolume);
                root.combinedNames(stream.isSink).forEach(name => root.setNodeVolume(root.deviceByName(stream.isSink, name), 1));
            }
        }

        onNodeChanged: if (stream.node) stream.levelTimer.restart();

        function sync() {
            const names = root.combinedNames(isSink);
            if (running && names.join() === loadedNames.join()) return; // already as asked
            if (running) {
                // Stopping while the default still points at the combined node crashes
                // quickshell, so hold until onSinkChanged brings us back here.
                if (names.length < 2 && root.isCombineNode(isSink ? root.sink : root.source)
                    && root.devices(isSink).length > 0) return;
                restarting = names.length > 1; // a new member list needs a fresh load
                if (restarting) seedVolume = root.levelToCarry(isSink); // keep the level across the reload
                running = false;
                return;
            }
            if (names.length < 2) return;
            loadedNames = names;
            command = Combine.command(isSink, names,
                isSink ? Translation.tr("Multiple devices") : Translation.tr("Multiple microphones"));
            running = true;
        }

        onExited: {
            loadedNames = [];
            if (!restarting) return;
            restarting = false;
            sync();
        }
    }
    CombineStream {
        id: combineSinkProcess
        isSink: true
    }
    CombineStream {
        id: combineSourceProcess
        isSink: false
    }
    PwObjectTracker {
        objects: [sink, source]
    }

    onSinkChanged: {
        volumeProtection.lastReady = false; // another device, another volume
        combineSinkProcess.sync(); // the default may just have left the combined node
    }
    onSourceChanged: combineSourceProcess.sync()

    Connections { // Protection against sudden volume changes
        id: volumeProtection
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable) return;
            const newVolume = sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }

    function playSystemSound(soundName) {
        const ogaPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.oga`;
        const oggPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.ogg`;

        // Try playing .oga first
        let command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            ogaPath
        ];
        Quickshell.execDetached(command);

        // Also try playing .ogg (ffplay will just fail silently if file doesn't exist)
        command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            oggPath
        ];
        Quickshell.execDetached(command);
    }
}
