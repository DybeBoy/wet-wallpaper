#version 440

// ---------------------------------------------------------------------------
// Wallpaper transition — fragment shader
//
// Blends between the outgoing (bgFrom) and incoming (bgTo) background image
// according to `progress` (0 = fully old, 1 = fully new) using one of a
// handful of selectable reveal patterns. Driven by WaterSurface.qml's
// transitionTimer while a wallpaper switch is in progress; the surrounding
// water simulation/render pass is untouched — this only replaces what feeds
// into water_render.frag's `bgSource`.
//
// Uniform block layout — must be identical to water_transition.vert:
//   offset   0 : mat4  qt_Matrix
//   offset  64 : float qt_Opacity
//   offset  68 : float progress    — 0..1 transition position
//   offset  72 : float mode        — 0 crossfade, 1 ripple, 2 iris, 3 wipe
//   offset  76 : float direction   — wipe only: 0 left, 1 right, 2 up, 3 down
//   offset  80 : float aspectRatio
// ---------------------------------------------------------------------------

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float progress;
    float mode;
    float direction;
    float aspectRatio;
};

layout(binding = 1) uniform sampler2D bgFrom;
layout(binding = 2) uniform sampler2D bgTo;

void main() {
    vec2 uv = texCoord;
    vec4 fromColor = texture(bgFrom, uv);
    vec4 toColor   = texture(bgTo, uv);

    if (mode < 0.5) {
        // Crossfade — plain alpha blend.
        fragColor = mix(fromColor, toColor, progress);
        return;
    }

    // Aspect-corrected distance from screen centre, shared by ripple/iris.
    vec2  centered = vec2((uv.x - 0.5) * aspectRatio, uv.y - 0.5);
    float dist      = length(centered);
    float maxDist   = length(vec2(0.5 * aspectRatio, 0.5));

    if (mode < 1.5) {
        // Ripple reveal — an expanding circle with a wobbly, water-like edge
        // and a faint trailing highlight ring that fades out near the end.
        float angle  = atan(centered.y, centered.x);
        float wobble = sin(angle * 6.0 + progress * 14.0) * 0.04 * (1.0 - progress);
        float edge   = progress * maxDist * 1.2 + wobble;
        float front  = smoothstep(edge - 0.025, edge + 0.025, dist);

        float ringDist = dist - edge + 0.09;
        float ring     = smoothstep(0.0, 0.02, ringDist) * (1.0 - smoothstep(0.02, 0.05, ringDist));
        float ringGlow = ring * (1.0 - progress) * 0.25;

        vec4 base = mix(toColor, fromColor, front);
        fragColor = mix(base, vec4(1.0), ringGlow);
        return;
    }

    if (mode < 2.5) {
        // Iris — clean circle expanding from centre, no wobble.
        float edge  = progress * maxDist * 1.05;
        float front = smoothstep(edge - 0.02, edge + 0.02, dist);
        fragColor   = mix(toColor, fromColor, front);
        return;
    }

    // Wipe — a straight edge sweeps across the screen. `direction` selects
    // which side is revealed first: 0 left, 1 right, 2 up (from bottom), 3 down (from top).
    float t;
    if (direction < 0.5)      t = uv.x;
    else if (direction < 1.5) t = 1.0 - uv.x;
    else if (direction < 2.5) t = 1.0 - uv.y;
    else                       t = uv.y;

    float front = smoothstep(progress - 0.05, progress + 0.05, t);
    fragColor = mix(toColor, fromColor, front);
}
