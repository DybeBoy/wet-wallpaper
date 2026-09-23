#version 440

// ---------------------------------------------------------------------------
// Water render — vertex shader (passthrough)
// Transforms vertex position and forwards the UV texture coordinate.
// Must declare the full uniform block identically to water_render.frag
// because both shaders share the same UBO at binding 0.
// ---------------------------------------------------------------------------

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;

layout(location = 0) out vec2 texCoord;

// std140 layout — offsets must match water_render.frag exactly:
//   offset   0 : mat4  qt_Matrix              (64 bytes)
//   offset  64 : float qt_Opacity             ( 4 bytes)
//   offset  68 : float distortionStrength     ( 4 bytes)
//   offset  72 : float specularIntensity      ( 4 bytes)
//   offset  76 : float texelSize              ( 4 bytes)
//   offset  80 : float aspectRatio            ( 4 bytes)
//   offset  84 : float ambientAmplitude       ( 4 bytes)
//   offset  88 : float ambientScale           ( 4 bytes)
//   offset  92 : float ambientSpeed           ( 4 bytes)
//   offset  96 : float ambientDirection       ( 4 bytes)
//   offset 100 : float ambientComplexity      ( 4 bytes)
//   offset 104 : float time                   ( 4 bytes)
//   total: 108 bytes
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float distortionStrength;
    float specularIntensity;
    float texelSize;
    float aspectRatio;
    float ambientAmplitude;
    float ambientScale;
    float ambientSpeed;
    float ambientDirection;
    float ambientComplexity;
    float time;
};

void main() {
    texCoord    = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
