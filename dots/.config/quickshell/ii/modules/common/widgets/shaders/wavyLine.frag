#version 450

// The M3 Expressive wavy fill, as an analytic stroke instead of a path.
//
// This used to be a QML Canvas that appended one lineTo per pixel and stroked
// it on the CPU every frame, then re-uploaded the result as a texture - for a
// shape that is fully described by five numbers. Here each fragment measures
// its own distance to the sine and shades itself, so a frame costs nothing on
// the CPU and the wave drift is a single uniform.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;     // item size in px, so everything below can be px
    vec4 waveColor;      // straight (non-premultiplied) RGBA
    float amplitude;     // px of vertical swing, peak from the centre line
    float frequency;     // whole cycles across fullLength
    float fullLength;    // px the frequency is counted over, not item width
    float lineWidth;     // px of stroke thickness
    float phase;         // radians, animated to drift the wave sideways
};

const float PI = 3.14159265359;

// Signed vertical offset of the wave from the centre line at x.
float waveY(float x, float k, float centreY) {
    return centreY + amplitude * sin(k * x + phase);
}

void main() {
    vec2 p = qt_TexCoord0 * resolution;
    float centreY = resolution.y * 0.5;
    float k = 2.0 * PI * frequency / max(fullLength, 1.0);
    float halfWidth = lineWidth * 0.5;

    // The Canvas walked x from lineWidth/2 to width - lineWidth/2 and let
    // round caps cover the rest, so the stroke ends in a half circle rather
    // than being clipped square. Reproduce that: inside the span measure the
    // perpendicular distance to the curve, past either end measure straight-
    // line distance to that end point.
    float x0 = halfWidth;
    float x1 = max(resolution.x - halfWidth, x0);
    float dist;
    if (p.x < x0) {
        dist = distance(p, vec2(x0, waveY(x0, k, centreY)));
    } else if (p.x > x1) {
        dist = distance(p, vec2(x1, waveY(x1, k, centreY)));
    } else {
        // Perpendicular distance to a curve is the vertical distance divided
        // by the local slope's hypotenuse; exact for a line, and close enough
        // for a sine this shallow that the width never visibly pinches.
        float slope = amplitude * k * cos(k * p.x + phase);
        dist = abs(p.y - waveY(p.x, k, centreY)) / sqrt(1.0 + slope * slope);
    }

    // One pixel of feather, which is what the Canvas's own antialiasing gave.
    float alpha = 1.0 - smoothstep(halfWidth - 1.0, halfWidth, dist);

    // Qt composites premultiplied.
    fragColor = vec4(waveColor.rgb, 1.0) * (waveColor.a * alpha * qt_Opacity);
}
