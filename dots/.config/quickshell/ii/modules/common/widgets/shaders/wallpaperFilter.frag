#version 450

// Every wallpaper effect the custom ROMs ship, in one pass. The maths is
// lifted from risingOS's SystemUI WallpaperUtils (inherited by Evolution X,
// Matrixx, Mist, Lunaris, PenguinOS) so the results match a ROM's, but run on
// the GPU per frame instead of once over a Bitmap on the CPU.
//
//   filterMode  1 grayscale  2 sepia  3 negative  4 posterize
//               5 pixelate   6 sharpen  7 chromatic aberration  8 radial blur
//
// saturation, vignette, grain and dim stack on top of any of them; the ROM
// applies dim last, so this does too.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    float saturation;      // 1.0 untouched, 0.0 grey, >1 punchier
    float dim;             // 0..1
    float vignette;        // 0..1
    float grain;           // 0..1
    float pixelSize;       // px per block
    float posterizeLevels; // 2..16
    float sharpen;         // 1.0 == the ROM's [0,-1,0,-1,5,-1,0,-1,0] kernel
    float chromatic;       // px of R/B separation
    float radialBlur;      // 0..1 of the distance from centre
    int filterMode;
};

layout(binding = 1) uniform sampler2D src;

// Android ColorMatrix.setSaturation() weights, so grey matches the ROM's grey.
const vec3 LUMA = vec3(0.213, 0.715, 0.072);

float hash21(vec2 p) {
    vec3 p3 = fract(p.xyx * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 col;

    // Filters that need to sample somewhere other than this pixel.
    if (filterMode == 5) {
        // Pixelation: nearest-neighbour down/upscale, i.e. snap to a block.
        vec2 cell = max(vec2(1.0), vec2(pixelSize)) / resolution;
        col = texture(src, (floor(uv / cell) + 0.5) * cell).rgb;
    } else if (filterMode == 7) {
        // Chromatic aberration: red pulled left, blue pulled right.
        float o = chromatic / max(resolution.x, 1.0);
        col = vec3(texture(src, uv - vec2(o, 0.0)).r,
                   texture(src, uv).g,
                   texture(src, uv + vec2(o, 0.0)).b);
    } else if (filterMode == 8) {
        // Radial blur: 10 taps back toward the centre, reach grows with radius.
        vec2 d = uv - 0.5;
        float dist = length(d);
        if (dist < 1e-5) {
            col = texture(src, uv).rgb;
        } else {
            vec2 dir = d / dist;
            float reach = dist * radialBlur;
            col = vec3(0.0);
            for (int i = 0; i < 10; ++i)
                col += texture(src, uv - dir * (float(i) / 10.0 * reach)).rgb;
            col /= 10.0;
        }
    } else if (filterMode == 6) {
        // Sharpen: centre * (1 + 4k) minus the four neighbours * k.
        vec2 t = 1.0 / resolution;
        vec3 c = texture(src, uv).rgb;
        vec3 n = texture(src, uv - vec2(0.0, t.y)).rgb + texture(src, uv + vec2(0.0, t.y)).rgb
               + texture(src, uv - vec2(t.x, 0.0)).rgb + texture(src, uv + vec2(t.x, 0.0)).rgb;
        col = clamp(c + sharpen * (4.0 * c - n), 0.0, 1.0);
    } else {
        col = texture(src, uv).rgb;
    }

    // Colour-matrix filters.
    if (filterMode == 1) {
        col = vec3(dot(col, LUMA));
    } else if (filterMode == 2) {
        col = clamp(mat3(0.393, 0.349, 0.272,
                         0.769, 0.686, 0.534,
                         0.189, 0.168, 0.131) * col, 0.0, 1.0);
    } else if (filterMode == 3) {
        col = 1.0 - col;
    } else if (filterMode == 4) {
        float q = 256.0 / max(2.0, posterizeLevels);
        col = floor(col * 255.0 / q) * q / 255.0;
    }

    col = mix(vec3(dot(col, LUMA)), col, saturation);

    if (vignette > 0.0) {
        // Clear out to half the diagonal, then ramp to full, as the ROM's
        // RadialGradient stops at 0.5 and 1.0 do.
        vec2 p = (uv - 0.5) * resolution;
        float t = clamp((length(p) / (0.5 * length(resolution)) - 0.5) * 2.0, 0.0, 1.0);
        col *= 1.0 - vignette * t;
    }

    // Monochrome film grain, +-25/255 like the ROM's Random.nextInt(51) - 25.
    if (grain > 0.0)
        col += (hash21(uv * resolution) - 0.5) * 2.0 * (25.0 / 255.0) * grain;

    col *= 1.0 - dim;

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
