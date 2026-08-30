#version 300 es
precision mediump float;

in vec2 v_texcoord;
uniform sampler2D tex;

layout(location = 0) out vec4 fragColor;

// Android 17 Comfort View - Dynamic Shader (Intensity: 38%)
const float u_saturation = 0.677;
const float u_warmth = 0.190;
const float u_highlightCap = 0.943;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    float lum = dot(pixColor.rgb, vec3(0.2126, 0.7152, 0.0722));
    
    // 1. Desaturation (Chrominance dampening)
    vec3 desaturated = mix(vec3(lum), pixColor.rgb, u_saturation);
    
    // 2. Warm spectrum shift (Boost red/green, attenuate blue)
    desaturated.r *= (1.0 + u_warmth * 0.20);
    desaturated.g *= (1.0 + u_warmth * 0.05);
    desaturated.b *= (1.0 - u_warmth * 0.75);
    
    // 3. Highlight softening (Glare reduction)
    vec3 clampedColor = min(desaturated, vec3(u_highlightCap));
    
    fragColor = vec4(clampedColor, pixColor.a);
}
