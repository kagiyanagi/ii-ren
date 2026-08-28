// node services/combineStream.test.js
const assert = require("assert");
const Combine = require("./combineStream.js");

assert.deepStrictEqual(Combine.toggleMember(["a"], "b"), ["a", "b"]);
assert.deepStrictEqual(Combine.toggleMember(["a", "b"], "a"), ["b"]);
assert.strictEqual(Combine.toggleMember(["a"], "a"), null); // the last member stays

const cmd = Combine.command(true, ["alsa_output.pci-0000_00_1f.3.analog-stereo", "bluez_output.2C:DE:DF:0C:16:C3"], "Multiple devices");
assert.deepStrictEqual(cmd.slice(0, 4), ["pw-cli", "-m", "load-module", "libpipewire-module-combine-stream"]);
assert.match(cmd[4], /combine\.mode = sink/);
assert.match(cmd[4], /node\.name = ii_combine_sink/);
assert.match(cmd[4], /matches = \[ \{ node\.name = "alsa_output\.pci-0000_00_1f\.3\.analog-stereo" \} \{ node\.name = "bluez_output\.2C:DE:DF:0C:16:C3" \} \]/);
assert.match(Combine.command(false, ["a"], "Multiple microphones")[4], /combine\.mode = source/);
assert.strictEqual(Combine.nodeName(false), "ii_combine_source");

console.log("ok");
