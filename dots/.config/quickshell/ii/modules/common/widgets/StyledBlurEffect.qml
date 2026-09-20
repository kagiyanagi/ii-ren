import QtQuick
import QtQuick.Effects

// The wallpaper-backed blur of DESIGN.md 8: blur the source once and sample it,
// never stack blurs per panel. Every caller uses it as a `layer.effect`, which
// is what fills in `source` - it carries no default of its own.
MultiEffect {
    id: root

    anchors.fill: source
    saturation: 0.2
    blurEnabled: true
    // MultiEffect gains a blur level above 32, not above 64: measured, blurMax
    // 8/16/32 build 11 internal blur items and 64/100/128 all build 13. Cutting
    // 100 to 64 would therefore cost blur radius and save no pass at all; 32 is
    // the value that saves one, and AndroidMediaWidgetToggle already sets it
    // for its small tile. Anything larger is free next to it.
    blurMax: 100
    blur: 1
}
