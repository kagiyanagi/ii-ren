// One screen shader for Comfort View, Reading Mode and Anti-flashbang together.
// Hyprland runs one decoration:screen_shader, so separate files meant each effect
// replaced the others and turning one off cleared them all. Pure, so
// screenShader.test.js runs it under node.
//
// effects: { comfort: null | { intensity }, reading: null | { intensity, paperTone },
//            antiFlashbang: bool }, intensities 0-100. "" when nothing is on.

function num(value) {
    return Math.max(0, Math.min(1, Number(value) || 0)).toFixed(3);
}

function source(effects) {
    const comfort = effects?.comfort ?? null;
    const reading = effects?.reading ?? null;
    const antiFlashbang = !!effects?.antiFlashbang;
    if (!comfort && !reading && !antiFlashbang)
        return "";

    const lines = [
        "#version 300 es",
        // Anti-flashbang averages 100 samples; mediump banding shows in its result.
        `precision ${antiFlashbang ? "highp" : "mediump"} float;`,
        "",
        "in vec2 v_texcoord;",
        "uniform sampler2D tex;",
        "layout(location = 0) out vec4 fragColor;",
        "",
        "const vec3 kLuminance = vec3(0.2126, 0.7152, 0.0722); // Rec. 709",
        "",
    ];
    if (antiFlashbang) {
        lines.push(
            "// Anti-flashbang: darken the whole screen by how bright it is on average,",
            "// sampled on a 10x10 grid - dense enough for small text, light enough to run.",
            "float screenBrightness() {",
            "    vec3 total = vec3(0.0);",
            "    for (float x = 0.05; x < 1.0; x += 0.1)",
            "        for (float y = 0.05; y < 1.0; y += 0.1)",
            "            total += texture(tex, vec2(x, y)).rgb;",
            "    return dot(total / 100.0, kLuminance);",
            "}",
            "",
        );
    }
    lines.push(
        "void main() {",
        "    vec4 pixColor = texture(tex, v_texcoord);",
        "    vec3 color = pixColor.rgb;",
        "    float lum = dot(color, kLuminance);",
    );
    if (reading) {
        // AOSP ColorDisplayService grayscale (GlobalSaturationTintController).
        lines.push(`    color = mix(color, vec3(lum), ${num(reading.intensity / 100)});`);
        if (reading.paperTone) {
            lines.push(
                "    // Paper tone: softens the blue end, as Android's reading mode does.",
                "    color = vec3(min(1.0, color.r * 1.06), min(1.0, color.g * 1.02), color.b * 0.88);",
            );
        }
    } else if (comfort) {
        // Comfort View: damp chroma, then shift warm.
        const warmth = comfort.intensity * 0.50 / 100;
        lines.push(
            `    color = mix(vec3(lum), color, ${num(1 - comfort.intensity * 0.85 / 100)});`,
            `    color *= vec3(${(1 + warmth * 0.20).toFixed(3)}, ${(1 + warmth * 0.05).toFixed(3)}, ${(1 - warmth * 0.75).toFixed(3)});`,
        );
    }
    if (comfort) {
        // Comfort View's glare cap applies under Reading Mode as well.
        lines.push(`    color = min(color, vec3(${num(1 - comfort.intensity * 0.15 / 100)}));`);
    }
    if (antiFlashbang)
        lines.push("    color = mix(color, vec3(0.0), clamp(screenBrightness() * 0.75, 0.001, 1.0));");
    lines.push("    fragColor = vec4(color, pixColor.a);", "}", "");
    return lines.join("\n");
}

// Lua for `hyprctl eval` that puts `path` on screen ("" turns the shader off).
// Anti-flashbang also turns damage tracking down to monitor-only, or the parts
// of the screen that did not change keep their old, differently darkened pixels;
// the value it replaced is kept in the compositor's Lua state and put back after.
// A reload starts a fresh Lua state and re-reads the config, which restores it too.
function lua(path, antiFlashbang) {
    const set = `hl.config({ decoration = { screen_shader = ${JSON.stringify(String(path))} } })`;
    if (antiFlashbang)
        return 'if ii_damage_tracking == nil then ii_damage_tracking = hl.get_config("debug.damage_tracking") end; '
            + `hl.config({ debug = { damage_tracking = 1 } }); ${set}`;
    return `${set}; if ii_damage_tracking ~= nil then hl.config({ debug = { damage_tracking = ii_damage_tracking } }); ii_damage_tracking = nil end`;
}

if (typeof module !== "undefined")
    module.exports = { source: source, lua: lua };
