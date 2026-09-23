#version 440

// ---------------------------------------------------------------------------
// Water physics — vertex shader (passthrough)
// Transforms vertex position and forwards the UV texture coordinate.
// Must declare the full uniform block identically to water_physics.frag
// because both shaders share the same UBO at binding 0.
// ---------------------------------------------------------------------------

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;

layout(location = 0) out vec2 texCoord;

// std140 layout — offsets must match water_physics.frag exactly:
//   offset   0 : mat4  qt_Matrix         (64 bytes)
//   offset  64 : float qt_Opacity        ( 4 bytes)
//   offset  68 : float waveSpeed         ( 4 bytes)
//   offset  72 : float damping           ( 4 bytes)
//   offset  76 : float texelSize         ( 4 bytes)
//   offset  80 : float aspectRatio       ( 4 bytes)  — screenWidth / screenHeight
//   [padding 84–95 for vec4 alignment]
//   offset  80 : float aspectRatio       ( 4 bytes)  — screenWidth / screenHeight
//   offset  84 : float dtScale           ( 4 bytes)  — actualInterval_ms / (1000/60)
//   [padding 88–95 for vec4 alignment]
//   offset  96 : vec4  hover0            (16 bytes)  — hover trail slot  0
//   offset 112 : vec4  hover1            (16 bytes)  — hover trail slot  1
//   offset 128 : vec4  hover2            (16 bytes)  — hover trail slot  2
//   offset 144 : vec4  hover3            (16 bytes)  — hover trail slot  3
//   offset 160 : vec4  hover4            (16 bytes)  — hover trail slot  4
//   offset 176 : vec4  hover5            (16 bytes)  — hover trail slot  5
//   offset 192 : vec4  hover6            (16 bytes)  — hover trail slot  6
//   offset 208 : vec4  hover7            (16 bytes)  — hover trail slot  7
//   offset 224 : vec4  hover8            (16 bytes)  — hover trail slot  8
//   offset 240 : vec4  hover9            (16 bytes)  — hover trail slot  9
//   offset 256 : vec4  hover10           (16 bytes)  — hover trail slot 10
//   offset 272 : vec4  hover11           (16 bytes)  — hover trail slot 11
//   offset 288 : vec4  hover12           (16 bytes)  — hover trail slot 12
//   offset 304 : vec4  hover13           (16 bytes)  — hover trail slot 13
//   offset 320 : vec4  hover14           (16 bytes)  — hover trail slot 14
//   offset 336 : vec4  hover15           (16 bytes)  — hover trail slot 15
//   offset 352 : vec4  ripple1           (16 bytes)  — click
//   offset 368 : vec4  ripple2           (16 bytes)  — droplet A
//   offset 384 : vec4  ripple3           (16 bytes)  — droplet B
//   total: 400 bytes
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float waveSpeed;
    float damping;
    float texelSize;
    float aspectRatio;
    float dtScale;  // unused in vert; declared to keep UBO layout identical to frag
    vec4  hover0;
    vec4  hover1;
    vec4  hover2;
    vec4  hover3;
    vec4  hover4;
    vec4  hover5;
    vec4  hover6;
    vec4  hover7;
    vec4  hover8;
    vec4  hover9;
    vec4  hover10;
    vec4  hover11;
    vec4  hover12;
    vec4  hover13;
    vec4  hover14;
    vec4  hover15;
    vec4  ripple1;
    vec4  ripple2;
    vec4  ripple3;
};

void main() {
    texCoord    = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
