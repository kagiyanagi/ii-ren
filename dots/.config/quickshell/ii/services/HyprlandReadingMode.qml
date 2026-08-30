pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.models.hyprland

Singleton {
    id: root

    readonly property string shaderPath: Quickshell.shellPath("services/hyprlandReadingModeShader/reading-mode.glsl")

    property bool manualEnable: Config.options?.light?.readingMode?.enable ?? false
    property bool automatic: Config.options?.light?.readingMode?.automatic ?? false
    property int intensity: Config.options?.light?.readingMode?.intensity ?? 100
    property bool paperTone: Config.options?.light?.readingMode?.paperTone ?? false

    readonly property bool effectiveActive: manualEnable || (automatic && Hyprsunset.shouldBeOn)
    readonly property bool active: confOpt.value == root.shaderPath

    function load() {
        if (root.effectiveActive) {
            root.applyShader();
        }
    }

    function applyShader() {
        const intensityNormalized = (root.intensity / 100.0).toFixed(3);
        const cvActive = HyprlandComfortView.effectiveActive;
        const cvCap = cvActive ? (1.0 - (HyprlandComfortView.intensity * 0.15 / 100.0)).toFixed(3) : "1.000";

        const glslContent = `#version 300 es
precision mediump float;

in vec2 v_texcoord;
uniform sampler2D tex;

layout(location = 0) out vec4 fragColor;

// Android AOSP ColorDisplayService - 1:1 Rec. 709 Grayscale Architecture
// LEVEL_COLOR_MATRIX_GRAYSCALE & GlobalSaturationTintController
// Luminance coefficients: Red 0.2126, Green 0.7152, Blue 0.0722
const vec3 kLuminanceWeights = vec3(0.2126, 0.7152, 0.0722);
const float u_intensity = ${intensityNormalized};
const bool u_paperTone = ${root.paperTone ? "true" : "false"};
const bool u_comfortViewCap = ${cvActive ? "true" : "false"};
const float u_highlightCap = ${cvCap};

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    float lum = dot(pixColor.rgb, kLuminanceWeights);

    // 1. AOSP GlobalSaturationTintController desaturation interpolation
    // (0.0 = full chromatic color, 1.0 = complete monochrome grayscale)
    vec3 result = mix(pixColor.rgb, vec3(lum), u_intensity);

    // 2. Android Paper Reading Mode tone (softens high-frequency blue spectral emission)
    if (u_paperTone) {
        result.r = min(1.0, result.r * 1.06);
        result.g = min(1.0, result.g * 1.02);
        result.b = result.b * 0.88;
    }

    // 3. Highlight softening if Comfort View is concurrently active
    if (u_comfortViewCap) {
        result = min(result, vec3(u_highlightCap));
    }

    fragColor = vec4(result, pixColor.a);
}`;

        let singleLineContent = glslContent.split("\n").join("\\n");
        Quickshell.execDetached(["bash", "-c", `echo -e "${singleLineContent}" > "${root.shaderPath}" && ${Directories.cliPath} hyprset key decoration:screen_shader "${root.shaderPath}" && hyprctl reload`]);
    }

    function enable() {
        root.manualEnable = true;
        if (Config.options?.light?.readingMode) {
            Config.options.light.readingMode.enable = true;
        }
        root.applyShader();
    }

    function disable() {
        root.manualEnable = false;
        if (Config.options?.light?.readingMode) {
            Config.options.light.readingMode.enable = false;
        }
        if (!root.automatic || !Hyprsunset.shouldBeOn) {
            if (HyprlandComfortView.effectiveActive) {
                HyprlandComfortView.applyShader();
            } else {
                Quickshell.execDetached(["bash", "-c", `${Directories.cliPath} hyprset reset decoration:screen_shader && hyprctl reload`]);
            }
        }
    }

    function toggleManual(checked) {
        if (checked === undefined) {
            checked = !root.manualEnable;
        }
        if (checked) {
            root.enable();
        } else {
            root.disable();
        }
    }

    function toggleAutomatic(checked) {
        if (checked === undefined) {
            checked = !root.automatic;
        }
        root.automatic = checked;
        if (Config.options?.light?.readingMode) {
            Config.options.light.readingMode.automatic = checked;
        }
        if (checked && Hyprsunset.shouldBeOn) {
            root.applyShader();
        } else if (!root.manualEnable) {
            root.disable();
        }
    }

    function togglePaperTone(checked) {
        if (checked === undefined) {
            checked = !root.paperTone;
        }
        root.paperTone = checked;
        if (Config.options?.light?.readingMode) {
            Config.options.light.readingMode.paperTone = checked;
        }
        if (root.effectiveActive) {
            root.applyShader();
        }
    }

    function setIntensity(val) {
        const clamped = Math.max(0, Math.min(100, Math.round(val)));
        root.intensity = clamped;
        if (Config.options?.light?.readingMode) {
            Config.options.light.readingMode.intensity = clamped;
        }
        if (root.effectiveActive) {
            root.applyShader();
        }
    }

    Connections {
        target: Hyprsunset
        function onShouldBeOnChanged() {
            if (root.automatic && !root.manualEnable) {
                if (Hyprsunset.shouldBeOn) {
                    root.applyShader();
                } else {
                    if (HyprlandComfortView.effectiveActive) {
                        HyprlandComfortView.applyShader();
                    } else {
                        Quickshell.execDetached(["bash", "-c", `${Directories.cliPath} hyprset reset decoration:screen_shader && hyprctl reload`]);
                    }
                }
            }
        }
    }

    Connections {
        target: Config.options?.light?.readingMode ?? null
        function onEnableChanged() {
            root.manualEnable = Config.options.light.readingMode.enable;
            if (root.manualEnable) root.applyShader();
            else if (!root.automatic || !Hyprsunset.shouldBeOn) root.disable();
        }
        function onAutomaticChanged() {
            root.automatic = Config.options.light.readingMode.automatic;
        }
        function onIntensityChanged() {
            root.intensity = Config.options.light.readingMode.intensity;
            if (root.effectiveActive) root.applyShader();
        }
        function onPaperToneChanged() {
            root.paperTone = Config.options.light.readingMode.paperTone;
            if (root.effectiveActive) root.applyShader();
        }
    }

    HyprlandConfigOption {
        id: confOpt
        key: "decoration:screen_shader"
    }
}
