#version 300 es
precision mediump float;

in vec2 v_texcoord;
uniform sampler2D tex;

layout(location = 0) out vec4 fragColor;

// Android AOSP ColorDisplayService - 1:1 Rec. 709 Grayscale Architecture
// LEVEL_COLOR_MATRIX_GRAYSCALE & GlobalSaturationTintController
// Luminance coefficients: Red 0.2126, Green 0.7152, Blue 0.0722
const vec3 kLuminanceWeights = vec3(0.2126, 0.7152, 0.0722);
const float u_intensity = 1.000;
const bool u_paperTone = false;
const bool u_comfortViewCap = false;
const float u_highlightCap = 1.000;

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
}
