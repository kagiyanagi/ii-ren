#version 450

// Android's unlock ripple: SystemUI's RippleShader (CIRCLE) with its sparkle
// noise, which AuthRippleView bursts out from wherever the unlock came from.
// Ported line for line from AOSP frameworks/base, packages/SystemUI/animation/
// src/com/android/systemui/surfaceeffects/: ripple/RippleShader.kt
// (SHADER_CIRCLE_MAIN), shaderutil/ShaderUtilLibrary.kt (triangleNoise,
// sparkles) and shaderutil/SdfShaderLibrary.kt (CIRCLE_SDF, soften, subtract).
// Apache 2.0, (C) 2021 The Android Open Source Project.
//
// distort() is left out: the unlock ripple never sets distortionStrength, so
// it returns p unchanged. Every uniform below is the AGSL one minus `in_`, and
// all lengths are physical pixels, as on the phone.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;      // item size, physical px
    vec2 center;          // physical px
    float radius;         // in_size.x * 0.5
    float time;           // ms since the ripple started
    float fadeSparkle;
    float fadeFill;
    float fadeRing;
    float blur;
    float pixelDensity;   // displayMetrics.density; here the screen's scale
    vec4 color;           // straight RGBA
    float sparkleStrength;
};

const float PI = 3.1415926535897932384626;

float triangleNoise(vec2 n) {
    n = fract(n * vec2(5.3987, 5.4421));
    n += dot(n.yx, n.xy + vec2(21.5351, 14.3137));
    float xy = n.x * n.y;
    // compute in [0..2[ and remap to [-1.0..1.0[
    return fract(xy * 95.4307) + fract(xy * 75.04961) - 1.0;
}

float sparkles(vec2 uv, float t) {
    float n = triangleNoise(uv);
    float s = 0.0;
    for (float i = 0.0; i < 4.0; i += 1.0) {
        float l = i * 0.01;
        float h = l + 0.1;
        float o = smoothstep(n - l, h, n);
        o *= abs(sin(PI * o * (t + 0.55 * i)));
        s += o;
    }
    return s;
}

float soften(float d, float blur) {
    float blurHalf = blur * 0.5;
    return smoothstep(-blurHalf, blurHalf, d);
}

float subtract(float outer, float inner) {
    return max(outer, -inner);
}

float sdCircle(vec2 p, float r) {
    return (length(p) - r) / r;
}

float circleRing(vec2 p, float radius) {
    float thicknessHalf = radius * 0.25;
    float outerCircle = sdCircle(p, radius + thicknessHalf);
    float innerCircle = sdCircle(p, radius);
    return subtract(outerCircle, innerCircle);
}

void main() {
    vec2 p = qt_TexCoord0 * resolution;
    float r = max(radius, 1e-3);   // progress 0 is radius 0, which AGSL let divide
    float sparkleRing = soften(circleRing(p - center, r), blur);
    float inside = soften(sdCircle(p - center, r * 1.25), blur);
    float sparkle = sparkles(p - mod(p, pixelDensity * 0.8), time * 0.00175)
        * (1. - sparkleRing) * fadeSparkle;

    float rippleInsideAlpha = (1. - inside) * fadeFill;
    float rippleRingAlpha = (1. - sparkleRing) * fadeRing;
    float rippleAlpha = max(rippleInsideAlpha, rippleRingAlpha) * color.a;
    vec4 ripple = vec4(color.rgb, 1.0) * rippleAlpha;
    // Already premultiplied, which is what Qt composites. The clamp is Skia's:
    // sparkle sums four octaves, so the mix can overshoot 1.
    fragColor = clamp(mix(ripple, vec4(sparkle), sparkle * sparkleStrength), 0.0, 1.0) * qt_Opacity;
}
