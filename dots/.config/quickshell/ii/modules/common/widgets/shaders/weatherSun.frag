#version 450

// Android's sunny wallpaper: god rays out of an off-screen sun, a warm/cool
// split-tone over the scene, and a six-element lens flare.
//
// Ported line for line from AOSP's weathereffects library:
//   frameworks/libs/systemui/weathereffects/graphics/assets/shaders/
//     sun_effect.agsl         (this main, godRays, calculateRay)
//     lens_flare.agsl         (addFlare and its circles, rings and ghosts)
//     color_grading_lut.agsl  (colorGrade)
// Apache-2.0, see licenses/Apache-2.0.txt. Every constant below is theirs,
// including the `sunCenter` that AOSP's own TODO(b/375214506) is unhappy with.
//
// The one thing dropped is the foreground blend in the middle: this layer draws
// over the finished desktop, so there is no cut-out subject to composite, and
// AOSP's blend is the identity at alpha 0.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 screenSize;
    float time;
    float intensity;
    float lutIntensity;
};

layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D lut;

/** sun_effect.agsl */
const vec2 sunCenter = vec2(0.57, -0.8);
const vec3 godRaysColor = vec3(1.0, 0.857, 0.71428);

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

float relativeLuminance(vec3 color) {
    return dot(vec3(0.2126, 0.7152, 0.0722), color);
}

vec3 imageRangeConversion(vec3 color, float rangeCompression, float blackLevel, float noise, float amount) {
    color *= mix(1.0, rangeCompression + noise, amount);
    color += blackLevel * amount;
    return color;
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

/** lens_flare.agsl */
vec3 addFlareCircle(vec2 uv, vec2 sunPos, float distScale, float size, float chroAb, float definition) {
    float dR = distance(uv, distScale * (1.0 - chroAb) * sunPos) / (size * (1.0 - chroAb));
    float dG = distance(uv, distScale * 1.0 * sunPos) / size;
    float dB = distance(uv, distScale * (1.0 + chroAb) * sunPos) / (size * (1.0 + chroAb));
    float wR = 1.0 - smoothstep(definition, 0.75, dR);
    float wG = 1.0 - smoothstep(definition, 0.75, dG);
    float wB = 1.0 - smoothstep(definition, 0.75, dB);
    return vec3(wR, wG, wB);
}

vec3 addFlareCircle(vec2 uv, vec2 sunPos, float distScale, float size, float chroAb) {
    return addFlareCircle(uv, sunPos, distScale, size, chroAb, 0.25);
}

vec3 addFlareRing(vec2 uv, vec2 sunPos, float distScale, float size, float chroAb, float stroke) {
    float dR = distance(uv, distScale * (1.0 - chroAb) * sunPos) / (size * (1.0 - chroAb));
    float dG = distance(uv, distScale * 1.0 * sunPos) / size;
    float dB = distance(uv, distScale * (1.0 + chroAb) * sunPos) / (size * (1.0 + chroAb));
    float wR = smoothstep(0.75 - stroke, 0.75, dR) - smoothstep(0.75, 0.75 + stroke, dR);
    float wG = smoothstep(0.75 - stroke, 0.75, dG) - smoothstep(0.75, 0.75 + stroke, dG);
    float wB = smoothstep(0.75 - stroke, 0.75, dB) - smoothstep(0.75, 0.75 + stroke, dB);
    return vec3(wR, wG, wB);
}

vec3 addFlareDistorted(vec2 uv, vec2 sunPos, float distScale, float size, float chroAb) {
    vec2 uvd = uv * length(uv);
    return addFlareCircle(uvd, sunPos, distScale, size, chroAb, 0.35);
}

vec3 addFlare(vec3 color, vec2 uv, vec2 sunPos, float amount) {
    vec3 ret = vec3(0.0);
    ret += vec3(0.7) * addFlareCircle(uv, sunPos, -0.1, 0.1, 0.04);
    ret += vec3(0.64) * addFlareCircle(uv, sunPos, 0.05, 0.035, 0.04);
    ret += vec3(0.5) * addFlareCircle(uv, sunPos, -0.22, 0.18, 0.04);
    ret += vec3(0.34) * addFlareRing(uv, sunPos, -0.35, 0.4, 0.02, 0.16);
    ret += vec3(0.52) * addFlareDistorted(uv, sunPos, -0.4, 0.3, 0.08);
    ret += vec3(0.57) * addFlareDistorted(uv, sunPos, 0.4, 0.15, 0.06);
    return mix(color, vec3(1.0, 0.95, 0.88), amount * ret);
}

/** sun_effect.agsl - the god rays themselves. */
// God ray oscillations. It works like a Fourier series, using the uv position
// angle and time and phase to adjust how it looks.
float calculateRay(float angle, float t) {
    float rays = 17.5 + 8.0 * sin(3.0 * angle + t);
    rays += 4.0 * sin(12.0 * angle - 0.3 * t);
    rays += 4.0 * sin(25.0 * angle + 0.9252 * t);
    rays += -1.8 * cos(38.0 * angle - 0.114 * t);
    rays += 0.45 * cos(60.124 * angle + 0.251 * t);
    return rays;
}

float godRays(vec2 uv, vec2 center, float phase, float frequency, float t, float amount) {
    uv -= center;
    float angle = atan(uv.y, uv.x);
    // The glow around the position of the sun.
    float sunGlow = 1.0 / (1.0 + 20.0 * length(uv));
    float rays = calculateRay(angle * frequency, phase + t);
    return amount * sunGlow * (rays * 0.4 + 2.0 + 2.0 * length(uv));
}

vec3 addGodRays(vec3 background, vec2 fragCoord, vec2 uv, vec2 sunPos,
                float phase, float frequency, float timeSpeed) {
    float rays = godRays(uv, sunPos, phase, frequency, timeSpeed * time, intensity);
    // Dithering.
    rays -= triangleNoise(fragCoord) * 0.025;
    rays = clamp(rays, 0.0, 1.0);
    vec3 raysColor = mix(godRaysColor, min(godRaysColor + 0.5, vec3(1.0)), smoothstep(0.15, 0.6, rays));
    return normalBlendNotPremultiplied(background, raysColor, smoothstep(0.1, 1.0, rays));
}

float checkBrightnessGodRaysAtCenter(vec2 center, float phase, float frequency, float timeSpeed) {
    float angle = atan(-center.y, -center.x);
    float rays = calculateRay(angle * frequency, phase + timeSpeed * time);
    // Normalize [0, 1] the brightness.
    return smoothstep(-0.75, 35.25, rays);
}

void main() {
    vec2 fragCoord = qt_TexCoord0 * screenSize;

    // AOSP measures this effect in units of screen *width*, which on the phones
    // it was tuned on is the short edge. On a landscape panel width is the long
    // edge, so the same constants put the sun roughly four times closer to the
    // frame and the glow - 1/(1 + 20 * distance) - saturates the whole screen.
    // Their own TODO(b/375214506) is about this uv placement.
    //
    // Normalising by the short edge instead is bit-identical on any portrait
    // screen, and on a wider one it puts the sun where a Pixel puts it relative
    // to the frame, at the same falloff. Everything downstream - the ray
    // frequencies, the flare radii, the glow constant - is left alone, because
    // it is now being fed the units it was written for.
    vec2 unit = screenSize / min(screenSize.x, screenSize.y);
    vec2 uv = (qt_TexCoord0 - vec2(0.5, 0.5)) * unit;

    // AOSP's `sunCenter / vec2(1, screenAspectRatio)` is the same mapping
    // written for width units; this is it in short-edge units.
    vec2 sunBase = sunCenter * unit;
    vec2 sunVariation = vec2(0.1 * sin(time * 0.3), 0.14 * cos(time * 0.5));
    sunVariation += 0.1 * (0.5 * sin(time * 0.456) + 0.5) * sunBase;
    vec2 sunPos = sunVariation + sunBase;

    vec3 color = texture(src, qt_TexCoord0).rgb;
    /* AOSP blends the cut-out subject in here; we have none. */

    // Calculate brightness from sunrays.
    float brightnessSunray = checkBrightnessGodRaysAtCenter(sunPos, 10.0, 1.1, 0.9);
    brightnessSunray *= brightnessSunray;

    // Adjusts contrast and brightness.
    float noise = 0.025 * triangleNoise(fragCoord + vec2(12.31, 1024.1241));
    color = imageRangeConversion(color, 0.88, 0.02, noise, intensity);

    // Split-tone: cool highlights, warm shadows, both leaning on the rays.
    float lum = relativeLuminance(color);
    vec3 highlightColor = vec3(0.41, 0.69, 0.856);
    float highlightThres = 0.66;
    float highlightBlend = 0.30 + brightnessSunray * 0.1;
    vec3 shadowColor = vec3(0.756, 0.69, 0.31);
    float shadowThres = 0.33;
    float shadowBlend = 0.2 + brightnessSunray * 0.1;

    float highlightsMask = smoothstep(highlightThres, 1.0, lum);
    float shadowsMask = 1.0 - smoothstep(0.0, shadowThres, lum);

    color = normalBlendNotPremultiplied(color, shadowColor, intensity * shadowBlend * shadowsMask);
    color = normalBlendNotPremultiplied(color, highlightColor, intensity * highlightBlend * highlightsMask);

    // Add god rays.
    color = addGodRays(color, fragCoord, uv, sunPos, 10.0, 1.1, 0.9);
    // Add flare.
    color = addFlare(color, uv, sunPos, (0.4 + 0.8 * brightnessSunray) * intensity);

    fragColor = vec4(colorGrade(color, lutIntensity), 1.0) * qt_Opacity;
}
