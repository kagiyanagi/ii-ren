// Self-check: node modules/ii/bar/test_visualizer.js
const src = require("fs").readFileSync(__dirname + "/Visualizer.qml", "utf8");
const CavaService = { visualizerPoints: [] };
const root = { barCount: 14, maxValue: 1000, active: true };
Object.defineProperty(root, "points", { set: v => CavaService.visualizerPoints = v });
eval("root.levelAt = function" + src.match(/function levelAt\(i\)[\s\S]*?\n    \}/)[0].slice("function levelAt".length));

const bars = () => Array.from({ length: root.barCount }, (_, i) => root.levelAt(i));
const check = (label, cond) => { console.assert(cond, label); if (!cond) process.exit(1); };

check("silent when no points", bars().every(v => v === 0));

root.points = new Array(50).fill(1000);
check("full scale", bars().every(v => v === 1));

root.active = false;
check("idle when nothing plays", bars().every(v => v === 0));
root.active = true;

root.points = new Array(50).fill(0).map((_, i) => i === 49 ? 5000 : 0); // clamp + last bucket reached
check("clamped to 1", root.levelAt(13) === 1);
check("only the loud bucket lights up", bars().slice(0, 13).every(v => v === 0));

root.points = [1000, 0, 0, 0, 0]; // fewer points than bars: every bar still gets a slice
check("no empty slices", bars().every(v => v >= 0 && v <= 1));
check("first bar tracks first point", root.levelAt(0) === 1);

console.log("ok");
