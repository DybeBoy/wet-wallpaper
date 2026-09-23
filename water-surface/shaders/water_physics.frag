#version 440

// ---------------------------------------------------------------------------
// Water physics — fragment shader
//
// Implements a discrete wave equation on a 2D grid using a ping-pong texture
// technique.  The simulation state is packed into two channels of a texture:
//   R channel : height at time t     (current frame)
//   G channel : height at time t-1   (previous frame)
//
// Each frame this shader reads the previous state, advances the simulation
// by one step, and outputs the new state in the same R/G packing.
//
// The ShaderEffectSource { recursive: true } in QML feeds the output of this
// shader back to itself as "prevState" on the next frame.
//
// Uniform block layout — must be identical to water_physics.vert:
//   offset   0 : mat4  qt_Matrix
//   offset  64 : float qt_Opacity
//   offset  68 : float waveSpeed   — wave propagation speed (0.1 – 0.5)
//   offset  72 : float damping     — energy loss per step   (0.95 – 0.999)
//   offset  76 : float texelSize   — 1.0 / simulationResolution
//   offset  80 : float aspectRatio — screenWidth / screenHeight
//   offset  84 : float dtScale     — actualInterval_ms / (1000/60); normalises sim speed to 60fps
//   [padding 88–95 for vec4 alignment]
//   offset  96 : vec4  hover0      — hover trail slot  0
//   offset 112 : vec4  hover1      — hover trail slot  1
//   offset 128 : vec4  hover2      — hover trail slot  2
//   offset 144 : vec4  hover3      — hover trail slot  3
//   offset 160 : vec4  hover4      — hover trail slot  4
//   offset 176 : vec4  hover5      — hover trail slot  5
//   offset 192 : vec4  hover6      — hover trail slot  6
//   offset 208 : vec4  hover7      — hover trail slot  7
//   offset 224 : vec4  hover8      — hover trail slot  8
//   offset 240 : vec4  hover9      — hover trail slot  9
//   offset 256 : vec4  hover10     — hover trail slot 10
//   offset 272 : vec4  hover11     — hover trail slot 11
//   offset 288 : vec4  hover12     — hover trail slot 12
//   offset 304 : vec4  hover13     — hover trail slot 13
//   offset 320 : vec4  hover14     — hover trail slot 14
//   offset 336 : vec4  hover15     — hover trail slot 15
//   offset 352 : vec4  ripple1     — mouse click
//   offset 368 : vec4  ripple2     — droplet A
//   offset 384 : vec4  ripple3     — droplet B
// ---------------------------------------------------------------------------

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float waveSpeed;
    float damping;
    float texelSize;
    float aspectRatio;
    float dtScale;  // actualInterval_ms / (1000/60) — keeps sim speed constant regardless of cfgFPS
    vec4  hover0;   // hover trail slot  0
    vec4  hover1;   // hover trail slot  1
    vec4  hover2;   // hover trail slot  2
    vec4  hover3;   // hover trail slot  3
    vec4  hover4;   // hover trail slot  4
    vec4  hover5;   // hover trail slot  5
    vec4  hover6;   // hover trail slot  6
    vec4  hover7;   // hover trail slot  7
    vec4  hover8;   // hover trail slot  8
    vec4  hover9;   // hover trail slot  9
    vec4  hover10;  // hover trail slot 10
    vec4  hover11;  // hover trail slot 11
    vec4  hover12;  // hover trail slot 12
    vec4  hover13;  // hover trail slot 13
    vec4  hover14;  // hover trail slot 14
    vec4  hover15;  // hover trail slot 15
    vec4  ripple1;  // click
    vec4  ripple2;  // droplet A
    vec4  ripple3;  // droplet B
};

// Ping-pong texture: R = h(t), G = h(t-1)
layout(binding = 1) uniform sampler2D prevState;

// ---------------------------------------------------------------------------
// Add a ring-shaped ripple impulse centred at ripple.xy.
//
// Distance is computed in screen-pixel-normalised space (both axes in units of
// screen height) so the stamp is circular on screen rather than an ellipse.
// ripple.xy : UV position of centre
// ripple.z  : amplitude  (0 = inactive)
// ripple.w  : radius in height-fraction UV units
// ---------------------------------------------------------------------------
void applyRipple(inout float h, vec2 uv, vec4 ripple) {
    if (ripple.z <= 0.001) return;
    vec2  delta  = uv - ripple.xy;
    delta.x     *= aspectRatio;   // convert UV-x to height-fraction units
    float dist   = length(delta);
    float radius = max(ripple.w, 0.001);
    float env    = exp(-(dist * dist) / (radius * radius));
    h += ripple.z * env * cos((dist / radius) * 3.14159265);
}

void main() {
    vec2 uv = texCoord;

    // ------------------------------------------------------------------
    // Read packed height values from the previous frame.
    // ------------------------------------------------------------------
    vec2  packed = texture(prevState, uv).rg;
    float hC     = packed.r;   // current height
    float hP     = packed.g;   // previous height

    // Sample orthogonal neighbours for the isotropic Laplacian.
    // The physics grid is aspect-ratio-matched (512×288 for 16:9) so each texel
    // covers the same physical screen area in both axes.  The Y UV step is
    // texelSize * aspectRatio = (1/simResX) * (W/H) = 1/simResY, which steps
    // exactly one texel in the shorter (Y) dimension of the texture.
    float hL  = texture(prevState, uv + vec2(-texelSize,                   0.0)).r;
    float hR  = texture(prevState, uv + vec2( texelSize,                   0.0)).r;
    float hU  = texture(prevState, uv + vec2( 0.0,       -texelSize * aspectRatio)).r;
    float hD  = texture(prevState, uv + vec2( 0.0,        texelSize * aspectRatio)).r;

    // ------------------------------------------------------------------
    // Discrete wave equation — timestep correction.
    //
    // Each step covers dtScale reference frames (1/60 s each). Without
    // compensation the simulation runs faster at high cfgFPS and slower at
    // low cfgFPS because the same formula is applied more/fewer times per
    // second.
    //
    // Variable-dt form (velocity term projected over s steps):
    //   h[n+1] = (1+s)*h[n] - s*h[n-1] + (waveSpeed*s)² * lap
    // At s=1 this is identical to the standard 2*hC - hP form.
    //
    // safeScale clamps s to the Von Neumann stability limit so the shader
    // never diverges even when dtScale is large.
    // cMax = 1/sqrt(2): Von Neumann stability bound for isotropic 2-D leapfrog
    // (equal stencil coefficients in X and Y — valid because the grid is
    // aspect-ratio-matched so both axes have equal physical texel spacing).
    // stepDamp = damping^s keeps energy decay rate constant in real time.
    // ------------------------------------------------------------------
    float cMax      = 1.0 / sqrt(2.0);
    float s         = (waveSpeed > 0.001) ? min(dtScale, cMax / waveSpeed) : dtScale;
    float effC      = waveSpeed * s;
    float stepDamp  = pow(damping, s);
    float lapX = hL + hR - 2.0 * hC;
    float lapY = hU + hD - 2.0 * hC;
    float lap  = lapX + lapY;
    float hNew = (2.0 * hC - hP + effC * effC * lap) * stepDamp;

    // ------------------------------------------------------------------
    // Inject ripple impulses.
    // hover0-15: interpolated hover trail (all active simultaneously)
    // ripple1:   mouse click
    // ripple2/3: random droplets
    // ------------------------------------------------------------------
    applyRipple(hNew, uv, hover0);
    applyRipple(hNew, uv, hover1);
    applyRipple(hNew, uv, hover2);
    applyRipple(hNew, uv, hover3);
    applyRipple(hNew, uv, hover4);
    applyRipple(hNew, uv, hover5);
    applyRipple(hNew, uv, hover6);
    applyRipple(hNew, uv, hover7);
    applyRipple(hNew, uv, hover8);
    applyRipple(hNew, uv, hover9);
    applyRipple(hNew, uv, hover10);
    applyRipple(hNew, uv, hover11);
    applyRipple(hNew, uv, hover12);
    applyRipple(hNew, uv, hover13);
    applyRipple(hNew, uv, hover14);
    applyRipple(hNew, uv, hover15);
    applyRipple(hNew, uv, ripple1);
    applyRipple(hNew, uv, ripple2);
    applyRipple(hNew, uv, ripple3);

    // ------------------------------------------------------------------
    // Clamp to prevent divergence.
    // Apply an edge mask so waves are absorbed at the border (no reflections).
    // ------------------------------------------------------------------
    hNew = clamp(hNew, -1.0, 1.0);

    // Narrow absorption ramp — just 3 texels to prevent hard-edge artefacts
    // without creating a visible dead zone near the screen border.
    float borderW = texelSize * 3.0;
    float ex = smoothstep(0.0, borderW, uv.x) * smoothstep(0.0, borderW, 1.0 - uv.x);
    float ey = smoothstep(0.0, borderW, uv.y) * smoothstep(0.0, borderW, 1.0 - uv.y);
    hNew *= ex * ey;

    // ------------------------------------------------------------------
    // Output: pack new height into R, old current into G (becomes t-1).
    // ------------------------------------------------------------------
    fragColor = vec4(hNew, hC, 0.0, 1.0);
}
