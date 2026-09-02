#version 450

// Android's fog wallpaper: four drifting layers sampled from AOSP's own
// tileable fog and cloud textures.
//
// Ported line for line from AOSP's weathereffects library:
//   frameworks/libs/systemui/weathereffects/graphics/assets/shaders/
//     fog_effect.agsl         (this main)
//     color_grading_lut.agsl  (colorGrade)
// with textures/fog.png and textures/clouds.png shipped alongside.
// Apache-2.0, see licenses/Apache-2.0.txt. Every constant below is theirs.
//
// AOSP interleaves the layers with the wallpaper's cut-out subject: two behind
// it, two in front. This layer draws over the finished desktop, so the
// foreground blend in the middle is the identity and all four layers land in
// front. The height bands that decide where each layer lives are unchanged.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 time;
    vec2 screenSize;
    vec2 fogSize;
    vec2 cloudsSize;
    float screenAspectRatio;
    float pixelDensity;
    float intensity;
    float lutIntensity;
};

layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D fogTex;
layout(binding = 3) uniform sampler2D cloudsTex;
layout(binding = 4) uniform sampler2D lut;

// Both AOSP textures are 512x512 and tile; fogSize/cloudsSize are in texels of
// them, so a sample is (size * uv + offset) / this.
const float TEX_SIZE = 512.0;

const vec3 fogScrimColor = vec3(0.20);
const vec3 fogColor = vec3(1.0);

/** utils.agsl */
float triangleNoise(vec2 n) {
    n = fract(n * vec2(5.3987, 5.4421));
    n += dot(n.yx, n.xy + vec2(21.5351, 14.3137));
    float xy = n.x * n.y;
    return fract(xy * 95.4307) + fract(xy * 75.04961) - 1.0;
}

vec3 normalBlendNotPremultiplied(vec3 b, vec3 f, float o) {
    return mix(b, f, o);
}

vec3 imageRangeConversion(vec3 color, float rangeCompression, float blackLevel, float noise, float amount) {
    color *= mix(1.0, rangeCompression + noise, amount);
    color += blackLevel * amount;
    return color;
}

float mapRange(float value, float inMin, float inMax, float outMin, float outMax) {
    float v = clamp(value, inMin, inMax);
    float p = (v - inMin) / (inMax - inMin);
    return p * (outMax - outMin) + outMin;
}

/** color_grading_lut.agsl */
const float LUT_CUBE_SIZE = 32.0;
const float LUT_IMAGE_WIDTH = LUT_CUBE_SIZE * LUT_CUBE_SIZE;
const float LUT_SLICE_LAST_IDX = LUT_CUBE_SIZE - 1.0;

vec3 lutTexel(vec2 px) {
    return texture(lut, (px + 0.5) / vec2(LUT_IMAGE_WIDTH, LUT_CUBE_SIZE)).rgb;
}

vec3 colorGrade(vec3 color, float amount) {
    vec3 colorTmp = clamp(color, 0.0, 1.0) * LUT_SLICE_LAST_IDX;
    vec3 lo = floor(colorTmp);
    vec3 hi = ceil(colorTmp);
    vec3 graded = mix(
        lutTexel(vec2(lo.b * LUT_CUBE_SIZE + lo.r, lo.g)),
        lutTexel(vec2(hi.b * LUT_CUBE_SIZE + hi.r, hi.g)),
        fract(colorTmp));
    return mix(color, graded, amount);
}

vec4 sampleFog(vec2 coord) {
    return texture(fogTex, coord / TEX_SIZE);
}

vec4 sampleClouds(vec2 coord) {
    return texture(cloudsTex, coord / TEX_SIZE);
}

void main() {
    vec2 timeForeground = time.xy;
    vec2 timeBackground = time.zw;

    vec2 fragCoord = qt_TexCoord0 * screenSize;
    vec2 uv = qt_TexCoord0;
    uv.y /= screenAspectRatio;

    vec3 color = texture(src, qt_TexCoord0).rgb;

    // Adjusts contrast and brightness.
    float noise = 0.025 * triangleNoise(fragCoord + vec2(12.31, 1024.1241));
    color = imageRangeConversion(color, 0.8, 0.02, noise, intensity);

    // Blend with the constant solid fog colour. The scene behind us is opaque,
    // so AOSP's `bgd.a` factor is 1.
    color = mix(color, fogScrimColor, 0.14 * intensity);

    /* Prepare fog layers. */
    // Dither to be applied to background noise.
    float bgdDither = triangleNoise((fragCoord + 0.0002 * timeBackground) * pixelDensity) * 0.075;

    // The furthest fog layer in the background.
    vec4 bgdFogFar = sampleFog(
        fogSize * uv
        // Moves UV based on time.
        + vec2(timeBackground * 1.5)
        // Adds sampling dithering.
        + vec2(bgdDither * 14.0));

    // The closer fog layer in the background.
    vec4 bgdFogClose = sampleFog(
        0.5 * fogSize * uv
        + vec2(timeBackground * 5.5)
        + vec2(bgdDither * 40.0));

    float fgdDither = triangleNoise((fragCoord + 0.003 * timeForeground) * pixelDensity) * 0.09;
    vec4 fgdFogFar = sampleClouds(
        0.5 * cloudsSize * uv
        + vec2(timeForeground * 15.0)
        // Adds distortions based on noise.
        + vec2(bgdFogFar.b * 20.0, bgdFogFar.g * 2.0)
        + vec2(fgdDither * 12.0));
    vec4 fgdFogClose = sampleClouds(
        0.5 * cloudsSize * uv
        + vec2(timeForeground * 32.0)
        + vec2(bgdFogFar.g * 2.0, bgdFogFar.b * 10.0)
        + vec2(fgdDither * 22.0));

    // Undo aspect ratio adjustment.
    uv.y *= screenAspectRatio;

    /* Background fog, layer 1 (far). */
    float fogHeightVariation;
    if (uv.y < 0.38) {
        fogHeightVariation = 0.03 * cos(uv.x * 2.5 + timeBackground.x * 0.07);
        float bgFogFarCombined = mapRange(bgdFogFar.r, 0.74, 0.9, fgdFogFar.g, 0.95) * bgdFogFar.r;
        float bgdFogLayer1 =
            bgFogFarCombined *
            smoothstep(-0.1, 0.05, uv.y + fogHeightVariation) *
            (1.0 - smoothstep(0.15, 0.35, uv.y + fogHeightVariation));
        bgdFogLayer1 *= 1.1;
        bgdFogLayer1 += 0.55 * bgdDither;
        bgdFogLayer1 = clamp(bgdFogLayer1, 0.0, 1.0);
        color = normalBlendNotPremultiplied(color, fogColor * 0.8, bgdFogLayer1 * intensity);
    }

    /* Background fog, layer 2 (close). */
    if (uv.y > 0.23 && uv.y < 0.87) {
        float fbmSimplexWorley = bgdFogClose.g * 0.625 + bgdFogClose.b * 0.3755;
        float bgFogCloseCombined = smoothstep(0.88 * fbmSimplexWorley, 1.0, bgdFogClose.r);
        fogHeightVariation = 0.02 * sin(uv.x * 2.5 + timeBackground.x * 0.09);
        float bgdFogLayer2 =
            bgFogCloseCombined *
            smoothstep(0.25, 0.55, uv.y + fogHeightVariation) *
            (1.0 - smoothstep(0.7, 0.85, uv.y + fogHeightVariation));
        bgdFogLayer2 *= 1.2;
        bgdFogLayer2 += 0.6 * bgdDither;
        bgdFogLayer2 = clamp(bgdFogLayer2, 0.0, 1.0);
        color = normalBlendNotPremultiplied(color, fogColor * 0.85, bgdFogLayer2 * intensity);
    }

    /* AOSP blends the cut-out subject in here; we have none. */

    /* Foreground fog, layer 1 (far). */
    if (uv.y > 0.32) {
        fogHeightVariation = 0.1 * cos(uv.x * 2.5 + timeForeground.x * 0.085);
        float fgdFogLayer1 =
            mix(fgdFogFar.r, 1.0,
                0.5 * intensity * smoothstep(0.72, 0.92, uv.y + fogHeightVariation)) *
            smoothstep(0.42, 0.82, uv.y + fogHeightVariation);
        fgdFogLayer1 *= 1.3;
        fgdFogLayer1 += 0.6 * fgdDither;
        fgdFogLayer1 = clamp(fgdFogLayer1, 0.0, 1.0);
        color = normalBlendNotPremultiplied(color, fogColor * 0.9, fgdFogLayer1 * intensity);
    }

    /* Foreground fog, layer 2 (close). */
    if (uv.y > 0.25) {
        fogHeightVariation = 0.05 * sin(uv.x * 2.0 + timeForeground.y * 0.5);
        float fgdFogLayer2 =
            mix(fgdFogClose.g, 1.0,
                0.65 * intensity * smoothstep(0.85, 1.3, uv.y + fogHeightVariation)) *
            smoothstep(0.30, 0.90, uv.y + uv.x * 0.09);
        fgdFogLayer2 *= 1.4;
        fgdFogLayer2 += 0.6 * fgdDither;
        fgdFogLayer2 = clamp(fgdFogLayer2, 0.0, 1.0);
        color = normalBlendNotPremultiplied(color, fogColor, fgdFogLayer2 * intensity);
    }

    fragColor = vec4(colorGrade(color, lutIntensity), 1.0) * qt_Opacity;
}
