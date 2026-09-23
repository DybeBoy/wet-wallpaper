#version 440

// ---------------------------------------------------------------------------
// Wallpaper transition — vertex shader (passthrough)
// Transforms vertex position and forwards the UV texture coordinate.
// Must declare the full uniform block identically to water_transition.frag
// because both shaders share the same UBO at binding 0.
// ---------------------------------------------------------------------------

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;

layout(location = 0) out vec2 texCoord;

// std140 layout — offsets must match water_transition.frag exactly:
//   offset   0 : mat4  qt_Matrix     (64 bytes)
//   offset  64 : float qt_Opacity    ( 4 bytes)
//   offset  68 : float progress      ( 4 bytes)  — 0 (old image) .. 1 (new image)
//   offset  72 : float mode          ( 4 bytes)  — 0 crossfade, 1 ripple, 2 iris, 3 wipe
//   offset  76 : float direction     ( 4 bytes)  — wipe only: 0 left,1 right,2 up,3 down
//   offset  80 : float aspectRatio   ( 4 bytes)
//   total: 84 bytes
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float progress;
    float mode;
    float direction;
    float aspectRatio;
};

void main() {
    texCoord    = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
