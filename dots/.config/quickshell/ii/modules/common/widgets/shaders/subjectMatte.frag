#version 450

// Unpacks a subject-depth video frame: the wallpaper frame is the top half of
// the texture, its alpha matte the bottom half, both baked into one file by
// scripts/images/subject_cutout.py.
//
// Packing is what makes the effect possible at all. A matte playing as its own
// video is a second clock, and a matte a few frames off shows up at once as the
// subject sliding out of its own silhouette. One decoder cannot drift from
// itself, so the two halves are always the same instant.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float texel;    // 1.0 / packed texture height, to stay off the seam
    float toe;      // matte level that counts as fully clear
    float shoulder; // matte level that counts as fully opaque
};

layout(binding = 1) uniform sampler2D src;

void main() {
    // Half a texel inside each half. Sampling the boundary itself lets the
    // bilinear filter mix the last row of the frame into the first row of the
    // matte, which paints a bright seam across the bottom of the subject.
    float vFrame = clamp(qt_TexCoord0.y * 0.5, texel * 0.5, 0.5 - texel * 0.5);
    float vMatte = clamp(0.5 + qt_TexCoord0.y * 0.5, 0.5 + texel * 0.5, 1.0 - texel * 0.5);

    vec3 colour = texture(src, vec2(qt_TexCoord0.x, vFrame)).rgb;
    float matte = texture(src, vec2(qt_TexCoord0.x, vMatte)).r;

    // h.264 does not hand back exactly what went in: measured over a baked
    // wallpaper, clear pixels return a mean of 0.18/255 and the opaque interior
    // bottoms out around 237/255. Rescaling between those pins clear to fully
    // clear and opaque to fully opaque without flattening the soft edge in
    // between, which is the part worth having.
    float alpha = clamp((matte - toe) / (shoulder - toe), 0.0, 1.0);

    // Qt composites premultiplied.
    fragColor = vec4(colour * alpha, alpha) * qt_Opacity;
}
