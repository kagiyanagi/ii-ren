#version 450

// Android's snow wallpaper: ten parallax layers of flakes over the scene.
//
// Ported line for line from AOSP's weathereffects library:
//   frameworks/libs/systemui/weathereffects/graphics/assets/shaders/
//     snow_effect.agsl        (this main)
//     snow.agsl               (generateSnow)
//     color_grading_lut.agsl  (colorGrade)
// Apache-2.0, see licenses/Apache-2.0.txt. Every constant below is theirs.
//
// AOSP splits the ten layers around the wallpaper's cut-out subject and piles
// accumulated snow on its shoulders. This layer draws over the finished
// desktop, so there is no subject to split around: the layers run straight
// through from farthest to closest and the accumulation pass is dropped.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 screenSize;
    vec2 gridSize;
    float time;
    float screenAspectRatio;
    float intensity;
    float lutIntensity;
};

layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D lut;

/** snow_effect.agsl */
// Snow tint.
const vec4 snowColor = vec4(1.0, 1.0, 1.0, 0.95);
// Background tint.
const vec4 bgdTint = vec4(0.8, 0.8, 0.8, 0.07);

// Indices of the different snow layers.
const float farthestSnowLayerIndex = 9.0;
const float closestSnowLayerIndex = 0.0;

/** snow.agsl */
const mat2 rot45 = mat2(0.7071067812, 0.7071067812, -0.7071067812, 0.7071067812);
const float farthestSnowLayerWiggleSpeed = 2.18;
const float closestSnowLayerWiggleSpeed = 0.9;

/** utils.agsl */
float idGenerator(vec2 point) {
    vec2 p = fract(point * vec2(723.123, 236.209));
    p += dot(p, p + 17.1512);
    return fract(p.x * p.y);
}

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

float wiggle(float t, float wiggleSpeed) {
    return sin(wiggleSpeed * t + 0.5 * sin(wiggleSpeed * 5.0 * t)) * sin(wiggleSpeed * t) - 0.5;
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

/** snow.agsl - generateSnow, returning the flake mask alone. */
float generateSnow(vec2 uv, float aspect, float t, vec2 snowGridSize, float layerIndex) {
    // Normalize the layer index. 0 is closest, 1 is farthest.
    float normalizedLayerIndex = mapRange(layerIndex, closestSnowLayerIndex, farthestSnowLayerIndex, 0.0, 1.0);

    /* Grid. */
    // Increase the last number to make each layer more separate from the previous one.
    float depth = 0.65 + layerIndex * 0.37;
    float speedAdj = 1.0 + layerIndex * 0.15;
    float layerR = idGenerator(vec2(layerIndex, 1.412));
    snowGridSize *= depth;
    t += layerR * 58.3;
    float cellAspectRatio = snowGridSize.x / snowGridSize.y;
    // Aspect ratio impacts visible cells.
    uv.y /= aspect;
    // Skew uv.x so it goes to left or right.
    uv.x += uv.y * (0.8 * layerR - 0.4);
    vec2 gridUv = uv * snowGridSize;
    gridUv.y = 1.0 - gridUv.y;
    gridUv.y += 0.4 * t / speedAdj;
    // Generate column id, to offset columns vertically.
    float columnId = idGenerator(vec2(floor(gridUv.x), 1.412));
    // Have time affect the position of each column as well.
    gridUv.y += columnId * 2.6 + t * 0.19 * (1.0 - columnId);

    /* Cell. */
    float cellId = idGenerator(floor(gridUv));
    vec2 cellUv = fract(gridUv) - 0.5;
    cellUv.y *= -1.0;

    // Disable snow flakes with some probability.
    float cellIntensity = idGenerator(floor(vec2(cellId * 856.16, 272.2)));
    if (cellIntensity < 1.0 - intensity)
        return 0.0;

    /* Cell-id-based variations. */
    float visibilityFactor = smoothstep(
        cellIntensity,
        max(cellIntensity - (0.02 + 0.18 * intensity), 0.0),
        1.0 - intensity);
    // Adjust the size of each snow flake (higher is smaller) based on cell ID.
    float decreaseFactor = 2.0 + mapRange(cellId, 0.0, 1.0, -0.1, 2.8) + 5.0 * (1.0 - visibilityFactor);
    // Adjust the opacity based on the cell id and distance from the camera.
    float farLayerFadeOut = mapRange(normalizedLayerIndex, 0.7, 1.0, 1.0, 0.4);
    float closeLayerFadeOut = mapRange(normalizedLayerIndex, 0.0, 0.2, 0.6, 1.0);
    float opacityVariation = (1.0 - 0.9 * cellId) * visibilityFactor * closeLayerFadeOut * farLayerFadeOut;

    /* Cell snow flake. */
    // Horizontal movement: wiggle, slower the closer the layer is.
    float wiggleSpeed = mapRange(normalizedLayerIndex, 0.2, 0.7,
        closestSnowLayerWiggleSpeed, farthestSnowLayerWiggleSpeed);
    float wiggleAmp = 0.6 + 0.4 * smoothstep(0.5, 2.5, layerIndex);
    float horizontalStartAmp = 0.5;
    float horizontalWiggle = wiggle(
        // Current uv position, unskewed, varied by cell ID.
        uv.y - cellUv.y / snowGridSize.y + cellId * 2.1,
        wiggleSpeed * speedAdj);
    horizontalWiggle = horizontalStartAmp * wiggleAmp * horizontalWiggle;

    vec2 snowFlakeShape = vec2(0.28, 0.26);
    vec2 snowFlakePos = vec2(cellUv.x - horizontalWiggle, cellUv.y * cellAspectRatio);
    snowFlakePos -= vec2(0.0, (uv.y - 0.5 / aspect) - cellUv.y / snowGridSize.y) * aspect;
    snowFlakePos *= snowFlakeShape * decreaseFactor;
    vec2 snowFlakeShapeVariation = vec2(0.055) * vec2(
        cellId * 2.0 - 1.0,
        fract((cellId + 0.03521) * 34.21) * 2.0 - 1.0);
    vec2 snowFlakePosR = 1.016 * abs(rot45 * (snowFlakePos + snowFlakeShapeVariation));
    snowFlakePos = abs(snowFlakePos);

    return smoothstep(
        0.3,
        0.200 - 0.3 * opacityVariation,
        snowFlakePos.x + snowFlakePos.y + snowFlakePosR.x + snowFlakePosR.y
    ) * opacityVariation;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 fragCoord = uv * screenSize;

    vec3 color = texture(src, uv).rgb;

    // Adjusts contrast and brightness.
    float noiseT = triangleNoise(fragCoord + vec2(12.31, 1024.1241));
    color = imageRangeConversion(color, 0.88, 0.02, noiseT * 0.025, intensity);

    // Slight tint on the scene behind the snow.
    color = normalBlendNotPremultiplied(color, bgdTint.rgb, bgdTint.a);

    // Ten layers, farthest first.
    for (float i = farthestSnowLayerIndex; i >= closestSnowLayerIndex; i--) {
        float flakeMask = generateSnow(uv, screenAspectRatio, time, gridSize, i);
        color = normalBlendNotPremultiplied(color, snowColor.rgb, snowColor.a * flakeMask);
    }

    fragColor = vec4(colorGrade(color, lutIntensity), 1.0) * qt_Opacity;
}
