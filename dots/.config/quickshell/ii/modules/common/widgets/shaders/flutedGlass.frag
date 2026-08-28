#version 450

// Fluted / reeded glass. A per-cell surface normal is refracted through
// Snell's law (refract()) instead of being displaced by a gradient ramp, so
// the flutes compress toward their seams like real cast glass. Per-channel
// IOR gives dispersion; a Blinn-Phong lobe off the same normal gives the
// highlight down each rib.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;      // item size in px, so cellSize can be in px
    float cellSize;       // px across one flute
    float angle;          // flute direction, radians
    float distortion;     // refraction strength, 0..1
    float dispersion;     // chromatic aberration, 0..1
    float blurAmount;     // smear along the rib, 0..1
    float highlights;     // specular down the rib, 0..1
    float shadows;        // seam darkening, 0..1
    float edges;          // extra bend at the seams, 0..1
    float grain;          // frost, 0..1
    float irregularity;   // varies flute widths, 0..1
    float waviness;       // bends the rib axis, 0..1
    int pattern;          // 0 lines, 1 rain, 2 chevron, 3 bubble
    int profile;          // 0 lens, 1 prism, 2 contour, 3 cascade, 4 flat
};

layout(binding = 1) uniform sampler2D src;

const float PI = 3.14159265;
const float IOR = 1.5; // soda-lime glass

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    return fract(p * (p + p));
}

float hash21(vec2 p) {
    vec3 p3 = fract(p.xyx * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise11(float x) {
    float i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(hash11(i), hash11(i + 1.0), f);
}

vec3 tap(vec2 uv, vec2 oR, vec2 oG, vec2 oB) {
    if (dispersion <= 0.0)
        return texture(src, uv + oG).rgb;
    return vec3(texture(src, uv + oR).r, texture(src, uv + oG).g, texture(src, uv + oB).b);
}

void main() {
    float ca = cos(angle), sa = sin(angle);
    vec2 px = qt_TexCoord0 * resolution;
    // Flute space: x runs across the ribs, y along them.
    vec2 rot = vec2(px.x * ca + px.y * sa, -px.x * sa + px.y * ca);

    float cs = max(2.0, cellSize);
    float coord = rot.x;

    if (pattern == 1) // rain glass: sine-bent ribs
        coord += sin(rot.y / cs * 0.9) * cs * waviness * 2.0;
    else if (pattern == 2) // chevron: triangle-bent ribs
        coord += (abs(fract(rot.y / (cs * 8.0)) * 2.0 - 1.0) - 0.5) * cs * waviness * 6.0;

    // Warping the axis with low-frequency noise gives uneven flute widths.
    if (irregularity > 0.0)
        coord += (noise11(coord / (cs * 7.0)) - 0.5) * cs * irregularity * 6.0;

    vec2 nxy;
    float nz, edgeT;

    if (pattern == 3) {
        // Bubble glass: a grid of spherical lenses, flat between them.
        vec2 c = fract(vec2(coord, rot.y) / cs) * 2.0 - 1.0;
        float r = length(c);
        nxy = c * step(r, 1.0);
        nz = sqrt(max(1e-4, 1.0 - min(r * r, 1.0)));
        edgeT = min(r, 1.0);
    } else {
        float u = fract(coord / cs) * 2.0 - 1.0; // -1..1 across one flute
        float nx = 0.0;
        nz = 1.0;
        if (profile == 0) {          // lens: circular arc
            nx = u;
            nz = sqrt(max(1e-4, 1.0 - u * u));
        } else if (profile == 1) {   // prism: two flat facets
            nx = sign(u) * 0.82;
            nz = 0.57;
        } else if (profile == 2) {   // contour: bulge, dip, bulge
            nx = sin(u * PI);
            nz = sqrt(max(1e-4, 1.0 - nx * nx));
        } else if (profile == 3) {   // cascade: one-sided ramp
            float t = u * 0.5 + 0.5;
            nx = t;
            nz = sqrt(max(1e-4, 1.0 - t * t));
        }                            // profile 4 stays flat
        nxy = vec2(nx, 0.0);
        edgeT = abs(u);
    }

    vec3 N = normalize(vec3(nxy, nz));
    vec3 I = vec3(0.0, 0.0, -1.0); // looking into the pane

    float thickness = distortion * cs * (1.0 + edges * smoothstep(0.6, 1.0, edgeT) * 3.0);
    float d = dispersion * 0.12;

    // Flute-space refraction offsets, rotated back into screen space.
    vec2 axisX = vec2(ca, sa), axisY = vec2(-sa, ca);
    vec2 rR = refract(I, N, 1.0 / (IOR * (1.0 - d))).xy;
    vec2 rG = refract(I, N, 1.0 / IOR).xy;
    vec2 rB = refract(I, N, 1.0 / (IOR * (1.0 + d))).xy;
    vec2 oR = (axisX * rR.x + axisY * rR.y) * thickness / resolution;
    vec2 oG = (axisX * rG.x + axisY * rG.y) * thickness / resolution;
    vec2 oB = (axisX * rB.x + axisY * rB.y) * thickness / resolution;

    vec3 col;
    if (blurAmount > 0.0) {
        // Smear along the rib, the way cast glass loses detail lengthwise.
        vec2 step0 = axisY * (blurAmount * cs * 1.5) / resolution;
        col = vec3(0.0);
        float wsum = 0.0;
        for (int i = -3; i <= 3; ++i) {
            float t = float(i) / 3.0;
            float w = exp(-t * t * 2.0);
            col += tap(qt_TexCoord0 + step0 * t, oR, oG, oB) * w;
            wsum += w;
        }
        col /= wsum;
    } else {
        col = tap(qt_TexCoord0, oR, oG, oB);
    }

    vec3 V = -I;
    vec3 L = normalize(vec3(-0.5, -0.55, 0.67));
    float spec = pow(max(dot(N, normalize(L + V)), 0.0), 32.0);
    col += highlights * spec * 1.3;
    col *= 1.0 - shadows * pow(edgeT, 6.0);

    if (grain > 0.0)
        col += (hash21(px) - 0.5) * grain * 0.25;

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
