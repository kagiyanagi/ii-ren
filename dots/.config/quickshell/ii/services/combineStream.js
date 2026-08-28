// A virtual audio device that plays to (or records from) several real devices
// at once, hosted by pipewire's combine-stream module. What the shell stores is
// the member list: none means one plain default device, one means multi-device
// mode with a single member, two or more means a combined device.

const NODE_PREFIX = "ii_combine";

function nodeName(isSink) {
    return `${NODE_PREFIX}_${isSink ? "sink" : "source"}`;
}

// Add or drop a member. Null means the click was refused: the last member has
// to stay, or there is nothing left to be the default device.
function toggleMember(names, name) {
    if (!names.includes(name))
        return names.concat([name]);
    const left = names.filter(member => member !== name);
    return left.length === 0 ? null : left;
}

// pw-cli -m stays alive hosting the module, so killing it removes the virtual
// device again. The rules match members by name, which also means a member
// that disconnects rejoins by itself when it comes back.
function command(isSink, names, description) {
    const matches = names.map(name => `{ node.name = "${name}" }`).join(" ");
    const args = `{
    combine.mode = ${isSink ? "sink" : "source"}
    node.name = ${nodeName(isSink)}
    node.description = "${description}"
    combine.props = { audio.position = [ FL FR ] }
    stream.rules = [ { matches = [ ${matches} ] actions = { create-stream = { } } } ]
}`;
    return ["pw-cli", "-m", "load-module", "libpipewire-module-combine-stream", args];
}

if (typeof module !== "undefined")
    module.exports = { NODE_PREFIX: NODE_PREFIX, nodeName: nodeName, toggleMember: toggleMember, command: command };
