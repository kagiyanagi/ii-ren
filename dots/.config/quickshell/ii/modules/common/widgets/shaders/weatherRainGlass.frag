#version 450

// Android's rain wallpaper, layer 2 of 2: the drops running down the glass in
// front of it, refracting whatever layer 1 produced, plus the LUT colour grade.
//
// Ported line for line from AOSP's weathereffects library:
//   frameworks/libs/systemui/weathereffects/graphics/assets/shaders/
//     rain_glass_layer.agsl   (this main)
//     glass_rain.agsl         (generateGlassRain, generateStaticGlassRain)
//     rain_constants.agsl     (the drop colours and intensities)
//     color_grading_lut.agsl  (colorGrade)
// Apache-2.0, see licenses/Apache-2.0.txt. Every constant below is theirs.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 screenSize;
    float time;
    float screenAspectRatio;
    float gridScale;
    float intensity;
    float lutIntensity;
};

layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D lut;

const float TAU = 6.2831853072;

/** rain_constants.agsl */
const vec3 highlightColor = vec3(0.9, 1.0, 1.0);
const vec3 contactShadowColor = vec3(0.2);
const vec3 dropTint = vec3(1.0);
const float dropTintIntensity = 0.09;
const float highlightIntensity = 0.7;
const float dropShadowIntensity = 0.5;

/** utils.agsl */
float idGenerator(vec2 point) {
    vec2 p = fract(point * vec2(723.123, 236.209));
    p += dot(p, p + 17.1512);
    return fract(p.x * p.y);
}

// Noise range of [0, 1].
float valueNoise(vec2 fragCoord) {
    float scale = 0.021;
    vec2 i = floor(fragCoord * scale);
    vec2 f = fract(fragCoord * scale);

    float a = idGenerator(i);
    float b = idGenerator(i + vec2(1.0, 0.0));
    float c = idGenerator(i + vec2(0.0, 1.0));
    float d = idGenerator(i + vec2(1.0, 1.0));

    vec2 u = smoothstep(vec2(0.0), vec2(1.0), f);

    float noise = mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
    // Remap the range back to [0,3].
    return noise / 3.0;
}

float wiggle(float t, float wiggleSpeed) {
    return sin(wiggleSpeed * t + 0.5 * sin(wiggleSpeed * 5.0 * t)) * sin(wiggleSpeed * t) - 0.5;
}

float mapRange(float value, float inMin, float inMax, float outMin, float outMax) {
    float v = clamp(value, inMin, inMax);
    float p = (v - inMin) / (inMax - inMin);
    return p * (outMax - outMin) + outMin;
}

/** color_grading_lut.agsl - a 32x32x32 cube sliced along the image width. */
const float LUT_CUBE_SIZE = 32.0;
const float LUT_IMAGE_WIDTH = LUT_CUBE_SIZE * LUT_CUBE_SIZE;
const float LUT_SLICE_LAST_IDX = LUT_CUBE_SIZE - 1.0;

vec3 lutTexel(vec2 px) {
    return texture(lut, (px + 0.5) / vec2(LUT_IMAGE_WIDTH, LUT_CUBE_SIZE)).rgb;
}

vec3 colorGrade(vec3 color, float amount) {
    // Right is red, up is blue, forward (slice) is green - so a slice is picked
    // by blue, and within it x is red and y is green.
    vec3 colorTmp = clamp(color, 0.0, 1.0) * LUT_SLICE_LAST_IDX;
    vec3 lo = floor(colorTmp);
    vec3 hi = ceil(colorTmp);
    vec3 graded = mix(
        lutTexel(vec2(lo.b * LUT_CUBE_SIZE + lo.r, lo.g)),
        lutTexel(vec2(hi.b * LUT_CUBE_SIZE + hi.r, hi.g)),
        fract(colorTmp));
    return mix(color, graded, amount);
}

/** glass_rain.agsl */
struct GlassRain {
    vec2 drop;
    float dropMask;
    vec2 dropplets;
    float droppletsMask;
    float trailMask;
};

GlassRain generateGlassRain(vec2 uv, float aspect, float t, vec2 rainGridSize, float rainIntensity) {
    vec2 dropPos = vec2(0.0);
    float cellMainDropMask = 0.0;
    vec2 trailDropsPos = vec2(0.0);
    float cellDroppletsMask = 0.0;
    float cellTrailMask = 0.0;

    /* Grid. */
    float cellAspectRatio = rainGridSize.x / rainGridSize.y;
    uv.y /= aspect;
    vec2 gridUv = uv * rainGridSize;
    gridUv.y = 1.0 - gridUv.y;
    float verticalGridPos = 2.4 * t / 5.0;
    gridUv.y += verticalGridPos;

    /* Cell. */
    float cellId = idGenerator(floor(gridUv));
    vec2 cellUv = fract(gridUv) - 0.5;

    /* Cell-id-based variations. */
    t += cellId * 7.1203;
    uv.y += cellId * 3.83027;
    // Adjusts scale of each drop (higher is smaller).
    float scaleVariation = 1.0 + 0.7 * cellId;
    // Make some cells to not have drops.
    if (cellId < 1.0 - rainIntensity)
        return GlassRain(dropPos, cellMainDropMask, trailDropsPos, cellDroppletsMask, cellTrailMask);

    /* Cell main drop. */
    // Vertical movement: Fourier Series-Sawtooth Wave (ascending: /|/|/|).
    float verticalSpeed = TAU / 5.0;
    float verticalPosVariation = 0.45 * 0.63 * (
        -1.2 * sin(verticalSpeed * t)
        - 0.5 * sin(2.0 * verticalSpeed * t)
        - 0.3333 * sin(3.0 * verticalSpeed * t));

    // Horizontal movement: wiggle.
    float wiggleSpeed = 6.0;
    float wiggleAmp = 0.5;
    float horizontalStartAmp = 0.5;
    float horizontalStart = (cellId - 0.5) * 2.0 * horizontalStartAmp / cellAspectRatio;
    float horizontalWiggle = wiggle(uv.y, wiggleSpeed);
    // Closer to the edge, wiggle less, so the drop stays inside its cell.
    horizontalWiggle = horizontalStart
        + (horizontalStartAmp - abs(horizontalStart)) * wiggleAmp * horizontalWiggle;

    float dropPosUncorrected = cellUv.x - horizontalWiggle;
    dropPos.x = dropPosUncorrected / cellAspectRatio;
    // Create tear drop shape.
    verticalPosVariation -= dropPosUncorrected * dropPosUncorrected / cellAspectRatio;
    dropPos.y = cellUv.y - verticalPosVariation;
    dropPos *= scaleVariation;
    cellMainDropMask = smoothstep(0.06, 0.04, length(dropPos));

    /* Cell trail dropplets. */
    trailDropsPos.x = (cellUv.x - horizontalWiggle) / cellAspectRatio;
    // Subtract verticalGridPos to make the dropplets stick in place.
    trailDropsPos.y = cellUv.y - verticalGridPos;
    trailDropsPos.y = (fract(trailDropsPos.y * 4.0) - 0.5) / 4.0;
    trailDropsPos *= scaleVariation;
    cellDroppletsMask = smoothstep(0.03, 0.02, length(trailDropsPos));
    // Fade the dropplets from the top the farther they are from the main drop.
    float verticalFading = 1.2 * smoothstep(0.5, verticalPosVariation, cellUv.y);
    cellDroppletsMask *= verticalFading;
    // Mask dropplets that are under the main cell drop.
    cellDroppletsMask *= smoothstep(-0.06, 0.08, dropPos.y);

    /* Cell trail mask (it will show the image unblurred). */
    cellTrailMask = smoothstep(-0.04, 0.04, dropPos.y);
    cellTrailMask *= verticalFading;
    // Only show the main section of the trail.
    cellTrailMask *= smoothstep(0.07, 0.02, abs(dropPos.x));

    cellDroppletsMask *= cellTrailMask;

    return GlassRain(dropPos, cellMainDropMask, trailDropsPos, cellDroppletsMask, cellTrailMask);
}

// Rain drops that stay in place on the glass surface and dissipate.
vec3 generateStaticGlassRain(vec2 uv, float t, float rainIntensity, vec2 gridSize) {
    vec2 gridUv = uv * gridSize;
    gridUv.y = 1.0 - gridUv.y;
    float columnId = idGenerator(vec2(floor(gridUv.x), 1.412));
    gridUv.y += columnId * 5.6;

    float cellId = idGenerator(floor(gridUv));
    // Draw rain drops with a probability based on the cell id.
    if (cellId < 0.8)
        return vec3(0.0);

    vec2 cellUv = fract(gridUv) - 0.5;

    float delay = 3.5173;
    float duration = 8.2;
    float tt = t + 100.0 * cellId;
    float circletime = floor(tt / (duration + delay));
    float delayOffset = idGenerator(floor(gridUv) + vec2(circletime, 43.14 * cellId));
    float normalizedTime = mapRange(mod(tt, duration + delay) - delay * delayOffset,
                                    0.0, duration, 0.0, 1.0);
    // Apply a curve to the time.
    normalizedTime *= normalizedTime;

    vec2 pos = cellUv * (1.5 - 0.5 * cellId + normalizedTime * 50.0);
    float mask = smoothstep(0.3, 0.2, length(pos))
        * smoothstep(0.2, 0.06, normalizedTime)
        * smoothstep(0.0, 0.45, rainIntensity);

    return vec3(pos * 0.19, mask);
}

void main() {
    vec2 fragCoord = qt_TexCoord0 * screenSize;

    // 0. Add a bit of noise so that the droplets are not perfect circles.
    vec2 uv = vec2(valueNoise(fragCoord) * 0.015 - 0.0025) + qt_TexCoord0;

    // 1. Small glass rain.
    GlassRain small = generateGlassRain(uv, screenAspectRatio, time * 0.7,
        vec2(5.0, 1.6) * gridScale, intensity * 0.6);
    float dropMask = small.dropMask;
    float droppletsMask = small.droppletsMask;
    vec2 dropUvMasked = small.drop * dropMask;
    vec2 droppletsUvMasked = small.dropplets * droppletsMask;

    // 2. Medium size glass rain.
    GlassRain med = generateGlassRain(uv, screenAspectRatio, time * 0.80,
        vec2(6.0, 0.945) * gridScale, intensity * 0.6);

    // 3. Combine those two glass rains.
    dropMask = max(med.dropMask, dropMask);
    droppletsMask = max(med.droppletsMask, droppletsMask);
    dropUvMasked = mix(dropUvMasked, med.drop * med.dropMask, med.dropMask);
    droppletsUvMasked = mix(droppletsUvMasked, med.dropplets * med.droppletsMask, med.droppletsMask);

    // 4. Static rain droplets on the glass surface.
    vec2 gridSize = vec2(12.0, 12.0) * gridScale;
    // Aspect ratio impacts visible cells.
    gridSize.y /= screenAspectRatio;
    vec3 staticRain = generateStaticGlassRain(uv, time, intensity, gridSize);
    dropMask = max(dropMask, staticRain.z);
    dropUvMasked = mix(dropUvMasked, staticRain.xy * staticRain.z, staticRain.z);

    // 5. Distort uv for the rain drops and dropplets. AOSP offsets fragCoord by
    // `uvDiffractionOffsets * screenSize` with y negated so the diffracted image
    // is not inverted; in normalised UVs that is the same offset times (1, -1).
    float distortionDrop = -0.1;
    vec2 uvDiffractionOffsets = distortionDrop * dropUvMasked;

    vec3 color = texture(src, qt_TexCoord0).rgb;
    vec3 sampledColor = texture(src, qt_TexCoord0 + uvDiffractionOffsets * vec2(1.0, -1.0)).rgb;
    color = mix(color, sampledColor, max(dropMask, droppletsMask));

    // 6. Colour tint in the rain drops.
    color = mix(color, dropTint,
        dropTintIntensity * smoothstep(0.7, 1.0, max(dropMask, droppletsMask)));

    // 7. Highlight on the drops.
    color = mix(color, highlightColor, highlightIntensity
        * smoothstep(0.05, 0.08, max(dropUvMasked * 1.7, droppletsUvMasked * 2.6)).x);

    // 8. Contact shadow under the drops.
    color = mix(color, contactShadowColor, dropShadowIntensity
        * smoothstep(0.055, 0.1, max(length(dropUvMasked * 1.7), length(droppletsUvMasked * 1.9))));

    fragColor = vec4(colorGrade(color, lutIntensity), 1.0) * qt_Opacity;
}
