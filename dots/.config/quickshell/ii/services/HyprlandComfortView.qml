pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.models.hyprland

Singleton {
    id: root

    readonly property string shaderPath: Quickshell.shellPath("services/hyprlandComfortViewShader/comfort-view.glsl")
    
    property bool manualEnable: Config.options?.light?.comfortView?.enable ?? false
    property bool automatic: Config.options?.light?.comfortView?.automatic ?? false
    property int intensity: Config.options?.light?.comfortView?.intensity ?? 50
    
    readonly property bool effectiveActive: manualEnable || (automatic && Hyprsunset.shouldBeOn)
    readonly property bool active: confOpt.value == root.shaderPath

    function load() {
        if (root.effectiveActive) {
            root.applyShader();
        }
    }

    function applyShader() {
        const sat = (1.0 - (root.intensity * 0.85 / 100.0)).toFixed(3);
        const warmth = (root.intensity * 0.50 / 100.0).toFixed(3);
        const cap = (1.0 - (root.intensity * 0.15 / 100.0)).toFixed(3);

        const glslContent = `#version 300 es
precision mediump float;

in vec2 v_texcoord;
uniform sampler2D tex;

layout(location = 0) out vec4 fragColor;

// Android 17 Comfort View - Dynamic Shader (Intensity: ${root.intensity}%)
const float u_saturation = ${sat};
const float u_warmth = ${warmth};
const float u_highlightCap = ${cap};

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    float lum = dot(pixColor.rgb, vec3(0.2126, 0.7152, 0.0722));
    
    // 1. Desaturation (Chrominance dampening)
    vec3 desaturated = mix(vec3(lum), pixColor.rgb, u_saturation);
    
    // 2. Warm spectrum shift (Boost red/green, attenuate blue)
    desaturated.r *= (1.0 + u_warmth * 0.20);
    desaturated.g *= (1.0 + u_warmth * 0.05);
    desaturated.b *= (1.0 - u_warmth * 0.75);
    
    // 3. Highlight softening (Glare reduction)
    vec3 clampedColor = min(desaturated, vec3(u_highlightCap));
    
    fragColor = vec4(clampedColor, pixColor.a);
}`;

        let singleLineContent = glslContent.split('\n').join('\\n');
        Quickshell.execDetached(["bash", "-c", `echo -e "${singleLineContent}" > "${root.shaderPath}" && ${Directories.cliPath} hyprset key decoration:screen_shader "${root.shaderPath}" && hyprctl reload`]);
    }

    function enable() {
        root.manualEnable = true;
        if (Config.options?.light?.comfortView) {
            Config.options.light.comfortView.enable = true;
        }
        root.applyShader();
    }

    function disable() {
        root.manualEnable = false;
        if (Config.options?.light?.comfortView) {
            Config.options.light.comfortView.enable = false;
        }
        if (!root.automatic || !Hyprsunset.shouldBeOn) {
            Quickshell.execDetached(["bash", "-c", `${Directories.cliPath} hyprset reset decoration:screen_shader && hyprctl reload`]);
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
        if (Config.options?.light?.comfortView) {
            Config.options.light.comfortView.automatic = checked;
        }
        if (checked && Hyprsunset.shouldBeOn) {
            root.applyShader();
        } else if (!root.manualEnable) {
            root.disable();
        }
    }

    function setIntensity(val) {
        const clamped = Math.max(0, Math.min(100, Math.round(val)));
        root.intensity = clamped;
        if (Config.options?.light?.comfortView) {
            Config.options.light.comfortView.intensity = clamped;
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
                    Quickshell.execDetached(["bash", "-c", `${Directories.cliPath} hyprset reset decoration:screen_shader && hyprctl reload`]);
                }
            }
        }
    }

    Connections {
        target: Config.options?.light?.comfortView ?? null
        function onEnableChanged() {
            root.manualEnable = Config.options.light.comfortView.enable;
            if (root.manualEnable) root.applyShader();
            else if (!root.automatic || !Hyprsunset.shouldBeOn) root.disable();
        }
        function onAutomaticChanged() {
            root.automatic = Config.options.light.comfortView.automatic;
        }
        function onIntensityChanged() {
            root.intensity = Config.options.light.comfortView.intensity;
            if (root.effectiveActive) root.applyShader();
        }
    }

    HyprlandConfigOption {
        id: confOpt
        key: "decoration:screen_shader"
    }
}
