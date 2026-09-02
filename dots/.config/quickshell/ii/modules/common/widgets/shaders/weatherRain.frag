#version 450

// Android's rain wallpaper, layer 1 of 2: the shower falling through the scene.
//
// Ported line for line from AOSP's weathereffects library:
//   frameworks/libs/systemui/weathereffects/graphics/assets/shaders/
//     rain_shower_layer.agsl  (this main)
//     rain_shower.agsl        (generateRain)
//     rain_constants.agsl     (highlightColor)
//     utils.agsl              (idGenerator, triangleNoise, wiggle, ...)
// Apache-2.0, see licenses/Apache-2.0.txt. Every constant below is theirs.
//
// Two things AOSP does here are dropped, both because this layer draws over the
// finished desktop rather than between a wallpaper and its cut-out subject:
// the foreground blend (our foreground alpha is 0, so it is the identity) and
// the splashes, which need the subject's outline buffer to know what to splash
// against.

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
};

layout(binding = 1) uniform sampler2D src;

const float PI = 3.14159265359;

// rain_constants.agsl: the colour of the highlight of each drop.
const vec3 highlightColor = vec3(0.9, 1.0, 1.0);
// rain_shower_layer.agsl: controls how visible the rain drops are.
const float rainVisibility = 0.4;

/** utils.agsl */
float idGenerator(vec2 point) {
    vec2 p = fract(point * vec2(723.123, 236.209));
    p += dot(p, p + 17.1512);
    return fract(p.x * p.y);
}

// Noise range of [-1.0, 1.0[ with triangle distribution.
float triangleNoise(vec2 n) {
    n = fract(n * vec2(5.3987, 5.4421));
    n += dot(n.yx, n.xy + vec2(21.5351, 14.3137));
    float xy = n.x * n.y;
    return fract(xy * 95.4307) + fract(xy * 75.04961) - 1.0;
}

mat2 rotationMat(float angleRad) {
    float c = cos(angleRad);
    float s = sin(angleRad);
    return mat2(c, s, -s, c);
}

vec2 rotateAroundPoint(vec2 point, vec2 centerPoint, float angleRad) {
    return (point - centerPoint) * rotationMat(angleRad) + centerPoint;
}

vec3 imageRangeConversion(vec3 color, float rangeCompression, float blackLevel, float noise, float amount) {
    color *= mix(1.0, rangeCompression + noise, amount);
    color += blackLevel * amount;
    return color;
}

// Equation decided by testing in Grapher, per the AOSP comment.
float wiggle(float t, float wiggleSpeed) {
    return sin(wiggleSpeed * t + 0.5 * sin(wiggleSpeed * 5.0 * t)) * sin(wiggleSpeed * t) - 0.5;
}

/** rain_shower.agsl - generateRain, returning the drop mask alone. */
float generateRain(vec2 uv, float aspect, float t, vec2 rainGridSize, float rainIntensity) {
    /* Grid. */
    // Aspect ratio impacts visible cells.
    uv.y /= aspect;
    // Scale the UV to allocate number of rows and columns.
    vec2 gridUv = uv * rainGridSize;
    // Invert y (otherwise it goes from 0=top to 1=bottom).
    gridUv.y = 1.0 - gridUv.y;
    // Move grid vertically down.
    gridUv.y += 0.4 * t;
    // Generate column id, to offset columns vertically (so rain is not aligned).
    float columnId = idGenerator(vec2(floor(gridUv.x), 1.412));
    gridUv.y += columnId * 2.6;

    /* Cell. */
    float cellId = idGenerator(floor(gridUv));
    vec2 cellUv = fract(gridUv) - 0.5;

    float cellIntensity = idGenerator(floor(vec2(cellId * 8.16, 27.2)));
    if (rainIntensity < cellIntensity)
        return 0.0;

    /* Cell-id-based variations. */
    float visibilityFactor = smoothstep(cellIntensity, min(cellIntensity + 0.18, 1.0), rainIntensity);
    // Adjusts scale of each drop (higher is smaller).
    float scaleVariation = 1.0 - 0.3 * cellId;

    /* Cell drop. */
    float horizontalStart = 0.8 * (cellIntensity - 0.5);
    vec2 dropPos = cellUv;
    dropPos.y += -0.052;
    dropPos.x += horizontalStart;
    dropPos *= scaleVariation * vec2(14.2, 2.728);

    return smoothstep(
        0.0,
        // Adjust the opacity.
        0.80 + 3.0 * cellId,
        // Adjust the shape.
        1.0 - length(vec2(dropPos.x, dropPos.y - dropPos.x * dropPos.x))
    ) * visibilityFactor;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 fragCoord = uv * screenSize;

    vec3 color = texture(src, uv).rgb;

    // Adjusts contrast and brightness.
    float noise = 0.025 * triangleNoise(fragCoord + vec2(12.31, 1024.1241));
    color = imageRangeConversion(color, 0.84, 0.02, noise, intensity);

    // Add rotation for the rain (as a default sin(time * 0.05) can be used).
    float variation = wiggle(time - uv.y * 1.1, 0.10);
    vec2 uvRot = rotateAroundPoint(uv, vec2(0.5, -1.42), variation * PI / 9.0);

    // 1. A layer of rain that AOSP puts behind the subject.
    color = mix(color, highlightColor, rainVisibility
        * generateRain(uvRot, screenAspectRatio, time * 18.0, vec2(20.0, 2.0) * gridScale, intensity));

    // 2. The mid layer.
    color = mix(color, highlightColor, rainVisibility
        * generateRain(uvRot, screenAspectRatio, time * 21.4, vec2(30.0, 4.0) * gridScale, intensity));

    // 3. The near layer, bigger and faster. Closer rain drops are less visible.
    color = mix(color, highlightColor, 0.7 * rainVisibility
        * generateRain(uvRot, screenAspectRatio, time * 27.0, vec2(8.0, 3.0) * gridScale, intensity));

    fragColor = vec4(color, 1.0) * qt_Opacity;
}
